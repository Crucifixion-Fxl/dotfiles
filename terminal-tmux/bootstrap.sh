#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# macOS + Debian/Ubuntu 可复现安装入口
#
# 默认模式：安装系统依赖、锁定版本工具/插件、刷新配置链接，最后验证。
# --check 模式：只读验证现有安装，不修改文件或安装软件。
#
# 可复现策略：
#   - pre-commit/tmux/lazygit/delta/fzf/zoxide/Yazi 及 shell 插件由 versions.lock 锁定。
#   - Release 下载包校验 SHA256，Git 插件校验完整 commit。
#   - Codex CLI 按约定始终安装 @openai/codex@latest，不锁版本。
#   - 已有目标文件会先备份再链接，不静默覆盖用户配置。
# =============================================================================

DOTFILES_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=versions.lock
source "$DOTFILES_DIR/versions.lock"

export PATH="$HOME/.local/bin:$PATH"

log() {
  printf '==> %s\n' "$*"
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

yazi_is_locked_version() {
  command -v yazi >/dev/null 2>&1 &&
    command -v ya >/dev/null 2>&1 &&
    [[ $(yazi --version 2>/dev/null | awk '{print $1, $2}') == "Yazi $YAZI_VERSION" ]] &&
    [[ $(ya --version 2>/dev/null | awk '{print $1, $2}') == "Ya $YAZI_VERSION" ]]
}

codex_is_installed() {
  command -v codex >/dev/null 2>&1 && codex --version 2>/dev/null | grep -Eq '^codex-cli [0-9]'
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
      bash bison bubblewrap ca-certificates curl fd-find ffmpeg file fonts-noto-cjk gcc git imagemagick jq locales make
      ncurses-base ncurses-bin nodejs npm p7zip-full pkg-config poppler-utils python3 ripgrep tar unzip vim zsh
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
      bash bison curl git libevent ncurses node pkgconf python utf8proc zsh
      yazi ffmpeg-full sevenzip jq poppler fd ripgrep resvg imagemagick-full
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
  codex_is_installed || fail "latest Codex CLI installation verification failed"
  log "Installed $(codex --version)"
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
  install_git_checkout zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git \
    "$ZSH_AUTOSUGGESTIONS_COMMIT" "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  install_git_checkout zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$ZSH_SYNTAX_HIGHLIGHTING_COMMIT" "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
}

install_iterm2_profile() {
  [[ "$PLATFORM_OS" == darwin ]] || return 0

  local profile destination
  profile="$DOTFILES_DIR/iterm2/dev.json"
  destination="$HOME/Library/Application Support/iTerm2/DynamicProfiles/dev.json"

  command -v plutil >/dev/null 2>&1 || fail "plutil is required to validate the iTerm2 profile"
  plutil -convert xml1 -o /dev/null "$profile" || fail "invalid iTerm2 dynamic profile: $profile"
  backup_and_link "$profile" "$destination"
}

install_links() {
  backup_and_link "$DOTFILES_DIR/shell/zshrc" "$HOME/.zshrc"
  backup_and_link "$DOTFILES_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"
  backup_and_link "$DOTFILES_DIR/tmux/session-status-counts.sh" "$HOME/.tmux/session-status-counts.sh"
  backup_and_link "$DOTFILES_DIR/bin/tmux-zsh" "$HOME/.local/bin/tmux-zsh"
  backup_and_link "$DOTFILES_DIR/bin/lazygit-safe" "$HOME/.local/bin/lazygit-safe"
  backup_and_link "$DOTFILES_DIR/bin/remote-dev-entry" "$HOME/.local/bin/remote-dev-entry"
  backup_and_link "$DOTFILES_DIR/bin/connect-remote-dev" "$HOME/.local/bin/connect-remote-dev"
  backup_and_link "$DOTFILES_DIR/shell/tmux-window-name.zsh" "$HOME/.config/tmux/window-name.zsh"
  backup_and_link "$DOTFILES_DIR/yazi/yazi.toml" "$HOME/.config/yazi/yazi.toml"
  backup_and_link "$DOTFILES_DIR/yazi/init.lua" "$HOME/.config/yazi/init.lua"
  backup_and_link "$DOTFILES_DIR/codex/notify-tmux.sh" "$HOME/.codex/hooks/notify-tmux.sh"
  backup_and_link "$DOTFILES_DIR/codex/hooks.json" "$HOME/.codex/hooks.json"

  local lazygit_config_dir
  lazygit_config_dir=$(lazygit --print-config-dir)
  backup_and_link "$DOTFILES_DIR/lazygit/config.yml" "$lazygit_config_dir/config.yml"
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

# --- 安装后合同验证 ---------------------------------------------------------
validate() {
  local iterm2_profile iterm2_destination pre_commit_link pre_commit_wrapper yazi_config yazi_config_destination yazi_init yazi_init_destination

  log "Validating locked environment"
  tmux_is_locked_version || fail "expected tmux $TMUX_VERSION"
  lazygit_is_locked_version || fail "expected lazygit $LAZYGIT_VERSION"
  delta_is_locked_version || fail "expected git-delta $DELTA_VERSION"
  fzf_is_locked_version || fail "expected fzf $FZF_VERSION"
  zoxide_is_locked_version || fail "expected zoxide $ZOXIDE_VERSION"
  yazi_is_locked_version || fail "expected Yazi $YAZI_VERSION and matching ya CLI"
  pre_commit_is_locked_version || fail "expected pre-commit $PRE_COMMIT_VERSION"
  codex_is_installed || fail "Codex CLI is required"
  command -v zsh >/dev/null 2>&1 || fail "zsh is required"
  command -v bash >/dev/null 2>&1 || fail "bash is required"
  command -v git >/dev/null 2>&1 || fail "git is required"
  command -v vi >/dev/null 2>&1 || fail "vi is required"
  vi --version 2>/dev/null | grep -Eq '\+mouse([[:space:]]|$)' || fail "vi must support mouse input"
  infocmp tmux-256color >/dev/null 2>&1 || fail "tmux-256color terminfo is missing"
  LC_ALL=zh_CN.UTF-8 locale charmap 2>/dev/null | grep -qi 'UTF-8' || fail "zh_CN.UTF-8 locale is required"

  zsh -n "$DOTFILES_DIR/shell/tmux-window-name.zsh"
  zsh -n "$DOTFILES_DIR/shell/zshrc"
  bash -n "$DOTFILES_DIR/bootstrap.sh"
  bash -n "$DOTFILES_DIR/bin/remote-dev-entry"
  bash -n "$DOTFILES_DIR/bin/connect-remote-dev"
  bash -n "$DOTFILES_DIR/bin/pre-commit"
  sh -n "$DOTFILES_DIR/bin/lazygit-safe"
  bash -n "$DOTFILES_DIR/tmux/session-status-counts.sh"
  bash -n "$DOTFILES_DIR/codex/notify-tmux.sh"
  bash "$DOTFILES_DIR/tests/test-remote-dev-entry.sh"
  bash "$DOTFILES_DIR/tests/test-connect-remote-dev.sh"
  sh "$DOTFILES_DIR/tests/test-lazygit-safe.sh"

  pre_commit_wrapper="$DOTFILES_DIR/bin/pre-commit"
  pre_commit_link="$HOME/.local/bin/pre-commit"
  [[ -L "$pre_commit_link" && $(readlink "$pre_commit_link") == "$pre_commit_wrapper" ]] || \
    fail "pre-commit launcher link is missing"

  yazi_config="$DOTFILES_DIR/yazi/yazi.toml"
  yazi_config_destination="$HOME/.config/yazi/yazi.toml"
  [[ -L "$yazi_config_destination" && $(readlink "$yazi_config_destination") == "$yazi_config" ]] || \
    fail "Yazi main config link is missing"

  yazi_init="$DOTFILES_DIR/yazi/init.lua"
  yazi_init_destination="$HOME/.config/yazi/init.lua"
  [[ -L "$yazi_init_destination" && $(readlink "$yazi_init_destination") == "$yazi_init" ]] || \
    fail "Yazi init config link is missing"

  if [[ "$PLATFORM_OS" == darwin ]]; then
    iterm2_profile="$DOTFILES_DIR/iterm2/dev.json"
    iterm2_destination="$HOME/Library/Application Support/iTerm2/DynamicProfiles/dev.json"
    plutil -convert xml1 -o /dev/null "$iterm2_profile" || fail "invalid iTerm2 dynamic profile"
    [[ -L "$iterm2_destination" && $(readlink "$iterm2_destination") == "$iterm2_profile" ]] || \
      fail "iTerm2 dev profile link is missing"
  fi

  [[ $(git -C "$HOME/.tmux/plugins/tpm" rev-parse HEAD) == "$TPM_COMMIT" ]] || fail "TPM commit mismatch"
  [[ $(git -C "$HOME/.tmux/plugins/tmux-resurrect" rev-parse HEAD) == "$RESURRECT_COMMIT" ]] || fail "tmux-resurrect commit mismatch"
  [[ $(git -C "$HOME/.tmux/plugins/tmux-continuum" rev-parse HEAD) == "$CONTINUUM_COMMIT" ]] || fail "tmux-continuum commit mismatch"
  [[ $(git -C "$HOME/.oh-my-zsh" rev-parse HEAD) == "$OH_MY_ZSH_COMMIT" ]] || fail "Oh My Zsh commit mismatch"
  [[ $(git -C "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" rev-parse HEAD) == "$ZSH_AUTOSUGGESTIONS_COMMIT" ]] || fail "zsh-autosuggestions commit mismatch"
  [[ $(git -C "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" rev-parse HEAD) == "$ZSH_SYNTAX_HIGHLIGHTING_COMMIT" ]] || fail "zsh-syntax-highlighting commit mismatch"

  tmux -L terminal-tmux-check kill-server >/dev/null 2>&1 || true
  tmux -L terminal-tmux-check -f "$DOTFILES_DIR/tmux/tmux.conf" new-session -d -s terminal-tmux-check
  [[ $(tmux -L terminal-tmux-check show-options -gqv @continuum-restore) == off ]] || fail "tmux config validation failed"
  tmux -L terminal-tmux-check kill-server

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
  # PATH/locale 必须在可能失败的下载之前持久化。bootstrap 子进程无法改变
  # 已打开的父 shell，但后续新 shell 会立即获得 ~/.local/bin 和正确 locale。
  ensure_shell_path
  ensure_shell_locale
  install_prerequisites
  ensure_linux_fd_command
  configure_locale
  install_tmux
  ensure_tmux_terminfo
  install_lazygit
  install_delta
  install_fzf
  install_zoxide
  install_yazi
  install_pre_commit
  install_codex
  install_oh_my_zsh

  install_plugin tpm https://github.com/tmux-plugins/tpm.git "$TPM_COMMIT"
  install_plugin tmux-resurrect https://github.com/tmux-plugins/tmux-resurrect.git "$RESURRECT_COMMIT"
  install_plugin tmux-continuum https://github.com/tmux-plugins/tmux-continuum.git "$CONTINUUM_COMMIT"

  install_links
  seed_zoxide_history
  install_iterm2_profile
  validate

  if tmux list-sessions >/dev/null 2>&1; then
    tmux source-file "$HOME/.tmux.conf"
  fi

  log "Installation complete"
  printf '%s\n' 'Reload Bash with: source "$HOME/.bashrc"'
  printf '%s\n' 'Reload zsh with: exec zsh -l'
  printf '%s\n' 'Connect with menu: connect-remote-dev <host>'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
