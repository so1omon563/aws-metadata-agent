"""Credential-free checks using the parsing rules of botocore's configloader."""

import configparser
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[1] / "libexec/aws-metadata-config"
ALIASES = (
    "default",
    "profile default",
    'profile "default"',
    "profile 'default'",
    "profile    default ",
    'profile de"fa"ult',
    "profile de'fa'ult",
    r"profile de\fault",
    'profile ""default',
    "profile\tdefault",
    # Botocore checks a raw 'profile' prefix, then shell-splits two words.
    "profiles default",
)


def read_profiles(path):
    """Use RawConfigParser and shlex exactly as the AWS profile map does.

    No credentials are resolved or provider commands executed. Preserve raw
    nested option values so we can compare all settings before and after.
    """
    config = configparser.RawConfigParser()
    config.read(path)
    profiles = {}
    for section in config.sections():
        values = dict(config[section])
        if section.startswith("profile"):
            try:
                parts = shlex.split(section)
            except ValueError:
                continue
            if len(parts) == 2:
                profiles[parts[1]] = values
        elif section == "default":
            profiles[section] = values
    return profiles


class DefaultConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="aws-config-test.")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / "config"
        self.credentials = self.root / "credentials"
        self.command = self.root / "synthetic command"
        self.command.write_text("#!/bin/sh\nexit 99\n")
        self.command.chmod(0o700)

    def run_helper(self, operation, *, reject=False, credentials=False):
        args = [str(HELPER), operation, str(self.config)]
        if operation == "add":
            args.append(str(self.command))
        if credentials:
            args.append(str(self.credentials))
        result = subprocess.run(args, capture_output=True, text=True, check=False)
        if reject:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        else:
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_settings_and_round_trip(self):
        for alias in ALIASES:
            for ending in ("\n", "\r\n"):
                for last_section in (False, True):
                    with self.subTest(alias=alias, ending=repr(ending), last=last_section):
                        default = (
                            f"[{alias}] # existing default settings\n"
                            "    region = us-west-2\n"
                            "    output: json\n"
                            "    s3 =\n"
                            "        addressing_style = path\n"
                            "    # retain this indented comment\n"
                        )
                        named = "[profile example-other]\nregion = us-east-1\n"
                        original = (named + default if last_section else default + named)
                        original = original.replace("\n", ending).encode()
                        self.config.write_bytes(original)
                        before = read_profiles(self.config)
                        self.run_helper("validate")
                        self.run_helper("add")
                        after = read_profiles(self.config)
                        command = after["default"].pop("credential_process")
                        self.assertEqual(command, f'"{self.command}" _credential-process')
                        self.assertEqual(after, before)
                        installed = self.config.read_bytes()
                        if ending == "\r\n":
                            self.assertNotIn(b"\n", installed.replace(b"\r\n", b""))
                        self.run_helper("add")
                        self.assertEqual(self.config.read_bytes(), installed)
                        self.run_helper("remove")
                        self.assertEqual(self.config.read_bytes(), original)
                        self.run_helper("remove")
                        self.assertEqual(self.config.read_bytes(), original)

    def test_bracketed_continuations_remain_option_values(self):
        original = (
            "[default]\n"
            "custom = first\n"
            "    [literal]\n"
            "    [profile default]\n"
            "    last\n"
            "[profile example-other]\n"
            "region = us-east-1\n"
        ).encode()
        self.config.write_bytes(original)
        before = read_profiles(self.config)
        self.run_helper("add")
        after = read_profiles(self.config)
        self.assertEqual(after["default"].pop("credential_process"),
                         f'"{self.command}" _credential-process')
        self.assertEqual(after, before)
        self.run_helper("remove")
        self.assertEqual(self.config.read_bytes(), original)

    def test_indented_section_boundaries_are_preserved(self):
        for default in ("[default]\n  region = us-west-2\n", "[default]\n"):
            with self.subTest(default=default):
                original = (default + " [profile example-other]\nregion = us-east-1\n").encode()
                self.config.write_bytes(original)
                before = read_profiles(self.config)
                self.run_helper("add")
                after = read_profiles(self.config)
                self.assertEqual(after["default"].pop("credential_process"),
                                 f'"{self.command}" _credential-process')
                self.assertEqual(after, before)
                installed = self.config.read_bytes()
                self.run_helper("add")
                self.assertEqual(self.config.read_bytes(), installed)
                self.run_helper("remove")
                self.assertEqual(self.config.read_bytes(), original)

    def test_conflicting_providers_are_unchanged(self):
        for alias in ALIASES:
            for delimiter in ("=", ":"):
                with self.subTest(alias=alias, delimiter=delimiter):
                    original = (
                        f"[{alias}]; preserve this comment\r\n"
                        f"    credential_process {delimiter} /synthetic/provider\r\n"
                        "    region = us-west-2\r\n"
                    ).encode()
                    self.config.write_bytes(original)
                    self.assertIn("credential_process", read_profiles(self.config)["default"])
                    for operation in ("validate", "add"):
                        self.run_helper(operation, reject=True)
                        self.assertEqual(self.config.read_bytes(), original)

    def test_duplicate_effective_defaults_are_unchanged(self):
        for alias in ALIASES:
            with self.subTest(alias=alias):
                original = f"[default]\nregion = us-west-2\n[{alias}]\noutput = json\n".encode()
                self.config.write_bytes(original)
                for operation in ("validate", "add"):
                    self.run_helper(operation, reject=True)
                    self.assertEqual(self.config.read_bytes(), original)

    def test_named_syntax_is_not_used_for_shared_credentials(self):
        for alias in ALIASES[1:]:
            with self.subTest(alias=alias):
                self.config.write_text("[default]\nregion = us-west-2\n")
                original = f"[{alias}]\naws_access_key_id = SYNTHETIC\n".encode()
                self.credentials.write_bytes(original)
                self.run_helper("validate", credentials=True)
                self.run_helper("add", credentials=True)
                self.assertEqual(self.credentials.read_bytes(), original)

    def test_rerun_repairs_earlier_insertion_position(self):
        self.config.write_text(
            "[default]\n"
            "# aws-metadata-agent user mode: begin\n"
            f'credential_process = "{self.command}" _credential-process\n'
            "# aws-metadata-agent user mode: end\n"
            "    region = us-west-2\n"
            "    output = json\n"
        )
        self.run_helper("add")
        default = read_profiles(self.config)["default"]
        self.assertEqual(default["region"], "us-west-2")
        self.assertEqual(default["output"], "json")
        self.assertEqual(default["credential_process"], f'"{self.command}" _credential-process')

    def test_other_profile_names_are_not_default(self):
        for section in ("profile defaults", 'profile "default team"', r"profile de\xault", "profile\vdefault", "profile\fdefault"):
            with self.subTest(section=section):
                self.config.write_text(f"[{section}]\ncredential_process = /synthetic/provider\n")
                before = read_profiles(self.config)
                self.run_helper("add")
                after = read_profiles(self.config)
                self.assertIn("default", after)
                del after["default"]
                self.assertEqual(after, before)


if __name__ == "__main__":
    unittest.main()
