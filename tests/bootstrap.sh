#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_DIR

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/aws-metadata-bootstrap-test.XXXXXX")
readonly TEMP_ROOT
trap 'rm -rf "$TEMP_ROOT"' EXIT

fake_bin=$TEMP_ROOT/bin
mkdir -p "$fake_bin"

case $(uname -s) in
  Darwin) fake_platform=darwin ;;
  Linux) fake_platform=linux ;;
esac
case $(uname -m) in
  x86_64|amd64) fake_architecture=amd64 ;;
  arm64|aarch64) fake_architecture=arm64 ;;
  armv6l|armv7l) fake_architecture=arm ;;
esac
export FAKE_ARCHIVE_NAME="aws-runas-3.9.0-${fake_platform}-${fake_architecture}.zip"

hash_files() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

fish_completion_checksum=$( \
  hash_files "$PROJECT_DIR/completions/aws-runas.fish" | awk '{print $1}'
)
[[ $fish_completion_checksum == \
  e130bc795ccc2d54e11070ec965523a2b6d24a527c36bb0ae192f8d6e3d23db2 ]]

cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -eu

output=
url=
while (($#)); do
  case $1 in
    --output)
      shift
      output=$1
      ;;
    http://*|https://*) url=$1 ;;
  esac
  shift
done

case $url in
  *.zip)
    printf '%s\n' 'fake archive' >"$output"
    ;;
  *.sha256sum)
    printf '%s  %s\n' \
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
      "$FAKE_ARCHIVE_NAME" >"$output"
    ;;
  *aws-runas-bash-completion)
    cat >"$output" <<'BASH_COMPLETION'
_cli_bash_autocomplete() { :; }
complete -F _cli_bash_autocomplete "$PROG"
BASH_COMPLETION
    ;;
  *aws-runas-zsh-completion)
    cat >"$output" <<'ZSH_COMPLETION'
_cli_zsh_autocomplete() { :; }
compdef _cli_zsh_autocomplete $PROG
ZSH_COMPLETION
    ;;
  *)
    printf 'Unexpected curl URL: %s\n' "$url" >&2
    exit 1
    ;;
esac
EOF
chmod 0755 "$fake_bin/curl"

cat >"$fake_bin/unzip" <<'EOF'
#!/usr/bin/env bash
set -eu

destination=
while (($#)); do
  if [[ $1 == -d ]]; then
    shift
    destination=$1
  fi
  shift
done
mkdir -p "$destination"
cat >"$destination/aws-runas" <<'BINARY'
#!/usr/bin/env bash
printf '%s\n' 'fake aws-runas'
BINARY
chmod 0755 "$destination/aws-runas"
EOF
chmod 0755 "$fake_bin/unzip"

cat >"$fake_bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
set -eu

file=${!#}
case ${file##*/} in
  aws-runas-bash-completion)
    if [[ ${FAKE_BAD_COMPLETION:-} == true ]]; then
      checksum=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    else
      checksum=0d5b208644aa53e55a7200cab9fc82db7be8334b8e803f58f7db77db55ab370e
    fi
    ;;
  aws-runas-zsh-completion)
    checksum=ef28853bfd267e09f4eb3b2335581294ad12099daa4a27fe3290e76259f16dec
    ;;
  aws-runas.fish)
    checksum=e130bc795ccc2d54e11070ec965523a2b6d24a527c36bb0ae192f8d6e3d23db2
    ;;
  *)
    checksum=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    ;;
esac
printf '%s  %s\n' "$checksum" "$file"
EOF
chmod 0755 "$fake_bin/sha256sum"
cp "$fake_bin/sha256sum" "$fake_bin/shasum"

assert_contains() {
  local file=$1
  local expected=$2

  if ! grep -Fq -- "$expected" "$file"; then
    printf 'Expected %s to contain: %s\n' "$file" "$expected" >&2
    exit 1
  fi
}

assert_count() {
  local file=$1
  local expected=$2
  local value=$3
  local actual

  actual=$(grep -Fc -- "$value" "$file")
  if [[ $actual != "$expected" ]]; then
    printf 'Expected %s occurrences of %s in %s, found %s.\n' \
      "$expected" "$value" "$file" "$actual" >&2
    exit 1
  fi
}

