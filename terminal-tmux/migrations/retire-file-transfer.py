#!/usr/bin/env python3
"""Remove dotfiles-owned file-transfer entrypoints and SSH grants on upgrade."""

import hashlib
import os
from pathlib import Path
import re
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
# The old connector also deployed regular copies of these scripts remotely.
COPY_HASHES = {
    'termscp-key-authorizer': 'c4fc5f04f392c80ca17bf60bd3b0226b16188099c71bf5cfe099ee5900830cbf',
    'termscp-bridge-relay': '6aa8c920ef35d55b6f8134d178530ebcef21c3918ed5f0a6415c2c20b249e7c1',
    'termscp-mac': '225560f9842a1a20fef05789cbcb16bd47f0657a629876fa307f3b7365cc6219',
}


def backup(path):
    with tempfile.NamedTemporaryFile(prefix=path.name + '.retired-', dir=path.parent, delete=False) as output:
        destination = Path(output.name)
    shutil.copy2(path, destination)
    destination.chmod(0o600)


def replace_text(path, original, updated):
    if updated == original:
        return
    backup(path)
    # Follow an existing user-managed symlink rather than replacing it.
    target = path.resolve()
    with tempfile.NamedTemporaryFile(mode='w', prefix='.' + target.name + '.', dir=target.parent, delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(updated)
            output.flush()
            temporary.chmod(target.stat().st_mode & 0o777)
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)


def main():
    home = Path.home()
    config = home / '.ssh/config'
    if config.is_file():
        original = config.read_text()
        begin = '# BEGIN dotfiles termscp-mac'
        end = '# END dotfiles termscp-mac'
        lines = original.splitlines()
        if lines.count(begin) != lines.count(end):
            raise SystemExit('Incomplete retired file-transfer block in ~/.ssh/config; leaving it intact.')
        updated = re.sub(r'(?ms)^' + re.escape(begin) + r'\n.*?^' + re.escape(end) + r'(?:\n|$)', '', original)
        replace_text(config, original, updated)

    authorized = home / '.ssh/authorized_keys'
    if authorized.is_file():
        original = authorized.read_text()
        # Match both the generated restrictions and hashed identity comment.
        grant = re.compile(r'^from="127\.0\.0\.1,::1",restrict,command="(?:/usr/libexec/sftp-server|internal-sftp)" \S+ \S+ termscp-[A-Za-z0-9_.-]+-[0-9a-f]{16}$')
        updated = ''.join(line for line in original.splitlines(keepends=True) if not grant.fullmatch(line.rstrip('\r\n')))
        replace_text(authorized, original, updated)

    for name, fingerprint in COPY_HASHES.items():
        path = home / '.local/bin' / name
        if path.is_symlink():
            if Path(os.readlink(path)) == ROOT / 'bin' / name:
                path.unlink()
        elif path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == fingerprint:
            path.unlink()
    # Existing SSH connections own their relay processes. They end on
    # disconnect; the new connector never starts relays or forwards ports.


if __name__ == '__main__':
    main()
