#!/bin/bash

set -e -o pipefail  # if a command or a command in a pipe fails, exit
set -u  # treat unset variables as error
set -x  # print all debug information

if [[ -z "$GITHUB_TOKEN" ]]; then  # This is populated by our secret from the Workflow file.
	echo "Set the GITHUB_TOKEN envvar."
	exit 1
fi
if [[ -z "$INPUT_LINTER" ]]; then  # This is a required input.
	echo "Set the INPUT_LINTER envvar with the name of the linter you're trying to run."
	exit 1
fi

echo "Linter $INPUT_LINTER has been selected"

ACTION=$(jq --raw-output .action "$GITHUB_EVENT_PATH")
# First 2 actions are for pull requests, last 2 are for check suites.
ENABLED_ACTIONS="synchronize opened requested rerequested"

if [[ $ENABLED_ACTIONS != *"$ACTION"* ]]; then
  echo -e "Not interested in this event: $ACTION.\nExiting..."
  exit
fi

BASE_COMMIT=$(jq --raw-output .pull_request.base.sha "$GITHUB_EVENT_PATH")
if [[ "$BASE_COMMIT" == null ]]; then  # If this is not a pull request action it can be a check suite re-requested.
  BASE_COMMIT=$(jq --raw-output .check_suite.pull_requests[0].base.sha "$GITHUB_EVENT_PATH")
fi

PULL_REQUEST_NUMBER=$(jq --raw-output '.pull_request.number // .check_suite.pull_requests[0].number // empty' "$GITHUB_EVENT_PATH")
REPO_FULL_NAME=$(jq --raw-output '.repository.full_name // empty' "$GITHUB_EVENT_PATH")
GITHUB_API_URL=${GITHUB_API_URL:-https://api.github.com}

list_pr_files() {
	local page=1
	local response=""
	local file_count=0

	while true; do
		response=$(curl --silent --show-error --fail \
			-H 'Accept: application/vnd.github+json' \
			-H "Authorization: Bearer $GITHUB_TOKEN" \
			"$GITHUB_API_URL/repos/$REPO_FULL_NAME/pulls/$PULL_REQUEST_NUMBER/files?per_page=100&page=$page") || return 1

		file_count=$(jq 'length' <<< "$response") || return 1
		if [[ "$file_count" -eq 0 ]]; then
			break
		fi

		jq --raw-output '.[] | select(.status != "removed") | .filename' <<< "$response" || return 1

		if [[ "$file_count" -lt 100 ]]; then
			break
		fi

		((page++))
	done
}

list_changed_files() {
	if [[ -n "$PULL_REQUEST_NUMBER" && -n "$REPO_FULL_NAME" ]]; then
		echo "Listing changed files from GitHub PR API for PR #$PULL_REQUEST_NUMBER" >&2
		if list_pr_files; then
			return 0
		fi

		echo "Falling back to git diff because the GitHub PR files API request failed." >&2
	fi

	git diff --name-only --diff-filter=AM "$BASE_COMMIT"
}

filter_changed_files() {
	local regex="$1"
	local file=""

	while IFS= read -r file; do
		if [[ -n "$file" && $file =~ $regex ]]; then
			printf '%s\n' "$file"
		fi
	done <<< "$changed_files"
}

run_flake8() {
	# Document ignore codes here:
	# 	E402 - Some scripts (deploy scripts in particular) lazy-load modules.
	flake8 \
		--format=json \
		--max-line-length 120 \
		--ignore=E402 \
		"$@" \
		| jq '.' > flake8_output.json || true
}

run_cfn_lint() {
	cfn-lint \
		--format json \
		--output-file cfnlint_output.json \
		"$@" || true
}

run_jshint() {
	jshint \
		--reporter /usr/lib/node_modules/jshint-json/json.js \
		"$@" | jq '.' > jshint_output.json || true
}

run_linter_if_files_match() {
	local regex="$1"
	local description="$2"
	local runner="$3"
	local annotator="$4"
	local -a files=()

	readarray -t files < <(filter_changed_files "$regex")
	if [[ ${#files[@]} -eq 0 ]]; then
		return 0
	fi

	echo "Running $description against files: ${files[*]}"
	"$runner" "${files[@]}"
	python "$annotator"
}

# Our Github actions are hosted in a separate repo from the ones that the actions run.
# Git introduced a security measure for that and since we're the owner of both repos, we decided to disable it.
# See https://impel.atlassian.net/browse/PID-51 for more.”
git config --global --add safe.directory /github/workspace

changed_files=$(list_changed_files)

case "$INPUT_LINTER" in
	flake8)
		run_linter_if_files_match '\.py$' "flake8 against Python files" run_flake8 /src/flake8_annotator.py
		;;
	cfn-lint)
		run_linter_if_files_match 'template\.yaml$' "cfn-lint against CloudFormation templates" run_cfn_lint /src/cfn_lint_annotator.py
		;;
	jshint)
		run_linter_if_files_match '\.js$' "jshint against Javascript files" run_jshint /src/jshint_annotator.py
		;;
esac
