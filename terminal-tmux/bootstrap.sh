#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# macOS + Debian/Ubuntu 可复现安装入口
#
# 默认模式：安装系统依赖、锁定版本工具/插件、刷新配置链接，最后验证。
# --check 模式：只读验证现有安装，不修改文件或安装软件。
#
# 可复现策略：
#   - pre-commit/tmux/lazygit/glab/delta/fzf/zoxide/Yazi 及 shell 插件由 versions.lock 锁定。
#   - 官方 Todoist CLI 和它在 Linux 上使用的 Node.js LTS 由 versions.lock 锁定。
#   - Release 下载包校验 SHA256，Git 插件校验完整 commit。
#   - Codex CLI 与 Iris 始终跟随官方最新稳定版；termscp 和 Fresh 使用各自官方
#     通用安装脚本，这些工具均不锁版本。
#   - 已有目标文件会先备份再链接，不静默覆盖用户配置。
# =============================================================================

DOTFILES_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FRESH_INSTALL_URL=https://raw.githubusercontent.com/sinelaw/fresh/refs/heads/master/scripts/install.sh
TERMSCP_INSTALL_URL=https://termscp.rs/install.sh
IRIS_LATEST_RELEASE_URL=https://github.com/versenilvis/iris/releases/latest/download
# shellcheck source=versions.lock
source "$DOTFILES_DIR/versions.lock"

export PATH="$HOME/.local/bin:$PATH"

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'terminal-tmux: warning: %s\n' "$*" >&2
}

