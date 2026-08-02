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
  [ -n "${REPO:-}" ] && return 0
  # FROM THE GIT REMOTE, NOT FROM THE API. `gh repo view` is a GraphQL call, and GraphQL has its
  # own quota: measured exhausted (5000/5000) on a working day while REST still had headroom. With
  # the API version, every role's queue became "no repository" the moment that quota ran out —
  # an outage in one subsystem silently disabling the thing that tells every agent what to do.
  # The remote URL is already on disk and answers the same question.
  local url
  url=$(git config --get remote.origin.url 2>/dev/null || echo "")
  if [ -n "$url" ]; then
    REPO=$(printf '%s' "$url" | sed -E 's#^(https://[^/]+/|git@[^:]+:)##; s#\.git$##')
  fi
  # Only then the API, for a checkout with no origin.
  [ -n "${REPO:-}" ] || REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")
  [ -n "${REPO:-}" ] || { echo "::error::no repository: this checkout has no 'origin' remote and the API could not be asked. Set REPO." >&2; exit 2; }
}

# REST, not GraphQL: the shared GraphQL quota was measured exhausted (5000/5000) while REST still
# had headroom, and `gh issue list` returned an EMPTY FILE rather than an error when that happened.
issues() { resolve_repo; api --paginate "repos/$REPO/issues?state=open&per_page=100"; }

