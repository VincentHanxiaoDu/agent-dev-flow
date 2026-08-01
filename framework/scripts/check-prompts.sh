#!/usr/bin/env bash
# The prompts are the process. This checks that they still say what the PRD requires.
#
# WHY THIS EXISTS. In the previous build the routing rule lived in a prose document, the script
# that enforced part of it was deleted, and nothing noticed for hours — the document went on
# asserting an enforced rule that nothing enforced. And three of four role prompts had no
# parallelism instruction at all, so those roles worked one Issue at a time forever while the
# document said the process fanned out.
#
# So the properties the PRD names are asserted against the prompt files themselves, mechanically.
#
# Usage: check-prompts.sh [agents-dir]      default: .claude/commands
#        check-prompts.sh --self-test
set -euo pipefail

case "${1:-}" in
  -*) [ "$1" = "--self-test" ] || {
        echo "::error::unknown option '$1'. This is a typo, not an argument — refusing." >&2; exit 2; } ;;
esac

run_check() {
  local dir=${1:-.claude/commands} rc=0 f role

  # A MISSING DIRECTORY MUST NOT READ AS "EVERY PROMPT IS FINE". This is the defect this whole
  # project is about, and the check that reports on it is the last place it should appear.
  [ -d "$dir" ] || {
    echo "::error::$dir does not exist, so no prompt was examined. This is a LOOKUP FAILURE and NOT a statement that the prompts are correct." >&2
    return 1
  }

  # Every role the queue can dispatch must have a prompt. A role with a queue arm and no prompt is
  # a role that receives work and does not know what to do with it.
  for role in dev-workflow qa-workflow product-workflow create-feature release-version; do
    [ -f "$dir/$role.md" ] || { echo "::error::no prompt for role '$role'" >&2; rc=1; }
  done

  # R1 — EVERY WORKING ROLE PULLS ITS WHOLE QUEUE AND FANS OUT. pm is excluded deliberately: it
  # dispatches one message per role and must NOT fan out over Issues itself.
  for role in dev-workflow qa-workflow product-workflow; do
    f="$dir/$role.md"; [ -f "$f" ] || continue
    grep -q 'queue\.sh' "$f" \
      || { echo "::error::$role.md never tells the role to pull its queue — it can only ever work what it is handed" >&2; rc=1; }
    grep -qi 'in parallel\|all at once' "$f" \
      || { echo "::error::$role.md has no instruction to work the queue in parallel — this is the defect that made three of four roles serial" >&2; rc=1; }
    grep -qi 'no cap on width' "$f" \
      || { echo "::error::$role.md does not say the width is uncapped, so the role will pick a safe small number" >&2; rc=1; }
    # The lookup-failure distinction, in the prompt rather than only in the script.
    grep -qi 'failed lookup and an empty queue are different\|not learned that you have no work' "$f" \
      || { echo "::error::$role.md does not tell the role that a failed lookup is not an empty queue" >&2; rc=1; }
    # SELF-DRIVING. A role that reads its queue once works one round and stops, and somebody then
    # has to notice new work and restart it — which is a coordinator, which is the bottleneck this
    # process exists to remove. The queue is a state the role watches.
    grep -q 'watch-queue\.sh' "$f" \
      || { echo "::error::$role.md starts no monitor, so the role works one round and waits to be told about the next" >&2; rc=1; }
    # AND IT MUST WATCH ITS OWN PULL REQUESTS. Watching only the Issue queue leaves an agent
    # waiting for new work with its own branch red and nothing saying so.
    grep -q 'watch-prs\.sh' "$f" \
      || { echo "::error::$role.md never watches its own PRs — a red gate or a requested change would never reach it" >&2; rc=1; }
  done

  # R4 — CLOSURE AUTHORITY LIVES IN THE PROMPT OF THE ROLE THAT CLOSES, and nowhere else.
  grep -qi 'you close bugs and chores' "$dir/qa-workflow.md" 2>/dev/null \
    || { echo "::error::qa.md does not state that qa closes bugs and chores" >&2; rc=1; }
  grep -qi 'you close features' "$dir/product-workflow.md" 2>/dev/null \
    || { echo "::error::product.md does not state that product closes features" >&2; rc=1; }
  for role in dev-workflow; do
    grep -qi 'close nothing\|You close nothing' "$dir/$role.md" 2>/dev/null \
      || { echo "::error::$role.md does not state that $role closes nothing" >&2; rc=1; }
  done

  # WRITING REQUIREMENTS: a criterion that can be softened to make it reachable is not a criterion,
  # and the previous build produced one Issue carrying 247 of them in a single milestone.
  grep -qi 'testable or it is not a criterion' "$dir/create-feature.md" 2>/dev/null \
    || { echo "::error::create-feature.md does not require criteria to be testable" >&2; rc=1; }
  grep -qi 'never soften' "$dir/create-feature.md" 2>/dev/null \
    || { echo "::error::create-feature.md does not forbid softening a criterion to make it reachable" >&2; rc=1; }

  # RELEASING: product decides, ops executes; and an unnamed defect is not shippable.
  grep -qi 'product decides' "$dir/release-version.md" 2>/dev/null \
    || { echo "::error::release-version.md does not state that product decides and ops only executes" >&2; rc=1; }
  grep -qi 'named defect is shippable' "$dir/release-version.md" 2>/dev/null \
    || { echo "::error::release-version.md does not require known limitations to be named" >&2; rc=1; }

  # EVERY COMMAND CARRIES ITS PROJECT INJECTION POINT. Without it a project cannot add its own
  # process or knowledge without editing a framework file, and an edit to a framework file is
  # reverted by the next install — silently, which is how a team learns to stop upgrading.
  for role in dev-workflow qa-workflow product-workflow create-feature release-version; do
    f="$dir/$role.md"; [ -f "$f" ] || continue
    grep -q '@\.workflow/' "$f" \
      || { echo "::error::$role.md has no @.workflow/<role>/AGENT.md injection point — a project could only extend it by editing a file the installer overwrites" >&2; rc=1; }
  done

  [ "$rc" -eq 0 ] && echo "prompts ok: every role pulls its own queue and fans out uncapped, closure authority is stated where it is exercised, criteria cannot be softened, every working role watches its queue and its own PRs, and every command has its project injection point"
  return "$rc"
}

