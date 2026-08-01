# dotfiles

个人开发环境配置仓库。目前包含 `terminal-tmux/`：一套可在 macOS 和
Debian/Ubuntu 远端服务器上严格复现的 Ghostty、pre-commit、tmux、lazygit、
git-delta、Yazi、Glow Markdown 预览、Iris、termscp、Codex CLI、Fresh、Oh My Zsh、
Codex 状态通知、Todoist TUI 和 zsh 交互环境。

## 目录结构

```text
.
├── README.md
└── terminal-tmux/
    ├── bootstrap.sh                 # 安装、链接和验证入口
    ├── versions.lock                # 工具版本、插件 commit 和 SHA256
    ├── bin/
    │   ├── tmux-zsh                 # tmux pane 的统一 zsh 入口
    │   ├── lazygit-safe             # 信任当前仓库后启动 lazygit
    │   ├── pre-commit               # 为官方 zipapp 选择 Python 3.10+
    │   ├── ghostty-dev              # 新 Ghostty tab 中的远端开发入口
    │   ├── ghostty-tab-command      # 远端入口结束后精确关闭对应 tab
    │   ├── remote-dev-entry         # SSH 后选择宿主机或容器开发环境
    │   ├── connect-remote-dev       # 启动交互 SSH 和 SFTP 反向转发
    │   ├── termscp-mac              # 在服务器/容器浏览并传输 Mac 文件
    │   ├── termscp-bridge-relay     # Docker bridge 到宿主机隧道的临时中继
    │   ├── termscp-key-authorizer   # Mac 侧受限 SFTP 公钥自动授权
    │   ├── todo                     # 基于官方 Todoist CLI 的交互式 TUI
    │   └── todo-agent               # Todoist 项目到 Codex worktree 的调度器
    ├── tmux/
    │   ├── tmux.conf                # 本地与远端共用的 tmux 主配置
    │   └── session-status-counts.sh # session 选择器的 Codex 状态统计
    ├── shell/
    │   ├── zshrc                    # Oh My Zsh、主题、插件和 Yazi y() 包装函数
    │   └── tmux-window-name.zsh     # 根据目录和前台命令更新窗口名
    ├── tests/
    │   ├── test-bootstrap-contract.sh # bootstrap 回归检查
    │   ├── test-remote-dev-entry.sh   # 宿主机/容器入口路由检查
    │   ├── test-connect-remote-dev.sh # SSH 自举上传和反向转发检查
    │   ├── test-termscp-mac.sh        # Mac SFTP 入口参数检查
    │   ├── test-termscp-bridge-relay.sh # Docker bridge 中继检查
    │   ├── test-termscp-key-authorizer.sh # 容器公钥自动授权检查
    │   ├── test-todo-tui.py          # TUI 数据、中文宽度和视觉契约检查
    │   ├── test-todo-agent.py        # Agent 注册、状态、worktree 和重试检查
    │   ├── test-ghostty-dev.sh        # Ghostty 启动参数检查
    │   └── test-lazygit-safe.sh       # Git safe.directory 回归检查
    ├── codex/
    │   ├── hooks.json               # Codex 生命周期 hook 注册
    │   └── notify-tmux.sh           # 🔄、❓、✅ 状态写入 tmux
    ├── systemd/
    │   └── todo-agent.service       # Linux 用户级常驻调度服务
    ├── lazygit/
    │   └── config.yml               # 使用 git-delta 渲染 diff
    ├── yazi/
    │   ├── yazi.toml                # 文本编辑与 Markdown 预览规则
    │   ├── init.lua                 # zoxide 历史同步
    │   └── package.toml             # Yazi 插件版本锁
    ├── ghostty/
    │   ├── config.ghostty           # 本地 zsh、字体及 SSH shell integration
    │   ├── close-tab.applescript    # 按稳定 ID 关闭已结束的开发 tab
    │   └── open-tab.applescript     # 在现有 Ghostty 窗口创建开发 tab
    └── iterm2/
        └── dev.json                 # 可移植的 iTerm2 Dynamic Profile
```

## 提供的行为

- `Prefix + t`：在当前目录打开 zsh popup。
- `Prefix + g`：在当前目录打开 lazygit popup。
- `Prefix + G`：在当前目录创建 lazygit window，退出后自动关闭。
- `Prefix + <`：将当前 window 在底部状态栏中向左移动，并保持选中。
- `Prefix + >`：将当前 window 在底部状态栏中向右移动，并保持选中。
- 启动 lazygit 前自动定位当前 Git 仓库根目录，并将该具体路径加入用户级
  `safe.directory`；不会配置通配符 `*`。
