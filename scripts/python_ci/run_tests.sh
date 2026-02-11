#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d tests && ! -d test ]]; then
  echo "No tests directory found; skipping automated tests."
  exit 0
fi

pkg_root=""
if [[ -f setup.py || -f pyproject.toml ]]; then
  pkg_root="."
elif [[ -f pypkg/setup.py || -f pypkg/pyproject.toml ]]; then
  pkg_root="pypkg"
fi

if [[ -n "${pkg_root}" ]]; then
  python -m pip install -e "${pkg_root}[dev]" || python -m pip install -e "${pkg_root}"
fi

python -m pip install pytest

if [[ -n "${TEST_ARGS:-}" ]]; then
  # Intentionally split TEST_ARGS into argv for pytest (e.g. "-q -k smoke")
  read -r -a pytest_args <<<"${TEST_ARGS}"
else
  pytest_args=(-q)
fi

python -m pytest "${pytest_args[@]}"