file_mode() {
  case $(uname -s) in
    Darwin) stat -f '%Lp' "$1" ;;
    *) stat -c '%a' "$1" ;;
  esac
}

run_bootstrap() {
  local home=$1
  local login_shell=$2
  shift 2

  env \
    HOME="$home" \
    SHELL="$login_shell" \
    PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    AWS_RUNAS_INSTALL_DIR="$home/.local/bin" \
    FAKE_BAD_COMPLETION="${FAKE_BAD_COMPLETION:-}" \
    "$PROJECT_DIR/bootstrap.sh" "$@"
}

for shell_name in zsh bash fish tcsh; do
  home=$TEMP_ROOT/dry-$shell_name
  mkdir -p "$home"
  output=$(run_bootstrap \
    "$home" "/usr/local/bin/$shell_name" --configure-shell --dry-run)
  case $shell_name in
    zsh)
      [[ $output == *"Shell: zsh"* ]]
      [[ $output == *"$home/.zprofile"* ]]
      [[ $output == *"$home/.zshrc"* ]]
      ;;
    bash)
      [[ $output == *"Shell: bash"* ]]
      if [[ $fake_platform == darwin ]]; then
        [[ $output == *"$home/.bash_profile"* ]]
      else
        [[ $output == *"$home/.bashrc"* ]]
      fi
      [[ $output == *'aws-runas-bash-completion'* ]]
      ;;
    fish)
      [[ $output == *"Shell: fish"* ]]
      [[ $output == *"$home/.config/fish/conf.d/aws-metadata-agent.fish"* ]]
      [[ $output == *"$home/.config/fish/completions/aws-runas.fish"* ]]
      ;;
    tcsh)
      [[ $output == *"Shell: unsupported"* ]]
      [[ $output == *'Shell files: unchanged'* ]]
      ;;
  esac
  [[ ! -e $home/.local ]]
  [[ ! -e $home/.config ]]
done

zsh_home=$TEMP_ROOT/zsh
mkdir -p "$zsh_home"
printf '%s\n' '# retained zprofile' >"$zsh_home/.zprofile"
printf '%s\n' '# retained zshrc' >"$zsh_home/.zshrc"
chmod 0600 "$zsh_home/.zprofile" "$zsh_home/.zshrc"
run_bootstrap "$zsh_home" /bin/zsh --configure-shell >/dev/null
assert_contains "$zsh_home/.zprofile" '# retained zprofile'
assert_contains "$zsh_home/.zprofile" '# >>> aws-metadata-agent PATH >>>'
assert_contains "$zsh_home/.zshrc" '# retained zshrc'
assert_contains "$zsh_home/.zshrc" 'aws-runas-zsh-completion'
[[ $(file_mode "$zsh_home/.zprofile") == 600 ]]
[[ $(file_mode "$zsh_home/.zshrc") == 600 ]]
zsh_before=$(hash_files "$zsh_home/.zprofile" "$zsh_home/.zshrc")
run_bootstrap "$zsh_home" /bin/zsh --configure-shell >/dev/null
zsh_after=$(hash_files "$zsh_home/.zprofile" "$zsh_home/.zshrc")
[[ $zsh_before == "$zsh_after" ]]
assert_count "$zsh_home/.zprofile" 1 '# >>> aws-metadata-agent PATH >>>'
assert_count "$zsh_home/.zshrc" 1 '# >>> aws-metadata-agent aws-runas completion >>>'

bash_home=$TEMP_ROOT/bash
mkdir -p "$bash_home"
if [[ $fake_platform == darwin ]]; then
  bash_startup=$bash_home/.bash_profile
else
  bash_startup=$bash_home/.bashrc
fi
printf '%s\n' '# retained Bash content' '# custom aws-runas setup' >"$bash_startup"
chmod 0640 "$bash_startup"
bash_output=$(run_bootstrap "$bash_home" /bin/bash --configure-shell 2>&1)
[[ $bash_output == *'Existing unmanaged aws-runas configuration'* ]]
assert_contains "$bash_startup" '# retained Bash content'
assert_contains "$bash_startup" '# custom aws-runas setup'
assert_contains "$bash_startup" 'aws-runas-bash-completion'
[[ $(file_mode "$bash_startup") == 640 ]]
HOME=$bash_home bash --noprofile --norc -c \
  'source "$1"; complete -p aws-runas >/dev/null' bash "$bash_startup"
