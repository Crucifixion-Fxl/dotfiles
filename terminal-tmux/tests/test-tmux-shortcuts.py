#!/usr/bin/env python3
"""Send real terminal input to an isolated tmux server (no user sessions)."""

import fcntl
import argparse
import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import struct
import subprocess
import tempfile
import termios
import time


ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=str(ROOT / "tmux/tmux.conf"))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="tmux-shortcuts-") as directory:
        env = dict(os.environ, HOME=directory, TERM="xterm-256color")
        env.pop("TMUX", None)
        command = [shutil.which("tmux"), "-S", directory + "/socket"]

        def tmux(*args):
            return subprocess.check_output(command + list(args), env=env, text=True).strip()

        master = pid = None
        failures = []
        try:
            tmux("-f", args.config, "new-session", "-d", "-s", "test", "sleep 60")
            tmux("set-option", "-g", "default-command", "sleep 60")
            pane = tmux("display-message", "-p", "-t", "test:0", "#{pane_id}")
            pid, master = pty.fork()
            if pid == 0:
                os.execvpe(command[0], command + ["attach-session", "-t", "test"], env)
            fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))

            def pump(duration=0.05):
                deadline = time.monotonic() + duration
                while time.monotonic() < deadline:
                    ready, _, _ = select.select([master], [], [], max(0, deadline - time.monotonic()))
                    if ready:
                        os.read(master, 65536)

            def wait_for(predicate):
                deadline = time.monotonic() + 1.5
                while time.monotonic() < deadline:
                    if predicate():
                        return True
                    pump()
                return False

            assert wait_for(lambda: bool(tmux("list-clients"))), "client did not attach"
            client = tmux("list-clients", "-F", "#{client_name}")
            pump(0.15)

            def press(key):
                os.write(master, b"\x02")
                pump(0.03)
                assert "[Ctrl-b]" in tmux("display-message", "-p", "-c", client, "#{E:status-left}"), "missing prefix feedback"
                os.write(master, key)

            def check(label, predicate):
                passed = wait_for(predicate)
                print(f"{'PASS' if passed else 'FAIL'}: {label}", flush=True)
                if not passed:
                    failures.append(label)

            for mode in ("normal pane", "copy mode"):
                for key, name, action in ((b"c", "c", "window"), (b"\x03", "Ctrl+C", "window"),
                                          (b"s", "s", "sessions"), (b"\x13", "Ctrl+S", "sessions")):
                    tmux("select-window", "-t", "test:0")
                    if tmux("display-message", "-p", "-t", pane, "#{pane_mode}") == "tree-mode":
                        os.write(master, b"q")
                        assert wait_for(lambda: tmux("display-message", "-p", "-t", pane, "#{pane_mode}") != "tree-mode")
                    if tmux("display-message", "-p", "-t", pane, "#{pane_in_mode}") == "1":
                        tmux("send-keys", "-X", "-t", pane, "cancel")
                    if mode == "copy mode":
                        tmux("copy-mode", "-t", pane)
                    before = int(tmux("display-message", "-p", "-t", "test", "#{session_windows}"))
                    press(key)
                    if action == "window":
                        check(f"{mode}: Prefix + {name} creates a window on first press",
                              lambda: int(tmux("display-message", "-p", "-t", "test", "#{session_windows}")) == before + 1)
                    else:
                        check(f"{mode}: Prefix + {name} opens sessions on first press",
                              lambda: tmux("display-message", "-p", "-t", pane, "#{pane_mode}") == "tree-mode")
            # Without a prefix, control keys must still reach the foreground app.
            received = Path(directory) / "keys"
            raw_pane = tmux("new-window", "-P", "-F", "#{pane_id}", "-t", "test",
                            "stty raw -echo; exec cat > " + shlex.quote(str(received)))
            assert wait_for(lambda: tmux("display-message", "-p", "-t", raw_pane,
                                         "#{pane_current_command}") == "cat")
            os.write(master, b"\x03\x13")
            check("Ctrl+C / Ctrl+S without prefix still reach the foreground app",
                  lambda: received.exists() and received.read_bytes() == b"\x03\x13")
            if failures:
                raise SystemExit(f"{len(failures)} shortcut checks failed")
        finally:
            subprocess.run(command + ["kill-server"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if master is not None:
                os.close(master)
            if pid:
                os.waitpid(pid, 0)


if __name__ == "__main__":
    main()
