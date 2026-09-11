#!/usr/bin/env python3
"""Upgrade removes owned SSH grants, preserving other entries and key files."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'migrations/retire-file-transfer.py'
with tempfile.TemporaryDirectory() as directory:
    home = Path(directory)
    ssh = home / '.ssh'
    ssh.mkdir()
    config = ssh / 'config'
    existing = 'Host work\n  HostName example.invalid\n'
    config.write_text('# BEGIN dotfiles termscp-mac\nHost dotfiles-termscp-mac\n  HostName 127.0.0.1\n# END dotfiles termscp-mac\n' + existing)
    keys = ssh / 'authorized_keys'
    personal = 'ssh-ed25519 PERSONAL personal\n'
    custom = 'ssh-ed25519 CUSTOM termscp-user-custom\n'
    keys.write_text(personal + 'from="127.0.0.1,::1",restrict,command="/usr/libexec/sftp-server" ssh-ed25519 MANAGED termscp-host-container-0123456789abcdef\n' + custom)
    keys.chmod(0o600)
    private = ssh / 'id_ed25519'
    private.write_text('keep private key')
    bindir = home / '.local/bin'
    bindir.mkdir(parents=True)
    owned = bindir / 'termscp-mac'
    owned.symlink_to(ROOT / 'bin/termscp-mac')
    custom_command = bindir / 'termscp-key-authorizer'
    custom_command.write_text('custom independent tool')
    environment = dict(os.environ, HOME=str(home))
    subprocess.run(['python3', str(SCRIPT)], env=environment, check=True)
    assert config.read_text() == existing
    assert keys.read_text() == personal + custom
    assert keys.stat().st_mode & 0o777 == 0o600
    assert private.read_text() == 'keep private key'
    assert not owned.is_symlink()
    assert custom_command.read_text() == 'custom independent tool'
    backups = sorted(ssh.glob('*.retired-*'))
    assert len(backups) == 2
    assert all(path.stat().st_mode & 0o777 == 0o600 for path in backups)
    subprocess.run(['python3', str(SCRIPT)], env=environment, check=True)
    assert sorted(ssh.glob('*.retired-*')) == backups
    config.write_text('# BEGIN dotfiles termscp-mac\n' + existing)
    result = subprocess.run(['python3', str(SCRIPT)], env=environment, capture_output=True)
    assert result.returncode != 0 and existing in config.read_text()
print('retired file-transfer migration tests passed')
