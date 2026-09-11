#!/usr/bin/env python3
"""Check that installing the IME rule preserves existing Karabiner settings."""

import json
import re
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "bin/install-tmux-input-source"

# Restoration must name the original IME, not emit a global shortcut such as
# Ctrl+Space (which can launch another app instead of switching input sources).
managed = json.loads((ROOT / "karabiner/tmux-input-source.json").read_text())["rules"][0]
for command_key in ("c", "s"):
    restorers = [m for m in managed["manipulators"]
                 if m["from"].get("key_code") == command_key and "to_after_key_up" in m]
    for original in ("com.tencent.inputmethod.wetype.pinyin", "com.apple.inputmethod.SCIM.ITABC"):
        assert any(re.fullmatch(action.get("select_input_source", {}).get("input_source_id", ""), original)
                   for m in restorers for action in m["to_after_key_up"]), f"missing exact restoration: {original}"
    assert all("key_code" not in action and "shell_command" not in action
               for m in restorers for action in m["to_after_key_up"]), "restoration must not emit global shortcuts"

with tempfile.TemporaryDirectory() as directory:
    config = Path(directory) / "karabiner.json"

    def install():
        subprocess.run([sys.executable, str(INSTALLER), "--config", str(config)], check=True)

    install()
    assert not config.exists(), "must not configure Karabiner for new users"
    custom = {"description": "User Caps Lock rule", "manipulators": []}
    inactive = {"name": "Other", "selected": False, "simple_modifications": [{"custom": True}]}
    data = {"global": {"show_in_menu_bar": False}, "profiles": [
        {"name": "Active", "selected": True, "devices": [{"ignore": True}],
         "complex_modifications": {"parameters": {"basic.to_if_alone_timeout_milliseconds": 300},
                                   "rules": [custom]}}, inactive]}
    original = json.dumps(data).encode()
    config.write_bytes(original)
    config.chmod(0o600)
    install()
    result = json.loads(config.read_bytes())
    rules = result["profiles"][0]["complex_modifications"]["rules"]
    assert len(rules) == 2
    assert rules[0] == json.loads((ROOT / "karabiner/tmux-input-source.json").read_text())["rules"][0]
    rules.pop(0)
    assert result == data, "unrelated user settings were changed"
    assert (config.stat().st_mode & 0o777) == 0o600
    backups = list(config.parent.glob("karabiner.json.backup.*"))
    assert len(backups) == 1 and backups[0].read_bytes() == original
    installed = config.read_bytes()
    install()
    assert config.read_bytes() == installed
    assert list(config.parent.glob("karabiner.json.backup.*")) == backups

print("tmux input-source installation checks passed")