- `Prefix + s`：显示 session tree，并汇总各 window 的 Codex 状态。
- 普通命令运行时，window 名显示命令名；Python/Node 脚本优先显示脚本名。
- 回到 zsh prompt 后，window 名恢复为当前目录名。
- Codex 运行、等待输入、完成时分别显示 `🔄 codex`、`❓ codex`、`✅ codex`。
- zsh 使用 Oh My Zsh 的 `robbyrussell` 主题，并启用 `git` 和
  `zsh-syntax-highlighting` 插件；本地、SSH 和 tmux 中的命令建议统一由 Iris 提供，
  不再加载 `zsh-autosuggestions`。
- 使用 `y` 启动 Yazi；退出时当前 shell 会切换到 Yazi 最后所在目录。
- Yazi 中按 Enter 用可编辑的 Vim 打开文本文件，并支持鼠标滚轮查看内容。
- Vim 在本地和远端默认显示绝对行号。
- Yazi 通过官方 `piper.yazi` 调用 Glow，在预览区渲染可滚动的 Markdown。
- macOS 同时管理 iTerm2 `dev` Profile 和 Ghostty 配置；`ghostty-dev` 与
  iTerm2 Profile 共用同一个远端选择器。
- macOS bootstrap 会通过 Homebrew cask 安装 Ghostty 稳定版，并恢复当前使用的
  Maple Mono NF CN、Catppuccin、透明度、窗口、tab、分屏和快捷键配置。
- tmux 直接加载仓库内的 `tmux.conf`，保持 `Ctrl-b` Prefix、原始状态栏、popup、
  Lazygit、Codex session tree 与容器内 tmux 行为。
- tmux-continuum 每 15 分钟保存 session/window/pane 布局。
- tmux 启动时不自动恢复，也不保存 pane 的历史显示内容。
- `Prefix + S` 手动保存，`Prefix + R` 手动恢复。
- bootstrap 在本地 macOS 和远端 Debian/Ubuntu 默认安装 `pre-commit` CLI；
  仓库级 hook 仍由各项目在存在 `.pre-commit-config.yaml` 时执行
  `pre-commit install` 启用。

## 锁定版本

实际版本和校验值以 `terminal-tmux/versions.lock` 为准。当前锁定：

- tmux `3.7b`
- lazygit `0.63.0`
- git-delta `0.19.2`
- fzf `0.74.0`
- zoxide `0.10.0`
- Iris `0.4.8`
- Glow `2.1.2`
- Yazi `26.5.6`（`yazi` 与 `ya` 保持完全相同的版本）
- pre-commit `4.6.0`
- Ghostty：macOS 通过 Homebrew cask 安装当前稳定版（不锁版本）
- Codex CLI：每次安装时获取 npm 官方包的最新版本（不锁版本）
- termscp：通过官方通用安装脚本获取当前版本（不锁版本）
- Fresh：通过官方通用安装脚本安装（不锁版本）
- TPM、tmux-resurrect、tmux-continuum 的固定 Git commit
- Oh My Zsh、zsh-syntax-highlighting 的固定 Git commit

pre-commit、tmux、lazygit、git-delta、fzf、zoxide、Iris、Glow 和 Yazi 的官方
Release 包均进行 SHA256 校验。`piper.yazi` 由 Yazi 官方包管理器按
`package.toml` 中的 revision 和 hash 安装。tmux 和 zsh
相关 Git 仓库必须处于锁定 commit；如果目录存在本地修改，bootstrap 会停止，
避免覆盖用户改动。Ghostty、Codex CLI、termscp 和 Fresh 是例外：Ghostty 跟随
Homebrew cask 的稳定版，Codex 始终安装 `@openai/codex@latest`，termscp 与
Fresh 分别使用各自的官方通用安装脚本。

## 安装

仓库是私有仓库，目标机器需要先配置 GitHub HTTPS 凭据、PAT、GitHub CLI 或
其他允许读取该仓库的认证方式。

```bash
git clone https://github.com/Crucifixion-Fxl/dotfiles ~/.dotfiles
~/.dotfiles/terminal-tmux/bootstrap.sh
```

在一台新 Mac 上，先准备 Homebrew 和该私有仓库的读取权限，然后只需运行上面的
bootstrap 一次。脚本会安装 Ghostty 稳定版与 Maple Mono NF CN 字体、链接托管
配置并用 Ghostty 自带解析器验证；无需再手动复制 Ghostty 设置。

Debian/Ubuntu 使用 `apt` 安装以下类型的前置依赖：

- `bash`、`zsh`、`git`、`curl`
- `locales`、`fonts-noto-cjk`（中文 locale 和服务端 CJK 字体）
- `nodejs`、`npm`（用于安装最新 Codex CLI）
- Python 3.10+（用于运行官方 pre-commit zipapp）
- `gcc`、`make`、`pkg-config`、`bison`
- `bubblewrap`（Linux 的非特权进程沙箱工具，提供 `bwrap` 命令）
- Yazi 所需的 `file`、`unzip`，以及预览/搜索依赖 `ffmpeg`、`p7zip-full`、
  `jq`、`poppler-utils`、`fd-find`、`ripgrep`、`resvg`、
  `imagemagick`
