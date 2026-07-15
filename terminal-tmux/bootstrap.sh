#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=versions.lock
source "$DOTFILES_DIR/versions.lock"

export PATH="$HOME/.local/bin:$PATH"

log() {
  printf '==> %s\n' "$*"
}

fail() {
  printf 'terminal-dotfiles: %s\n' "$*" >&2
  exit 1
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

verify_sha256() {
  local file=$1 expected=$2 actual
  actual=$(sha256_file "$file")
  [[ "$actual" == "$expected" ]] || fail "checksum mismatch for $file: expected $expected, got $actual"
}

download() {
  local url=$1 destination=$2
  curl -fL --retry 3 --connect-timeout 15 "$url" -o "$destination"
}

run_as_root() {
  if [[ $(id -u) -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    fail "root access or sudo is required to install apt prerequisites"
  fi
}

tmux_is_locked_version() {
  command -v tmux >/dev/null 2>&1 && [[ $(tmux -V) == "tmux $TMUX_VERSION" ]]
}

lazygit_is_locked_version() {
  command -v lazygit >/dev/null 2>&1 && lazygit --version 2>/dev/null | grep -q "version=$LAZYGIT_VERSION"
}

delta_is_locked_version() {
  command -v delta >/dev/null 2>&1 && [[ $(delta --version 2>/dev/null) == "delta $DELTA_VERSION" ]]
}

detect_platform() {
  case "$(uname -s)" in
    Darwin) PLATFORM_OS=darwin ;;
    Linux) PLATFORM_OS=linux ;;
    *) fail "unsupported operating system: $(uname -s)" ;;
  esac

  case "$(uname -m)" in
    arm64|aarch64) PLATFORM_ARCH=arm64 ;;
    x86_64|amd64) PLATFORM_ARCH=x86_64 ;;
    *) fail "unsupported CPU architecture: $(uname -m)" ;;
  esac
}

install_prerequisites() {
  if [[ "$PLATFORM_OS" == linux ]]; then
    command -v apt-get >/dev/null 2>&1 || fail "Linux bootstrap currently requires a Debian/Ubuntu apt host"
    log "Installing Debian/Ubuntu prerequisites with apt"
    run_as_root apt-get update
    run_as_root apt-get install -y \
      bash bison ca-certificates curl gcc git make ncurses-bin pkg-config tar zsh \
      libevent-dev libncurses-dev libutf8proc-dev
  else
    command -v brew >/dev/null 2>&1 || fail "Homebrew is required on macOS"
    local packages=(bash bison curl git libevent ncurses pkgconf utf8proc zsh)
    log "Installing macOS prerequisites with Homebrew"
    brew install "${packages[@]}"
  fi
}

install_tmux() {
  tmux_is_locked_version && return 0

  local work archive source_dir configure_env
  work=$(mktemp -d)
  archive="$work/tmux-$TMUX_VERSION.tar.gz"
  trap 'rm -rf "$work"' RETURN

  log "Installing tmux $TMUX_VERSION into $HOME/.local"
  download "https://github.com/tmux/tmux/releases/download/$TMUX_VERSION/tmux-$TMUX_VERSION.tar.gz" "$archive"
  verify_sha256 "$archive" "$TMUX_SHA256"
  tar -xzf "$archive" -C "$work"
  source_dir="$work/tmux-$TMUX_VERSION"

  if [[ "$PLATFORM_OS" == darwin ]]; then
    configure_env="$(brew --prefix libevent)/lib/pkgconfig:$(brew --prefix ncurses)/lib/pkgconfig:$(brew --prefix utf8proc)/lib/pkgconfig"
    (
      cd "$source_dir"
      PKG_CONFIG_PATH="$configure_env" ./configure --prefix="$HOME/.local" --enable-utf8proc
      make -j "$(sysctl -n hw.ncpu)"
      make install
    )
  else
    (
      cd "$source_dir"
      ./configure --prefix="$HOME/.local" --enable-utf8proc
      make -j "$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2')"
      make install
    )
  fi

  mkdir -p "$HOME/.terminfo"
  tic -x -o "$HOME/.terminfo" "$source_dir/tmux.terminfo"
  trap - RETURN
  rm -rf "$work"
  tmux_is_locked_version || fail "tmux $TMUX_VERSION installation verification failed"
}

