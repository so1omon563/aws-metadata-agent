#!/usr/bin/env bash

set -eu
set -o pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly PROJECT_DIR
readonly UPSTREAM_REPOSITORY=https://github.com/mmmorris1975/aws-runas
version=${AWS_RUNAS_VERSION:-3.9.0}
install_dir=${AWS_RUNAS_INSTALL_DIR:-${HOME}/.local/bin}
fish_completion_source=${AWS_RUNAS_FISH_COMPLETION_SOURCE:-$PROJECT_DIR/completions/aws-runas.fish}
dry_run=false
configure_shell=false

replace_managed_block() {
  local file=$1
  local start_marker=$2
  local end_marker=$3
  local content=$4
  local file_dir temporary_file file_mode symlink_target

  while [[ -L $file ]]; do
    symlink_target=$(readlink "$file")
    if [[ $symlink_target == /* ]]; then
      file=$symlink_target
    else
      file=$(dirname "$file")/$symlink_target
    fi
  done

  file_dir=$(dirname "$file")
  mkdir -p "$file_dir"
  temporary_file=$(mktemp "${file}.XXXXXX")

  if [[ -f $file ]]; then
    awk -v start="$start_marker" -v end="$end_marker" '
      $0 == start { skipping = 1; next }
      $0 == end { skipping = 0; next }
      !skipping { print }
    ' "$file" >"$temporary_file"
    case $(uname -s) in
      Darwin) file_mode=$(stat -f '%Lp' "$file") ;;
      *) file_mode=$(stat -c '%a' "$file") ;;
    esac
    chmod "$file_mode" "$temporary_file"
  else
    chmod 0644 "$temporary_file"
  fi

  printf '%s\n%s\n%s\n' \
    "$start_marker" "$content" "$end_marker" >>"$temporary_file"
  mv "$temporary_file" "$file"
}

detect_login_shell() {
  case ${SHELL:-} in
    */zsh|zsh) printf '%s' zsh ;;
    */bash|bash) printf '%s' bash ;;
    */fish|fish) printf '%s' fish ;;
    *) printf '%s' unsupported ;;
  esac
}

checksum_file() {
  if [[ $checksum_command == sha256sum ]]; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

reviewed_upstream_completion_checksum() {
  local shell_name=$1

  case "$version:$shell_name" in
    3.9.0:bash)
      printf '%s' 0d5b208644aa53e55a7200cab9fc82db7be8334b8e803f58f7db77db55ab370e
      ;;
    3.9.0:zsh)
      printf '%s' ef28853bfd267e09f4eb3b2335581294ad12099daa4a27fe3290e76259f16dec
      ;;
    *)
      printf 'No reviewed %s completion checksum is recorded for aws-runas %s.\n' \
        "$shell_name" "$version" >&2
      printf '%s\n' \
        'The binary was installed, but shell completion was not configured.' >&2
      return 1
      ;;
  esac
}

install_upstream_completion() {
  local shell_name=$1
  local completion_path=$2
  local completion_name completion_url completion_download
  local completion_checksum completion_expected_checksum

  completion_name=aws-runas-${shell_name}-completion
  completion_url="https://raw.githubusercontent.com/mmmorris1975/aws-runas/${version}/extras/${completion_name}"
  completion_download=$temporary_dir/$completion_name

  curl --proto '=https' --tlsv1.2 --fail --location --show-error --silent \
    --output "$completion_download" "$completion_url"
  case $shell_name in
    bash)
      if [[ ! -s $completion_download ]] || \
         ! grep -q '_cli_bash_autocomplete' "$completion_download" || \
         ! grep -q 'complete .*_cli_bash_autocomplete' "$completion_download"; then
        printf '%s\n' 'The upstream Bash completion file failed validation.' >&2
        return 1
      fi
      ;;
    zsh)
      if [[ ! -s $completion_download ]] || \
         ! grep -q 'compdef.*PROG' "$completion_download"; then
        printf '%s\n' 'The upstream zsh completion file failed validation.' >&2
        return 1
      fi
      ;;
  esac

  completion_expected_checksum=$(
    reviewed_upstream_completion_checksum "$shell_name"
  ) || return
  completion_checksum=$(checksum_file "$completion_download")
  if [[ $completion_checksum != "$completion_expected_checksum" ]]; then
    printf 'The upstream %s completion checksum did not match; refusing to source it.\n' \
      "$shell_name" >&2
    return 1
  fi

  install -d -m 0755 "$(dirname "$completion_path")"
  install -m 0644 "$completion_download" "$completion_path"
}