fail() {
  printf 'terminal-tmux: %s\n' "$*" >&2
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

glab_is_locked_version() {
  command -v glab >/dev/null 2>&1 &&
    [[ $(glab --version 2>/dev/null | awk 'NR == 1 {print $2}') == "$GLAB_VERSION" ]]
}

delta_is_locked_version() {
  command -v delta >/dev/null 2>&1 && [[ $(delta --version 2>/dev/null) == "delta $DELTA_VERSION" ]]
}

fzf_is_locked_version() {
  command -v fzf >/dev/null 2>&1 &&
    [[ $(fzf --version 2>/dev/null | awk '{print $1}') == "$FZF_VERSION" ]]
}

zoxide_is_locked_version() {
  command -v zoxide >/dev/null 2>&1 &&
    [[ $(zoxide --version 2>/dev/null | awk '{print $2}') == "$ZOXIDE_VERSION" ]]
}

iris_is_installed() {
  command -v iris >/dev/null 2>&1 &&
    iris version 2>/dev/null | grep -Eq '^iris v?[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$'
}

iris_version() {
  iris version 2>/dev/null | awk 'NR == 1 {sub(/^v/, "", $2); print $2}'
}

iris_version_is_newer() {
  local current=${1#v} candidate=${2#v}
  local current_major current_minor current_patch candidate_major candidate_minor candidate_patch

  [[ $current =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)([-.][0-9A-Za-z.-]+)?$ ]] || return 1
  current_major=${BASH_REMATCH[1]}
  current_minor=${BASH_REMATCH[2]}
  current_patch=${BASH_REMATCH[3]}
  [[ $candidate =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)([-.][0-9A-Za-z.-]+)?$ ]] || return 1
  candidate_major=${BASH_REMATCH[1]}
  candidate_minor=${BASH_REMATCH[2]}
  candidate_patch=${BASH_REMATCH[3]}

  (( 10#$candidate_major > 10#$current_major )) && return 0
  (( 10#$candidate_major < 10#$current_major )) && return 1
  (( 10#$candidate_minor > 10#$current_minor )) && return 0
  (( 10#$candidate_minor < 10#$current_minor )) && return 1
  (( 10#$candidate_patch > 10#$current_patch )) && return 0
  (( 10#$candidate_patch < 10#$current_patch )) && return 1
  [[ $current == *-* && $candidate != *-* ]]
}

glow_is_locked_version() {
  command -v glow >/dev/null 2>&1 &&
    [[ $(glow --version 2>/dev/null | awk '/glow version/{print $3; exit}') == "$GLOW_VERSION" ]]
}

yazi_is_locked_version() {
  command -v yazi >/dev/null 2>&1 &&
    command -v ya >/dev/null 2>&1 &&
    [[ $(yazi --version 2>/dev/null | awk '{print $1, $2}') == "Yazi $YAZI_VERSION" ]] &&
    [[ $(ya --version 2>/dev/null | awk '{print $1, $2}') == "Ya $YAZI_VERSION" ]]
}

codex_is_installed() {
  command -v codex >/dev/null 2>&1 && codex --version 2>/dev/null | grep -Eq '^codex-cli [0-9]'
}

termscp_is_installed() {
  command -v termscp >/dev/null 2>&1 &&
    termscp -v 2>/dev/null | grep -Eq '^termscp v?[0-9]+\.[0-9]+\.[0-9]+'
}

fresh_is_installed() {
  command -v fresh >/dev/null 2>&1 &&
    fresh --version 2>/dev/null | grep -Eq '^fresh [0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$'
}

todoist_cli_is_locked_version() {
  command -v td >/dev/null 2>&1 &&
    [[ $(td --version 2>/dev/null) == "$TODOIST_CLI_VERSION" ]]
}

node_supports_todoist_cli() {
  command -v node >/dev/null 2>&1 &&
    node -e 'process.exit(Number(process.versions.node.split(".")[0]) < 24 ? 1 : 0)' 2>/dev/null
}

npm_supports_todoist_cli() {
  local major
  command -v npm >/dev/null 2>&1 || return 1
  major=$(npm --version 2>/dev/null | cut -d. -f1)
  [[ $major =~ ^[0-9]+$ && $major -ge 11 ]]
}

find_supported_python() {
  local candidate
  for candidate in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1 &&
      "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))' 2>/dev/null; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

druk_is_absent() {
  ! command -v druk >/dev/null 2>&1 &&
    [[ ! -e "$HOME/.druk/bin/druk" ]] &&
    [[ ! -e "$HOME/.local/bin/druk" ]] &&
    [[ ! -d "$HOME/.local/lib/node_modules/druk" ]] &&
    [[ ! -e "$HOME/.config/druk" ]] &&
    [[ ! -e "$HOME/.cache/druk" ]]
}

pre_commit_is_locked_version() {
  local launcher="$HOME/.local/bin/pre-commit"
  local pyz="$HOME/.local/share/pre-commit/pre-commit.pyz"
  [[ -L "$launcher" && $(readlink "$launcher") == "$DOTFILES_DIR/bin/pre-commit" ]] &&
  [[ -r "$pyz" ]] &&
    [[ $(sha256_file "$pyz") == "$PRE_COMMIT_SHA256" ]] &&
    command -v pre-commit >/dev/null 2>&1 &&
    [[ $(pre-commit --version 2>/dev/null) == "pre-commit $PRE_COMMIT_VERSION" ]]
}

# --- 平台检测与系统依赖 -------------------------------------------------
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
  local packages optional_package

  if [[ "$PLATFORM_OS" == linux ]]; then
    command -v apt-get >/dev/null 2>&1 || fail "Linux bootstrap currently requires a Debian/Ubuntu apt host"
    log "Installing Debian/Ubuntu prerequisites with apt"
    run_as_root apt-get update
    packages=(
      bash bison btop bubblewrap ca-certificates curl fd-find ffmpeg file fonts-noto-cjk gcc git imagemagick jq locales make
      ncurses-base ncurses-bin openssh-client p7zip-full passwd pkg-config poppler-utils python3 python3-venv ripgrep tar unzip xz-utils vim zsh
      libevent-dev libncurses-dev libutf8proc-dev
    )
    for optional_package in resvg; do
      if apt-cache show "$optional_package" >/dev/null 2>&1; then
        packages+=("$optional_package")
      else
        log "Skipping unavailable optional apt package: $optional_package"
      fi
    done
    run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
  else
    command -v brew >/dev/null 2>&1 || fail "Homebrew is required on macOS"
    packages=(
      bash bison btop curl git libevent ncurses node pkgconf python utf8proc zsh
      yazi glow ffmpeg-full sevenzip jq poppler fd ripgrep resvg imagemagick-full
      font-maple-mono-nf-cn font-symbols-only-nerd-font
    )
    log "Updating Homebrew"
    brew update
    log "Installing macOS prerequisites with Homebrew"
    brew install "${packages[@]}"
    brew link ffmpeg-full imagemagick-full -f --overwrite
  fi
}

ensure_linux_fd_command() {
  if [[ "$PLATFORM_OS" == linux ]] && ! command -v fd >/dev/null 2>&1; then
    command -v fdfind >/dev/null 2>&1 || fail "fd-find was installed but fdfind is unavailable"
    backup_and_link "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi
}

# Yazi's zoxide picker has nothing to display until the database contains at
# least one directory. Seed a brand-new database with existing common paths;
# never add them again once the user has started building their own history.
seed_zoxide_history() {
  command -v zoxide >/dev/null 2>&1 || return 0

  local directory history
  history=$(zoxide query --list 2>/dev/null || true)
  [[ -z "$history" ]] || return 0

  for directory in "$HOME/Documents" "$HOME/.dotfiles"; do
    if [[ -d "$directory" ]]; then
      log "Seeding zoxide history with $directory"
      zoxide add "$directory"
    fi
  done
}

configure_locale() {
  if [[ "$PLATFORM_OS" == linux ]]; then
    log "Generating zh_CN.UTF-8 locale"
    run_as_root sed -i \
      's/^[#[:space:]]*zh_CN.UTF-8[[:space:]]\+UTF-8/zh_CN.UTF-8 UTF-8/' \
      /etc/locale.gen
    run_as_root locale-gen zh_CN.UTF-8
  fi

  export LANG=zh_CN.UTF-8
  export LC_ALL=zh_CN.UTF-8
}

current_login_shell() {
  local user=$1

  if [[ "$PLATFORM_OS" == darwin ]]; then
    command -v dscl >/dev/null 2>&1 || fail "dscl is required to inspect the macOS login shell"
    dscl . -read "/Users/$user" UserShell | awk '{print $2}'
  else
    command -v getent >/dev/null 2>&1 || fail "getent is required to inspect the Linux login shell"
    getent passwd "$user" | awk -F: '{print $7}'
  fi
}

configure_login_shell() {
  local user zsh_path login_shell
  user=$(id -un)
  zsh_path=$(command -v zsh)
  [[ -n "$zsh_path" ]] || fail "zsh is required"
  login_shell=$(current_login_shell "$user")
  [[ -n "$login_shell" ]] || fail "unable to determine the login shell for $user"
  [[ "$login_shell" == "$zsh_path" ]] && return 0

  command -v chsh >/dev/null 2>&1 || fail "chsh is required to set zsh as the login shell"
  grep -Fxq "$zsh_path" /etc/shells || \
    fail "$zsh_path must be listed in /etc/shells before it can become the login shell"
  log "Setting the login shell for $user to $zsh_path"
  run_as_root chsh -s "$zsh_path" "$user"
}

# --- 锁定版本的用户级 CLI -------------------------------------------------
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

  trap - RETURN
  rm -rf "$work"
  tmux_is_locked_version || fail "tmux $TMUX_VERSION installation verification failed"
}

ensure_tmux_terminfo() {
  if infocmp tmux-256color >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$PLATFORM_OS" == linux ]]; then
    log "Installing tmux-256color terminfo from Debian/Ubuntu ncurses-base"
    run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y ncurses-base
  fi

  infocmp tmux-256color >/dev/null 2>&1 || \
    fail "tmux-256color terminfo is missing after installing ncurses prerequisites"
}

ensure_ghostty_terminfo() {
  local source_file="$DOTFILES_DIR/terminfo/xterm-ghostty.terminfo"

  if infocmp xterm-ghostty >/dev/null 2>&1; then
    return 0
  fi

  command -v tic >/dev/null 2>&1 || fail "tic is required to install xterm-ghostty terminfo"
  [[ -r "$source_file" ]] || fail "Ghostty terminfo source is missing: $source_file"
  log "Installing xterm-ghostty terminfo into $HOME/.terminfo"
  mkdir -p "$HOME/.terminfo"
  tic -x -o "$HOME/.terminfo" "$source_file"
  infocmp xterm-ghostty >/dev/null 2>&1 || \
    fail "xterm-ghostty terminfo is missing after user-level installation"
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

glab_asset() {
  case "$PLATFORM_OS/$PLATFORM_ARCH" in
    darwin/arm64)
      ASSET="glab_${GLAB_VERSION}_darwin_arm64.tar.gz"
      ASSET_SHA256=$GLAB_SHA256_DARWIN_ARM64
      ;;
    darwin/x86_64)
      ASSET="glab_${GLAB_VERSION}_darwin_amd64.tar.gz"
      ASSET_SHA256=$GLAB_SHA256_DARWIN_X86_64
      ;;
    linux/arm64)
      ASSET="glab_${GLAB_VERSION}_linux_arm64.tar.gz"
      ASSET_SHA256=$GLAB_SHA256_LINUX_ARM64
      ;;
    linux/x86_64)
      ASSET="glab_${GLAB_VERSION}_linux_amd64.tar.gz"
      ASSET_SHA256=$GLAB_SHA256_LINUX_X86_64
      ;;
  esac
}

install_glab() {
  glab_is_locked_version && return 0

  local work archive binary
  glab_asset
  work=$(mktemp -d)
  archive="$work/$ASSET"
  trap 'rm -rf "$work"' RETURN

  log "Installing GitLab CLI $GLAB_VERSION into $HOME/.local/bin"
  download \
    "https://gitlab.com/gitlab-org/cli/-/releases/v$GLAB_VERSION/downloads/$ASSET" \
    "$archive"
  verify_sha256 "$archive" "$ASSET_SHA256"
  tar -xzf "$archive" -C "$work"
  binary=$(find "$work" -type f -name glab -perm -u+x | head -1)
  [[ -n "$binary" ]] || fail "glab binary not found in $ASSET"
  install -m 0755 "$binary" "$HOME/.local/bin/glab"
  hash -r

  trap - RETURN
  rm -rf "$work"
  glab_is_locked_version || fail "GitLab CLI $GLAB_VERSION installation verification failed"
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

fzf_asset() {
  case "$PLATFORM_OS/$PLATFORM_ARCH" in
    darwin/arm64)
      ASSET="fzf-${FZF_VERSION}-darwin_arm64.tar.gz"
      ASSET_SHA256=$FZF_SHA256_DARWIN_ARM64
      ;;
    darwin/x86_64)
      ASSET="fzf-${FZF_VERSION}-darwin_amd64.tar.gz"
      ASSET_SHA256=$FZF_SHA256_DARWIN_X86_64
      ;;
    linux/arm64)
      ASSET="fzf-${FZF_VERSION}-linux_arm64.tar.gz"
      ASSET_SHA256=$FZF_SHA256_LINUX_ARM64
      ;;
    linux/x86_64)
      ASSET="fzf-${FZF_VERSION}-linux_amd64.tar.gz"
      ASSET_SHA256=$FZF_SHA256_LINUX_X86_64
      ;;
  esac
}

install_fzf() {
  fzf_is_locked_version && return 0

  local work archive binary
  fzf_asset
  work=$(mktemp -d)
  archive="$work/$ASSET"
  trap 'rm -rf "$work"' RETURN

  log "Installing fzf $FZF_VERSION into $HOME/.local/bin"
  download "https://github.com/junegunn/fzf/releases/download/v$FZF_VERSION/$ASSET" "$archive"
  verify_sha256 "$archive" "$ASSET_SHA256"
  tar -xzf "$archive" -C "$work"
  binary=$(find "$work" -type f -name fzf -perm -u+x | head -1)
  [[ -n "$binary" ]] || fail "fzf binary not found in $ASSET"
  install -m 0755 "$binary" "$HOME/.local/bin/fzf"
  hash -r

  trap - RETURN
  rm -rf "$work"
  fzf_is_locked_version || fail "fzf $FZF_VERSION installation verification failed"
}

zoxide_asset() {
  case "$PLATFORM_OS/$PLATFORM_ARCH" in
    darwin/arm64)
      ASSET="zoxide-${ZOXIDE_VERSION}-aarch64-apple-darwin.tar.gz"
      ASSET_SHA256=$ZOXIDE_SHA256_DARWIN_ARM64
      ;;
    darwin/x86_64)
      ASSET="zoxide-${ZOXIDE_VERSION}-x86_64-apple-darwin.tar.gz"
      ASSET_SHA256=$ZOXIDE_SHA256_DARWIN_X86_64
      ;;
    linux/arm64)
      ASSET="zoxide-${ZOXIDE_VERSION}-aarch64-unknown-linux-musl.tar.gz"
      ASSET_SHA256=$ZOXIDE_SHA256_LINUX_ARM64
      ;;
    linux/x86_64)
      ASSET="zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz"
      ASSET_SHA256=$ZOXIDE_SHA256_LINUX_X86_64
      ;;
  esac
}

install_zoxide() {
  zoxide_is_locked_version && return 0

  local work archive binary
  zoxide_asset
  work=$(mktemp -d)
  archive="$work/$ASSET"
  trap 'rm -rf "$work"' RETURN

  log "Installing zoxide $ZOXIDE_VERSION into $HOME/.local/bin"
  download "https://github.com/ajeetdsouza/zoxide/releases/download/v$ZOXIDE_VERSION/$ASSET" "$archive"
  verify_sha256 "$archive" "$ASSET_SHA256"
  tar -xzf "$archive" -C "$work"
  binary=$(find "$work" -type f -name zoxide -perm -u+x | head -1)
  [[ -n "$binary" ]] || fail "zoxide binary not found in $ASSET"
  install -m 0755 "$binary" "$HOME/.local/bin/zoxide"
  hash -r

  trap - RETURN
  rm -rf "$work"
  zoxide_is_locked_version || fail "zoxide $ZOXIDE_VERSION installation verification failed"
}

iris_asset() {
  case "$PLATFORM_OS/$PLATFORM_ARCH" in
    darwin/arm64)
      ASSET="iris_darwin_arm64.tar.gz"
      ;;
    darwin/x86_64)
      ASSET="iris_darwin_amd64.tar.gz"
      ;;
    linux/arm64)
      ASSET="iris_linux_arm64.tar.gz"
      ;;
    linux/x86_64)
      ASSET="iris_linux_amd64.tar.gz"
      ;;
  esac
}