lazygit_asset() {
  case "$PLATFORM_OS/$PLATFORM_ARCH" in
    darwin/arm64)
      ASSET="lazygit_${LAZYGIT_VERSION}_darwin_arm64.tar.gz"
      ASSET_SHA256=$LAZYGIT_SHA256_DARWIN_ARM64
      ;;
    darwin/x86_64)
      ASSET="lazygit_${LAZYGIT_VERSION}_darwin_x86_64.tar.gz"
      ASSET_SHA256=$LAZYGIT_SHA256_DARWIN_X86_64
      ;;
    linux/arm64)
      ASSET="lazygit_${LAZYGIT_VERSION}_linux_arm64.tar.gz"
      ASSET_SHA256=$LAZYGIT_SHA256_LINUX_ARM64
      ;;
    linux/x86_64)
      ASSET="lazygit_${LAZYGIT_VERSION}_linux_x86_64.tar.gz"
      ASSET_SHA256=$LAZYGIT_SHA256_LINUX_X86_64
      ;;
  esac
}

install_lazygit() {
  lazygit_is_locked_version && return 0

  local work archive binary
  lazygit_asset
  work=$(mktemp -d)
  archive="$work/$ASSET"
  trap 'rm -rf "$work"' RETURN

  log "Installing lazygit $LAZYGIT_VERSION into $HOME/.local/bin"
  download "https://github.com/jesseduffield/lazygit/releases/download/v$LAZYGIT_VERSION/$ASSET" "$archive"
  verify_sha256 "$archive" "$ASSET_SHA256"
  tar -xzf "$archive" -C "$work"
  binary=$(find "$work" -type f -name lazygit -perm -u+x | head -1)
  [[ -n "$binary" ]] || fail "lazygit binary not found in $ASSET"
  install -m 0755 "$binary" "$HOME/.local/bin/lazygit"

  trap - RETURN
  rm -rf "$work"
  lazygit_is_locked_version || fail "lazygit $LAZYGIT_VERSION installation verification failed"
}

delta_asset() {
  case "$PLATFORM_OS/$PLATFORM_ARCH" in
    darwin/arm64)
      ASSET="delta-$DELTA_VERSION-aarch64-apple-darwin.tar.gz"
      ASSET_SHA256=$DELTA_SHA256_DARWIN_ARM64
      ;;
    darwin/x86_64)
      fail "delta $DELTA_VERSION has no official Darwin x86_64 release asset"
      ;;
    linux/arm64)
      ASSET="delta-$DELTA_VERSION-aarch64-unknown-linux-gnu.tar.gz"
      ASSET_SHA256=$DELTA_SHA256_LINUX_ARM64
      ;;
    linux/x86_64)
      ASSET="delta-$DELTA_VERSION-x86_64-unknown-linux-gnu.tar.gz"
      ASSET_SHA256=$DELTA_SHA256_LINUX_X86_64
      ;;
  esac
}

install_delta() {
  delta_is_locked_version && return 0

  local work archive binary
  delta_asset
  work=$(mktemp -d)
  archive="$work/$ASSET"
  trap 'rm -rf "$work"' RETURN

  log "Installing git-delta $DELTA_VERSION into $HOME/.local/bin"
  download "https://github.com/dandavison/delta/releases/download/$DELTA_VERSION/$ASSET" "$archive"
  verify_sha256 "$archive" "$ASSET_SHA256"
  tar -xzf "$archive" -C "$work"
  binary=$(find "$work" -type f -name delta -perm -u+x | head -1)
  [[ -n "$binary" ]] || fail "delta binary not found in $ASSET"
  install -m 0755 "$binary" "$HOME/.local/bin/delta"

  trap - RETURN
  rm -rf "$work"
  delta_is_locked_version || fail "git-delta $DELTA_VERSION installation verification failed"
}

backup_and_link() {
  local source=$1 destination=$2 backup
  mkdir -p "$(dirname "$destination")"

  if [[ -L "$destination" && $(readlink "$destination") == "$source" ]]; then
    return 0
  fi

  if [[ -e "$destination" || -L "$destination" ]]; then
    backup="$destination.backup.$(date +%Y%m%d%H%M%S)"
    log "Backing up $destination to $backup"
    mv "$destination" "$backup"
  fi

  ln -s "$source" "$destination"
}

install_plugin() {
  local name=$1 repository=$2 commit=$3 destination="$HOME/.tmux/plugins/$name"
  mkdir -p "$HOME/.tmux/plugins"

  if [[ ! -d "$destination/.git" ]]; then
    git clone "$repository" "$destination"
  fi

  [[ -z $(git -C "$destination" status --porcelain) ]] || fail "plugin $name has local changes"
  if [[ $(git -C "$destination" rev-parse HEAD) != "$commit" ]]; then
    git -C "$destination" fetch --tags origin
    git -C "$destination" checkout --detach "$commit"
  fi
  [[ $(git -C "$destination" rev-parse HEAD) == "$commit" ]] || fail "plugin $name commit verification failed"
}

