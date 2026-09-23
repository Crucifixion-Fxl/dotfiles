# Agent Skills Management

本仓库使用 [Skills Manager](https://github.com/xingkongliang/skills-manager)
统一管理 Agent Skills。`agent-skills/sync.sh` 是 bootstrap 保留的稳定入口，
但实际同步、Preset 管理和 Agent 部署全部交给 `skills-manager-cli`。

## Language

**Skills Manager CLI**:
无界面机器使用的命令行程序。带界面的机器优先使用应用发布到
`~/.skills-manager/bin/skills-manager-cli` 的版本；服务器使用同版本的独立二进制，
通常放在 `~/.local/bin/skills-manager-cli`。
_Avoid_: 直接把 Skill 复制到某个 Agent 目录并绕过中央库

**Central Skill Library**:
Skills Manager 在 `~/.skills-manager/skills` 中维护的中央技能库。技能的来源、标签、
Preset 成员关系和部署状态由 Skills Manager 的数据库与库内元数据管理。
_Avoid_: dotfiles 自己整体替换 Agent 的 Skill 目录

**Skills Manager Backup Repository**:
由 GUI 机器配置的 Git 远端。当前默认值写在 `agent-skills/sync.sh` 中，服务器首次
运行时直接克隆，之后使用已保存的 remote 执行 `git pull`；也可通过
`SKILLS_MANAGER_GIT_REMOTE` 临时覆盖。
凭据只存在机器的 SSH agent、credential helper 或系统密钥存储中。
_Avoid_: 将 Token、PAT 或完整凭据写入 dotfiles

**Preset**:
Skills Manager 中的命名技能集合。同步时逐个调用
`skills-manager-cli presets deploy`，把每个 Preset 部署到当前机器已安装且启用的
coding Agent；Preset 成员变化本身不会自动改写 Agent 文件。
_Avoid_: 依赖已废弃的单一 active preset exclusive sync

**Global Agent Deployment**:
Skills Manager 根据 `agents list` 为 Codex、Claude Code、Cursor 等 Agent 管理的真实
技能目录，例如 `~/.codex/skills`、`~/.claude/skills`。本仓库不再把
`~/.agents/skills` 当作唯一安装目标，也不清理其他 Agent 的目录。
_Avoid_: per-agent 目录外的整体安装投影

**Skill Sync**:
`agent-skills/sync.sh sync` 先确保中央 Git 仓库存在，拉取最新内容，再把全部 Preset
部署到已安装且启用的 Agent。首次在新机器运行时使用脚本中的默认 remote，也可通过
`SKILLS_MANAGER_GIT_REMOTE` 覆盖。
_Avoid_: 从 `agent-skills/sources/` 临时克隆多个上游并整体替换目录

**Skill Check**:
`agent-skills/sync.sh check` 或 `bootstrap.sh --skills-only --check` 的只读检查。它
验证中央库存在、库中有 Skill、并且至少有一个已安装且启用的 Agent；它不拉取、不更新、
不删除文件。

**Upstream Skill Update**:
对中央库中带 Git 来源的 Skill 执行 `skills-manager-cli skills check --all` 与
`skills-manager-cli skills update --all`。这是上游 Skill 更新，不等同于把中央库部署到
本机 Agent。

## Bootstrap contract

- `bash terminal-tmux/bootstrap.sh --skills-only`：安装或复用 CLI，拉取中央库并部署 Preset。
- `bash terminal-tmux/bootstrap.sh --skills-only --check`：只读验证 Skills Manager 状态。
- 完整 bootstrap 在 CLI 已安装后调用同一同步入口；它不再执行旧的 source installer。
- `agent-skills/sources/` 和旧的 `lib.sh` 仅保留作历史迁移参考，不属于运行时同步路径。
