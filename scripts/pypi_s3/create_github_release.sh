#!/usr/bin/env bash
set -euo pipefail

VERSION=""
RELEASE_TYPE=""
DEFAULT_BRANCH="master"

usage() {
  echo "Usage: $0 --version <ver> --release-type <stable|prerelease> --default-branch <branch>"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --release-type) RELEASE_TYPE="$2"; shift 2 ;;
    --default-branch) DEFAULT_BRANCH="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

if [[ -z "${VERSION}" || -z "${RELEASE_TYPE}" || -z "${DEFAULT_BRANCH}" ]]; then
  usage
  exit 2
fi

DEFAULT_REF="refs/heads/${DEFAULT_BRANCH}"

# Only create a release if we actually published something in this run:
if [[ "${RELEASE_TYPE}" == "stable" && "${GITHUB_REF}" != "${DEFAULT_REF}" ]]; then
  echo "Not publishing stable (not default branch: ${DEFAULT_BRANCH}); skipping GitHub release."
  exit 0
fi

if [[ "${RELEASE_TYPE}" == "prerelease" && "${GITHUB_REF}" == "${DEFAULT_REF}" ]]; then
  echo "Not publishing prerelease on default branch (${DEFAULT_BRANCH}); skipping GitHub release."
  exit 0
fi

if gh release view "v${VERSION}" >/dev/null 2>&1; then
  echo "Release v${VERSION} already exists; skipping."
  exit 0
fi

if [[ "${RELEASE_TYPE}" == "prerelease" ]]; then
  gh release create "v${VERSION}" --prerelease --target "${GITHUB_SHA}" --title "v${VERSION}" --notes ""
else
  gh release create "v${VERSION}" --target "${GITHUB_SHA}" --title "v${VERSION}" --notes ""
fi