install_iris() {
  local current_version existing_iris=0
  if iris_is_installed; then
    existing_iris=1
    current_version=$(iris_version)
  fi

  local work archive binary candidate_version destination
  iris_asset
  if ! work=$(mktemp -d); then
    if (( existing_iris )); then
      warn "Iris update could not create a temporary directory; keeping the usable installed version: $current_version"
      return 0
    fi
    fail "cannot create a temporary directory for Iris installation"
  fi
  archive="$work/$ASSET"
  trap 'rm -rf "$work"' RETURN

  log "Checking the official latest stable Iris Release${current_version:+ from $current_version}"
  if ! download "$IRIS_LATEST_RELEASE_URL/$ASSET" "$archive"; then
    trap - RETURN
    rm -rf "$work"
    if (( existing_iris )); then
      warn "Iris stable update check failed; keeping the usable installed version: $current_version"
      return 0
    fi
    fail "latest stable Iris download failed"
  fi
  if ! tar -xzf "$archive" -C "$work"; then
    trap - RETURN
    rm -rf "$work"
    if (( existing_iris )); then
      warn "Iris stable archive is invalid; keeping the usable installed version: $current_version"
      return 0
    fi
    fail "latest stable Iris archive is invalid"
  fi
  binary=$(find "$work" -type f -name iris -perm -u+x | head -1)
  if [[ -z "$binary" ]] || ! candidate_version=$("$binary" version 2>/dev/null | \
    awk 'NR == 1 && $1 == "iris" {sub(/^v/, "", $2); print $2}'); then
    candidate_version=
  fi
  if [[ ! $candidate_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    trap - RETURN
    rm -rf "$work"
    if (( existing_iris )); then
      warn "Iris stable asset has an invalid binary; keeping the usable installed version: $current_version"
      return 0
    fi
    fail "latest stable Iris binary is invalid"
  fi
  if (( existing_iris )) && ! iris_version_is_newer "$current_version" "$candidate_version"; then
    trap - RETURN
    rm -rf "$work"
    log "Iris is already at the newest stable version allowed without downgrade: $current_version"
    return 0
  fi

  if ! mkdir -p "$HOME/.local/bin"; then
    trap - RETURN
    rm -rf "$work"
    if (( existing_iris )); then
      warn "Iris update cannot write $HOME/.local/bin; keeping the usable installed version: $current_version"
      return 0
    fi
    fail "cannot create $HOME/.local/bin for Iris installation"
  fi
  destination="$HOME/.local/bin/.iris.$$"
  if ! install -m 0755 "$binary" "$destination" || \
    ! "$destination" version >/dev/null 2>&1 || \
    ! mv -f "$destination" "$HOME/.local/bin/iris"; then
    rm -f "$destination"
    trap - RETURN
    rm -rf "$work"
    if (( existing_iris )); then
      warn "Iris stable update could not be installed; keeping the usable installed version: $current_version"
      return 0
    fi
    fail "latest stable Iris installation failed"
  fi
  hash -r

  trap - RETURN
  rm -rf "$work"
  iris_is_installed || fail "latest stable Iris installation verification failed"
  log "Installed Iris stable $candidate_version"
}

glow_asset() {
  case "$PLATFORM_OS/$PLATFORM_ARCH" in
    darwin/arm64)
      ASSET="glow_${GLOW_VERSION}_Darwin_arm64.tar.gz"
      ASSET_SHA256=$GLOW_SHA256_DARWIN_ARM64
      ;;
    darwin/x86_64)
      ASSET="glow_${GLOW_VERSION}_Darwin_x86_64.tar.gz"
      ASSET_SHA256=$GLOW_SHA256_DARWIN_X86_64
      ;;
    linux/arm64)
      ASSET="glow_${GLOW_VERSION}_Linux_arm64.tar.gz"
      ASSET_SHA256=$GLOW_SHA256_LINUX_ARM64
      ;;
    linux/x86_64)
      ASSET="glow_${GLOW_VERSION}_Linux_x86_64.tar.gz"
      ASSET_SHA256=$GLOW_SHA256_LINUX_X86_64
      ;;
  esac
}

install_glow() {
  glow_is_locked_version && return 0

  local work archive binary
  glow_asset
  work=$(mktemp -d)
  archive="$work/$ASSET"
  trap 'rm -rf "$work"' RETURN

  log "Installing Glow $GLOW_VERSION into $HOME/.local/bin"
  download "https://github.com/charmbracelet/glow/releases/download/v$GLOW_VERSION/$ASSET" "$archive"
  verify_sha256 "$archive" "$ASSET_SHA256"
  tar -xzf "$archive" -C "$work"
  binary=$(find "$work" -type f -name glow -perm -u+x | head -1)
  [[ -n "$binary" ]] || fail "glow binary not found in $ASSET"
  install -m 0755 "$binary" "$HOME/.local/bin/glow"
  hash -r

  trap - RETURN
  rm -rf "$work"
  glow_is_locked_version || fail "Glow $GLOW_VERSION installation verification failed"
}

yazi_asset() {
  case "$PLATFORM_OS/$PLATFORM_ARCH" in
    darwin/arm64)
      ASSET="yazi-aarch64-apple-darwin.zip"
      ASSET_SHA256=$YAZI_SHA256_DARWIN_ARM64
      ;;
    darwin/x86_64)
      ASSET="yazi-x86_64-apple-darwin.zip"
      ASSET_SHA256=$YAZI_SHA256_DARWIN_X86_64
      ;;
    linux/arm64)
      ASSET="yazi-aarch64-unknown-linux-gnu.zip"
      ASSET_SHA256=$YAZI_SHA256_LINUX_ARM64
      ;;
    linux/x86_64)
      ASSET="yazi-x86_64-unknown-linux-gnu.zip"
      ASSET_SHA256=$YAZI_SHA256_LINUX_X86_64
      ;;
  esac
}

