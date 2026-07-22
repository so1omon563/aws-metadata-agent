# Shell prompt and status integrations

`aws-metadata active-profile` is the portable interface for displaying the
broker's exact active profile name in a prompt, status bar, editor, or other
local integration:

```sh
aws-metadata active-profile
```

The command makes one live request with a 200 ms default ceiling. It prints the
name and a newline when a profile is active. It prints nothing and exits
successfully when no profile is active or the service cannot answer quickly.
It never reads the live profile detail object, persists a name, or changes
broker state.

## Choose a display pattern

| Use case | Recommended pattern |
| --- | --- |
| Keep the active identity visible everywhere | Add one always-enabled custom prompt segment. |
| Distinguish broker state from `AWS_PROFILE` | Label the segment `imds:` and keep the prompt's normal AWS module separate. |
| Make production-like names conspicuous | Apply a naming-convention warning in the display command. |
| Avoid showing AWS context in unrelated work | Enable the segment only for matching project files. |
| Use a native shell prompt | Call the command from zsh, Bash, or fish prompt functions. |
| Share one indicator across many panes | Put the command in a tmux status bar. |

Profile names can identify environments or roles. Display them only on a
trusted workstation, and avoid capturing prompts in public screenshots or
logs when the configured names are sensitive.

## Distinguish broker and consumer profiles

The active metadata profile and a consumer's AWS configuration are different
states:

- `aws-metadata active-profile` reports the one globally active profile inside
  the local metadata broker.
- Starship's built-in `$aws` module normally reflects consumer environment such
  as `AWS_PROFILE` and region.

A consumer compatibility profile may remain constant while the broker switches
between upstream identities. Label the new segment `imds:` or `metadata:` so
the two states are not mistaken for each other.

## Starship: always-visible broker context

Add `${custom.aws_metadata}` near `$aws` in the top-level `format`. The example
below leaves the consumer AWS module first and then shows the live broker
identity:

```toml
format = """
$directory$git_branch$git_status$fill$aws${custom.aws_metadata}$kubernetes
$character"""

[custom.aws_metadata]
command = '''
profile=$(aws-metadata active-profile)
[ -n "$profile" ] && printf 'imds:%s' "$profile"
'''
when = true
shell = ["sh"]
style = "bold cyan"
description = "Active aws-metadata profile"
```

Starship's default custom-command format hides an empty command result. Keep
`when = true`: using `aws-metadata active-profile` as both the `when` condition
and the display command performs two live requests per prompt.

Starship escapes custom-command output by default. Do not enable
`unsafe_no_escape` for profile names. See Starship's
[custom-command reference](https://starship.rs/config/#custom-commands) for the
complete module contract.

### Put the segment in the right prompt

Prompts without a `$fill` layout can keep the identity out of the main prompt:

```toml
right_format = "${custom.aws_metadata}"

[custom.aws_metadata]
command = '''
profile=$(aws-metadata active-profile)
[ -n "$profile" ] && printf 'imds:%s' "$profile"
'''
when = true
shell = ["sh"]
style = "bold cyan"
description = "Active aws-metadata profile"
```

See Starship's [right-prompt guide](https://starship.rs/advanced-config/#enable-right-prompt)
for terminal compatibility and layout behavior.

### Warn on production-like names

When upstream names follow an environment convention, add a visual warning
without printing profile details or making another metadata request:

```toml
[custom.aws_metadata]
command = '''
profile=$(aws-metadata active-profile)
case "$profile" in
  "") ;;
  *prod*|*production*) printf 'WARNING imds:%s' "$profile" ;;
  *) printf 'imds:%s' "$profile" ;;
esac
'''
when = true
shell = ["sh"]
style = "bold yellow"
description = "Active aws-metadata profile"
```

Adjust the patterns to the user's naming convention. Keep the mapping local and
sanitized; do not publish real organization profile names as examples.

### Show the segment only in relevant projects

Starship can run the segment only in directories with selected files or file
extensions. This example enables it for Terraform and Terragrunt work:

```toml
[custom.aws_metadata]
command = '''
profile=$(aws-metadata active-profile)
[ -n "$profile" ] && printf 'imds:%s' "$profile"
'''
detect_extensions = ["tf"]
detect_files = ["terragrunt.hcl"]
shell = ["sh"]
style = "bold cyan"
description = "Active aws-metadata profile"
```

Do not also set `when = true` in a project-scoped module: Starship treats the
display conditions as alternatives, so an unconditional `when` would defeat
the file detection.

## Native zsh prompt

Call this helper from an existing prompt definition. Doubling `%` prevents a
profile name from being interpreted as a zsh prompt escape:

```zsh
aws_metadata_prompt() {
  local profile
  profile=$(aws-metadata active-profile)
  [[ -n $profile ]] || return 0
  profile=${profile//\%/%%}
  printf 'imds:%s' "$profile"
}

setopt PROMPT_SUBST
RPROMPT='$(aws_metadata_prompt)'"${RPROMPT:+ $RPROMPT}"
```

Use the same command substitution inside `PROMPT` for an inline segment.
Integrate it into the desired location instead of replacing a prompt supplied
by a theme or framework.

## Native Bash prompt

Call the helper from the existing `PS1`:

```bash
aws_metadata_prompt() {
  local profile
  profile=$(aws-metadata active-profile)
  [[ -n $profile ]] && printf '[imds:%s] ' "$profile"
}

PS1='$(aws_metadata_prompt)'"$PS1"
```

The command's successful empty result preserves the normal prompt when no
profile is available.

## Native fish prompt

Call this helper from the existing `fish_prompt` or `fish_right_prompt`
function:

```fish
function aws_metadata_prompt
    set -l profile (aws-metadata active-profile)
    if test -n "$profile"
        printf 'imds:%s' "$profile"
    end
end
```

For a new right prompt with no existing framework-owned function:

```fish
function fish_right_prompt
    aws_metadata_prompt
end
```

Avoid replacing an existing framework's prompt function solely to add this
segment; call the helper from that framework's supported extension point.

## Tmux status bar

A tmux status bar is useful when many panes share the same globally active
broker profile. Append a periodically refreshed indicator:

```tmux
set -ag status-right ' #(profile=$(aws-metadata active-profile); test -n "$profile" && printf "imds:%s" "$profile")'
set -g status-interval 5
```

This performs one lookup per tmux status refresh rather than one per pane
prompt. Integrate the command into an existing `status-right` definition when
spacing or ordering needs tighter control.

## Other status bars and editors

Any integration that can display command output can use the same primitive:

```sh
profile=$(aws-metadata active-profile)
if [ -n "$profile" ]; then
  printf 'imds:%s\n' "$profile"
fi
```

Prefer the plain output contract over parsing `status --json`. The dedicated
command avoids exposing the profile detail object and is bounded for frequent
rendering.

## Performance and troubleshooting

- Perform one `active-profile` call per render. Do not use it independently as
  both a visibility check and a display command.
- Do not add a separate cache unless stale display is acceptable. The command
  is uncached so a later render reflects `use`, `clear`, or broker restart.
- A blank result intentionally means there is nothing safe to display. Run
  `aws-metadata status` when inactive and unavailable states must be
  distinguished.
- `AWS_METADATA_ACTIVE_PROFILE_TIMEOUT_SECONDS` may set a different strictly
  positive deadline. Zero, negative, or malformed values fall back to 200 ms.
- Run `aws-metadata version` and upgrade to v0.3.3 or newer if the command is
  unavailable.