- `libevent`、`ncurses`、`utf8proc` 开发包，以及提供 `tmux-256color` 的
  `ncurses-base`

apt 安装使用 `DEBIAN_FRONTEND=noninteractive`，适用于容器、CI 和没有
`dialog`/`whiptail` 的精简服务器，不会等待 debconf 交互输入。
不同 Ubuntu/Debian 版本不一定提供可选的 `resvg`；bootstrap 会在 apt 索引中
检查后安装，缺失时只跳过 SVG 预览能力，不影响 Yazi 本体安装。fzf 和 zoxide
不使用发行版中可能过旧的 apt 包，而是安装锁定的官方 Release。

bootstrap 会在 `/etc/locale.gen` 中启用并生成 `zh_CN.UTF-8`，并向 Bash 与
托管 zshrc 持久化：

```bash
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
```

安装完成后，新 shell 会自动生效；当前 Bash 可以执行 `source ~/.bashrc`，当前
zsh 建议执行 `exec zsh -l`。`fonts-noto-cjk` 用于容器内的服务端渲染；SSH 终端
文字最终仍由本机 iTerm2 或 Ghostty 字体渲染。

如果 apt 中的 tmux 版本不同，bootstrap 会从官方源码构建锁定的 tmux，并安装到
`~/.local`。lazygit、git-delta、fzf、zoxide、Iris、Glow 和 Yazi 使用与操作系统、CPU 架构
匹配的官方 Release 包；Ubuntu 不接入非官方 Yazi apt 仓库。pre-commit 使用
macOS 与 Linux 共用的官方 zipapp，并由启动器自动选择 Python 3.10+。Yazi 的
`yazi` 与 `ya` 会一起安装并验证版本一致，随后由 `ya pkg install` 恢复锁定的
`piper.yazi`。Ubuntu 的 `fd-find` 只提供 `fdfind` 命令，
bootstrap 会在 `~/.local/bin` 创建 `fd` 链接。Codex CLI 通过官方 npm 包
`@openai/codex@latest` 安装到 `~/.local/bin`。termscp 使用官方
`https://termscp.rs/install.sh`：macOS 走官方 Homebrew tap，Debian/Ubuntu 下载
官方 `.deb`。安装器使用非交互 `--yes`，因此在服务器或容器中运行 bootstrap
不会等待确认。Fresh 通过
`sinelaw/fresh` 官方通用安装脚本安装：macOS 使用 Homebrew 的 `fresh-editor`，
Debian/Ubuntu 使用官方 `.deb`。迁移时 bootstrap 会先卸载旧的 Druk npm 包并
删除旧的 `~/.druk` standalone 安装、`~/.config/druk` 用户配置和 `~/.cache/druk`
缓存，再安装和验证 `fresh` 命令。Oh My Zsh 及第三方插件通过 Git
安装到用户目录。apt 安装需要 root 或 sudo 权限。

macOS 会先执行 `brew update`，再安装 Yazi、Glow、预览/搜索依赖、
Maple Mono NF CN 与 Symbols Nerd Font，并通过官方文档列出的
`brew install --cask ghostty` 安装 Ghostty 稳定版，最后强制链接
`ffmpeg-full` 与 `imagemagick-full`。如果 Homebrew
中的 Yazi、Glow、fzf 或 zoxide 与锁定版本不同，bootstrap 会用官方 Release 包把锁定
版本安装到 `~/.local/bin`。

Iris 使用同一份托管 `zshrc` 在本地、SSH 和 tmux 中初始化。bootstrap 会安装
锁定的 Iris 官方 Release 到 `~/.local/bin`；不会执行会自行改写 shell 配置的
`iris setup`。旧的 `zsh-autosuggestions` 目录即使还留在某台机器上也不会被加载。

zsh 启动时会初始化 zoxide。首次安装且 zoxide 历史为空时，bootstrap 会把实际
存在的 `~/Documents` 和 `~/.dotfiles` 加入数据库，避免 Yazi 中按大写 `Z` 时
提示“未找到目录历史记录”；已有任何历史时不会重复添加或改变目录权重。Yazi
内部通过小写 `z`（fzf）发生的目录跳转也会实时同步到 zoxide。

远程 Ubuntu 通过 SSH 使用时，图标最终由本机终端字体渲染，因此服务端无需安装
Nerd Font；本机 macOS 的 Homebrew 步骤会安装 `font-symbols-only-nerd-font`。

## 更新已有机器

拉取最新配置后重新执行 bootstrap。它会安装新增依赖、切换到锁定 commit、刷新
符号链接并完成验证：

