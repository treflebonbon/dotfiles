import hashlib
import os
import sys
from pathlib import Path


def fail_walk(error):
    raise error


root = Path(sys.argv[1])
tree_hash = hashlib.sha256()
for directory, dirs, files in os.walk(root, onerror=fail_walk):
    dirs.sort()
    for name in sorted(dirs + files):
        path = Path(directory) / name
        entry_hash = hashlib.sha256()
        if path.is_symlink():
            kind = b"L"
            entry_hash.update(os.fsencode(os.readlink(path)))
        elif path.is_file():
            kind = b"F"
            with path.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    entry_hash.update(chunk)
        else:
            continue
        # Relative paths and framed records keep ordering and names unambiguous.
        tree_hash.update(kind + os.fsencode(path.relative_to(root)) + b"\0")
        tree_hash.update(entry_hash.digest())

print(tree_hash.hexdigest())