review_fish_completion() {
  local expected_checksum actual_checksum

  case $version in
    3.9.0)
      expected_checksum=e130bc795ccc2d54e11070ec965523a2b6d24a527c36bb0ae192f8d6e3d23db2
      ;;
    *)
      printf 'No reviewed native fish completion is recorded for aws-runas %s.\n' \
        "$version" >&2
      printf '%s\n' \
        'The binary was installed, but shell completion was not configured.' >&2
      return 1
      ;;
  esac
  if [[ ! -f $fish_completion_source || -L $fish_completion_source ]]; then
    printf 'The reviewed native fish completion is missing at %s.\n' \
      "$fish_completion_source" >&2
    return 1
  fi
  actual_checksum=$(checksum_file "$fish_completion_source")
  if [[ $actual_checksum != "$expected_checksum" ]]; then
    printf '%s\n' \
      'The native fish completion checksum did not match the reviewed source.' >&2
    return 1
  fi
}

posix_path_line() {
  local install_relative

  install_relative=${install_dir#"$HOME"}
  if [[ $install_dir == "$HOME"/* ]]; then
    # $HOME and $PATH are intentionally written literally for future sessions.
    # shellcheck disable=SC2016
    printf 'export PATH="$HOME"%q:"$PATH"' "$install_relative"
  else
    # $PATH is intentionally written literally for future sessions.
    # shellcheck disable=SC2016
    printf 'export PATH=%q:"$PATH"' "$install_dir"
  fi
}

fish_quote() {
  local value=$1

  value=${value//\\/\\\\}
  value=${value//\'/\\\'}
  printf "'%s'" "$value"
}

warn_unmanaged_completion() {
  local file=$1
  local marker=$2
  local display_path=$3

  if [[ -f $file ]] && grep -q 'aws-runas' "$file" && \
     ! grep -Fq "$marker" "$file"; then
    printf 'WARNING: Existing unmanaged aws-runas configuration was found in %s.\n' \
      "$display_path" >&2
    printf '%s\n' \
      'It was preserved; review it to avoid loading completion twice.' >&2
  fi
}

bash_startup_file() {
  local candidate

  if [[ $platform == darwin ]]; then
    for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
      if [[ -e $candidate || -L $candidate ]]; then
        printf '%s' "$candidate"
        return
      fi
    done
    printf '%s' "$HOME/.bash_profile"
  else
    printf '%s' "$HOME/.bashrc"
  fi
}

configure_zsh() {
  local completion_path completion_relative path_line completion_block
  local path_start path_end completion_start completion_end

  completion_path=$HOME/.local/share/aws-runas/aws-runas-zsh-completion
  install_upstream_completion zsh "$completion_path"
  path_line=$(posix_path_line)
  completion_relative=${completion_path#"$HOME"}
  # $HOME is intentionally written literally for future sessions.
  # shellcheck disable=SC2016
  printf -v completion_block \
    'if [[ -r "$HOME"%q ]]; then\n  PROG=aws-runas\n  _CLI_ZSH_AUTOCOMPLETE_HACK=1\n  source "$HOME"%q\nfi' \
    "$completion_relative" "$completion_relative"

  path_start='# >>> aws-metadata-agent PATH >>>'
  path_end='# <<< aws-metadata-agent PATH <<<'
  completion_start='# >>> aws-metadata-agent aws-runas completion >>>'
  completion_end='# <<< aws-metadata-agent aws-runas completion <<<'
  warn_unmanaged_completion \
    "$HOME/.zshrc" "$completion_start" "$HOME/.zshrc"
  replace_managed_block "$HOME/.zprofile" "$path_start" "$path_end" "$path_line"
  replace_managed_block \
    "$HOME/.zshrc" "$completion_start" "$completion_end" "$completion_block"

  printf 'Configured zsh PATH in %s.\n' "$HOME/.zprofile"
  printf 'Installed and configured zsh completion at %s.\n' "$completion_path"
  printf '%s\n' 'Open a new zsh session to load the changes.'
}

configure_bash() {
  local startup_file completion_path completion_relative
  local path_line completion_block path_start path_end
  local completion_start completion_end

  startup_file=$(bash_startup_file)
  completion_path=$HOME/.local/share/aws-runas/aws-runas-bash-completion
  install_upstream_completion bash "$completion_path"
  path_line=$(posix_path_line)
  completion_relative=${completion_path#"$HOME"}
  # $HOME is intentionally written literally for future sessions.
  # shellcheck disable=SC2016
  printf -v completion_block \
    'if [[ -r "$HOME"%q ]]; then\n  PROG=aws-runas\n  source "$HOME"%q\nfi' \
    "$completion_relative" "$completion_relative"

  path_start='# >>> aws-metadata-agent PATH >>>'
  path_end='# <<< aws-metadata-agent PATH <<<'
  completion_start='# >>> aws-metadata-agent aws-runas completion >>>'
  completion_end='# <<< aws-metadata-agent aws-runas completion <<<'
  warn_unmanaged_completion \
    "$startup_file" "$completion_start" "${startup_file#"$HOME"/}"
  replace_managed_block "$startup_file" "$path_start" "$path_end" "$path_line"
  replace_managed_block \
    "$startup_file" "$completion_start" "$completion_end" "$completion_block"

  printf 'Configured Bash PATH and completion in %s.\n' "$startup_file"
  printf 'Installed verified upstream Bash completion at %s.\n' "$completion_path"
  printf '%s\n' 'Open a new Bash session to load the changes.'
}

configure_fish() {
  local fish_config_dir path_file completion_path
  local path_line completion_block path_start path_end
  local completion_start completion_end

  fish_config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/fish
  path_file=$fish_config_dir/conf.d/aws-metadata-agent.fish
  completion_path=$fish_config_dir/completions/aws-runas.fish
  review_fish_completion
  path_line="fish_add_path --path $(fish_quote "$install_dir")"
  completion_block=$(<"$fish_completion_source")

  path_start='# >>> aws-metadata-agent PATH >>>'
  path_end='# <<< aws-metadata-agent PATH <<<'
  completion_start='# >>> aws-metadata-agent aws-runas completion >>>'
  completion_end='# <<< aws-metadata-agent aws-runas completion <<<'
  warn_unmanaged_completion \
    "$path_file" "$path_start" "${path_file#"$HOME"/}"
  warn_unmanaged_completion \
    "$completion_path" "$completion_start" "${completion_path#"$HOME"/}"
  replace_managed_block "$path_file" "$path_start" "$path_end" "$path_line"
  replace_managed_block \
    "$completion_path" "$completion_start" "$completion_end" "$completion_block"

  printf 'Configured fish PATH in %s.\n' "$path_file"
  printf 'Installed native fish completion at %s.\n' "$completion_path"
  printf '%s\n' 'Open a new fish session to load the changes.'
}

configure_selected_shell() {
  case $selected_shell in
    zsh) configure_zsh ;;
    bash) configure_bash ;;
    fish) configure_fish ;;
    *)
      printf 'Unsupported login shell %s; shell files were not modified.\n' \
        "${SHELL:-unset}" >&2
      ;;
  esac
}

print_shell_dry_run() {
  local startup_file fish_config_dir

  printf 'Shell: %s (%s)\n' "$selected_shell" "${SHELL:-unset}"
  case $selected_shell in
    zsh)
      printf 'Zsh PATH: %s/.zprofile\n' "$HOME"
      printf 'Zsh completion config: %s/.zshrc\n' "$HOME"
      printf 'Zsh completion file: %s/.local/share/aws-runas/aws-runas-zsh-completion\n' \
        "$HOME"
      printf 'Zsh completion source: %s\n' \
        "https://raw.githubusercontent.com/mmmorris1975/aws-runas/${version}/extras/aws-runas-zsh-completion"
      ;;
    bash)
      startup_file=$(bash_startup_file)
      printf 'Bash PATH and completion config: %s\n' "$startup_file"
      printf 'Bash completion file: %s/.local/share/aws-runas/aws-runas-bash-completion\n' \
        "$HOME"
      printf 'Bash completion source: %s\n' \
        "https://raw.githubusercontent.com/mmmorris1975/aws-runas/${version}/extras/aws-runas-bash-completion"
      ;;
    fish)
      fish_config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/fish
      printf 'Fish PATH config: %s/conf.d/aws-metadata-agent.fish\n' \
        "$fish_config_dir"
      printf 'Fish completion file: %s/completions/aws-runas.fish\n' \
        "$fish_config_dir"
      printf 'Fish completion source: %s\n' "$fish_completion_source"
      ;;
    *)
      printf '%s\n' 'Shell files: unchanged (unsupported login shell)'
      ;;
  esac
}

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [--version VERSION] [--install-dir DIRECTORY]
                      [--configure-shell] [--dry-run]

Downloads aws-runas directly from the upstream GitHub release, verifies the
archive against the upstream SHA-256 checksum file, and installs the binary.
With --configure-shell, it configures PATH and reviewed completion for the
current zsh, Bash, or fish login shell.

Defaults:
  version:     3.9.0
  install-dir: ~/.local/bin

This project is not affiliated with or endorsed by the aws-runas author.
aws-runas is Copyright (c) 2017 Mike Morris and licensed under the MIT License.
EOF
}

while (($#)); do
  case $1 in
    --version)
      shift
      version=${1:?--version requires a value}
      ;;
    --install-dir)
      shift
      install_dir=${1:?--install-dir requires a value}
      ;;
    --dry-run)
      dry_run=true
      ;;
    --configure-shell)
      configure_shell=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Invalid aws-runas version: %s\n' "$version" >&2
  exit 2
fi

case $(uname -s) in
  Darwin) platform=darwin ;;
  Linux) platform=linux ;;
  *)
    printf '%s\n' 'Only macOS and Linux are supported.' >&2
    exit 2
    ;;
esac

selected_shell=$(detect_login_shell)

case $(uname -m) in
  x86_64|amd64) architecture=amd64 ;;
  arm64|aarch64) architecture=arm64 ;;
  armv6l|armv7l)
    if [[ $platform != linux ]]; then
      printf 'Unsupported architecture on %s: %s\n' "$platform" "$(uname -m)" >&2
      exit 2
    fi
    architecture=arm
    ;;
  *)
    printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2
    exit 2
    ;;
esac

archive_name="aws-runas-${version}-${platform}-${architecture}.zip"
checksum_name="aws-runas_${version}.sha256sum"
release_url="${UPSTREAM_REPOSITORY}/releases/download/${version}"
archive_url="${release_url}/${archive_name}"
checksum_url="${release_url}/${checksum_name}"

if [[ $dry_run == true ]]; then
  printf 'Upstream: %s\n' "$UPSTREAM_REPOSITORY"
  printf 'Archive: %s\n' "$archive_url"
  printf 'Checksums: %s\n' "$checksum_url"
  printf 'Install: %s/aws-runas\n' "$install_dir"
  if [[ $configure_shell == true ]]; then
    print_shell_dry_run
  else
    printf '%s\n' \
      'Optional: rerun with --configure-shell to configure zsh, Bash, or fish.'
    printf '%s\n' \
      'Preview it first with: ./bootstrap.sh --configure-shell --dry-run'
  fi
  exit 0
fi

for dependency in curl unzip; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$dependency" >&2
    exit 2
  fi
done

if command -v sha256sum >/dev/null 2>&1; then
  checksum_command=sha256sum
elif command -v shasum >/dev/null 2>&1; then
  checksum_command=shasum
else
  printf '%s\n' 'A SHA-256 utility is required: sha256sum or shasum.' >&2
  exit 2
fi

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/aws-runas-bootstrap.XXXXXX")
trap 'rm -rf "$temporary_dir"' EXIT
archive_path="$temporary_dir/$archive_name"
checksum_path="$temporary_dir/$checksum_name"
extract_dir="$temporary_dir/extract"

printf 'Downloading %s from upstream...\n' "$archive_name"
curl --proto '=https' --tlsv1.2 --fail --location --show-error --silent \
  --output "$archive_path" "$archive_url"
curl --proto '=https' --tlsv1.2 --fail --location --show-error --silent \
  --output "$checksum_path" "$checksum_url"

expected_checksum=$(awk -v name="$archive_name" '$2 == name {print $1}' "$checksum_path")
if [[ ! $expected_checksum =~ ^[0-9a-fA-F]{64}$ ]]; then
  printf 'The upstream checksum file has no valid entry for %s.\n' \
    "$archive_name" >&2
  exit 1
fi

if [[ $checksum_command == sha256sum ]]; then
  actual_checksum=$(sha256sum "$archive_path" | awk '{print $1}')
else
  actual_checksum=$(shasum -a 256 "$archive_path" | awk '{print $1}')
fi

actual_checksum=$(printf '%s' "$actual_checksum" | tr '[:upper:]' '[:lower:]')
expected_checksum=$(printf '%s' "$expected_checksum" | tr '[:upper:]' '[:lower:]')
if [[ $actual_checksum != "$expected_checksum" ]]; then
  printf '%s\n' 'SHA-256 verification failed; refusing to install aws-runas.' >&2
  printf 'Expected: %s\nActual:   %s\n' "$expected_checksum" "$actual_checksum" >&2
  exit 1
fi
printf 'Verified SHA-256: %s\n' "$actual_checksum"

mkdir -p "$extract_dir"
unzip -q "$archive_path" -d "$extract_dir"
binary_path="$extract_dir/aws-runas"
if [[ ! -f $binary_path || -L $binary_path ]]; then
  printf '%s\n' 'The verified archive did not contain a regular aws-runas binary.' >&2
  exit 1
fi

install_parent=$(dirname "$install_dir")
if [[ -d $install_dir && -w $install_dir ]]; then
  install -m 0755 "$binary_path" "$install_dir/aws-runas"
elif [[ ! -e $install_dir ]]; then
  if [[ (-d $install_parent && -w $install_parent) || \
        ($install_dir == "$HOME"/* && -w $HOME) ]]; then
    install -d -m 0755 "$install_dir"
    install -m 0755 "$binary_path" "$install_dir/aws-runas"
  else
    printf 'Administrator access is required to install into %s.\n' "$install_dir"
    sudo install -d -m 0755 "$install_dir"
    sudo install -m 0755 "$binary_path" "$install_dir/aws-runas"
  fi
else
  printf 'Administrator access is required to install into %s.\n' "$install_dir"
  sudo install -d -m 0755 "$install_dir"
  sudo install -m 0755 "$binary_path" "$install_dir/aws-runas"
fi

printf 'Installed upstream aws-runas %s at %s/aws-runas.\n' \
  "$version" "$install_dir"
printf 'Source: %s\n' "$UPSTREAM_REPOSITORY"
printf '%s\n' 'License: MIT; see THIRD_PARTY_NOTICES.md'

duplicate_found=false
for candidate in \
  /usr/local/bin/aws-runas \
  /opt/homebrew/bin/aws-runas \
  "$HOME/bin/aws-runas"; do
  if [[ -x $candidate && $candidate != "$install_dir/aws-runas" ]]; then
    if [[ $duplicate_found == false ]]; then
      printf '\n%s\n' 'WARNING: Additional aws-runas executables were found:' >&2
      duplicate_found=true
    fi
    printf '  %s\n' "$candidate" >&2
  fi
done
if [[ $duplicate_found == true ]]; then
  printf '%s\n' 'PATH order determines which version runs.' >&2
fi

if [[ $configure_shell == true ]]; then
  configure_selected_shell
else
  printf '\n%s\n' \
    'Optional shell setup: rerun with --configure-shell for zsh, Bash, or fish.'
  printf '%s\n' \
    'Preview it first with: ./bootstrap.sh --configure-shell --dry-run'
fi

case :${PATH}: in
  *:"$install_dir":*) ;;
  *)
    if [[ $configure_shell != true ]]; then
      printf '\n%s is not currently in PATH.\n' "$install_dir"
      case $selected_shell in
        zsh)
          printf '%s\n' 'For zsh, add this line to ~/.zprofile:'
          # $PATH is intentionally printed for the user's shell to expand later.
          # shellcheck disable=SC2016
          printf '  export PATH="%s:$PATH"\n' "$install_dir"
          ;;
        bash)
          printf 'For Bash, add this line to %s:\n' "$(bash_startup_file)"
          # $PATH is intentionally printed for the user's shell to expand later.
          # shellcheck disable=SC2016
          printf '  export PATH="%s:$PATH"\n' "$install_dir"
          ;;
        fish)
          printf '%s\n' 'For fish, run:'
          printf '  fish_add_path --path %s\n' "$(fish_quote "$install_dir")"
          ;;
        *)
          printf '%s\n' \
            'Add that directory to PATH in the login shell configuration.'
          ;;
      esac
    fi
    ;;
esac