```bash
git -C ~/.dotfiles pull --ff-only
bash ~/.dotfiles/terminal-tmux/bootstrap.sh
exec zsh -l
```

如果 Oh My Zsh 或插件目录存在未提交的本地修改，bootstrap 会停止，
不会覆盖。

安装收尾时，bootstrap 会检查当前用户的全局 Git `user.name` 和 `user.email`。
已有配置会原样保留；交互终端中可以选择现在补充缺失字段，也可以直接回车跳过，
下次运行 bootstrap 时再次设置。容器或 CI 等非交互环境不会等待输入，而是打印
稍后可执行的 `git config --global` 命令。身份信息属于当前机器或容器，不会写入
dotfiles 仓库。

最后，bootstrap 会报告已存在的 `~/.ssh/*.pub` 公钥，或给出生成 Ed25519 密钥的
`ssh-keygen` 命令，并提醒将公钥添加到远程代码托管账号。脚本不会自动上传密钥；
本仓库使用 GitHub，可以通过 `ssh -T git@github.com` 验证 SSH 权限。

## 配置链接

bootstrap 将仓库文件链接到程序实际读取的位置：

| 托管来源 | 目标路径 |
| --- | --- |
| `terminal-tmux/shell/zshrc` | `~/.zshrc` |
| `terminal-tmux/tmux/tmux.conf` | `~/.tmux.conf` |
| `terminal-tmux/tmux/session-status-counts.sh` | `~/.tmux/session-status-counts.sh` |
| `terminal-tmux/bin/tmux-zsh` | `~/.local/bin/tmux-zsh` |
| `terminal-tmux/bin/lazygit-safe` | `~/.local/bin/lazygit-safe` |
| `terminal-tmux/bin/pre-commit` | `~/.local/bin/pre-commit` |
| `terminal-tmux/bin/remote-dev-entry` | `~/.local/bin/remote-dev-entry` |
| `terminal-tmux/bin/connect-remote-dev` | `~/.local/bin/connect-remote-dev` |
| `terminal-tmux/bin/termscp-mac` | `~/.local/bin/termscp-mac` |
| `terminal-tmux/bin/termscp-bridge-relay` | `~/.local/bin/termscp-bridge-relay` |
| `terminal-tmux/bin/termscp-key-authorizer` | `~/.local/bin/termscp-key-authorizer` |
| `terminal-tmux/bin/todo` | `~/.local/bin/todo` |
| `terminal-tmux/bin/ghostty-dev` | `~/.local/bin/ghostty-dev`（仅 macOS） |
| `terminal-tmux/shell/tmux-window-name.zsh` | `~/.config/tmux/window-name.zsh` |
| `terminal-tmux/yazi/yazi.toml` | `~/.config/yazi/yazi.toml` |
| `terminal-tmux/yazi/init.lua` | `~/.config/yazi/init.lua` |
| `terminal-tmux/yazi/package.toml` | `~/.config/yazi/package.toml` |
| `terminal-tmux/vim/vimrc` | `~/.vimrc` |
| `terminal-tmux/codex/notify-tmux.sh` | `~/.codex/hooks/notify-tmux.sh` |
| `terminal-tmux/codex/hooks.json` | `~/.codex/hooks.json` |
| `terminal-tmux/lazygit/config.yml` | `lazygit --print-config-dir` 返回目录中的 `config.yml` |
| `terminal-tmux/iterm2/dev.json` | `~/Library/Application Support/iTerm2/DynamicProfiles/dev.json`（仅 macOS） |
| `terminal-tmux/ghostty/config.ghostty` | `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`（仅 macOS） |

修改配置时应编辑仓库内的源文件，不要直接改上表右侧的链接目标。

### 配置阅读与维护指南

可执行的 shell/tmux/YAML 配置使用中文分区注释，重点说明“为什么这样配置”
和“修改时不能破坏什么”。建议按以下入口查找：

