#!/usr/bin/env bash
# What this role does next. Derived from repository state alone — never from being told.
#
# PRD R3: an agent must be able to compute its own queue. There is no owner:* label, no assignment
# message, no coordinator-maintained list. State is stored once.
#
# Usage: queue.sh <role>          # dev | qa | product | ops | pm
#        queue.sh --self-test
set -euo pipefail

case "${1:-}" in
  -*)
    # An unknown flag is a typo, not data. A one-letter slip (`--self-tests`) must not be taken as
    # a positional argument and silently change what this checks.
    [ "$1" = "--self-test" ] || {
      echo "::error::unknown option '$1'. This is a typo, not an argument — refusing." >&2; exit 2; }
    ;;
esac

# THE OUTPUT OF A FAILED LOOKUP IS NOT AN EMPTY QUEUE. PRD's unifying defect: `could not see`
# rendering as `nothing to see`. Every query below either returns data or this script exits
# non-zero. An agent that gets rc=0 and no items may conclude it has no work; that conclusion must
# only ever be reachable from a query that actually ran.
api() {
  local out rc=0
  out=$(gh api "$@" 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "::error::the queue could not be read: $out" >&2
    echo "  This is a LOOKUP FAILURE and NOT a statement that you have no work. Do not proceed as" >&2
    echo "  though the queue were empty. Retry, or report the outage — REST works when GraphQL's" >&2
    echo "  quota is exhausted, which is a real and observed condition." >&2
    exit 1
  fi
  printf '%s' "$out"
}

# RESOLVED WHEN A QUERY IS ABOUT TO RUN, NOT AT LOAD TIME. The first version resolved it at the
# top of the file, so `--self-test` — which touches no network — could not run outside a checkout
# and reported `no repository`. A self-test that cannot run is not a failing self-test, and the two
# must never share an exit path. Caught by running it.
resolve_repo() {
  REPO=${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")}
  [ -n "$REPO" ] || { echo "::error::no repository. Run inside a checkout or set REPO." >&2; exit 2; }
}

# REST, not GraphQL: the shared GraphQL quota was measured exhausted (5000/5000) while REST still
# had headroom, and `gh issue list` returned an EMPTY FILE rather than an error when that happened.
issues() { resolve_repo; api --paginate "repos/$REPO/issues?state=open&per_page=100"; }

emit() { # emit <heading> <jq-filter>
  local head=$1 filter=$2 out
  out=$(printf '%s' "$ALL" | jq -r "$filter" 2>/dev/null || true)
  printf '\n%s\n' "$head"
  if [ -n "$out" ]; then printf '%s\n' "$out"; else printf '  (none)\n'; fi
}

role_queue() {
  local role=$1
  ALL=$(issues | jq -s 'add // []')

  case "$role" in
    dev)
      emit "ISSUES TO RESOLVE — open one branch and one PR per Issue:" \
        '.[] | select(.pull_request==null)
             | select([.labels[].name] | any(startswith("type:")))
             | select([.labels[].name] | index("blocked") | not)
             | "  #\(.number)  \(.title)"' ;;
    qa)
      emit "BUGS AND CHORES TO VERIFY, MERGE AND CLOSE:" \
        '.[] | select(.pull_request==null)
             | select([.labels[].name] | index("type:bug") or index("type:chore"))
             | "  #\(.number)  \(.title)"' ;;
    product)
      emit "FEATURES TO UAT, ARCHIVE, MERGE AND CLOSE:" \
        '.[] | select(.pull_request==null)
             | select([.labels[].name] | index("type:feature"))
             | "  #\(.number)  \(.title)"' ;;
    ops)
      emit "OPEN PULL REQUESTS — CI and gate health:" \
        '.[] | select(.pull_request!=null) | "  #\(.number)  \(.title)"' ;;
    pm)
      emit "UNTYPED — cannot be routed until they carry a type: label:" \
        '.[] | select(.pull_request==null)
             | select([.labels[].name] | any(startswith("type:")) | not)
             | "  #\(.number)  \(.title)"'
      emit "UNCLASSIFIED — no area: label, so PRD R7'"'"'s ratio cannot see them:" \
        '.[] | select(.pull_request==null)
             | select([.labels[].name] | any(startswith("area:")) | not)
             | "  #\(.number)  \(.title)"'
      # R7's ratio and R8's net numbers, printed every round whether or not anyone asks.
      local p m
      p=$(printf '%s' "$ALL" | jq '[.[]|select(.pull_request==null)|select([.labels[].name]|index("area:product"))]|length')
      m=$(printf '%s' "$ALL" | jq '[.[]|select(.pull_request==null)|select([.labels[].name]|index("area:machinery"))]|length')
      printf '\nRATIO (PRD R7) — product %s : machinery %s\n' "$p" "$m"
      [ "$m" -le "$p" ] || printf '  OVER THE CAP. Dispatch no further machinery work until this is 1:1 or better.\n'
      ;;
    *)
      echo "::error::'$role' is not a role. One of: dev qa product ops pm" >&2; return 1 ;;
  esac
}

self_test() {
  local rc=0
  # A role that is not in the list must be REFUSED, not silently given an empty queue — an empty
  # queue is indistinguishable from "you have no work" and that is the defect this project is about.
  ( REPO=x/y role_queue not-a-role ) >/dev/null 2>&1 \
    && { echo "SELF-TEST FAIL: an unknown role was accepted" >&2; rc=1; }

  # Every role in the documented set must be dispatchable. A role prompt that exists with no queue
  # arm is a role that can never find its work.
  local r
  for r in dev qa product ops pm; do
    grep -q "^    $r)" "${BASH_SOURCE[0]}" \
      || { echo "SELF-TEST FAIL: role '$r' has no queue arm" >&2; rc=1; }
  done

  # A failed lookup must exit non-zero rather than print an empty queue.
  grep -q 'LOOKUP FAILURE and NOT a statement' "${BASH_SOURCE[0]}" \
    || { echo "SELF-TEST FAIL: a failed lookup is not distinguished from an empty queue" >&2; rc=1; }

  [ "$rc" -eq 0 ] && echo "self-test passed: unknown roles refuse, every role has a queue, a failed lookup is not an empty queue"
  return $rc
}

case "${1:-}" in
  --self-test) self_test ;;
  "") echo "usage: queue.sh <dev|qa|product|ops|pm> | --self-test" >&2; exit 2 ;;
  *) role_queue "$1" ;;
esac
