#!/usr/bin/env bash
# Install (or upgrade) agent-dev-flow into a target repository.
#
# Reports every file it would overwrite BEFORE touching anything. An upgrade that silently discards
# a project's local edits is the fastest way to make a team stop upgrading — and in the previous
# build an install deleted 197 lines of a project's own process content, in a commit whose message
# claimed the install was safe.
#
# Usage: install.sh <target-repo> [--force]
set -euo pipefail

VERSION=0.1.0
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/framework"
target=${1:?usage: install.sh <target-repo> [--force]}
force=${2:-}

[ -d "$target" ] || { echo "error: $target does not exist" >&2; exit 1; }
target=$(cd "$target" && pwd)
[ "$target" != "$(dirname "$SRC")" ] || { echo "error: refusing to install the framework into itself" >&2; exit 1; }

manifest() { ( cd "$SRC" && find .claude scripts -type f | sed 's#^\./##' ); }

# --- dry run first -----------------------------------------------------------
declare -a overwrites=() news=()
while IFS= read -r f; do
  if [ ! -f "$target/$f" ]; then news+=("$f")
  elif ! cmp -s "$SRC/$f" "$target/$f"; then overwrites+=("$f"); fi
done < <(manifest)

echo "agent-dev-flow $VERSION -> $target"
[ ${#news[@]} -eq 0 ] || { echo; echo "new (${#news[@]}):"; printf '  + %s\n' "${news[@]}"; }
if [ ${#overwrites[@]} -gt 0 ]; then
  echo; echo "MODIFIED LOCALLY — these differ from the framework version (${#overwrites[@]}):"
  printf '  ! %s\n' "${overwrites[@]}"
  if [ "$force" != "--force" ]; then
    echo
    echo "Nothing has been written. Review the differences, then re-run with --force."
    echo "If a local edit is worth keeping, upstream it into the framework instead — a project that"
    echo "diverges from the process it claims to follow is worse off than one with no process."
    exit 1
  fi
  echo; echo "--force given; overwriting."
fi

while IFS= read -r f; do
  mkdir -p "$target/$(dirname "$f")"
  cp "$SRC/$f" "$target/$f"
done < <(manifest)
chmod +x "$target"/scripts/*.sh

printf 'version=%s\n' "$VERSION" > "$target/.agent-dev-flow"

# THE PROMPTS ARE THE PROCESS, so the install verifies them rather than assuming the copy was
# faithful. An install that reports success having written prompts that no longer satisfy the
# design is the same defect as a gate that passes having examined nothing.
echo
if ! ( cd "$target" && ./scripts/check-prompts.sh ); then
  echo "error: the installed prompts do not satisfy the design. The install wrote files; it did not" >&2
  echo "       deliver a working process. Fix the framework and re-run." >&2
  exit 1
fi
( cd "$target" && ./scripts/queue.sh --self-test >/dev/null ) || {
  echo "error: queue.sh's self-test fails in the target. Refusing to report a successful install." >&2; exit 1; }

cat <<EOF

Installed and verified. Remaining setup, none of which this script can do for you:

  1. Make \`main\` the default branch. It is the only long-lived branch; every other branch is
     \`<role>/<type>/<issue>-<slug>\` and merges into it.
  2. Protect \`main\`, requiring these five contexts — until this is done, every gate is advisory
     and the process is enforcing nothing:
       Build and tests
       Branch and commit convention
       Tasks complete / change archived
       Generated files not hand-authored
       Reviewed by an agent that authored none of its commits
     The gate set is FROZEN at five. A sixth requires the owner.
  3. Create the labels the queue reads: type:feature, type:bug, type:chore,
     area:product, area:machinery.
  4. Open one rolling debt Issue. A review may open at most one new Issue; the rest go there.

Then start the loop with one message per role. Each role pulls its own queue and fans out —
you do not schedule, enumerate, or assign.
EOF
