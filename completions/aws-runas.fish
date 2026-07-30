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
        set --append tokens "$current"
    end
    command aws-runas $tokens --generate-bash-completion 2>/dev/null |
        string replace --regex '^([^:]+):(.*)$' '$1\t$2'
end

function __fish_aws_runas_completes_own_arguments
    set -l tokens (commandline -opc)
    set -e tokens[1]
    set -l skip_value false

    for token in $tokens
        if test "$skip_value" = true
            set skip_value false
            continue
        end
        switch $token
            case -d -a -o -M -t -X -J -S -I -W -T -C -U -P -R -O \
                --duration --role-duration --otp --mfa-serial --mfa-type \
                --external-id --jump-role --saml-url --saml-entityid \
                --web-url --web-redirect --web-client --username --password \
                --provider --output
                set skip_value true
            case '-*'
            case '*'
                contains -- $token list ls serve srv ssm ecr password passwd pw \
                    diagnose diag help h
                return
        end
    end
    return 0
end

complete --command aws-runas \
    --condition __fish_aws_runas_completes_own_arguments \
    --no-files --arguments '(__fish_aws_runas_complete)'
