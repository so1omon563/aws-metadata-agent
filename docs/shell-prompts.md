# Shell prompt integration

`aws-metadata active-profile` is the portable interface for displaying the
broker's exact active profile name in a prompt, status bar, editor, or other
local shell integration:

```sh
aws-metadata active-profile
```

The command makes one live, tightly bounded request. It prints the name and a
newline when a profile is active. It prints nothing and exits successfully when
no profile is active or the service cannot answer quickly. It never reads the
live profile detail object, persists a name, or changes broker state.

Profile names can identify environments or roles. Display them only on a
trusted workstation, and avoid capturing prompts in public screenshots or
logs when the configured names are sensitive.

## Starship

Add `${custom.aws_metadata}` where the segment should appear in the top-level
`format`, then define the module:

```toml
format = """
$directory$git_branch$git_status${custom.aws_metadata}$aws
$character"""

[custom.aws_metadata]
command = "aws-metadata active-profile"
when = true
shell = ["sh"]
format = '(aws:$output )'
description = "Active aws-metadata profile"
```

The conditional format hides the complete segment when command output is
empty. Starship escapes custom-command output by default; do not enable
`unsafe_no_escape` for this module.

## zsh

Call this helper from an existing prompt definition. Doubling `%` prevents a
profile name from being interpreted as a zsh prompt escape:

```zsh
aws_metadata_prompt() {
  local profile
  profile=$(aws-metadata active-profile)
  [[ -n $profile ]] || return 0
  profile=${profile//\%/%%}
  printf ' [aws:%s]' "$profile"
}

setopt PROMPT_SUBST
PROMPT="$PROMPT"'$(aws_metadata_prompt)'
```

Integrate the command substitution into the desired location instead of
replacing a prompt supplied by a theme or framework.

## Bash

Call the helper from the existing `PS1`:

```bash
aws_metadata_prompt() {
  local profile
  profile=$(aws-metadata active-profile)
  [[ -n $profile ]] && printf ' [aws:%s]' "$profile"
}

PS1='$(aws_metadata_prompt)'"$PS1"
```

## fish

Call this function from the existing `fish_prompt` or `fish_right_prompt`
function:

```fish
function aws_metadata_prompt
    set -l profile (aws-metadata active-profile)
    if test -n "$profile"
        printf ' [aws:%s]' "$profile"
    end
end
```

For example, a prompt implementation can invoke `aws_metadata_prompt` at the
point where the segment should appear. Avoid replacing an existing framework's
prompt function solely to add this segment.