install_yazi() {
  yazi_is_locked_version && return 0

  local work archive yazi_binary ya_binary
  yazi_asset
  work=$(mktemp -d)
  archive="$work/$ASSET"
  trap 'rm -rf "$work"' RETURN

  log "Installing Yazi $YAZI_VERSION into $HOME/.local/bin"
  download "https://github.com/sxyazi/yazi/releases/download/v$YAZI_VERSION/$ASSET" "$archive"
  verify_sha256 "$archive" "$ASSET_SHA256"
  unzip -q "$archive" -d "$work"
  yazi_binary=$(find "$work" -type f -name yazi | head -1)
  ya_binary=$(find "$work" -type f -name ya | head -1)
  [[ -n "$yazi_binary" ]] || fail "yazi binary not found in $ASSET"
  [[ -n "$ya_binary" ]] || fail "ya binary not found in $ASSET"
  install -m 0755 "$yazi_binary" "$HOME/.local/bin/yazi"
  install -m 0755 "$ya_binary" "$HOME/.local/bin/ya"

  trap - RETURN
  rm -rf "$work"
  yazi_is_locked_version || fail "Yazi $YAZI_VERSION installation verification failed"
}

install_yazi_packages() {
  command -v ya >/dev/null 2>&1 || fail "ya is required to install Yazi packages"
  log "Installing locked Yazi packages"
  ya pkg install
  [[ -d "$HOME/.config/yazi/plugins/piper.yazi" ]] || fail "piper.yazi installation failed"
}

install_pre_commit() {
  pre_commit_is_locked_version && return 0

  local work archive destination
  work=$(mktemp -d)
  archive="$work/pre-commit-$PRE_COMMIT_VERSION.pyz"
  destination="$HOME/.local/share/pre-commit/pre-commit.pyz"
  trap 'rm -rf "$work"' RETURN

  log "Installing pre-commit $PRE_COMMIT_VERSION into $HOME/.local"
  download \
    "https://github.com/pre-commit/pre-commit/releases/download/v$PRE_COMMIT_VERSION/pre-commit-$PRE_COMMIT_VERSION.pyz" \
    "$archive"
  verify_sha256 "$archive" "$PRE_COMMIT_SHA256"
  mkdir -p "$(dirname "$destination")"
  install -m 0644 "$archive" "$destination"
  backup_and_link "$DOTFILES_DIR/bin/pre-commit" "$HOME/.local/bin/pre-commit"
  hash -r

  trap - RETURN
  rm -rf "$work"
  pre_commit_is_locked_version || fail "pre-commit $PRE_COMMIT_VERSION installation verification failed"
}

install_codex() {
  command -v npm >/dev/null 2>&1 || fail "npm is required to install Codex CLI"
  log "Installing the latest Codex CLI into $HOME/.local/bin"
  npm install --global --prefix "$HOME/.local" '@openai/codex@latest'
  hash -r
  codex_is_installed || fail "latest Codex CLI installation verification failed"
  log "Installed $(codex --version)"
}

install_termscp() {
  log "Installing termscp with its official universal installer"
  curl --proto '=https' --tlsv1.2 -sSLf --retry 3 --connect-timeout 15 \
    "$TERMSCP_INSTALL_URL" | sh -s -- --yes
  hash -r
  termscp_is_installed || fail "termscp installation verification failed"
  log "Installed $(termscp -v)"
}

uninstall_druk() {
  if [[ -e "$HOME/.local/bin/druk" || -d "$HOME/.local/lib/node_modules/druk" ]]; then
    command -v npm >/dev/null 2>&1 || fail "npm is required to uninstall the old Druk package"
    log "Uninstalling the old Druk npm package"
    npm uninstall --global --prefix "$HOME/.local" druk
  fi

  if [[ -x "$HOME/.druk/bin/druk" ]]; then
    log "Removing the old Druk standalone installation from $HOME/.druk"
    rm -rf "$HOME/.druk"
  fi

  if [[ -e "$HOME/.config/druk" || -e "$HOME/.cache/druk" ]]; then
    log "Removing the old Druk configuration and cache"
    rm -rf "$HOME/.config/druk" "$HOME/.cache/druk"
  fi

  hash -r
  druk_is_absent || fail "Druk is still installed at $(command -v druk 2>/dev/null || printf 'an unmanaged location')"
}

install_fresh() {
  log "Installing Fresh with its official universal installer"
  curl -fsSL --retry 3 --connect-timeout 15 "$FRESH_INSTALL_URL" | sh
  hash -r
  fresh_is_installed || fail "Fresh installation verification failed"
  log "Installed $(fresh --version)"
}

# --- 配置备份、插件和符号链接 -----------------------------------------------
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

install_git_checkout() {
  local name repository commit destination
  name=$1
  repository=$2
  commit=$3
  destination=$4
  mkdir -p "$(dirname "$destination")"

  if [[ ! -d "$destination/.git" ]]; then
    git clone "$repository" "$destination"
  fi

  [[ -z $(git -C "$destination" status --porcelain) ]] || fail "$name has local changes"
  if [[ $(git -C "$destination" rev-parse HEAD) != "$commit" ]]; then
    git -C "$destination" fetch --tags origin
    git -C "$destination" checkout --detach "$commit"
  fi
  [[ $(git -C "$destination" rev-parse HEAD) == "$commit" ]] || fail "$name commit verification failed"
}

install_plugin() {
  local name=$1 repository=$2 commit=$3
  install_git_checkout "$name" "$repository" "$commit" "$HOME/.tmux/plugins/$name"
}

install_oh_my_zsh() {
  install_git_checkout oh-my-zsh https://github.com/ohmyzsh/ohmyzsh.git \
    "$OH_MY_ZSH_COMMIT" "$HOME/.oh-my-zsh"
  install_git_checkout zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$ZSH_SYNTAX_HIGHLIGHTING_COMMIT" "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
}

install_iterm2_profile() {
  [[ "$PLATFORM_OS" == darwin ]] || return 0

  local profile destination legacy_profile legacy_destination
  profile="$DOTFILES_DIR/iterm2/dev.json"
  destination="$HOME/Library/Application Support/iTerm2/DynamicProfiles/dev.json"
  legacy_profile="$DOTFILES_DIR/iterm2/dev-4090.json"
  legacy_destination="$HOME/Library/Application Support/iTerm2/DynamicProfiles/dev-4090.json"

  command -v plutil >/dev/null 2>&1 || fail "plutil is required to validate the iTerm2 profile"
  plutil -convert xml1 -o /dev/null "$profile" || fail "invalid iTerm2 dynamic profile: $profile"

  # The profile was renamed from dev-4090.json to dev.json. Remove only the
  # obsolete dotfiles-managed link so iTerm2 does not keep reporting its now
  # missing target; preserve any independently managed file at the same path.
  if [[ -L "$legacy_destination" && $(readlink "$legacy_destination") == "$legacy_profile" ]]; then
    rm "$legacy_destination"
  fi

  backup_and_link "$profile" "$destination"
}

