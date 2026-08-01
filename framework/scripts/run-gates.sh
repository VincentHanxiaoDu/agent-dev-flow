#!/usr/bin/env bash
# Run the gates the way CI runs them. One command, no arguments to remember.
#
# WHY THIS EXISTS. Several gates behave DIFFERENTLY without their base sha rather than refusing —
# or they did, until each was made to refuse. An agent ran `check-naming.sh <branch>` with no base,
# reported `rc=0` twice, and CI then went red. The exit code was real; the invocation was a
# strictly weaker check than the one being claimed.
#
# So the invocations live HERE, next to the gates, and this is what agents and CI both use. An
# invocation assembled from memory is a place for memory to be wrong, on every run, for every agent.
#
# Usage: run-gates.sh [base-ref]      default: origin/main
#        run-gates.sh --self-test
set -euo pipefail

case "${1:-}" in
  -*) [ "$1" = "--self-test" ] || {
        echo "::error::unknown option '$1'. This is a typo, not an argument — refusing." >&2; exit 2; } ;;
esac

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# A GATE THIS RUNNER CANNOT RUN MUST BE NAMED HERE, WITH ITS REASON. An omission and a deliberate
# exclusion look identical from a green run, so the exclusion is data rather than an absence — and
# the self-test below requires that anything excluded is also disclosed in the closing message.
# Found by this file's own self-test, which failed the first time it was run.
CANNOT_RUN_LOCALLY="check-review.sh"   # needs the PR's comments; only CI has them

self_test() {
  local rc=0 g b
  # EVERY GATE THAT TAKES A BASE MUST BE GIVEN ONE HERE, asserted by pattern so a gate added later
  # without its argument is caught rather than discovered on a red CI run. Only gates this runner
  # actually invokes are in scope: asserting an argument for a gate we never call is a check that
  # cannot fail for the right reason.
  for g in check-naming; do
    grep -qE "$g\.sh\"? .*\\\$base" "${BASH_SOURCE[0]}" \
      || { echo "SELF-TEST FAIL: $g.sh is invoked without the base sha — it will check less than its name suggests" >&2; rc=1; }
  done
  # AND EVERY GATE THAT EXISTS MUST BE RUN OR EXPLICITLY EXCLUDED. A local runner silently missing
  # a gate is worse than no runner: it reports a green that CI will redden, which is the same shape
  # as the defect it was written for.
  for g in "$here"/check-*.sh; do
    b=$(basename "$g")
    case " $CANNOT_RUN_LOCALLY " in
      *" $b "*)
        # Excluded — but the closing message must SAY it is excluded, or a reader takes the pass
        # as covering it.
        grep -q "review gate" "${BASH_SOURCE[0]}" \
          || { echo "SELF-TEST FAIL: $b is excluded and the runner's output does not disclose it" >&2; rc=1; }
        continue ;;
    esac
    grep -q "$b" "${BASH_SOURCE[0]}" \
      || { echo "SELF-TEST FAIL: $b exists and this runner neither runs it nor declares it unrunnable" >&2; rc=1; }
  done
  [ "$rc" -eq 0 ] && echo "self-test passed: every gate present is run here, and every gate that takes a base sha is given one"
  return $rc
}

[ "${1:-}" = "--self-test" ] && { self_test; exit $?; }

base_ref=${1:-origin/main}
branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" = HEAD ]; then
  # A detached HEAD is how a reviewer checks out a PR, and reviewers are intended users.
  branch=$(gh pr view --json headRefName -q .headRefName 2>/dev/null || true)
  [ -n "$branch" ] || { echo "::error::HEAD is detached and this commit belongs to no branch this clone knows. That is a checkout problem, not a finding." >&2; exit 1; }
fi

base=$(git merge-base "$base_ref" HEAD) || {
  echo "::error::could not resolve a merge base against $base_ref. Fetch it first — this is a lookup failure and not a verdict about anything." >&2; exit 1; }

echo "gates for $branch against $base_ref ($(git rev-parse --short "$base"))"
echo

rc=0
run() { local label=$1; shift; local out status=0
  out=$("$@" 2>&1) || status=$?
  if [ "$status" -eq 0 ]; then printf '  ok    %s\n' "$label"
  else printf '  FAIL  %s\n' "$label"; printf '%s\n' "$out" | sed 's/^/          /'; rc=1; fi
}

# The self-tests first: a gate that cannot be shown to fail is not a gate.
run "gate self-tests" bash -c "for s in $here/check-*.sh; do bash \"\$s\" --self-test >/dev/null || exit 1; done"
# NOT APPLICABLE INSIDE A WORKTREE, and this is not a nicety. `.claude/commands/` is gitignored —
# local to a checkout, absent from every `git worktree add`. The dev prompt tells an agent to work
# in a worktree AND to run this runner, so both sub-agents on the first real fan-out hit a red
# `prompts` gate caused by nothing in their diff, and one tried copying the directory in and
# produced thirty false assertion failures. CI deliberately excludes this check for the same
# reason. A runner that is a strict superset of CI is wrong in the direction its own header
# forbids: it reports a red that CI will not.
# TESTED WHERE check-prompts.sh WILL LOOK — the CURRENT DIRECTORY, not next to this script. The
# first version asked `$here/../.claude/commands`, which resolves to the main checkout even when the
# runner is invoked from a worktree, so the condition was true and the gate still failed. Found by
# running it in a worktree rather than by reading it.
if [ -d ".claude/commands" ]; then
  run "prompts"         "$here/check-prompts.sh"
else
  printf '  --    prompts (no .claude/commands here — local-only and gitignored, so not checked)\n'
fi
run "queue"           "$here/queue.sh"        --self-test
run "queue watch"     "$here/watch-queue.sh"  --self-test
run "PR watch"        "$here/watch-prs.sh"    --self-test
run "tasks complete"  "$here/check-tasks-complete.sh" "$base"
run "generated files" "$here/check-generated.sh" "$base"
run "branch and commits" "$here/check-naming.sh" "$branch" "$base"

echo
if [ "$rc" -eq 0 ]; then
  echo "all gates pass. This is what CI runs, with the arguments CI uses."
  echo "It does NOT run: your project's build and tests, or the review gate — the first needs your"
  echo "toolchain and the second needs a second agent. A pass here says nothing about either."
else
  echo "at least one gate failed. Each line above is the gate's own output."
fi
exit $rc
