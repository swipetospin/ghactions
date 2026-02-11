#!/usr/bin/env bash
set -euo pipefail

EXTRA_INDEX_URL="${PIP_EXTRA_INDEX_URL:-https://pypi.spincar.com}"
PYTEST_REQUIREMENT="${PYTEST_REQUIREMENT:-pytest>=8,<9}"

if [[ ! -d tests && ! -d test ]]; then
  echo "No tests directory found; skipping automated tests."
  exit 0
fi

ensure_local_aws_profile() {
  local profile="$1"
  local aws_dir="${HOME}/.aws"
  local credentials_file="${aws_dir}/credentials"
  local config_file="${aws_dir}/config"

  mkdir -p "${aws_dir}"
  touch "${credentials_file}" "${config_file}"

  if ! grep -q "^\\[${profile}\\]$" "${credentials_file}"; then
    cat >>"${credentials_file}" <<EOF
[${profile}]
aws_access_key_id = test
aws_secret_access_key = test
aws_session_token = test
EOF
  fi

  local config_section="[profile ${profile}]"
  if [[ "${profile}" == "default" ]]; then
    config_section="[default]"
  fi

  if ! grep -q "^${config_section}$" "${config_file}"; then
    cat >>"${config_file}" <<EOF
${config_section}
region = us-east-1
output = json
EOF
  fi
}

# Some test suites load AWS profiles during conftest import.
ensure_local_aws_profile "default"
ensure_local_aws_profile "test"
ensure_local_aws_profile "prod"
export AWS_EC2_METADATA_DISABLED="true"

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