ghostty_binary() {
  local candidate

  if command -v ghostty >/dev/null 2>&1; then
    command -v ghostty
    return 0
  fi

  for candidate in \
    /Applications/Ghostty.app/Contents/MacOS/ghostty \
    "$HOME/Applications/Ghostty.app/Contents/MacOS/ghostty"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

install_ghostty() {
  [[ "$PLATFORM_OS" == darwin ]] || return 0

  if ghostty_binary >/dev/null 2>&1; then
    log "Ghostty is already installed"
    return 0
  fi

  command -v brew >/dev/null 2>&1 || fail "Homebrew is required to install Ghostty"
  log "Installing the current stable Ghostty with Homebrew"
  brew install --cask ghostty
  ghostty_binary >/dev/null 2>&1 || fail "Ghostty installation verification failed"
}

validate_ghostty_config_file() {
  local config=$1 binary
  [[ -r "$config" ]] || fail "Ghostty config is missing: $config"

  # 没有安装 Ghostty 的 macOS 机器仍可先同步配置；安装后下一次 bootstrap 会
  # 使用官方解析器验证。stderr 包含与配置无关的 crash reporter 初始化提示。
  if binary=$(ghostty_binary); then
    "$binary" +validate-config --config-file="$config" >/dev/null 2>&1 || \
      fail "invalid Ghostty config: $config"
  fi
}

validate_ghostty_applescript() {
  local script=$1 work
  [[ -r "$script" ]] || fail "Ghostty AppleScript is missing: $script"

  # osacompile 需要已安装 Ghostty 才能解析它的 scripting dictionary。
  if command -v osacompile >/dev/null 2>&1 && ghostty_binary >/dev/null; then
    work=$(mktemp -d)
    if ! osacompile -o "$work/ghostty-script.scpt" "$script" >/dev/null 2>&1; then
      rm -rf "$work"
      fail "invalid Ghostty AppleScript: $script"
    fi
    rm -rf "$work"
  fi
}

install_ghostty_config() {
  [[ "$PLATFORM_OS" == darwin ]] || return 0

  local applescript close_applescript config destination launcher launcher_destination wrapper
  applescript="$DOTFILES_DIR/ghostty/open-tab.applescript"
  close_applescript="$DOTFILES_DIR/ghostty/close-tab.applescript"
  config="$DOTFILES_DIR/ghostty/config.ghostty"
  destination="$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
  launcher="$DOTFILES_DIR/bin/ghostty-dev"
  launcher_destination="$HOME/.local/bin/ghostty-dev"
  wrapper="$DOTFILES_DIR/bin/ghostty-tab-command"

  validate_ghostty_config_file "$config"
  validate_ghostty_applescript "$applescript"
  validate_ghostty_applescript "$close_applescript"
  bash -n "$wrapper"
  backup_and_link "$config" "$destination"
  backup_and_link "$launcher" "$launcher_destination"
}

node_asset() {
  case "$PLATFORM_OS/$PLATFORM_ARCH" in
    linux/arm64)
      ASSET="node-v${NODE_VERSION}-linux-arm64.tar.xz"
      ASSET_SHA256=$NODE_SHA256_LINUX_ARM64
      ;;
    linux/x86_64)
      ASSET="node-v${NODE_VERSION}-linux-x64.tar.xz"
      ASSET_SHA256=$NODE_SHA256_LINUX_X86_64
      ;;
    *)
      fail "Node.js fallback is not available for $PLATFORM_OS/$PLATFORM_ARCH"
      ;;
  esac
}

install_node_for_todoist() {
  node_supports_todoist_cli && return 0
  [[ "$PLATFORM_OS" == linux ]] || \
    fail "Todoist CLI requires Node.js 24 or newer; update Homebrew node and rerun bootstrap"

  local work archive source_dir target binary
  node_asset
  work=$(mktemp -d)
  archive="$work/$ASSET"
  target="$HOME/.local/share/node-v$NODE_VERSION"
  trap 'rm -rf "$work"' RETURN

  log "Installing Node.js $NODE_VERSION for Todoist CLI"
  download "https://nodejs.org/dist/v$NODE_VERSION/$ASSET" "$archive"
  verify_sha256 "$archive" "$ASSET_SHA256"
  tar -xJf "$archive" -C "$work"
  source_dir="$work/${ASSET%.tar.xz}"
  mkdir -p "$target"
  cp -R "$source_dir/." "$target/"
  for binary in node npm npx corepack; do
    [[ -e "$target/bin/$binary" ]] && \
      backup_and_link "$target/bin/$binary" "$HOME/.local/bin/$binary"
  done
  hash -r

  trap - RETURN
  rm -rf "$work"
  node_supports_todoist_cli || fail "Node.js $NODE_VERSION installation verification failed"
}

install_todoist_cli() {
  node_supports_todoist_cli || fail "Todoist CLI requires Node.js 24 or newer"
  npm_supports_todoist_cli || fail "Todoist CLI requires npm 11 or newer"
  if ! todoist_cli_is_locked_version; then
    log "Installing official Todoist CLI $TODOIST_CLI_VERSION"
    npm install --global --prefix "$HOME/.local" \
      "@doist/todoist-cli@$TODOIST_CLI_VERSION"
    hash -r
  fi
  todoist_cli_is_locked_version || \
    fail "Todoist CLI $TODOIST_CLI_VERSION installation verification failed"
}

remove_legacy_todo_bridge() {
  local bridge="$HOME/.local/bin/todo-bridge"
  local backend="$HOME/.local/libexec/todo-reminders"
  local icloud="$HOME/.local/bin/icloud"

  if [[ -L "$bridge" && $(readlink "$bridge") == "$DOTFILES_DIR/bin/todo-bridge" ]]; then
    log "Removing obsolete Todo bridge link"
    rm -f "$bridge"
  fi
  if [[ -f "$backend" ]]; then
    log "Removing obsolete Todo EventKit backend"
    rm -f "$backend"
  fi
  if [[ -L "$icloud" && $(readlink "$icloud") == "$HOME/.venvs/pyicloud/bin/icloud" ]]; then
    log "Removing obsolete managed pyicloud CLI link"
    rm -f "$icloud"
  fi
}

install_links() {
  backup_and_link "$DOTFILES_DIR/shell/zshrc" "$HOME/.zshrc"
  backup_and_link "$DOTFILES_DIR/vim/vimrc" "$HOME/.vimrc"
  backup_and_link "$DOTFILES_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"
  backup_and_link "$DOTFILES_DIR/tmux/session-status-counts.sh" "$HOME/.tmux/session-status-counts.sh"
  backup_and_link "$DOTFILES_DIR/bin/tmux-zsh" "$HOME/.local/bin/tmux-zsh"
  backup_and_link "$DOTFILES_DIR/bin/lazygit-safe" "$HOME/.local/bin/lazygit-safe"
  backup_and_link "$DOTFILES_DIR/bin/remote-dev-entry" "$HOME/.local/bin/remote-dev-entry"
  backup_and_link "$DOTFILES_DIR/bin/connect-remote-dev" "$HOME/.local/bin/connect-remote-dev"
  backup_and_link "$DOTFILES_DIR/bin/termscp-mac" "$HOME/.local/bin/termscp-mac"
  backup_and_link "$DOTFILES_DIR/bin/termscp-bridge-relay" "$HOME/.local/bin/termscp-bridge-relay"
  backup_and_link "$DOTFILES_DIR/bin/termscp-key-authorizer" "$HOME/.local/bin/termscp-key-authorizer"
  backup_and_link "$DOTFILES_DIR/bin/todo" "$HOME/.local/bin/todo"
  backup_and_link "$DOTFILES_DIR/bin/todo-agent" "$HOME/.local/bin/todo-agent"
  backup_and_link "$DOTFILES_DIR/shell/tmux-window-name.zsh" "$HOME/.config/tmux/window-name.zsh"
  backup_and_link "$DOTFILES_DIR/yazi/yazi.toml" "$HOME/.config/yazi/yazi.toml"
  backup_and_link "$DOTFILES_DIR/yazi/init.lua" "$HOME/.config/yazi/init.lua"
  backup_and_link "$DOTFILES_DIR/yazi/package.toml" "$HOME/.config/yazi/package.toml"
  backup_and_link "$DOTFILES_DIR/codex/notify-tmux.sh" "$HOME/.codex/hooks/notify-tmux.sh"
  backup_and_link "$DOTFILES_DIR/codex/hooks.json" "$HOME/.codex/hooks.json"

  local lazygit_config_dir
  lazygit_config_dir=$(lazygit --print-config-dir)
  backup_and_link "$DOTFILES_DIR/lazygit/config.yml" "$lazygit_config_dir/config.yml"
}

install_todo_agent_service() {
  [[ "$PLATFORM_OS" == linux ]] || return 0

  backup_and_link \
    "$DOTFILES_DIR/systemd/todo-agent.service" \
    "$HOME/.config/systemd/user/todo-agent.service"

  if ! todo_agent_has_enabled_projects; then
    if todo_agent_fallback_running; then
      stop_todo_agent_fallback
    fi
    if todo_agent_systemd_available; then
      systemctl --user disable --now todo-agent.service >/dev/null 2>&1 || true
    fi
    log "Skipping todo-agent watcher because no enabled projects are configured"
    return 0
  fi

  if todo_agent_systemd_available; then
    systemctl --user daemon-reload
    systemctl --user enable todo-agent.service
    if todo_agent_fallback_running; then
      stop_todo_agent_fallback
    fi
    systemctl --user restart todo-agent.service
    systemctl --user is-active --quiet todo-agent.service || \
      fail "todo-agent systemd service failed to restart"
    log "todo-agent systemd watcher is enabled and running with the current code"
    return 0
  fi

  restart_todo_agent_fallback
}

