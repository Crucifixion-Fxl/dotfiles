# Agent Skills

Agent Skills are managed by [Skills Manager](https://github.com/xingkongliang/skills-manager).
The dotfiles bootstrap keeps the `sync.sh` and `check` entry points, but those
entry points now call `skills-manager-cli` instead of cloning individual source
repositories or replacing `~/.agents/skills`.

## First sync on a new machine

Install the standalone CLI (or let `bootstrap.sh` install it). The dotfiles
already point to the shared Skills Manager backup repository:

```sh
bash ~/.dotfiles/terminal-tmux/bootstrap.sh --skills-only
```

Set `SKILLS_MANAGER_GIT_REMOTE` only when you intentionally need to override
that default remote.

The CLI clones the repository into `~/.skills-manager`, pulls it on later runs,
and deploys every Preset to installed and enabled coding Agents. Git credentials
remain in the machine's SSH agent, credential helper, or token configuration;
they are never stored in this repository.

## Migrating an existing legacy installation

If an older checkout left Skills in an Agent directory, inspect them before
bringing them into the central library:

```sh
skills-manager-cli skills adopt ~/.agents/skills --dry-run
skills-manager-cli skills adopt ~/.agents/skills
```

The migration is intentionally explicit: Skills Manager must not overwrite or
delete an unmanaged Agent directory automatically.

## Checks and updates

```sh
bash ~/.dotfiles/terminal-tmux/bootstrap.sh --skills-only --check
bash ~/.dotfiles/terminal-tmux/bootstrap.sh --skills-only
```

Use `skills-manager-cli skills check --all` and `skills-manager-cli skills
update --all` when you also want to update a Skill from its upstream source.
