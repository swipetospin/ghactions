## Shell-specific checks

Check the shebang before you apply these rules. Some rules apply only to
Bash (`#!/bin/bash`, `#!/usr/bin/env bash`). Others apply only to POSIX
`sh` (`#!/bin/sh`). A file with no shebang that is only `source`d takes
the shell of its caller.

### Unquoted expansions (Blocking)

An unquoted `$var`, `$(cmd)`, or `$@` is split on whitespace and expanded
as a glob. A value with a space or a `*` breaks the command or hits the
wrong files. Flag it unless the splitting is clearly intended.

Do not flag unquoted expansions where no splitting occurs: the right side
of a plain assignment, inside `[[ ... ]]` (except the right side of `==`
or `=~`, which is a pattern), inside `(( ... ))`, and the word in `case`.

Bad:
```bash
cp $src $dest
for arg in $@; do
```

Good:
```bash
cp "$src" "$dest"
for arg in "$@"; do
```

When a command is built from parts, use an array, not a string that
relies on splitting.

Bad:
```bash
opts="--retry 3 --header 'Accept: application/json'"
curl $opts "$url"  # the quotes inside $opts are passed literally
```

Good:
```bash
opts=(--retry 3 --header "Accept: application/json")
curl "${opts[@]}" "$url"
```

### Strict mode (Minor)

A new executable script should start with `set -euo pipefail` (or
`set -eu` in POSIX `sh`, which has no `pipefail` before POSIX 2024).
Without it, a failed command lets the script continue with bad state.

Do not flag a missing `set -e` in a file that is only `source`d, since it
would change the caller's shell. Do not flag it when the script handles
errors on every command itself.

Bad:
```bash
#!/usr/bin/env bash
build_artifact
upload_artifact  # runs even if the build failed
```

Good:
```bash
#!/usr/bin/env bash
set -euo pipefail
build_artifact
upload_artifact
```

### Masked exit statuses (Blocking)

Some forms hide a failed command, even under `set -e`:

- `local`, `export`, `declare`, or `readonly` combined with a command
  substitution. The line returns the status of the builtin, which is 0.
- A pipeline without `pipefail`. Only the last command's status counts.
- A command inside a condition (`if`, `while`, `&&`, `||`), or inside a
  function called from one. `set -e` is off for all of it.

Bad:
```bash
local version=$(get_version)  # get_version can fail; the error is lost
```

Good:
```bash
local version
version=$(get_version)
```

### Checking `$?` after the fact (Minor)

Test the command directly. Under `set -e`, a separate `$?` check is dead
code: the script exits before it reaches the check. That makes it a
Blocking bug when the check does needed cleanup or reporting.

Bad:
```bash
make build
if [ $? -ne 0 ]; then
  echo "Build failed" >&2
  exit 1
fi
```

Good:
```bash
if ! make build; then
  echo "Build failed" >&2
  exit 1
fi
```

### Unchecked `cd` (Blocking)

If `cd` fails and the script continues, the next commands run in the
wrong directory. This is dangerous before `rm`, `mv`, or `git` commands.
Flag it when strict mode is off, or when `cd` is in a condition or a
subshell where `set -e` does not stop the script.

Bad:
```bash
cd "$release_dir"
rm -rf ./*
```

Good:
```bash
cd "$release_dir" || exit 1
rm -rf ./*
```

### Destructive commands with variable paths (Blocking)

`set -u` catches an unset variable, but not an empty one. An empty
variable in a path passed to `rm -rf` can delete from `/` or the current
directory. Use `${var:?}` to stop the script when the value is empty.

Bad:
```bash
rm -rf "$BUILD_DIR/"*  # if BUILD_DIR is empty, this is rm -rf /*
```

Good:
```bash
rm -rf "${BUILD_DIR:?}/"*
```

### Looping over command output (Blocking)

`for x in $(ls)` or `for line in $(cat file)` splits on every space, not
on each line or file name. Use a glob for files and `while read` for
lines. Use `read -r` so that backslashes are kept, and `IFS=` so that
leading and trailing spaces are kept.

Bad:
```bash
for f in $(ls *.log); do
  gzip $f
done

for line in $(cat hosts.txt); do
  ping -c 1 $line
done
```