self_test() {
  local tmp rc=0 out
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN

  # 1. A MISSING DIRECTORY MUST FAIL, and say why. The vacuous pass is the whole point.
  out=$(run_check "$tmp/nope" 2>&1) && { echo "SELF-TEST FAIL: a missing directory PASSED" >&2; rc=1; }
  case "$out" in *"LOOKUP FAILURE"*) : ;; *) echo "SELF-TEST FAIL: a missing directory gave no explanation" >&2; rc=1 ;; esac

  # 2. A directory of EMPTY prompts must fail — files existing is not the property being checked.
  mkdir -p "$tmp/empty"; for r in dev-workflow qa-workflow product-workflow create-feature release-version; do : > "$tmp/empty/$r.md"; done
  run_check "$tmp/empty" >/dev/null 2>&1 && { echo "SELF-TEST FAIL: empty prompts PASSED" >&2; rc=1; }

  # 3. THE REAL PROMPTS MUST PASS. If they do not, this check is wrong or the prompts regressed,
  #    and either way it must be visible here rather than discovered in a dispatch.
  local here; here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  if [ -d "$here/.claude/commands" ]; then
    run_check "$here/.claude/commands" >/dev/null 2>&1 \
      || { echo "SELF-TEST FAIL: the shipped prompts do not satisfy the check" >&2; rc=1; }

    # 4. AND THE CHECK MUST BE ABLE TO CATCH THE REGRESSION IT EXISTS FOR — the one that made three
    #    of four roles serial. Strip the parallelism line from a real prompt and require a red.
    cp -R "$here/.claude/commands" "$tmp/mutant"
    grep -qi 'in parallel' "$tmp/mutant/qa-workflow.md" || { echo "SELF-TEST FAIL: mutation target absent — refusing to report a mutation that did not happen" >&2; rc=1; }
    grep -vi 'in parallel\|all at once' "$tmp/mutant/qa-workflow.md" > "$tmp/m" && mv "$tmp/m" "$tmp/mutant/qa-workflow.md"
    run_check "$tmp/mutant" >/dev/null 2>&1 \
      && { echo "SELF-TEST FAIL: a prompt with its parallelism removed PASSED — this check would not have caught the defect it was written for" >&2; rc=1; }
  fi

  [ "$rc" -eq 0 ] && echo "self-test passed: a missing directory refuses, empty prompts fail, the shipped prompts pass, and removing a role's parallelism reddens it"
  return "$rc"
}

case "${1:-}" in
  --self-test) self_test ;;
  *) run_check "${1:-.claude/commands}" ;;
esac
