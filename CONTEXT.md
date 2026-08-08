# Agent Skills Management

本仓库记录个人开发环境所需 Agent Skills 的来源，并在新机器或服务器上恢复这些 Skills。

## Language

**External Skill Source**:
由独立 Git 仓库维护、安装时始终获取其最新可用版本的 Skill 唯一来源；仓库内容构成该来源的完整 Skills 集合。
_Avoid_: Pinned skill, vendored skill

**Temporary Source Clone**:
Skill Sync 为 External Skill Source 创建的临时仓库副本；它跟随远程默认分支，并在本次同步结束后删除，不作为机器持久状态。
_Avoid_: Persistent cache, Git submodule, installation directory, development clone

**Required Source**:
必须成功获取才能完成 Skill Sync 的 External Skill Source；失败时保留上一次完整安装结果并令同步失败。
_Avoid_: Optional source, best-effort source

**Optional Source**:
无法获取最新内容时允许 Skill Sync 警告后继续的 External Skill Source；已有对应 Installed Skills 时保留上次版本，新机器没有旧安装时跳过。
_Avoid_: Required source

**Whole-source Installation**:
一个 External Skill Source 由其 Source Installer 定义完整的期望安装集合；配置范围内上游以后新增的 Skills 会自动纳入。Matt 来源的范围是 `skills/engineering/` 全部 Skills 以及 6 个明确的 productivity 依赖，而不是整个仓库。
_Avoid_: Per-machine selection, ad hoc installation

**Source Prefix**:
由唯一的 Source Name 直接确定的命名空间；安装时无条件将它添加到每个上游 Skill 名称之前，即使上游名称已经带有相同文本。
_Avoid_: Automatic prefix, source precedence

**Source Name**:
External Skill Source 在 dotfiles 中的目录名，同时用作其 Source Checkout 名称和 Source Prefix，例如 `company` 或 `matt`。
_Avoid_: Source ID, separately configured prefix

**Native Skill**:
源文件直接由本 dotfiles 仓库维护，并通过暂存与复制流程安装的 Skill。
_Avoid_: External skill, linked skill

**Source Installer**:
由本 dotfiles 仓库维护、与一个 External Skill Source 对应的确定性 Bash 脚本；它通过统一的 `sync` 和 `check` 接口接收来源路径、安装目标与前缀，并负责发现、加前缀和安装该来源配置范围内的全部 Skills。
_Avoid_: POSIX sh script, discovery rule, upstream installer, generic installer

**Installed Skill**:
完成暂存、修正与验证后，由 bootstrap 复制到 `~/.agents/skills`、可在当前机器上被兼容工具发现的 Skill。
_Avoid_: Source skill, managed source

**Staged Skill**:
位于扁平暂存根目录的直接子目录中、正在等待完成名称修正、内部引用更新和验证的自包含 Skill；它不得含有软链接，只有完整通过后才能成为 Installed Skill。
_Avoid_: Source checkout, installed skill, symlink

**Installed Projection**:
Source Installer 从 External Skill Source 自动生成的安装副本；它为 Skill 名称和内部引用添加 Source Prefix，但不修改上游仓库。
_Avoid_: Vendored copy, source checkout, renamed symlink

**Managed Skill**:
由任一 External Skill Source 或 `native/` 提供的 Installed Skill；Skill Installation Directory 中不存在独立的未受管类别。
_Avoid_: State-file ownership, manually installed skill

**Skill Installation Directory**:
当前用户所有 Skills 的唯一安装目标，即 `~/.agents/skills`；它整体属于 dotfiles，可由完整暂存结果替换。
_Avoid_: `~/.codex/skills`, per-agent skill directory

**Skill Sync**:
拉取所有 External Skill Sources 的最新版本，由 Source Installers 与 `native/` 共同生成完整暂存结果，验证后整体替换 Skill Installation Directory；正常 bootstrap 自动执行，也可独立运行。
_Avoid_: Version restore, check mode

**Skill Check**:
只读验证当前 Skills 的配置、脚本、结构与名称，不联网、不更新内容，也不判断远程仓库是否已有更新。
_Avoid_: Skill sync, repair
