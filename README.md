# terminal-dotfiles

Strictly reproducible tmux, lazygit, git-delta, Codex hooks, and zsh window
naming for macOS and Debian/Ubuntu hosts.

## Install

Clone `https://github.com/Crucifixion-Fxl/terminal-dotfiles` to `~/.dotfiles`,
then run:

    ~/.dotfiles/bootstrap.sh

On Debian/Ubuntu, apt installs only prerequisites. Locked tmux, lazygit, and
git-delta releases are installed under `~/.local/bin` after SHA256 validation.

To validate an existing installation without changing it:

    ~/.dotfiles/bootstrap.sh --check

Connect directly to the remote tmux session with:

    ssh -t HOST 'PATH="$HOME/.local/bin:$PATH" exec tmux new-session -A -s main'

The remote login shell may remain bash. Panes created inside tmux use zsh so
the window naming hooks behave identically on every host.

The repository intentionally excludes tmux-resurrect saves, shell history,
Codex credentials, Codex `config.toml`, and all other machine-specific state.