todo_agent_has_enabled_projects() {
  local output
  if ! output=$("$HOME/.local/bin/todo-agent" project list 2>&1); then
    fail "cannot read todo-agent project configuration: $output"
  fi
  grep -Eq $'\tenabled$' <<< "$output"
}

todo_agent_systemd_available() {
  command -v systemctl >/dev/null 2>&1 && \
    systemctl --user show-environment >/dev/null 2>&1
}

todo_agent_pid_running() {
  local pid=$1 process_state
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1 || return 1

  # kill -0 also succeeds for zombies. This is common in development
  # containers whose PID 1 does not reap orphaned children, but a zombie no
  # longer watches Todoist or owns the dispatcher lock.
  if [[ -r "/proc/$pid/stat" ]]; then
    process_state=$(sed -n 's/^.*) \([A-Z]\) .*/\1/p' "/proc/$pid/stat")
  else
    process_state=$(ps -p "$pid" -o stat= 2>/dev/null | awk 'NR == 1 {print $1}')
  fi
  # If process inspection is restricted, retain kill -0 as the conservative
  # fallback. A reported Z state is the only case that is definitely stopped.
  [[ "$process_state" != Z* ]]
}

todo_agent_fallback_running() {
  local command_line pid pid_file
  pid_file="$HOME/.local/state/todoist-codex/watcher.pid"
  [[ -s "$pid_file" ]] || return 1
  IFS= read -r pid < "$pid_file"
  todo_agent_pid_running "$pid" || return 1

  # Contract tests run in a restricted macOS sandbox where neither /proc nor
  # process command inspection is available. Production callers never set
  # this test-only switch.
  [[ ${TODO_AGENT_SKIP_CMDLINE_CHECK:-0} == 1 ]] && return 0

  if [[ -r "/proc/$pid/cmdline" ]]; then
    command_line=$(tr '\0' ' ' < "/proc/$pid/cmdline")
  else
    command_line=$(ps -p "$pid" -o command= 2>/dev/null || true)
  fi
  [[ "$command_line" == *"todo-agent watch"* ]]
}

stop_todo_agent_fallback() {
  local attempt pid pid_file
  pid_file="$HOME/.local/state/todoist-codex/watcher.pid"
  if ! todo_agent_fallback_running; then
    [[ ! -e "$pid_file" ]] || unlink "$pid_file"
    return 0
  fi

  IFS= read -r pid < "$pid_file"
  log "Stopping todo-agent fallback watcher with PID $pid"
  kill "$pid"
  for attempt in {1..50}; do
    todo_agent_pid_running "$pid" || break
    sleep 0.1
  done
  todo_agent_pid_running "$pid" && \
    fail "todo-agent fallback watcher PID $pid did not stop"
  unlink "$pid_file"
}

start_todo_agent_fallback() {
  local log_file pid pid_file state_directory
  state_directory="$HOME/.local/state/todoist-codex"
  pid_file="$state_directory/watcher.pid"
  log_file="$state_directory/watcher.log"

  mkdir -p "$state_directory"
  chmod 700 "$state_directory"
  if todo_agent_fallback_running; then
    IFS= read -r pid < "$pid_file"
    log "todo-agent fallback watcher is already running with PID $pid"
    return 0
  fi

  log "Starting todo-agent fallback watcher in the background"
  nohup "$HOME/.local/bin/todo-agent" watch --interval 10 \
    >> "$log_file" 2>&1 < /dev/null &
  pid=$!
  printf '%s\n' "$pid" > "$pid_file"
  chmod 600 "$pid_file"
  sleep 1
  todo_agent_pid_running "$pid" || \
    fail "todo-agent fallback watcher failed to start; inspect $log_file"
  todo_agent_fallback_running || \
    fail "todo-agent fallback watcher PID verification failed"
  log "todo-agent fallback watcher is running with PID $pid"
}

restart_todo_agent_fallback() {
  stop_todo_agent_fallback
  start_todo_agent_fallback
}

todo_agent_background_running() {
  if todo_agent_systemd_available && \
    systemctl --user is-active --quiet todo-agent.service; then
    return 0
  fi
  todo_agent_fallback_running
}

# --- Shell 持久环境 ---------------------------------------------------------
ensure_shell_path() {
  local path_line='export PATH="$HOME/.local/bin:$PATH"'
  local startup_file
  local startup_files=("$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc")

  # An existing .bash_profile takes precedence over .profile for login Bash.
  if [[ -e "$HOME/.bash_profile" ]]; then
    startup_files+=("$HOME/.bash_profile")
  fi

  for startup_file in "${startup_files[@]}"; do
    touch "$startup_file"
    if ! grep -Fqx "$path_line" "$startup_file"; then
      printf '\n%s\n' "$path_line" >> "$startup_file"
    fi
  done
}

ensure_shell_locale() {
  local startup_file locale_line
  local startup_files=("$HOME/.bashrc" "$HOME/.zshrc")
  local locale_lines=(
    'export LANG=zh_CN.UTF-8'
    'export LC_ALL=zh_CN.UTF-8'
  )

  for startup_file in "${startup_files[@]}"; do
    touch "$startup_file"
    for locale_line in "${locale_lines[@]}"; do
      if ! grep -Fqx "$locale_line" "$startup_file"; then
        printf '\n%s\n' "$locale_line" >> "$startup_file"
      fi
    done
  done
}

# Git identity belongs to the current machine or container, not to the dotfiles
# repository. Preserve existing values; prompt only for missing fields when the
# bootstrap owns an interactive terminal, and never block headless installs.
configure_git_identity() {
  local git_name git_email input configure_now
  git_name=$(git config --global --get user.name 2>/dev/null || true)
  git_email=$(git config --global --get user.email 2>/dev/null || true)

  if [[ -n "$git_name" && -n "$git_email" ]]; then
    log "Git identity already configured: $git_name <$git_email>"
    return 0
  fi

  log "Git global identity is incomplete"
  if [[ -t 0 ]]; then
    printf 'Configure the missing Git identity now? [y/N]: '
    configure_now=
    IFS= read -r configure_now || true
    case "$configure_now" in
      y|Y|yes|YES)
        if [[ -z "$git_name" ]]; then
          printf 'Git user.name (leave blank to skip): '
          input=
          IFS= read -r input || true
          [[ -z "$input" ]] || git config --global user.name "$input"
        fi
        if [[ -z "$git_email" ]]; then
          printf 'Git user.email (leave blank to skip): '
          input=
          IFS= read -r input || true
          [[ -z "$input" ]] || git config --global user.email "$input"
        fi
        ;;
      *)
        printf '%s\n' 'Skipping Git identity setup; bootstrap will ask again next time.'
        ;;
    esac
  fi

  git_name=$(git config --global --get user.name 2>/dev/null || true)
  git_email=$(git config --global --get user.email 2>/dev/null || true)
  if [[ -n "$git_name" && -n "$git_email" ]]; then
    log "Git identity configured: $git_name <$git_email>"
    return 0
  fi

  printf '%s\n' 'Complete the missing Git identity fields later with:'
  [[ -n "$git_name" ]] || printf '%s\n' '  git config --global user.name "Your Name"'
  [[ -n "$git_email" ]] || printf '%s\n' '  git config --global user.email "you@example.com"'
}

remind_gitlab_auth() {
  log "GitLab token authentication reminder"
  printf '%s\n' 'Authenticate GitLab when needed with:'
  printf '%s\n' '  glab auth login --hostname gitlab.addx.ai'
  printf '%s\n' 'Paste a GitLab token with api scope only into the interactive prompt; do not put it in shell history.'
}

remind_ssh_key() {
  local candidate public_key= git_email
  for candidate in \
    "$HOME/.ssh/id_ed25519.pub" \
    "$HOME/.ssh/id_ecdsa.pub" \
    "$HOME/.ssh/id_rsa.pub"; do
    if [[ -f "$candidate" ]]; then
      public_key=$candidate
      break
    fi
  done

  log "SSH key reminder"
  if [[ -n "$public_key" ]]; then
    printf 'Existing public key: %s\n' "$public_key"
    printf 'Display it with: cat "%s"\n' "$public_key"
  else
    git_email=$(git config --global --get user.email 2>/dev/null || true)
    if [[ -n "$git_email" ]]; then
      printf 'Generate a key with: ssh-keygen -t ed25519 -C "%s"\n' "$git_email"
    else
      printf '%s\n' 'Generate a key with: ssh-keygen -t ed25519 -C "you@example.com"'
    fi
  fi
  printf '%s\n' 'Add the public key to the remote repository account before using SSH Git URLs.'
  printf '%s\n' 'For this GitHub repository, verify access with: ssh -T git@github.com'
}

