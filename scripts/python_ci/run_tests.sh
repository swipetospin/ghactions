#!/usr/bin/env bash
set -euo pipefail

EXTRA_INDEX_URL="${PIP_EXTRA_INDEX_URL:-https://pypi.spincar.com}"
PYTEST_REQUIREMENT="${PYTEST_REQUIREMENT:-pytest>=8,<9}"
AWS_PROFILE_ALIASES="${AWS_PROFILE_ALIASES:-default,test,prod}"

if [[ ! -d tests && ! -d test ]]; then
  echo "No tests directory found; skipping automated tests."
  exit 0
fi

remove_ini_section() {
  local file="$1"
  local header="$2"
  local temp_file

  temp_file="$(mktemp)"
  awk -v header="${header}" '
    BEGIN { skip = 0 }
    /^\[.*\]$/ {
      skip = ($0 == header)
    }
    !skip { print }
  ' "${file}" > "${temp_file}"
  mv "${temp_file}" "${file}"
}

ensure_local_aws_profile() {
  local profile="$1"
  local access_key="$2"
  local secret_key="$3"
  local session_token="$4"
  local region="$5"
  local aws_dir="${HOME}/.aws"
  local credentials_file="${aws_dir}/credentials"
  local config_file="${aws_dir}/config"

  mkdir -p "${aws_dir}"
  touch "${credentials_file}" "${config_file}"

  remove_ini_section "${credentials_file}" "[${profile}]"
  cat >>"${credentials_file}" <<EOF
[${profile}]
aws_access_key_id = ${access_key}
aws_secret_access_key = ${secret_key}
EOF
  if [[ -n "${session_token}" ]]; then
    printf 'aws_session_token = %s\n' "${session_token}" >> "${credentials_file}"
  fi

  local config_section="[profile ${profile}]"
  if [[ "${profile}" == "default" ]]; then
    config_section="[default]"
  fi

  remove_ini_section "${config_file}" "${config_section}"
  cat >>"${config_file}" <<EOF
${config_section}
region = ${region}
output = json
EOF
}

seed_local_aws_profiles() {
  local access_key=""
  local secret_key=""
  local session_token=""
  local profile_region="${AWS_PROFILE_REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}}"
  local profiles_csv="${AWS_PROFILE_ALIASES}"
  local -a profiles=()

  if [[ -n "${AWS_PROFILE:-}" ]]; then
    profiles_csv="${profiles_csv},${AWS_PROFILE}"
  fi

  if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    access_key="${AWS_ACCESS_KEY_ID}"
    secret_key="${AWS_SECRET_ACCESS_KEY}"
    session_token="${AWS_SESSION_TOKEN:-}"
  else
    access_key="test"
    secret_key="test"
    session_token="test"
  fi

  IFS=',' read -r -a profiles <<< "${profiles_csv}"
  for raw_profile in "${profiles[@]}"; do
    local profile="${raw_profile//[[:space:]]/}"
    [[ -z "${profile}" ]] && continue
    ensure_local_aws_profile "${profile}" "${access_key}" "${secret_key}" "${session_token}" "${profile_region}"
  done
}

apply_test_env_lines() {
  if [[ -z "${TEST_ENV_LINES:-}" ]]; then
    return
  fi

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    export "${line}"
  done <<< "${TEST_ENV_LINES}"
}

# Some test suites load AWS profiles during conftest import.
apply_test_env_lines
seed_local_aws_profiles
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
  # Parse TEST_ARGS like a shell command line so callers can quote pytest expressions.
  mapfile -t pytest_args < <(
    python - "${TEST_ARGS}" <<'PY'
import shlex
import sys

for arg in shlex.split(sys.argv[1]):
    print(arg)
PY
  )
else
  pytest_args=(-q)
fi

python -m pytest "${pytest_args[@]}"
