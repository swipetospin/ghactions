#!/usr/bin/env python3
import argparse

from versioning import read_version, normalize, release_type


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--package-name", required=True)
    ap.add_argument("--package-root", default=".")
    args = ap.parse_args()

    raw = read_version(args.package_name, args.package_root)
    norm = normalize(raw)
    rtype = release_type(norm)

    # GitHub Actions output format
    print(f"raw_version={raw}")
    print(f"normalized_version={norm}")
    print(f"release_type={rtype}")


if __name__ == "__main__":
    main()