| 想修改的行为 | 主要文件 | 注意事项 |
| --- | --- | --- |
| zsh 环境、插件、Yazi `y()` | `shell/zshrc` | 机器专属配置放 `~/.zshrc.local` |
| Vim 默认行为 | `vim/vimrc` | 本地和远端共用，默认显示绝对行号 |
| Yazi 文本编辑与 Markdown 预览 | `yazi/yazi.toml` | Enter 使用 Vim；Piper 调用 Glow 渲染 `.md` |
| Yazi 内部目录历史同步 | `yazi/init.lua` | `update_db` 让 fzf 跳转写入 zoxide |
| Yazi 插件版本 | `yazi/package.toml` | 由 `ya pkg` 维护 Piper 的 revision 和 hash |
| tmux 按键、状态栏、插件 | `tmux/tmux.conf` | Prefix 仍为 `Ctrl-b`；修改后可用 `tmux source-file ~/.tmux.conf` 重载 |
| tmux window 动态命名 | `shell/tmux-window-name.zsh` | 不要破坏 Codex owner pane 机制 |
| Codex 的 🔄/❓/✅ 状态 | `codex/hooks.json` + `codex/notify-tmux.sh` | JSON 事件和 shell 状态名必须一致 |
| lazygit diff 渲染 | `lazygit/config.yml` | lazygit 负责滚动，delta 不再开二级 pager |
| Docker 询问和容器列表 | `bin/remote-dev-entry` | 容器分支必须直接 `exec docker exec`，不嵌套宿主机 tmux |
| 连接并更新远程入口 | `bin/connect-remote-dev` | 保持单条 SSH 连接和原子替换 |
| 容器访问 Mac SFTP | `bin/termscp-bridge-relay` + `bin/termscp-mac` | 中继只绑定所选 Docker 网关，并随 SSH 容器入口退出 |
| 容器公钥自动授权 | `bin/termscp-key-authorizer` | 只接收令牌保护的公钥，并写入仅回环、仅 SFTP 的 Mac 授权 |
| 服务器访问 Todoist | `bin/todo` + 官方 `td` CLI | 服务器直接访问 Todoist API；不经过 Mac 或 SSH 反向转发 |
| Ghostty 字体、shell integration | `ghostty/config.ghostty` | 默认窗口保持本地 zsh，远端入口不要写入 `command` |
| Ghostty 远端启动 | `bin/ghostty-dev` | 在现有窗口创建 tab，并用方向键选择 `~/.ssh/config` Host |
| 工具版本 | `versions.lock` | 升级 Release 时同时更新版本和各平台 SHA256 |

JSON 标准不允许写注释，因此不要在下面两个文件中加 `//` 或 `#`：

- `codex/hooks.json`：`UserPromptSubmit` 和 `PostToolUse` 设为 `running`，
  `PermissionRequest` 设为 `input-required`，`Stop` 设为 `done`。每个 hook
  最多运行 5 秒，最终调用 `notify-tmux.sh`。
- `iterm2/dev.json`：这是 iTerm2 导出的完整 Dynamic Profile。常用可维护字段为
  `Name`、`Guid`、`Command` 和 `Normal Font`。`Guid` 必须全局唯一，不能复用
  普通 Profile 的 GUID；颜色字段数量较多，建议在 iTerm2 中调整后重新导出，
  不要手工逐项修改。

`ghostty/config.ghostty` 使用 Ghostty 原生文本格式，可以写 `#` 注释。默认窗口
进入本地 zsh；不要把远端命令写成全局 `command`，否则新窗口和标签页都会自动
连接远端。

已有目标文件会先重命名为带时间戳的 `.backup.*` 文件。`~/.zshrc` 由仓库完整
托管，包含中文 locale、Oh My Zsh、主题、插件、Conda 条件加载和 tmux 窗口命名配置。
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

bootstrap 会把本地和远端账户的登录 shell 设置为 zsh；普通 SSH 登录和 tmux
新 pane 都会进入受管的 login zsh，以保证 PATH、Iris 和窗口命名 hook 行为一致。
修改登录 shell 后，已打开的连接不变，下一次 SSH 登录开始生效。

## 验证

只验证、不修改现有安装：

```bash
~/.dotfiles/terminal-tmux/bootstrap.sh --check
```

验证内容包括：

- pre-commit、tmux、lazygit、git-delta、fzf、zoxide、Iris、Glow、Yazi/`ya`、termscp、Codex CLI、Fresh 版本
- Yazi `package.toml` 链接、官方 `piper.yazi` 安装状态和 Markdown 预览规则
- bash、zsh、git、`zh_CN.UTF-8` locale 和 `tmux-256color` terminfo
- 托管 zshrc 和其他 Bash/zsh 脚本的语法
- Ghostty 应用、iTerm2 Dynamic Profile、Ghostty 配置和 `ghostty-dev` 启动参数
- 三个 tmux 插件以及 Oh My Zsh、zsh-syntax-highlighting 的 commit
- SSH 入口的宿主机/容器分支不会互相嵌套 tmux
- 使用隔离 socket 启动 tmux 并加载完整配置
- tmux 与 lazygit 配置文件 SHA256

## 连接远端

直接进入宿主机 tmux：

```bash
ssh -t HOST 'PATH="$HOME/.local/bin:$PATH" exec tmux new-session -A -s main'
```

该命令连接已有的 `main` session；不存在时创建。SSH 断开不会终止远端 tmux
中的任务。

需要在 SSH 后选择宿主机或 Docker 容器时，从本机运行：

```bash
~/.dotfiles/terminal-tmux/bin/connect-remote-dev HOST
```

