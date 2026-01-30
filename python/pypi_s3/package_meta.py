#!/usr/bin/env python3
import argparse
import re
from pathlib import Path
from packaging.version import Version

VERSION_RE = re.compile(r'__version__\s*=\s*[\'"]([^\'"]+)[\'"]')

def read_version(pkg: str) -> str:
    init_py = Path(pkg) / "__init__.py"
    txt = init_py.read_text(encoding="utf-8")

    m = VERSION_RE.search(txt)
    if m:
        return m.group(1).strip()

    # fallback: find semantic-ish version anywhere (matches old deployer pattern)
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

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--package-name", required=True)
    args = ap.parse_args()

    raw = read_version(args.package_name)
    norm = normalize(raw)
    pv = Version(norm)

    release_type = "stable"
    if pv.is_prerelease or pv.is_devrelease:
        release_type = "prerelease"

    print(f"raw_version={raw}")
    print(f"normalized_version={norm}")
    print(f"release_type={release_type}")

if __name__ == "__main__":
    main()
