# dotfiles

个人开发环境配置仓库。目前包含 `terminal-tmux/`：一套可在 macOS 和
Debian/Ubuntu 远端服务器上严格复现的 tmux、lazygit、git-delta、Codex CLI、
Oh My Zsh、Codex 状态通知和 zsh 交互环境。

## 目录结构

```text
.
├── README.md
└── terminal-tmux/
    ├── bootstrap.sh                 # 安装、链接和验证入口
    ├── versions.lock                # 工具版本、插件 commit 和 SHA256
    ├── bin/
    │   └── tmux-zsh                 # tmux pane 的统一 zsh 入口
    ├── tmux/
    │   ├── tmux.conf                # tmux 主配置
    │   └── session-status-counts.sh # session 选择器的 Codex 状态统计
    ├── shell/
    │   ├── zshrc                    # Oh My Zsh、主题和插件配置
    │   └── tmux-window-name.zsh     # 根据目录和前台命令更新窗口名
    ├── tests/
    │   └── test-bootstrap-contract.sh # bootstrap 回归检查
    ├── codex/
    │   ├── hooks.json               # Codex 生命周期 hook 注册
    │   └── notify-tmux.sh           # 🔄、❓、✅ 状态写入 tmux
    └── lazygit/
        └── config.yml               # 使用 git-delta 渲染 diff
```

## 提供的行为

- `Prefix + t`：在当前目录打开 zsh popup。
- `Prefix + g`：在当前目录打开 lazygit popup。
- `Prefix + G`：在当前目录创建 lazygit window，退出后自动关闭。
- `Prefix + s`：显示 session tree，并汇总各 window 的 Codex 状态。
- 普通命令运行时，window 名显示命令名；Python/Node 脚本优先显示脚本名。
- 回到 zsh prompt 后，window 名恢复为当前目录名。
- Codex 运行、等待输入、完成时分别显示 `🔄 codex`、`❓ codex`、`✅ codex`。
- zsh 使用 Oh My Zsh 的 `robbyrussell` 主题，并启用 `git`、
  `zsh-autosuggestions` 和 `zsh-syntax-highlighting` 插件。
- tmux-continuum 每 15 分钟保存 session/window/pane 布局。
- tmux 启动时不自动恢复，也不保存 pane 的历史显示内容。
- `Prefix + S` 手动保存，`Prefix + R` 手动恢复。

## 锁定版本

实际版本和校验值以 `terminal-tmux/versions.lock` 为准。当前锁定：

- tmux `3.7b`
- lazygit `0.63.0`
- git-delta `0.19.2`
- Codex CLI：每次安装时获取 npm 官方包的最新版本（不锁版本）
- TPM、tmux-resurrect、tmux-continuum 的固定 Git commit
- Oh My Zsh、zsh-autosuggestions、zsh-syntax-highlighting 的固定 Git commit

tmux、lazygit 和 git-delta 的官方 Release 包均进行 SHA256 校验。tmux 和 zsh
相关 Git 仓库必须处于锁定 commit；如果目录存在本地修改，bootstrap 会停止，
避免覆盖用户改动。Codex CLI 是例外：bootstrap 始终安装
`@openai/codex@latest`。

## 安装

仓库是私有仓库，目标机器需要先配置 GitHub HTTPS 凭据、PAT、GitHub CLI 或
其他允许读取该仓库的认证方式。

```bash
git clone https://github.com/Crucifixion-Fxl/dotfiles ~/.dotfiles
~/.dotfiles/terminal-tmux/bootstrap.sh
```

Debian/Ubuntu 使用 `apt` 安装以下类型的前置依赖：

- `bash`、`zsh`、`git`、`curl`
- `nodejs`、`npm`（用于安装最新 Codex CLI）
- `gcc`、`make`、`pkg-config`、`bison`
- `libevent`、`ncurses`、`utf8proc` 开发包，以及提供 `tmux-256color` 的
  `ncurses-base`

apt 安装使用 `DEBIAN_FRONTEND=noninteractive`，适用于容器、CI 和没有
`dialog`/`whiptail` 的精简服务器，不会等待 debconf 交互输入。

