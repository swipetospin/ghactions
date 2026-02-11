#!/usr/bin/env bash
set -euo pipefail

EXTRA_INDEX_URL="${PIP_EXTRA_INDEX_URL:-https://pypi.spincar.com}"
PYTEST_REQUIREMENT="${PYTEST_REQUIREMENT:-pytest>=8,<9}"

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
  install_with_internal_index_fallback() {
    local target="$1"
    python -m pip install -e "${target}" \
      || python -m pip install --extra-index-url "${EXTRA_INDEX_URL}" -e "${target}"
  }

  install_with_internal_index_fallback "${pkg_root}[dev]" \
    || install_with_internal_index_fallback "${pkg_root}"
fi

# Some repos pin very old pytest in dev extras (e.g. pytest==4.6),
# which breaks on modern Python runtimes used in CI.
python -m pip install --upgrade "${PYTEST_REQUIREMENT}"

if [[ -n "${TEST_ARGS:-}" ]]; then
  # Intentionally split TEST_ARGS into argv for pytest (e.g. "-q -k smoke")
  read -r -a pytest_args <<<"${TEST_ARGS}"
else
  pytest_args=(-q)
fi

python -m pytest "${pytest_args[@]}"