# --- 安装后合同验证 ---------------------------------------------------------
validate() {
  local prefix_bindings
  local ghostty_config ghostty_destination ghostty_launcher ghostty_launcher_destination
  local iterm2_profile iterm2_destination pre_commit_link pre_commit_wrapper
  local login_shell login_user zsh_path
  local todo_agent_link todo_agent_service todo_agent_service_destination
  local tmux_config tmux_config_destination
  local yazi_config yazi_config_destination yazi_init yazi_init_destination
  local yazi_package yazi_package_destination yazi_package_list

  log "Validating locked environment"
  tmux_is_locked_version || fail "expected tmux $TMUX_VERSION"
  lazygit_is_locked_version || fail "expected lazygit $LAZYGIT_VERSION"
  glab_is_locked_version || fail "expected GitLab CLI $GLAB_VERSION"
  delta_is_locked_version || fail "expected git-delta $DELTA_VERSION"
  fzf_is_locked_version || fail "expected fzf $FZF_VERSION"
  zoxide_is_locked_version || fail "expected zoxide $ZOXIDE_VERSION"
  iris_is_installed || fail "Iris is required"
  glow_is_locked_version || fail "expected Glow $GLOW_VERSION"
  yazi_is_locked_version || fail "expected Yazi $YAZI_VERSION and matching ya CLI"
  pre_commit_is_locked_version || fail "expected pre-commit $PRE_COMMIT_VERSION"
  codex_is_installed || fail "Codex CLI is required"
  termscp_is_installed || fail "termscp is required"
  fresh_is_installed || fail "Fresh is required"
  node_supports_todoist_cli || fail "Todoist CLI requires Node.js 24 or newer"
  npm_supports_todoist_cli || fail "Todoist CLI requires npm 11 or newer"
  todoist_cli_is_locked_version || fail "expected Todoist CLI $TODOIST_CLI_VERSION"
  [[ ! -e "$HOME/.local/libexec/todo-reminders" ]] || \
    fail "obsolete Todo EventKit backend is still installed"
  [[ ! -e "$HOME/.local/bin/todo-bridge" && ! -L "$HOME/.local/bin/todo-bridge" ]] || \
    fail "obsolete Todo bridge launcher is still installed"
  druk_is_absent || fail "Druk must be uninstalled after migration to Fresh"
  command -v zsh >/dev/null 2>&1 || fail "zsh is required"
  command -v bash >/dev/null 2>&1 || fail "bash is required"
  command -v btop >/dev/null 2>&1 || fail "btop is required"
  command -v git >/dev/null 2>&1 || fail "git is required"
  command -v ssh-keygen >/dev/null 2>&1 || fail "ssh-keygen is required"
  command -v vi >/dev/null 2>&1 || fail "vi is required"
  vi --version 2>/dev/null | grep -Eq '\+mouse([[:space:]]|$)' || fail "vi must support mouse input"
  infocmp tmux-256color >/dev/null 2>&1 || fail "tmux-256color terminfo is missing"
  infocmp xterm-ghostty >/dev/null 2>&1 || fail "xterm-ghostty terminfo is missing"
  LC_ALL=zh_CN.UTF-8 locale charmap 2>/dev/null | grep -qi 'UTF-8' || fail "zh_CN.UTF-8 locale is required"
  login_user=$(id -un)
  zsh_path=$(command -v zsh)
  login_shell=$(current_login_shell "$login_user")
  [[ "$login_shell" == "$zsh_path" ]] || \
    fail "login shell for $login_user must be $zsh_path, got $login_shell"

  zsh -n "$DOTFILES_DIR/shell/tmux-window-name.zsh"
  zsh -n "$DOTFILES_DIR/shell/zshrc"
  bash -n "$DOTFILES_DIR/bootstrap.sh"
  bash -n "$DOTFILES_DIR/bin/remote-dev-entry"
  bash -n "$DOTFILES_DIR/bin/connect-remote-dev"
  bash -n "$DOTFILES_DIR/bin/termscp-mac"
  python3 "$DOTFILES_DIR/bin/termscp-bridge-relay" --help >/dev/null
  python3 "$DOTFILES_DIR/bin/termscp-key-authorizer" --help >/dev/null
  python3 "$DOTFILES_DIR/bin/todo" --help >/dev/null
  python3 -c 'import pathlib, sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' \
    "$DOTFILES_DIR/bin/todo"
  python3 "$DOTFILES_DIR/bin/todo-agent" --help >/dev/null
  python3 -c 'import pathlib, sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' \
    "$DOTFILES_DIR/bin/todo-agent"
  bash -n "$DOTFILES_DIR/bin/ghostty-dev"
  bash -n "$DOTFILES_DIR/bin/ghostty-tab-command"
  bash -n "$DOTFILES_DIR/bin/pre-commit"
  sh -n "$DOTFILES_DIR/bin/lazygit-safe"
  bash -n "$DOTFILES_DIR/tmux/session-status-counts.sh"
  bash -n "$DOTFILES_DIR/codex/notify-tmux.sh"
  bash "$DOTFILES_DIR/tests/test-remote-dev-entry.sh"
  bash "$DOTFILES_DIR/tests/test-connect-remote-dev.sh"
  bash "$DOTFILES_DIR/tests/test-termscp-mac.sh"
  bash "$DOTFILES_DIR/tests/test-termscp-bridge-relay.sh"
  bash "$DOTFILES_DIR/tests/test-termscp-key-authorizer.sh"
  bash "$DOTFILES_DIR/tests/test-iris-update.sh"
  python3 "$DOTFILES_DIR/tests/test-todo-tui.py"
  python3 "$DOTFILES_DIR/tests/test-todo-agent.py"
  bash "$DOTFILES_DIR/tests/test-ghostty-dev.sh"
  sh "$DOTFILES_DIR/tests/test-lazygit-safe.sh"

  pre_commit_wrapper="$DOTFILES_DIR/bin/pre-commit"
  pre_commit_link="$HOME/.local/bin/pre-commit"
  [[ -L "$pre_commit_link" && $(readlink "$pre_commit_link") == "$pre_commit_wrapper" ]] || \
    fail "pre-commit launcher link is missing"

  todo_agent_link="$HOME/.local/bin/todo-agent"
  [[ -L "$todo_agent_link" && $(readlink "$todo_agent_link") == "$DOTFILES_DIR/bin/todo-agent" ]] || \
    fail "todo-agent launcher link is missing"
  if [[ "$PLATFORM_OS" == linux ]]; then
    todo_agent_service="$DOTFILES_DIR/systemd/todo-agent.service"
    todo_agent_service_destination="$HOME/.config/systemd/user/todo-agent.service"
    [[ -L "$todo_agent_service_destination" &&
      $(readlink "$todo_agent_service_destination") == "$todo_agent_service" ]] || \
      fail "todo-agent systemd service link is missing"
    if todo_agent_has_enabled_projects; then
      todo_agent_background_running || fail "todo-agent background watcher is not running"
    fi
  fi

  vim_config="$DOTFILES_DIR/vim/vimrc"
  vim_config_destination="$HOME/.vimrc"
  [[ -L "$vim_config_destination" && $(readlink "$vim_config_destination") == "$vim_config" ]] || \
    fail "Vim config link is missing"
  vim -Nu "$vim_config" -n -es -i NONE \
    -c 'if !&number | cquit | endif' -c 'qa!' || fail "Vim line numbers are not enabled"

  yazi_config="$DOTFILES_DIR/yazi/yazi.toml"
  yazi_config_destination="$HOME/.config/yazi/yazi.toml"
  [[ -L "$yazi_config_destination" && $(readlink "$yazi_config_destination") == "$yazi_config" ]] || \
    fail "Yazi main config link is missing"

  yazi_init="$DOTFILES_DIR/yazi/init.lua"
  yazi_init_destination="$HOME/.config/yazi/init.lua"
  [[ -L "$yazi_init_destination" && $(readlink "$yazi_init_destination") == "$yazi_init" ]] || \
    fail "Yazi init config link is missing"

  yazi_package="$DOTFILES_DIR/yazi/package.toml"
  yazi_package_destination="$HOME/.config/yazi/package.toml"
  [[ -L "$yazi_package_destination" && $(readlink "$yazi_package_destination") == "$yazi_package" ]] || \
    fail "Yazi package manifest link is missing"
  [[ -d "$HOME/.config/yazi/plugins/piper.yazi" ]] || fail "piper.yazi is missing"
  yazi_package_list=$(ya pkg list 2>/dev/null)
  grep -Fq 'yazi-rs/plugins:piper (' <<< "$yazi_package_list" || fail "piper.yazi is not managed by ya pkg"

  if [[ "$PLATFORM_OS" == darwin ]]; then
    iterm2_profile="$DOTFILES_DIR/iterm2/dev.json"
    iterm2_destination="$HOME/Library/Application Support/iTerm2/DynamicProfiles/dev.json"
    plutil -convert xml1 -o /dev/null "$iterm2_profile" || fail "invalid iTerm2 dynamic profile"
    [[ -L "$iterm2_destination" && $(readlink "$iterm2_destination") == "$iterm2_profile" ]] || \
      fail "iTerm2 dev profile link is missing"

    ghostty_binary >/dev/null 2>&1 || fail "Ghostty is required on macOS"
    ghostty_config="$DOTFILES_DIR/ghostty/config.ghostty"
    ghostty_destination="$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
    ghostty_launcher="$DOTFILES_DIR/bin/ghostty-dev"
    ghostty_launcher_destination="$HOME/.local/bin/ghostty-dev"
    validate_ghostty_config_file "$ghostty_config"
    validate_ghostty_applescript "$DOTFILES_DIR/ghostty/open-tab.applescript"
    validate_ghostty_applescript "$DOTFILES_DIR/ghostty/close-tab.applescript"
    [[ -L "$ghostty_destination" && $(readlink "$ghostty_destination") == "$ghostty_config" ]] || \
      fail "Ghostty config link is missing"
    [[ -L "$ghostty_launcher_destination" &&
      $(readlink "$ghostty_launcher_destination") == "$ghostty_launcher" ]] || \
      fail "Ghostty dev launcher link is missing"
  fi

  [[ $(git -C "$HOME/.tmux/plugins/tpm" rev-parse HEAD) == "$TPM_COMMIT" ]] || fail "TPM commit mismatch"
  [[ $(git -C "$HOME/.tmux/plugins/tmux-resurrect" rev-parse HEAD) == "$RESURRECT_COMMIT" ]] || fail "tmux-resurrect commit mismatch"
  [[ $(git -C "$HOME/.tmux/plugins/tmux-continuum" rev-parse HEAD) == "$CONTINUUM_COMMIT" ]] || fail "tmux-continuum commit mismatch"
  tmux_config="$DOTFILES_DIR/tmux/tmux.conf"
  tmux_config_destination="$HOME/.tmux.conf"
  [[ -L "$tmux_config_destination" && $(readlink "$tmux_config_destination") == "$tmux_config" ]] || \
    fail "managed tmux config link is missing"
  [[ $(git -C "$HOME/.oh-my-zsh" rev-parse HEAD) == "$OH_MY_ZSH_COMMIT" ]] || fail "Oh My Zsh commit mismatch"
  [[ $(git -C "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" rev-parse HEAD) == "$ZSH_SYNTAX_HIGHLIGHTING_COMMIT" ]] || fail "zsh-syntax-highlighting commit mismatch"

  tmux -L terminal-tmux-check kill-server >/dev/null 2>&1 || true
  tmux -L terminal-tmux-check -f "$tmux_config" new-session -d -s terminal-tmux-check
  [[ $(tmux -L terminal-tmux-check show-options -gqv prefix) == C-b ]] || \
    fail "managed tmux prefix was not preserved"
  [[ $(tmux -L terminal-tmux-check show-options -gqv default-terminal) == tmux-256color ]] || \
    fail "managed tmux default-terminal was not preserved"
  [[ $(tmux -L terminal-tmux-check show-options -gqv mouse) == on ]] || \
    fail "managed tmux mouse setting was not preserved"
  [[ $(tmux -L terminal-tmux-check show-options -gqv history-limit) == 50000 ]] || \
    fail "managed tmux history limit was not preserved"
  [[ $(tmux -L terminal-tmux-check show-options -gqv status-interval) == 60 ]] || \
    fail "managed tmux status interval was not preserved"
  [[ $(tmux -L terminal-tmux-check show-options -gqv @continuum-restore) == off ]] || fail "tmux config validation failed"
  prefix_bindings=$(tmux -L terminal-tmux-check list-keys -T prefix)
  grep -Eq '^bind-key +(-r +)?-T prefix < +swap-window -d -t -1$' <<< "$prefix_bindings" || \
    fail "managed tmux Prefix+< binding was not preserved"
  grep -Eq '^bind-key +(-r +)?-T prefix > +swap-window -d -t \+1$' <<< "$prefix_bindings" || \
    fail "managed tmux Prefix+> binding was not preserved"
  grep -Eq '^bind-key +(-r +)?-T prefix t +display-popup ' <<< "$prefix_bindings" || \
    fail "managed tmux Prefix+t popup binding was not preserved"
  grep -E '^bind-key +(-r +)?-T prefix g +' <<< "$prefix_bindings" | grep -Fq 'lazygit-safe' || \
    fail "managed tmux Prefix+g binding was not preserved"
  grep -E '^bind-key +(-r +)?-T prefix s +' <<< "$prefix_bindings" | grep -Fq 'session-status-counts.sh' || \
    fail "managed tmux Prefix+s chooser binding was not preserved"
  tmux -L terminal-tmux-check kill-server

  printf 'tmux.conf sha256: %s\n' "$(sha256_file "$tmux_config")"
  printf 'lazygit config sha256: %s\n' "$(sha256_file "$DOTFILES_DIR/lazygit/config.yml")"
}

