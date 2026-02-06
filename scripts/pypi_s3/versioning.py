import re
from pathlib import Path

from packaging.version import Version

VERSION_RE = re.compile(
    r'^\s*(?:__version__|version)\s*=\s*[\'"]([^\'"]+)[\'"]\s*$',
    re.MULTILINE,
)


def read_version(pkg: str, package_root: str = ".") -> str:
    init_py = Path(package_root) / pkg / "__init__.py"
    txt = init_py.read_text(encoding="utf-8")

    m = VERSION_RE.search(txt)
    if m:
        return m.group(1).strip()

    # Fallback: find semantic-ish version anywhere (matches old deployer pattern)
    m2 = re.search(r'([0-9]+\.[0-9]+\.[0-9]+[^\s\'"]*)', txt)
    if not m2:
        raise SystemExit(f"Could not find version in {init_py}")
    return m2.group(1).strip()


def normalize(v: str) -> str:
    # Support "1.0.0b1-xyz" by converting to PEP440 local version "1.0.0b1+xyz"
    if "-" in v and "+" not in v:
        base, suffix = v.split("-", 1)
        return f"{base}+{suffix}"
    return v


def release_type(normalized_version: str) -> str:
    pv = Version(normalized_version)
    if pv.is_prerelease or pv.is_devrelease:
        return "prerelease"
    return "stable"
