# Native fish completion for the aws-runas 3.9.0 command surface.
#
# aws-runas exposes completion candidates through its
# --generate-bash-completion flag. This file calls that command surface from
# native fish syntax; it does not source or translate the upstream Bash or zsh
# completion scripts.

function __fish_aws_runas_complete
    set -l tokens (commandline -opc)
    set -e tokens[1]
    set -l current (commandline -ct)

    if string match --quiet -- '-*' "$current"
        command aws-runas $tokens "$current" --generate-bash-completion 2>/dev/null
    else
        command aws-runas $tokens --generate-bash-completion 2>/dev/null
    end
end

complete --command aws-runas --arguments '(__fish_aws_runas_complete)'