main() {
  detect_platform

  if [[ ${1:-} == --check ]]; then
    validate
    return
  fi

  mkdir -p "$HOME/.local/bin"
  # PATH/locale 必须在可能失败的下载之前持久化。bootstrap 子进程无法改变
  # 已打开的父 shell，但后续新 shell 会立即获得 ~/.local/bin 和正确 locale。
  ensure_shell_path
  ensure_shell_locale
  install_prerequisites
  configure_login_shell
  install_ghostty
  ensure_linux_fd_command
  configure_locale
  install_tmux
  ensure_tmux_terminfo
  ensure_ghostty_terminfo
  install_lazygit
  install_glab
  install_delta
  install_fzf
  install_zoxide
  install_iris
  install_glow
  install_yazi
  install_pre_commit
  install_node_for_todoist
  install_codex
  install_termscp
  install_todoist_cli
  remove_legacy_todo_bridge
  uninstall_druk
  install_fresh
  install_oh_my_zsh
  install_plugin tpm https://github.com/tmux-plugins/tpm.git "$TPM_COMMIT"
  install_plugin tmux-resurrect https://github.com/tmux-plugins/tmux-resurrect.git "$RESURRECT_COMMIT"
  install_plugin tmux-continuum https://github.com/tmux-plugins/tmux-continuum.git "$CONTINUUM_COMMIT"

  install_links
  install_todo_agent_service
  install_yazi_packages
  seed_zoxide_history
  install_iterm2_profile
  install_ghostty_config
  validate

  if tmux list-sessions >/dev/null 2>&1; then
    tmux source-file "$HOME/.tmux.conf"
  fi

  configure_git_identity
  log "Installation complete"
  printf '%s\n' 'Start the managed login shell now with: exec zsh -l'
  printf '%s\n' 'Connect with menu: connect-remote-dev <host>'
  printf '%s\n' 'Transfer between the SSH server and this Mac: termscp-mac'
  printf '%s\n' 'Ghostty stable app and managed config are ready on macOS'
  printf '%s\n' 'Choose an SSH host and open the remote menu in Ghostty: ghostty-dev'
  remind_gitlab_auth
  remind_ssh_key
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