`connect-remote-dev` 不要求远端运行 bootstrap，也不需要远端 root 权限。它把本机
仓库里的最新版 `remote-dev-entry`、`termscp-bridge-relay` 和
`termscp-key-authorizer` 编码进 SSH 命令，在同一次连接中分别原子写入远端
`~/.local/bin`、设置仅当前用户可执行，然后立即启动菜单。SSH 的 stdin 始终保留
给交互菜单，因此不会额外建立上传连接。同时它建立
`127.0.0.1:6022`（服务器）到 `127.0.0.1:22`（Mac）的 SSH 反向转发；服务器端
端口只监听回环地址，不会暴露给服务器所在局域网。第二条服务器回环转发默认使用
`6023`，只连接本机随机端口上的临时公钥授权服务。Todo 不再建立反向转发；
`ExitOnForwardFailure` 会在任一 SFTP 端口被占用或服务器禁用 TCP forwarding 时
直接终止连接并显示错误。

### 在服务器上使用 Todoist TUI

在要运行 Todo 的 Linux 服务器中拉取本仓库并运行一次 bootstrap。bootstrap
会安装锁定版本的官方 `@doist/todoist-cli`，并把 `td` 和 `todo` 放入
`~/.local/bin`。官方 CLI 要求 Node.js 24 或更高版本；Linux 系统版本过旧时，
bootstrap 会安装经过 SHA256 校验的 Node.js 24 LTS 用户级运行时。安装后直接运行：

```bash
todo
```

服务器上第一次使用且没有有效凭据时，`todo` 会显示紫色可视化登录弹窗。到 Todoist
“设置 → 集成 → 开发者”复制 API Token，并在隐藏输入框中粘贴。Token 先通过
`td auth status --json` 验证，成功后以 `0600` 权限保存在
`~/.local/state/todoist-cli/token`，不会出现在命令参数或 dotfiles 中；之后运行
`todo` 会直接进入任务界面。若已经通过 `td auth login` 登录，或已设置
`TODOIST_API_TOKEN`，TUI 会优先复用官方 CLI 的现有认证，不再弹窗。

`todo` 只打开全屏 TUI，不提供日常 CRUD 子命令。左侧显示“今天、已计划、全部、
已完成”和所有真实 Todoist 项目，中间显示当前项目的任务，宽终端还会显示右侧详情。
任务保持 Todoist CLI 返回的顺序，搜索和刷新只过滤内容，不会再按到期时间或标题重新
排列。TUI 启动和手动刷新时读取项目、全部未完成任务，以及最近 89 天的已完成任务；
运行期间每 30 秒自动刷新一次。
所有面板、输入框、确认框和按钮都使用紫色 Unicode 圆角矩形边界。可以用鼠标点击
列表、任务复选框和按钮，用滚轮滚动；也可以用方向键或 `j/k` 导航，`n` 新建、
`e`/`Enter` 编辑、`Space` 完成或恢复、`d` 删除、`/` 搜索。新建和编辑任务时都可以
选择项目；编辑已有任务切换项目时，后端会调用官方 `td task move`。

所有读取、创建、修改、移动、完成、恢复和删除操作都由服务器上的官方 `td` CLI 直接
发往 Todoist，不依赖 Mac 在线，也不使用 EventKit、Todo bridge 或 SSH Todo 反向端口。
Token 失效时，下一次运行 `todo` 会自动重新显示同一套可视化登录弹窗。

需要改用单独的 Token 文件时，可以设置 `TODOIST_TOKEN_FILE`；需要覆盖 `td` 路径时，
可以设置 `TODOIST_CLI`。

### 用 Todoist 项目调度 Codex Agent

`todo-agent` 以 Todoist 项目作为仓库管理粒度，以全局标签表示任务状态：

```text
codex-ready    等待领取
codex-running  正在执行
codex-review   等待人工审核
codex-failed   执行失败
```

在 Todoist App 中创建代码任务时，只需把任务放到对应项目；需求准备好后添加
`codex-ready`。没有 `codex-*` 标签的任务不会被调度。

每个仓库只需在服务器上注册一次。先 clone 仓库并停留在希望使用的基础分支：

```bash
cd /srv/repos/terminal-tmux
todo-agent project add --todoist-project terminal-tmux
```

注册命令会通过已登录的官方 `td` CLI 解析稳定的 Todoist Project ID，校验当前 Git
仓库和基础分支，创建缺失的四个状态标签，然后以 `0600` 权限写入服务器本地配置：

```text
~/.config/todoist-codex/projects.toml
```

可以明确指定仓库和基础分支：

```bash
todo-agent project add \
  --todoist-project terminal-tmux \
  --repository /srv/repos/terminal-tmux \
  --base-branch main
```

同一项目中一次扫描发现的所有 `codex-ready` 任务都会分别创建 Agent 并行执行，
不设置项目并发上限。不同项目仍按注册顺序逐个调度。