Good:
```bash
for f in ./*.log; do
  [[ -e "$f" ]] || continue  # no match leaves the literal pattern
  gzip "$f"
done

while IFS= read -r line; do
  ping -c 1 "$line"
done < hosts.txt
```

### Variables set in a pipeline (Blocking)

In Bash, each part of a pipeline runs in a subshell. A variable changed
inside `cmd | while read ...` is lost when the loop ends.

Bad:
```bash
count=0
grep ERROR app.log | while IFS= read -r line; do
  count=$((count + 1))
done
echo "$count"  # always prints 0
```

Good:
```bash
count=0
while IFS= read -r line; do
  count=$((count + 1))
done < <(grep ERROR app.log)
echo "$count"
```

### Numeric vs. string comparison (Blocking)

In `[[ ... ]]`, `<` and `>` compare strings, not numbers. `[[ 10 > 9 ]]`
is false. In `[ ... ]`, `>` is a redirect and creates a file. Use `-lt`,
`-gt`, and so on, or `(( ... ))` for numbers.

Bad:
```bash
if [[ $count > $limit ]]; then
```

Good:
```bash
if (( count > limit )); then
```

### Bash features in `#!/bin/sh` scripts (Blocking)

On Debian, Ubuntu, and GitHub-hosted Linux runners, `/bin/sh` is `dash`.
On Alpine it is BusyBox `ash`. Neither supports Bash features. On macOS,
`/bin/sh` is Bash, so the script works locally and fails in CI or in a
container. Flag these in a `#!/bin/sh` script: `[[ ... ]]`, arrays,
`function` keyword, `source`, `==` inside `[ ... ]`, `<(...)`, `$'...'`,
`{a,b}` or `{1..5}` brace expansion, and `echo -e`.

Bad:
```sh
#!/bin/sh
if [[ "$env" == "prod" ]]; then
```

Good (stay POSIX):
```sh
#!/bin/sh
if [ "$env" = "prod" ]; then
```

Good (switch to Bash):
```bash
#!/usr/bin/env bash
if [[ "$env" == "prod" ]]; then
```

### Conditionals in Bash (Minor)

In a Bash script, prefer `[[ ... ]]` over `[ ... ]`. It does not split
words or expand globs, and it supports `&&`, `||`, and `=~`. Only flag
this when the file already uses `[[ ... ]]`, or when the `[ ... ]` form
causes a real bug (for example, an unquoted variable inside it).

Bad:
```bash
if [ -n $name -a $name != "root" ]; then
```

Good:
```bash
if [[ -n "$name" && "$name" != "root" ]]; then
```

### Temporary files (Blocking)

A fixed or predictable name in `/tmp` (such as `/tmp/myscript.$$`) lets
another user replace the file or plant a symlink. Two runs of the script
at the same time also overwrite each other's data. Use `mktemp`, and
remove the file with a `trap`.

Bad:
```bash
tmp=/tmp/deploy.$$
curl -o "$tmp" "$url"
```

Good:
```bash
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -o "$tmp" "$url"
```

### Shell-specific security (Blocking)

Flag these when they touch untrusted input or secrets:

- `eval` on a string that holds any external value. Use an array or a
  `case` statement.
- A variable passed as a file name to `rm`, `mv`, `cp`, and similar
  commands with no `--` before it. A value that starts with `-` becomes an
  option.
- `set -x` while secrets are in variables. The trace prints them to the
  log.
- A secret passed as a command-line argument (for example
  `mysql -p"$PASSWORD"`). Other users can see it in `ps`. Use an
  environment variable, a file, or stdin.
- `curl ... | sh` or `curl ... | bash` from a URL with no checksum or
  pinned version.

Bad:
```bash
eval "git log --author=$author"
```

Good:
```bash
git log --author="$author"
```

### Command substitution syntax (Minor)

Prefer `$(...)` over backticks. Backticks do not nest cleanly and treat
backslashes in a way that is hard to read. Only flag this in new code,
and not when the file uses backticks everywhere.

Bad:
```bash
dir=`dirname \`readlink -f "$0"\``
```

Good:
```bash
dir=$(dirname "$(readlink -f "$0")")
```
