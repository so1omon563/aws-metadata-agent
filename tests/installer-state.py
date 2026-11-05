#!/usr/bin/env python3
"""Credential-free installer checks with synthetic packages and mocked launchd.

Runs on Linux and macOS. This is not native launchd/Homebrew acceptance testing.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

PROJECT = Path(__file__).resolve().parent.parent


class InstallerStateTests(unittest.TestCase):
    def setUp(self):
        if Path('/etc/aws-metadata-agent/config').exists():
            self.skipTest('host has system-mode state; do not interact with it')
        self.temp = tempfile.TemporaryDirectory(prefix='aws-metadata-installer-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home with spaces'
        self.state = self.home / 'Library/Application Support/aws-metadata-agent'
        self.state.mkdir(parents=True)
        (self.home / '.aws').mkdir()
        (self.home / '.aws/config').write_text('# synthetic settings\n')
        (self.home / '.aws/credentials').write_text('# no credentials\n')
        self.mock = self.root / 'mock-bin'
        self.mock.mkdir()
        self.pid_file = self.root / 'pid'
        self.addCleanup(self.stop_process)
        self.write_executable(self.mock / 'uname', '#!/bin/sh\necho Darwin\n')
        self.write_executable(self.mock / 'id', '#!/bin/sh\necho 501\n')
        self.write_executable(self.mock / 'dscl',
                              '#!/bin/sh\nprintf "NFSHomeDirectory: %s\\n" "$HOME"\n')
        self.write_executable(self.mock / 'sudo', '#!/bin/sh\nexit 99\n')
        self.write_executable(self.mock / 'aws-runas', '#!/bin/sh\nexit 0\n')
        self.write_executable(self.mock / 'curl', '''#!/bin/sh
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then shift; output=$1; fi
  shift
done
printf 'profile not set' >"$output"
printf 500
''')
        self.write_executable(self.mock / 'launchctl', f'''#!{sys.executable}
import json, os, pathlib, plistlib, signal, subprocess, sys, time
root = pathlib.Path(os.environ['MOCK_ROOT'])
with (root / 'service-log').open('a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\\n')
pid_file = root / 'pid'
if sys.argv[1] == 'bootout':
    if pid_file.exists():
        try: os.kill(int(pid_file.read_text()), signal.SIGTERM)
        except ProcessLookupError: pass
        pid_file.unlink()
elif sys.argv[1] == 'bootstrap':
    with open(sys.argv[3], 'rb') as source: plist = plistlib.load(source)
    env = dict(os.environ, **plist['EnvironmentVariables'])
    child = subprocess.Popen(plist['ProgramArguments'], env=env,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
    pid_file.write_text(str(child.pid))
    for _ in range(100):
        report = root / 'running-version'
        if report.exists() and report.read_text().endswith(':' + str(child.pid)):
            break
        time.sleep(0.02)
    else:
        sys.exit('synthetic payload did not start')
else:
    sys.exit(2)
''')
        self.opt = self.root / 'opt'
        for version in ('old', 'new'):
            package = self.root / version
            package.mkdir()
            for name in ('install.sh', 'VERSION', 'bin', 'libexec', 'launchd'):
                source = PROJECT / name
                if source.is_dir():
                    shutil.copytree(source, package / name)
                else:
                    shutil.copy2(source, package / name)
            # A running payload publishes its loaded identity on demand, so a
            # symlink switch cannot make a stale startup marker pass the test.
            self.write_executable(package / 'libexec/aws-metadata-server', f'''#!{sys.executable}
import os, pathlib, signal, sys, time
root = pathlib.Path(os.environ['MOCK_ROOT'])
def report(*args):
    (root / 'running-version').write_text('{version}:' + str(os.getpid()))
def stop(*args):
    (root / ('stopped-' + str(os.getpid()))).touch()
    sys.exit(0)
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGUSR1, report)
report()
while True: time.sleep(1)
''')
        self.opt.symlink_to(self.root / 'old', target_is_directory=True)
        self.env = dict(os.environ, HOME=str(self.home), USER='synthetic-user',
                        PATH=str(self.mock) + os.pathsep + os.environ['PATH'],
                        MOCK_ROOT=str(self.root), AWS_METADATA_PACKAGE_ROOT=str(self.opt),
                        AWS_METADATA_PACKAGE_CLI=str(self.opt / 'bin/aws-metadata'))
        self.env.pop('SUDO_USER', None)

    @staticmethod
    def write_executable(path, content):
        path.write_text(content)
        path.chmod(0o755)

    def stop_process(self):
        if self.pid_file.exists():
            try:
                pid = int(self.pid_file.read_text())
                os.kill(pid, signal.SIGTERM)
                for _ in range(100):
                    if (self.root / f'stopped-{pid}').exists():
                        break
                    time.sleep(0.02)
            except ProcessLookupError:
                pass

    def setup(self):
        return subprocess.run([str(self.opt / 'bin/aws-metadata'), 'setup',
                               '--mode', 'user'], env=self.env,
                              capture_output=True, text=True, timeout=15)

    def snapshot(self):
        return {str(p.relative_to(self.home)): (p.read_bytes() if p.is_file() else None,
                                               p.stat().st_mode)
                for p in self.home.rglob('*')}

    def report(self, expected):
        report = self.root / 'running-version'
        for _ in range(100):
            if report.exists() and report.read_text().startswith(expected + ':'):
                return report.read_text()
            time.sleep(0.02)
        self.fail('synthetic running process did not report ' + expected)

    def test_rejected_schema_preserves_all_artifacts(self):
        agent = self.home / ('Library/LaunchAgents/'
                             'com.github.so1omon563.aws-metadata-agent.broker.plist')
        agent.parent.mkdir()
        agent.write_text('existing synthetic service definition\n')
        for name in ('user-mode', 'aws-runas-path', 'auto-clear-seconds'):
            (self.state / name).write_text('synthetic saved value\n')
        for value in ('2', '0002', 'invalid', '', '1\nAWS_METADATA_CONFIG_VERSION=1',
                      '18446744073709551617', '1=ignored'):
            with self.subTest(schema=value):
                (self.state / 'config').write_text(
                    f'AWS_METADATA_CONFIG_VERSION={value}\nFUTURE_REQUIRED_SETTING=synthetic\n')
                before = self.snapshot()
                result = self.setup()
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn('schema', result.stderr)
                self.assertEqual(self.snapshot(), before)
                self.assertFalse((self.root / 'service-log').exists())

    def test_current_and_legacy_reinstall(self):
        for schema in ('1', '0001', None):
            with self.subTest(schema=schema):
                config = '' if schema is None else f'AWS_METADATA_CONFIG_VERSION={schema}\n'
                (self.state / 'config').write_text(config + 'AWS_METADATA_MODE=user\n')
                (self.state / 'auto-clear-seconds').write_text('900\n')
                result = self.setup()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.report('old')
                self.assertIn('AWS_METADATA_CONFIG_VERSION=1\n',
                              (self.state / 'config').read_text())
                self.assertEqual((self.state / 'auto-clear-seconds').read_text(), '900\n')

    def test_explicit_setup_restarts_after_opt_switch(self):
        (self.state / 'auto-clear-seconds').write_text('900\n')
        result = self.setup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        old_report = self.report('old')
        old_pid = int(old_report.split(':')[1])
        aws_config = (self.home / '.aws/config').read_bytes()
        self.opt.unlink()
        self.opt.symlink_to(self.root / 'new', target_is_directory=True)
        (self.root / 'running-version').unlink()
        os.kill(old_pid, signal.SIGUSR1)
        self.assertEqual(self.report('old'), old_report)
        result = self.setup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        new_report = self.report('new')
        self.assertNotEqual(new_report.split(':')[1], str(old_pid))
        for _ in range(100):
            if (self.root / f'stopped-{old_pid}').exists():
                break
            time.sleep(0.02)
        self.assertTrue((self.root / f'stopped-{old_pid}').exists(),
                        'old synthetic process was not stopped')
        self.assertEqual((self.state / 'auto-clear-seconds').read_text(), '900\n')
        self.assertEqual((self.home / '.aws/config').read_bytes(), aws_config)
        actions = [json.loads(line) for line in (self.root / 'service-log').read_text().splitlines()]
        self.assertEqual([action[0] for action in actions],
                         ['bootout', 'bootstrap', 'bootout', 'bootstrap'])
        self.assertEqual(actions[2][1],
                         'gui/501/com.github.so1omon563.aws-metadata-agent.broker')
        self.assertEqual(actions[3][1], 'gui/501')


if __name__ == '__main__':
    unittest.main()