检查映射和待执行任务：

```bash
todo-agent project list
todo-agent run --once --dry-run
```

手动执行一轮：

```bash
todo-agent run --once
```

领取任务时，调度器会保留任务上的普通标签，只把 Codex 状态切换为
`codex-running`。每个任务使用独立的本地分支和 Git worktree；Codex 在
`workspace-write` 沙箱中执行，不会自动提交、推送、部署或创建 PR。成功后任务改为
`codex-review`，失败后改为 `codex-failed`，结果摘要和服务器 worktree 路径会写入
任务评论。审核后可直接完成任务；需要继续修改时，在 App 中追加评论并重新添加
`codex-ready`，调度器会复用原分支和 worktree。

bootstrap 会在 Linux 上自动启动常驻轮询：存在可用的 user systemd 时启用并立即
启动 `todo-agent.service`；容器没有 user systemd 时自动使用 `nohup` watcher，PID
和日志分别写入 `~/.local/state/todoist-codex/watcher.pid` 与 `watcher.log`。重复运行
bootstrap 会停止旧 watcher 并启动当前代码对应的新 watcher，不会留下多个进程。

systemd 环境可以查看状态和日志：

```bash
systemctl --user enable --now todo-agent.service
systemctl --user status todo-agent.service
journalctl --user -u todo-agent.service -f
```

没有 systemd 的容器可以查看自动启动的 watcher：

```bash
cat ~/.local/state/todoist-codex/watcher.pid
tail -f ~/.local/state/todoist-codex/watcher.log
```

运行状态、SQLite 去重记录、Codex 事件和结果分别保存在
`~/.local/state/todoist-codex/`；worktree 默认保存在
`~/.local/share/todoist-codex/worktrees/`。同一服务器只允许一个 Dispatcher
进程领取任务；进程被意外终止后，下一次启动会把遗留的 `codex-running` 任务标记为
`codex-failed`，保留 worktree 供检查和重试。

### 在 SSH 服务器中打开 Mac ↔ 服务器文件传输

先在 Mac 的“系统设置 → 通用 → 共享”中打开“远程登录”，并只允许需要使用的
Mac 用户。Ghostty 中继续使用原来的受管入口：

```bash
ghostty-dev
ghostty-dev HOST
```

`ghostty-dev` 会在新 tab 中调用 `connect-remote-dev`，因此反向转发会自动建立，
不需要再手动执行第二条 SSH 命令。只有不通过 Ghostty 启动时，才直接运行
`connect-remote-dev HOST`。

在入口界面进入服务器宿主机或已经运行过本仓库 bootstrap 的 Docker 容器，然后运行：

```bash
termscp-mac
```

termscp 左侧的本地文件系统是当前服务器宿主机或容器，右侧 SFTP 文件系统是 Mac；
按 `Tab` 切换面板，选中文件后按 `Space` 上传或下载。
`termscp-mac [服务器或容器目录]` 可以指定左侧起始目录，默认使用当前目录。

反向转发只复用网络通道，不会复用当前 SSH 登录的身份。选择 Docker 容器后，
`remote-dev-entry` 在容器内运行 `ssh-keygen -y`，只导出默认
`~/.ssh/id_ed25519` 对应的公钥，再通过令牌保护的 `127.0.0.1:6023` 转发交给
Mac。Mac 会幂等写入 `~/.ssh/authorized_keys`，规则限定来源只能是
`127.0.0.1/::1`、强制运行 SFTP server，并由 `restrict` 禁止 PTY、Agent/X11
和端口转发。容器私钥不会离开容器，也不会写入 dotfiles；随机令牌和本机授权服务
都会随当前 SSH 进程退出。如果容器没有 Ed25519 默认密钥，入口只显示警告并继续
进入容器，不会自动创建或替换身份文件。

直接进入服务器宿主机时不会自动授权宿主机密钥，仍需单独配置密码或公钥。连接变量
由 `connect-remote-dev` 自动传入；Mac 用户名默认为本机 `id -un`，两个服务器
回环端口可按需覆盖：

```bash
TERMSCP_MAC_USER=a4x \
TERMSCP_REVERSE_PORT=16022 \
TERMSCP_AUTH_REVERSE_PORT=16023 \
TERMSCP_MAC_SSH_PORT=22 \
ghostty-dev HOST
```

SSH 反向端口始终只绑定服务器宿主机的 `127.0.0.1`。选中 host 网络容器时直接复用
这个回环地址；选中 bridge/custom-network 容器时，入口只在该容器网络的 Docker
网关地址启动一个临时 TCP 中继，并把网关、Mac 用户名和端口同步到容器 tmux。
中继不会监听服务器物理网卡，会随当前 SSH/`docker exec` 入口退出；同一 bridge
中的其他容器在这段连接期间能到达该端口，但仍必须通过 Mac 的 SSH 身份验证。

