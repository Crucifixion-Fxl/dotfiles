# dotfiles

一套可重复部署的终端开发环境，覆盖 Mac、Linux 服务器和 Docker 容器。
以 **Ghostty · tmux · zsh** 为核心，统一远程入口、日常工具与 Agent Skills。

[快速开始](#快速开始) · [日常使用](#日常使用) · [配置与维护](#配置与维护)

![dotfiles 整体工作流](terminal-tmux/assets/terminal-workflow.drawio.png)

<sub>宿主机与容器各自运行 tmux，连接时选择其一。[编辑架构图](terminal-tmux/assets/terminal-workflow.drawio)</sub>

## 快速开始

支持 macOS、Debian / Ubuntu，兼容 Apple Silicon / ARM64 与 x86_64。
Mac 需先安装 Homebrew；Linux 需具备 root 或 sudo 权限以安装系统依赖。

```sh
git clone https://github.com/Crucifixion-Fxl/dotfiles ~/.dotfiles
bash ~/.dotfiles/terminal-tmux/bootstrap.sh
exec zsh -l
```

服务器和容器内使用同一套命令，以实际开发用户运行。容器建议持久化该用户的 HOME。

更新已有环境：

```sh
git -C ~/.dotfiles pull --ff-only && \
  bash ~/.dotfiles/terminal-tmux/bootstrap.sh
exec zsh -l
```

## 日常使用

### 进入工作区

```sh
ghostty-dev                 # 新建 Ghostty 标签页，选择 SSH 主机
ghostty-dev dev-4090        # 直接连接 ~/.ssh/config 中的主机别名
connect-remote-dev HOST     # 从当前终端连接
```

连接后选择宿主机或运行中的 Docker 容器，进入对应的 `dev` tmux 会话。
重连会保留已有窗口和进程；容器需先完成 bootstrap。

### tmux

先按 **Ctrl+B**，再按下表中的键。状态栏出现 `[Ctrl-b]` 表示前缀已收到。

| 按键 | 操作 |
| --- | --- |
| `c` / `s` | 新建窗口 / 查看会话与 Codex 状态 |
| `t` | 打开 shell 浮窗 |
| `g` / `G` | 在浮窗 / 新窗口打开 lazygit |
| `<` / `>` | 调整窗口顺序 |
| `d` | 离开会话，保留进程 |
| `S` / `R` | 手动保存 / 恢复会话布局 |

`c`、`s` 也兼容持续按住 Ctrl。会话每 15 分钟自动保存，恢复由手动触发。
Mac 上启用 Karabiner 规则后，Ghostty 中按 Ctrl+B 临时切到英文，完成 `c` / `s` 后恢复原输入法。

### 随手可用的工具

| 命令 | 用途 |
| --- | --- |
| `codex` | 在当前仓库运行编码 Agent |
| `lazygit` / `glab` | Git 工作流 / GitLab CLI |
| `y` | 用 Yazi 浏览文件，退出后进入选中的目录 |
| `glow README.md` | 在终端阅读 Markdown；Yazi 预览也使用 Glow |
| `vim` / `fresh` | 编辑文本 |
| `btop` | 查看系统资源 |

## 配置与维护

| 入口 | 内容 |
| --- | --- |
| [bootstrap.sh](terminal-tmux/bootstrap.sh) | 安装、更新、旧组件迁移与环境校验 |
| [versions.lock](terminal-tmux/versions.lock) | 工具版本、校验和与插件 revision |
| [tmux.conf](terminal-tmux/tmux/tmux.conf) | 快捷键、状态栏与会话保存 |
| [zshrc](terminal-tmux/shell/zshrc) · [Ghostty](terminal-tmux/ghostty/config.ghostty) | Shell 与终端配置 |
| [Yazi](terminal-tmux/yazi/yazi.toml) · [lazygit](terminal-tmux/lazygit/config.yml) | 文件预览与 Git 界面 |
| [Agent Skills](agent-skills/sources) | Skills 来源与同步规则 |
| [tests](terminal-tmux/tests) | 安装、远程连接与交互回归检查 |

```sh
# 检查当前安装
bash ~/.dotfiles/terminal-tmux/bootstrap.sh --check

# 仅更新 Agent Skills；完成后开启新的 Agent 会话
bash ~/.dotfiles/terminal-tmux/bootstrap.sh --skills-only
```

Skills 同步至 `~/.agents/skills`，Codex CLI 在每次完整更新时跟随最新版。
Mac 字体由安装器配置；Linux GUI 终端字体需自行设置。

机器专属配置放在 `~/.zshrc.local`。SSH 密钥、Token、Git 身份、历史记录和会话数据留在各机器，不纳入仓库。
