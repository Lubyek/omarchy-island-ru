"""Cache the official Stacky sheet for the Codex avatar."""
import hashlib
import os
from pathlib import Path
import tempfile
from urllib.request import urlopen

URL = "https://cdn.openai.com/c6d7b0d0-3abf-40b5-9d0c-ecd2b9364692/stacky-spritesheet-v4.webp"
DIGEST = "f532c6701fb5f21d94be898e349f44fb218f1521d3747da1281f7b80fd3c35d1"
LIMIT = 1 << 20


def matches(data):
    return hashlib.sha256(data).hexdigest() == DIGEST


def cached_asset(path):
    try:
        with path.open("rb") as cached:
            if matches(cached.read(LIMIT + 1)):
                return path
    except FileNotFoundError:
        pass
    with urlopen(URL, timeout=7) as response:
        data = response.read(LIMIT + 1)
    if not matches(data):
        raise ValueError("Stacky sheet failed integrity check")
    path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(data)
            output.flush()
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
    return path


if __name__ == "__main__":
    root = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    try:
        print(cached_asset(root / "huesos.island" / "stacky.webp").resolve().as_uri())
    except (OSError, ValueError):
        # The built-in mascot remains available without the optional asset.
        pass