Ghostty 默认使用 `TERM=xterm-ghostty`。远端入口会分别在宿主机和最终选中的容器
中用 `infocmp` 检查该 terminfo：存在时保留 Ghostty 的完整能力，缺失或没有
`infocmp` 时只对当前远端环境回退为 `TERM=xterm-256color`。iTerm2 原有的
`xterm-256color` 路径不受影响。

入口先在终端中央询问是否进入 Docker，并在终端尺寸变化时重新居中。按 `Enter`
列出正在运行的容器，按 `Esc` 则直接进入宿主机的 `dev` tmux。容器列表也会在
窗口缩放后重新计算起始行列，让整个选择器保持居中；可用高度不足时会自动减少
每页行数，宽度不足时会压缩表格字段并切换为紧凑提示。使用 `↑/↓` 移动高亮，按
`Enter` 进入；
列表默认每页显示 12 个并随高亮自动翻页，`r` 刷新列表、`h` 返回宿主机、`q`
退出。选中后直接执行 `docker exec`，并在容器内部附加或创建名为 `dev` 的
tmux。容器路径不会创建或附加宿主机 tmux，因此不存在宿主机 tmux 嵌套容器
tmux 的情况。进入宿主机已有 `dev` session 时会优先选择 zsh/Iris pane；如果
历史 session 只有 Bash pane，则保留旧 pane 并新建一个 zsh window。宿主机尚未
安装完整 dotfiles 时，入口也会直接使用系统 zsh，不会退回 Bash。进入容器时会
优先使用 `zh_CN.UTF-8`，不可用时回退到
`C.UTF-8`，并同步已有 tmux server 的 `LANG` 和 `LC_ALL`，避免重新连接后
中文显示异常。容器入口会直接 `exec tmux`，tmux 再通过 `default-command`
启动受管的 login zsh，避免 Iris 在 tmux 外包装 zsh 后阻断 attach。如果容器内
已经存在 tmux server，还会重新加载 `~/.tmux.conf`，确保它与手动进入容器后
启动 tmux 的配置一致。附加已有 session 前会优先选择空闲的受管 shell pane；
启用 Iris 时该 pane 的前台进程可能显示为 `iris` 而不是 `zsh`，两者都会被正确
识别。如果所有 pane 都在运行其他前台命令，则新建一个 zsh window，不会终止
现有 pane 中的进程。

容器内必须为 `docker exec` 使用的用户预先安装 tmux。推荐在容器镜像构建阶段运行
bootstrap，或者为该用户持久化 HOME 后在容器内执行：

```bash
bash ~/.dotfiles/terminal-tmux/bootstrap.sh
```

如果容器内找不到 tmux，入口会报错退出，不会回退到宿主机 tmux。容器必须持续
运行，容器内的 tmux session 才能保留。

iTerm2 的 `dev` Dynamic Profile 由 bootstrap 自动链接。它保存当前字体、颜色、
窗口和终端设置，并使用可移植的 Custom Command：

```bash
/bin/zsh -lc 'exec "$HOME/.dotfiles/terminal-tmux/bin/connect-remote-dev" dev-4090'
```

iTerm2 会监视 DynamicProfiles 目录并自动加载变更。Dynamic Profile 使用
独立 GUID，避免与 `New Bookmarks` 中的普通 Profile 冲突。如果某台旧机器已有同名
的普通 `dev` Profile，只需在 iTerm2 Settings 中删除旧项一次；之后由
dotfiles 中的 Dynamic Profile 统一管理。

Ghostty 的默认窗口继续打开本地 zsh。要在当前 Ghostty 窗口的新 tab 中选择 SSH 服务器，
再启动与 iTerm2 `dev` Profile 相同的远端菜单，运行：

```bash
ghostty-dev
ghostty-dev OTHER_SSH_HOST
```

无参数时，启动器从 `~/.ssh/config` 读取不含 `*`、`?`、`!` 的具体 `Host`
alias，并在新 tab 中用 `↑/↓` 移动高亮、`Enter` 确认、`q` 或 `Esc` 取消；
如果列表中存在 `dev-4090`，它会成为初始选中项。传入参数则跳过服务器菜单，
直接连接指定 SSH host。启动器通过 Ghostty 1.3+ AppleScript API 向当前 front
window 添加 tab；只有 Ghostty 没有任何窗口时才创建首个窗口。Ghostty 配置同时
启用 `ssh-env` 和 `ssh-terminfo`，因此在普通 Ghostty zsh 中直接输入 `ssh` 时也会
自动处理远端环境。容器内执行 tmux detach 后，启动 wrapper 会按稳定 tab ID 关闭
刚结束的开发 tab，不会停在 `Process exited. Press any key to close the terminal.`。

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
