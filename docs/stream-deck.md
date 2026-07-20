# Stream Deck integration

An Elgato Stream Deck key can select an AWS profile by invoking the packaged
`aws-metadata` CLI directly. This does not require a wrapper script, a terminal
window, or direct requests to the metadata HTTP API.

The action changes the one globally active agent profile. Every host
application and reachable container sees the latest successful selection; a
Stream Deck key does not reserve a profile for one application.

## Prerequisites

- macOS with `aws-metadata-agent` [installed](homebrew.md),
  [configured](aws-runas-configuration.md), and
  [running](getting-started.md#3-verify-native-service-state)
- Elgato Stream Deck 6.9 or later
- The free
  [Mac Automation plugin](https://marketplace.elgato.com/product/mac-automation-8468fc12-644b-427a-84cb-127c82c5bb30)

Mac Automation provides a **Run Shell Command** action that executes arbitrary
command-line instructions. Its
[setup guide](https://streamdeckstash.thoughtasylum.com/plugin/2025/06/25/macauto/)
documents the action and additional examples.

## Configure a profile key

1. Install **Mac Automation** from the Elgato Marketplace.
2. Open the Stream Deck application.
3. Drag **Mac Automation -> Run Shell Command** onto a key.
4. In a terminal, locate the package-managed command:

   ```sh
   command -v aws-metadata
   ```

   Confirm the upstream profile name before adding it to a key:

   ```sh
   aws configure list-profiles
   ```

5. Set the key's command to that absolute path followed by the profile
   selection arguments. A Homebrew installation on Apple Silicon commonly
   uses:

   ```sh
   /opt/homebrew/bin/aws-metadata profile example-nonprod --open --wait 300 --json
   ```

6. Give the key an appropriate title and icon.
7. Repeat for each desired AWS profile.
8. Restart the Stream Deck application after initially installing the plugin
   or adding the actions if the physical device does not begin dispatching the
   new action. This restart was required during project validation.

Use fictional profile names in shared examples. Replace `example-nonprod` with
the name of a profile from the user's AWS configuration.

### Why the absolute path matters

Stream Deck runs as a GUI application and may not inherit the `PATH` of an
interactive terminal. An absolute path avoids a configuration that works in a
terminal but fails because Stream Deck cannot locate `aws-metadata`.

Use the stable package symlink returned by `command -v aws-metadata`, commonly
`/opt/homebrew/bin/aws-metadata` on Apple Silicon Homebrew. Do not copy a
versioned path from Homebrew's Cellar because that path changes during package
upgrades.

### Why not use System -> Open?

Stream Deck's built-in **System -> Open** action is intended to open
applications, files, folders, and executable script files. It does not provide
a general command-with-arguments execution contract. Use **Mac Automation ->
Run Shell Command** to invoke `aws-metadata` directly with profile-selection
arguments.

## Command behavior

The recommended command is:

```sh
/absolute/path/to/aws-metadata profile example-nonprod --open --wait 300 --json
```

It:

- requests the specified profile;
- opens the supported browser flow if authentication is required;
- waits up to 300 seconds for authentication to complete;
- emits machine-readable JSON; and
- returns a process exit code that distinguishes success, authentication
  requirements, timeouts, service unavailability, and unexpected responses.

When credentials and browser state are already valid, profile selection can
complete without opening either a terminal or a browser. When authentication
is required, the browser can open without opening Terminal.

The JSON is useful for troubleshooting and for command runners that capture
output, although Stream Deck does not display it directly on the key. A
successful response resembles:

```json
{
  "state": "ready",
  "message": "AWS metadata profile set to example-nonprod.",
  "profile": "example-nonprod"
}
```

See the [`profile` exit-code table](cli-reference.md#profile-exit-codes) for
the complete command contract.

## Verify the action

First, run the exact configured command in a terminal:

```sh
/opt/homebrew/bin/aws-metadata profile example-nonprod --open --wait 300 --json
```

Then select a different profile, press the configured physical Stream Deck
key, and verify that metadata consumers use the expected profile. Remember
that the metadata endpoint has one globally active profile: the most recent
successful selection wins.

Avoid rapid repeated presses or conflicting profile keys. Stream Deck does not
display the JSON result, the agent does not implement a per-key lock, and a
later successful action can replace the identity selected by an earlier one.

## Troubleshooting

If the key does nothing:

1. Confirm the metadata agent is running:

   ```sh
   aws-metadata status --json
   ```

2. Run the exact configured command in a terminal.
3. Confirm the Stream Deck command uses an absolute binary path.
4. Restart the Stream Deck application.
5. Confirm the action is **Mac Automation -> Run Shell Command**, not
   **System -> Open**.
6. Temporarily configure the key to capture command output:

   ```sh
   /opt/homebrew/bin/aws-metadata profile example-nonprod --open --wait 300 --json > "$TMPDIR/aws-metadata-streamdeck.log" 2>&1
   ```

   After pressing the key, inspect the file:

   ```sh
   cat "$TMPDIR/aws-metadata-streamdeck.log"
   ```

If the file is not created, the Stream Deck action did not launch. If it
contains JSON or an error, the action launched and the contents identify the
CLI or agent boundary to investigate. Remove the temporary log after testing;
even though the CLI output is designed for automation, local profile names may
still be sensitive:

```sh
rm -f "$TMPDIR/aws-metadata-streamdeck.log"
```

macOS assigns the GUI session a private `TMPDIR`. Keep diagnostic output there
rather than at a predictable path directly under the shared `/tmp` directory.

For agent-side failures, continue with the bounded diagnostics in
[Troubleshooting](troubleshooting.md).

## Security considerations

- Store only the AWS profile name in the Stream Deck command.
- Do not embed AWS credentials, tokens, passwords, role secrets, authentication
  cookies, or metadata responses.
- Let `aws-metadata-agent` and the normal AWS configuration own credentials and
  authentication.
- Prefer `--open` so interactive authentication follows the supported browser
  flow.
- Treat temporary logs as local diagnostic material and delete them when the
  investigation is complete.

## Related documentation

- [CLI reference](cli-reference.md)
- [Consumer recipes](consumers.md#gui-and-command-automation)
- [Troubleshooting](troubleshooting.md)
- [Security model](security.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)