emit() { # emit <heading> <jq-filter> [--unclaimed]
  local head=$1 filter=$2 skip=${3:-} out
  out=$(printf '%s' "$ALL" | jq -r "$filter" 2>/dev/null || true)
  # AN ISSUE SOMEBODY IS ALREADY ON IS NOT WORK TO START. Dropped rather than hidden: the count is
  # printed, because "nothing here" and "three of these are in flight" are different answers.
  # --landed: only Issues whose branch is GONE from the remote, i.e. the work merged and the branch
  # was deleted, or there never was one. An Issue still holding an open branch is somebody else's
  # turn, and showing it here is how a role goes looking for work that does not exist yet.
  if [ "$skip" = "--landed" ] && [ -n "${VERIFIED:-}" ]; then
    out=$(printf '%s\n' "$out" | grep -vE "^  #($(printf '%s' "$VERIFIED" | tr '\n' '|' | sed 's/|$//'))  " || true)
  fi
  if [ "$skip" = "--landed" ]; then
    if [ -n "${OPEN_BRANCH_ISSUES:-}" ]; then
      out=$(printf '%s\n' "$out" | grep -vE "^  #($(printf '%s' "$OPEN_BRANCH_ISSUES" | tr '\n' '|' | sed 's/|$//'))  " || true)
    fi
    # And an Issue nobody has ever built is not landed either.
    if [ -n "${EVER_BUILT:-}" ]; then
      out=$(printf '%s\n' "$out" | grep -E "^  #($(printf '%s' "$EVER_BUILT" | tr '\n' '|' | sed 's/|$//'))  " || true)
    else
      out=""
    fi
  fi
  # --unbuilt: unclaimed AND never built. An Issue whose work already merged is not dev's to
  # resolve — a dev agent spent a whole round discovering that by hand, which is a round the queue
  # could have saved it.
  if [ "$skip" = "--unbuilt" ] && [ -n "${EVER_BUILT:-}" ]; then
    out=$(printf '%s\n' "$out" | grep -vE "^  #($(printf '%s' "$EVER_BUILT" | tr '\n' '|' | sed 's/|$//'))  " || true)
  fi
  [ "$skip" = "--unbuilt" ] && skip=--unclaimed
  if [ "$skip" = "--unclaimed" ] && [ -n "${CLAIMED:-}" ]; then
    local before after
    local out_before=$out
    before=$(printf '%s\n' "$out" | grep -c . || true)
    out=$(printf '%s\n' "$out" | grep -vE "^  #($(printf '%s' "$CLAIMED" | tr '\n' '|' | sed 's/|$//'))  " || true)
    after=$(printf '%s\n' "$out" | grep -c . || true)
    # NAMED, NOT COUNTED. `(1 already have a branch — not shown)` is unfalsifiable from the output,
    # and it hid a real unclaimed Issue: another agent's branch happened to carry the number 4 in
    # its slug — `product/chore/4-archive-...`, about a pull request, nothing to do with Issue #4 —
    # so the claim set swallowed it. A dev agent found it only by listing Issues by hand, and
    # called it what it is: a second agent silently deleting an item from its queue while the
    # tooling returned rc=0 and a reassuring parenthesis.
    #
    # Naming them costs nothing and makes a wrong claim visible the moment it happens.
    if [ "$before" -ne "$after" ]; then
      local hidden
      hidden=$(printf '%s\n' "$out_before" | grep -E "^  #($(printf '%s' "$CLAIMED" | tr '\n' '|' | sed 's/|$//'))  " | sed 's/^  /      /' || true)
      head="$head
  (already has a branch — somebody is on it. If that is wrong, the branch's number is wrong:)
$hidden"
    fi
  fi
  printf '\n%s\n' "$head"
  if [ -n "$out" ]; then printf '%s\n' "$out"; else printf '  (none)\n'; fi
}

# YOUR OWN PULL REQUESTS, AND WHICH OF THEM NEED YOU. Without this a role has to call three
# separate things to work out what to do next, and the previous build showed what happens then: an
# agent fixed the one red it had been told about and never saw the one blocking the merge.
#
# THE VERDICT IS COMPUTED BY pr.sh, NOT RE-IMPLEMENTED HERE. It reads both the check runs and the
# commit statuses, and duplicating that logic is how the two answers drift apart.
# WHICH PULL REQUESTS ARE MINE IS NOT ALWAYS "THE ONES I AUTHORED". dev owns the branches it wrote;
# product owns the FEATURE pull requests whoever wrote them, because UAT is done on somebody else's
# branch. Filtering product by a `product/*` prefix returned (none) for a round whose entire workload
# was two dev branches — a successful lookup that filtered the answer away, which is worse than a
# failed one because the exit code is 0.
my_prs() {
  local match=$1 heading=${2:-YOUR PULL REQUESTS} prs line num branch st
  # RESOLVED HERE TOO. `issues()` calls resolve_repo inside a command substitution, so REPO is set in
  # a subshell that has already exited — the variable is unset by the time this runs. Found by
  # running it, not by reading it.
  resolve_repo
  prs=$(api --paginate "repos/$REPO/pulls?state=open&per_page=100")
  printf '\n%s:\n' "$heading"
  local any=0
  while IFS=$'\t' read -r num branch title; do
    [ -n "$num" ] || continue
    # THE PULL REQUEST'S TYPE IS IN ITS BRANCH NAME — `<role>/<type>/<issue>-<slug>`, which the
    # naming gate already enforces. Routing on it means a chore reaches qa and a feature reaches
    # product without anything being stored twice. Matching every branch instead put one archive
    # pull request in both queues at once, and two roles racing to merge the same thing is exactly
    # the collision this queue exists to prevent.
    local matched=0 pat
    IFS='|' read -ra _pats <<< "$match"
    for pat in "${_pats[@]}"; do case "$branch" in $pat) matched=1; break ;; esac; done
    [ "$matched" -eq 1 ] || continue
    any=1
    st=$("$(dirname "${BASH_SOURCE[0]}")/pr.sh" state "$num" --brief 2>&1) || true
    printf '  #%-4s %-46s %s\n' "$num" "$(printf '%s' "$title" | cut -c1-46)" "$st"
  done < <(printf '%s' "$prs" | jq -r '.[] | [.number, .head.ref, .title] | @tsv' 2>/dev/null || true)
  [ "$any" -eq 1 ] || printf '  (none)\n'
}

# WHAT IS ALREADY CLAIMED, DERIVED FROM THE BRANCH NAMES. `<role>/<type>/<issue>-<slug>` carries the
# Issue number, so a branch existing IS the claim — there is no label to set, no comment to post and
# nothing to expire. State is stored once, which is the whole reason the naming convention is a gate.
#
# Without this two agents of the same role both take the same Issue: it stayed in "to resolve" while
# its own pull request was open two lines below, which is what running it showed.
claimed_issues() {
  resolve_repo
  # AN OPEN PULL REQUEST IS THE CLAIM, NOT A BRANCH THAT EXISTS. Branches outlive their merges —
  # GitHub keeps them unless somebody deletes them — so a branch-based claim never expires, and an
  # Issue whose work had shipped stayed marked as "somebody is on it" forever. An open pull request
  # ends exactly when the work does, which is the property a claim needs.
  api --paginate "repos/$REPO/pulls?state=open&per_page=100" \
    | jq -r '.[].head.ref' 2>/dev/null \
    | sed -n 's#^[a-z]*/[a-z]*/\([0-9][0-9]*\)-.*#\1#p' | sort -u
}