bash_before=$(hash_files "$bash_startup")
run_bootstrap "$bash_home" /bin/bash --configure-shell >/dev/null 2>&1
bash_after=$(hash_files "$bash_startup")
[[ $bash_before == "$bash_after" ]]
assert_count "$bash_startup" 1 '# >>> aws-metadata-agent PATH >>>'
assert_count "$bash_startup" 1 '# >>> aws-metadata-agent aws-runas completion >>>'

fish_home=$TEMP_ROOT/fish
fish_config_home=$fish_home/xdg
fish_path_file=$fish_config_home/fish/conf.d/aws-metadata-agent.fish
fish_completion=$fish_config_home/fish/completions/aws-runas.fish
mkdir -p "$(dirname "$fish_path_file")" "$(dirname "$fish_completion")"
printf '%s\n' '# retained fish PATH content' >"$fish_path_file"
printf '%s\n' '# retained custom aws-runas completion' >"$fish_completion"
chmod 0600 "$fish_path_file" "$fish_completion"
fish_output=$(env XDG_CONFIG_HOME="$fish_config_home" \
  HOME="$fish_home" SHELL=/opt/homebrew/bin/fish \
  PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  AWS_RUNAS_INSTALL_DIR="$fish_home/.local/bin" \
  "$PROJECT_DIR/bootstrap.sh" --configure-shell 2>&1)
[[ $fish_output == *'Existing unmanaged aws-runas configuration'* ]]
assert_contains "$fish_path_file" '# retained fish PATH content'
assert_contains "$fish_path_file" 'fish_add_path --path'
assert_contains "$fish_completion" '# retained custom aws-runas completion'
assert_contains "$fish_completion" 'function __fish_aws_runas_complete'
assert_contains "$fish_completion" '--generate-bash-completion'
[[ $(file_mode "$fish_path_file") == 600 ]]
[[ $(file_mode "$fish_completion") == 600 ]]
fish_before=$(hash_files "$fish_path_file" "$fish_completion")
env XDG_CONFIG_HOME="$fish_config_home" \
  HOME="$fish_home" SHELL=/opt/homebrew/bin/fish \
  PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  AWS_RUNAS_INSTALL_DIR="$fish_home/.local/bin" \
  "$PROJECT_DIR/bootstrap.sh" --configure-shell >/dev/null 2>&1
fish_after=$(hash_files "$fish_path_file" "$fish_completion")
[[ $fish_before == "$fish_after" ]]
assert_count "$fish_path_file" 1 '# >>> aws-metadata-agent PATH >>>'
assert_count "$fish_completion" 1 '# >>> aws-metadata-agent aws-runas completion >>>'

unsupported_home=$TEMP_ROOT/unsupported
mkdir -p "$unsupported_home"
printf '%s\n' 'retained' >"$unsupported_home/.profile"
unsupported_output=$(run_bootstrap \
  "$unsupported_home" /bin/tcsh --configure-shell 2>&1)
[[ $unsupported_output == *'Unsupported login shell /bin/tcsh'* ]]
[[ $(<"$unsupported_home/.profile") == retained ]]
[[ -x $unsupported_home/.local/bin/aws-runas ]]
[[ ! -e $unsupported_home/.zshrc ]]
[[ ! -e $unsupported_home/.bashrc ]]
[[ ! -e $unsupported_home/.config ]]

no_config_home=$TEMP_ROOT/no-config
mkdir -p "$no_config_home"
run_bootstrap "$no_config_home" /bin/bash >/dev/null
[[ -x $no_config_home/.local/bin/aws-runas ]]
[[ ! -e $no_config_home/.bashrc ]]
[[ ! -e $no_config_home/.bash_profile ]]

bad_home=$TEMP_ROOT/bad-completion
mkdir -p "$bad_home"
if FAKE_BAD_COMPLETION=true run_bootstrap \
  "$bad_home" /bin/bash --configure-shell >/dev/null 2>&1; then
  printf '%s\n' 'Bootstrap accepted an unreviewed Bash completion checksum.' >&2
  exit 1
fi
[[ -x $bad_home/.local/bin/aws-runas ]]
[[ ! -e $bad_home/.bashrc ]]
[[ ! -e $bad_home/.bash_profile ]]

printf '%s\n' 'Bootstrap shell configuration tests passed.'