如果 apt 中的 tmux 版本不同，bootstrap 会从官方源码构建锁定的 tmux，并安装到
`~/.local`。lazygit 和 git-delta 使用与操作系统、CPU 架构匹配的官方 Release
包。Codex CLI 通过官方 npm 包 `@openai/codex@latest` 安装。它们都安装到
`~/.local/bin`。Oh My Zsh 及第三方插件通过 Git 安装到 `~/.oh-my-zsh`。apt
安装需要 root 或 sudo 权限。

macOS 使用 Homebrew 安装构建依赖；锁定版本已经存在时不会重复安装对应工具。

## 更新已有机器

拉取最新配置后重新执行 bootstrap。它会安装新增依赖、切换到锁定 commit、刷新
符号链接并完成验证：

```bash
git -C ~/.dotfiles pull --ff-only
bash ~/.dotfiles/terminal-tmux/bootstrap.sh
exec zsh -l
```

如果 Oh My Zsh 或插件目录存在未提交的本地修改，bootstrap 会停止，不会覆盖。

## 配置链接

bootstrap 将仓库文件链接到程序实际读取的位置：

| 仓库文件 | 目标路径 |
| --- | --- |
| `terminal-tmux/shell/zshrc` | `~/.zshrc` |
| `terminal-tmux/tmux/tmux.conf` | `~/.tmux.conf` |
| `terminal-tmux/tmux/session-status-counts.sh` | `~/.tmux/session-status-counts.sh` |
| `terminal-tmux/bin/tmux-zsh` | `~/.local/bin/tmux-zsh` |
| `terminal-tmux/shell/tmux-window-name.zsh` | `~/.config/tmux/window-name.zsh` |
| `terminal-tmux/codex/notify-tmux.sh` | `~/.codex/hooks/notify-tmux.sh` |
| `terminal-tmux/codex/hooks.json` | `~/.codex/hooks.json` |
| `terminal-tmux/lazygit/config.yml` | `lazygit --print-config-dir` 返回目录中的 `config.yml` |

已有目标文件会先重命名为带时间戳的 `.backup.*` 文件。`~/.zshrc` 由仓库完整
托管，包含 Oh My Zsh、主题、插件、Conda 条件加载和 tmux 窗口命名配置。
机器专属且不应提交的 zsh 配置可以写入 `~/.zshrc.local`，托管配置会在最后
自动加载它。

bootstrap 确保 `~/.profile`、`~/.bashrc` 和托管的 `~/.zshrc` 都将
`~/.local/bin` 加入 `PATH`；如果已有 `~/.bash_profile`，也会同步更新它。
PATH 配置会在安装开始时写入，因此后续步骤中断也不会遗漏。

bootstrap 子进程无法修改已经打开的父 shell。首次安装完成后，当前终端可以执行：

```bash
export PATH="$HOME/.local/bin:$PATH"
hash -r
```

远端登录 shell 可以继续使用 bash；tmux 新 pane 统一进入 zsh，以保证窗口命名
hook 在所有机器上的行为一致。

## 验证

只验证、不修改现有安装：

```bash
~/.dotfiles/terminal-tmux/bootstrap.sh --check
```

验证内容包括：

- tmux、lazygit、git-delta、Codex CLI 版本
- bash、zsh、git、UTF-8 locale 和 `tmux-256color` terminfo
- 托管 zshrc 和其他 Bash/zsh 脚本的语法
- 三个 tmux 插件以及 Oh My Zsh、两个 zsh 插件的 commit
- 使用隔离 socket 启动 tmux 并加载完整配置
- tmux 与 lazygit 配置文件 SHA256

## 连接远端

```bash
ssh -t HOST 'PATH="$HOME/.local/bin:$PATH" exec tmux new-session -A -s main'
```

该命令连接已有的 `main` session；不存在时创建。SSH 断开不会终止远端 tmux
中的任务。

## 不同步的内容

仓库不会收录：

- tmux-resurrect 生成的每台机器 session 数据
- shell history
- `~/.zshrc.local` 中的机器专属 shell 配置
- Codex 登录信息、凭据和完整 `config.toml`
- SSH key、PAT、API token
- 本地缓存、下载文件和机器专属配置

这些内容必须保留在各自机器上，不应提交到 dotfiles 仓库。

安装完成后，远端第一次使用 Codex 需要在该机器上单独登录：

```bash
codex login
```