role_queue() {
  local role=$1
  ALL=$(issues | jq -s 'add // []')
  # AN ISSUE YOU HAVE ALREADY VERIFIED IS NOT WORK WAITING FOR YOU. A product agent UAT'd two
  # Issues, found their criteria unreachable, deliberately left them open and recorded why — and the
  # queue went on listing them under "UAT and CLOSE", telling the next agent to do work already done.
  # A queue that repeats finished work is a queue people stop reading.
  #
  # The signal is the role's own marked comment, which is where the verdict already lives.
  CLAIMED=$(claimed_issues)
  resolve_repo
  # Issues that still have an open branch: not landed. And issues that have EVER had a pull request,
  # open or merged: the ones whose work exists at all.
  OPEN_BRANCH_ISSUES=$CLAIMED
  # Issues already carrying this role's own verdict comment.
  VERIFIED=$(api --paginate "repos/$REPO/issues/comments?per_page=100" \
    | jq -r --arg r "[$role]" '.[] | select(.body | startswith($r)) | .issue_url' 2>/dev/null \
    | sed -n 's#.*/issues/##p' | sort -u)
  EVER_BUILT=$(api --paginate "repos/$REPO/pulls?state=all&per_page=100" \
    | jq -r '.[].head.ref' 2>/dev/null \
    | sed -n 's#^[a-z]*/[a-z]*/\([0-9][0-9]*\)-.*#\1#p' | sort -u)

  case "$role" in
    dev)
      emit "ISSUES TO RESOLVE — open one branch and one PR per Issue:" \
        '.[] | select(.pull_request==null)
             | select([.labels[].name] | any(startswith("type:")))
             | select([.labels[].name] | index("blocked") | not)
             | "  #\(.number)  \(.title)"' --unbuilt
      my_prs "dev/*" ;;
    qa)
      # NOT EVERY BUG IS YOURS YET. An Issue with no branch has nothing to verify — it is dev's to
      # build first. Listing it under "to verify" is the same defect as the product arm one layer
      # down: a queue that cannot tell "yours to act on now" from "yours eventually" sends a role
      # looking for work that does not exist.
      emit "ISSUES WHOSE WORK HAS LANDED — verify on main and CLOSE:" \
        '.[] | select(.pull_request==null)
             | select([.labels[].name] | index("type:bug") or index("type:chore"))
             | "  #\(.number)  \(.title)"' --landed 
      my_prs "*/fix/*|*/bug/*|*/chore/*|*/docs/*|*/test/*|*/ci/*|*/build/*|*/refactor/*|*/perf/*" "PULL REQUESTS TO VERIFY, MERGE AND CLOSE — whoever wrote them" ;;
    product)
      emit "FEATURES WHOSE WORK HAS LANDED — UAT on main and CLOSE (already verified ones are dropped):" \
        '.[] | select(.pull_request==null)
             | select([.labels[].name] | index("type:feature"))
             | "  #\(.number)  \(.title)"' --landed 
      my_prs "*/feat/*|*/spec/*" "PULL REQUESTS TO UAT, MERGE AND CLOSE — whoever wrote them" ;;
    ops)
      emit "OPEN PULL REQUESTS — CI and gate health:" \
        '.[] | select(.pull_request!=null) | "  #\(.number)  \(.title)"' ;;
    pm)
      # AN ISSUE WAITING ON A DECISION IS IN NOBODY'S QUEUE, AND THAT IS CORRECT — nobody can build
      # it. But correct and invisible is an orphan: two Issues sat open, verified, deliberately left
      # open for the owner, and every role's queue dropped them for a good reason. Work nobody can
      # do is still work somebody must SEE, and the pm is the only channel to whoever decides.
      emit "WAITING ON A DECISION — nobody can build these; the owner must answer:" \
        '.[] | select(.pull_request==null)
             | select(.body // "" | test("## Blocked on a decision"))
             | "  #\(.number)  \(.title)"'
      emit "UNTYPED — cannot be routed until they carry a type: label:" \
        '.[] | select(.pull_request==null)
             | select([.labels[].name] | any(startswith("type:")) | not)
             | "  #\(.number)  \(.title)"'
      emit "UNCLASSIFIED — no area: label, so the R7 ratio cannot see them:" \
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
