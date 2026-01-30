#!/usr/bin/env python3
import argparse
import html
import re
import subprocess
from pathlib import Path

import boto3
from botocore.exceptions import ClientError
from packaging.version import Version

VERSION_RE = re.compile(r'__version__\s*=\s*[\'"]([^\'"]+)[\'"]')

def read_init_version(init_path: Path) -> str:
    txt = init_path.read_text(encoding="utf-8")
    m = VERSION_RE.search(txt)
    if m:
        return m.group(1).strip()

    m2 = re.search(r'([0-9]+\.[0-9]+\.[0-9]+[^\s\'"]*)', txt)
    if not m2:
        raise SystemExit(f"Could not find version in {init_path}")
    return m2.group(1).strip()

def normalize(v: str) -> str:
    if "-" in v and "+" not in v:
        base, suffix = v.split("-", 1)
        return f"{base}+{suffix}"
    return v

def maybe_patch_version(init_path: Path, raw: str, norm: str) -> bool:
    if raw == norm:
        return False
    txt = init_path.read_text(encoding="utf-8")
    init_path.write_text(txt.replace(raw, norm, 1), encoding="utf-8")
    return True

def s3_prefix(package_name: str) -> str:
    return package_name.replace("_", "-")

def list_objects(s3, bucket: str, prefix: str):
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=f"{prefix}/"):
        for obj in page.get("Contents", []):
            yield obj["Key"]

def object_exists(s3, bucket: str, key: str) -> bool:
    try:
        s3.head_object(Bucket=bucket, Key=key)
        return True
    except ClientError as e:
        if e.response["Error"]["Code"] in ("404", "NoSuchKey", "NotFound"):
            return False
        raise

def build_dist():
    subprocess.check_call(["python", "-m", "build", "--sdist", "--wheel"])

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--package-name", required=True)
    ap.add_argument("--bucket", required=True)
    args = ap.parse_args()

    pkg = args.package_name
    init_path = Path(pkg) / "__init__.py"
    if not init_path.exists():
        raise SystemExit(f"Expected {init_path} to exist")

    raw_version = read_init_version(init_path)
    norm_version = normalize(raw_version)

    # Ensure normalized version is valid PEP440
    Version(norm_version)

    patched = maybe_patch_version(init_path, raw_version, norm_version)

    try:
        build_dist()

        s3 = boto3.client("s3")
        prefix = s3_prefix(pkg)

        dist_dir = Path("dist")
        artifacts = sorted(dist_dir.glob("*"))
        if not artifacts:
            raise SystemExit("No artifacts in dist/")

        # Refuse overwriting an existing version/artifact
        for f in artifacts:
            key = f"{prefix}/{f.name}"
            if object_exists(s3, args.bucket, key):
                raise SystemExit(f"Refusing to overwrite existing artifact: s3://{args.bucket}/{key}")

        for f in artifacts:
            key = f"{prefix}/{f.name}"
            s3.upload_file(str(f), args.bucket, key)

        # Regenerate index.html
        keys = [k for k in list_objects(s3, args.bucket, prefix) if not k.endswith("/index.html")]
        filenames = [k.split("/", 1)[1] for k in keys if "/" in k]
        filenames = sorted(set(filenames))

        body = ["<html><head><meta charset='UTF-8'><title>Package Index</title></head><body>"]
        for fn in filenames:
            safe = html.escape(fn)
            body.append(f"<a href=\"{safe}\">{safe}</a><br/>")
        body.append("</body></html>")
        index_html = "\n".join(body).encode("utf-8")

        s3.put_object(
            Bucket=args.bucket,
            Key=f"{prefix}/index.html",
            Body=index_html,
            ContentType="text/html",
            CacheControl="public, must-revalidate, proxy-revalidate, max-age=0",
        )

        print(f"Published {pkg} {norm_version} to s3://{args.bucket}/{prefix}/")

    finally:
        if patched:
            # restore runner file content (runner is ephemeral, but keep it clean)
            txt = init_path.read_text(encoding="utf-8")
            init_path.write_text(txt.replace(norm_version, raw_version, 1), encoding="utf-8")

if __name__ == "__main__":
    main()