install_links() {
  backup_and_link "$DOTFILES_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"
  backup_and_link "$DOTFILES_DIR/tmux/session-status-counts.sh" "$HOME/.tmux/session-status-counts.sh"
  backup_and_link "$DOTFILES_DIR/bin/tmux-zsh" "$HOME/.local/bin/tmux-zsh"
  backup_and_link "$DOTFILES_DIR/shell/tmux-window-name.zsh" "$HOME/.config/tmux/window-name.zsh"
  backup_and_link "$DOTFILES_DIR/codex/notify-tmux.sh" "$HOME/.codex/hooks/notify-tmux.sh"
  backup_and_link "$DOTFILES_DIR/codex/hooks.json" "$HOME/.codex/hooks.json"

  local lazygit_config_dir
  lazygit_config_dir=$(lazygit --print-config-dir)
  backup_and_link "$DOTFILES_DIR/lazygit/config.yml" "$lazygit_config_dir/config.yml"
}

ensure_shell_loader() {
  local loader='source "$HOME/.config/tmux/window-name.zsh"'
  touch "$HOME/.zshrc"
  if ! grep -Fqx "$loader" "$HOME/.zshrc"; then
    {
      printf '\n%s\n' '# terminal-dotfiles: portable tmux window naming'
      printf '%s\n' "$loader"
    } >> "$HOME/.zshrc"
  fi
}

ensure_profile_path() {
  local path_line='export PATH="$HOME/.local/bin:$PATH"'
  touch "$HOME/.profile"
  if ! grep -Fqx "$path_line" "$HOME/.profile"; then
    printf '\n%s\n' "$path_line" >> "$HOME/.profile"
  fi
}

validate() {
  log "Validating locked environment"
  tmux_is_locked_version || fail "expected tmux $TMUX_VERSION"
  lazygit_is_locked_version || fail "expected lazygit $LAZYGIT_VERSION"
  delta_is_locked_version || fail "expected git-delta $DELTA_VERSION"
  command -v zsh >/dev/null 2>&1 || fail "zsh is required"
  command -v bash >/dev/null 2>&1 || fail "bash is required"
  command -v git >/dev/null 2>&1 || fail "git is required"
  infocmp tmux-256color >/dev/null 2>&1 || fail "tmux-256color terminfo is missing"
  LC_ALL=C.UTF-8 locale charmap 2>/dev/null | grep -qi 'UTF-8' || fail "C.UTF-8 locale is required"

  zsh -n "$DOTFILES_DIR/shell/tmux-window-name.zsh"
  bash -n "$DOTFILES_DIR/bootstrap.sh"
  bash -n "$DOTFILES_DIR/tmux/session-status-counts.sh"
  bash -n "$DOTFILES_DIR/codex/notify-tmux.sh"

  [[ $(git -C "$HOME/.tmux/plugins/tpm" rev-parse HEAD) == "$TPM_COMMIT" ]] || fail "TPM commit mismatch"
  [[ $(git -C "$HOME/.tmux/plugins/tmux-resurrect" rev-parse HEAD) == "$RESURRECT_COMMIT" ]] || fail "tmux-resurrect commit mismatch"
  [[ $(git -C "$HOME/.tmux/plugins/tmux-continuum" rev-parse HEAD) == "$CONTINUUM_COMMIT" ]] || fail "tmux-continuum commit mismatch"

  tmux -L terminal-dotfiles-check kill-server >/dev/null 2>&1 || true
  tmux -L terminal-dotfiles-check -f "$DOTFILES_DIR/tmux/tmux.conf" new-session -d -s terminal-dotfiles-check
  [[ $(tmux -L terminal-dotfiles-check show-options -gqv @continuum-restore) == off ]] || fail "tmux config validation failed"
  tmux -L terminal-dotfiles-check kill-server

  printf 'tmux.conf sha256: %s\n' "$(sha256_file "$DOTFILES_DIR/tmux/tmux.conf")"
  printf 'lazygit config sha256: %s\n' "$(sha256_file "$DOTFILES_DIR/lazygit/config.yml")"
}

main() {
  detect_platform

  if [[ ${1:-} == --check ]]; then
    validate
    return
  fi

  mkdir -p "$HOME/.local/bin"
  install_prerequisites
  install_tmux
  install_lazygit
  install_delta

  install_plugin tpm https://github.com/tmux-plugins/tpm.git "$TPM_COMMIT"
  install_plugin tmux-resurrect https://github.com/tmux-plugins/tmux-resurrect.git "$RESURRECT_COMMIT"
  install_plugin tmux-continuum https://github.com/tmux-plugins/tmux-continuum.git "$CONTINUUM_COMMIT"

  install_links
  ensure_shell_loader
  ensure_profile_path
  validate

  if tmux list-sessions >/dev/null 2>&1; then
    tmux source-file "$HOME/.tmux.conf"
  fi

  log "Installation complete"
  printf '%s\n' "Connect with: ssh -t <host> 'PATH=\"\$HOME/.local/bin:\$PATH\" exec tmux new-session -A -s main'"
}

main "$@"
