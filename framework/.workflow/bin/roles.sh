#!/usr/bin/env bash
# THE ROLE NAMES, IN ONE PLACE, BECAUSE TWO PLACES DISAGREED AND THE DISAGREEMENT WAS SILENT.
#
# Measured (Issue #126, found by driving the refreshed queue against a live board):
#
#   `check-naming.sh` accepted   ^(dev|qa|product|ops|flow)/<type>/<issue>-<slug>$
#   `queue.sh` routed a pull request to its author with   case "$branch" in "$role"/*)
#
# `flow` was in the gap. A `flow/` branch PASSED the naming gate — green, `Branch name and commit
# convention` — and there is no role called `flow`, so the routing skipped it for every role and the
# pull request appeared in NOBODY's queue. Nothing was printed about it anywhere.
#
# THIS IS THE PROJECT'S OWN DEFECT WEARING A NEW COSTUME: work that is not visible, with no error
# and a zero exit code. It was live on the very pull request that introduced it, and on this
# repository's own branches, which have used `flow/` since the framework began running under itself.
#
# So the two lists are now one list. A role added here gets a branch prefix and a queue together, or
# `queue.sh --self-test` fails — see the arm that asserts exactly that.

# ROLES THAT BUILD: may own a branch, therefore MUST have a queue arm that shows them their own
# pull requests. The naming gate's branch pattern is built from this.
ADF_BUILD_ROLES="dev qa product ops flow"

# ROLES THAT MAY BE ASKED FOR A QUEUE. The two that are not build roles never appear in a branch
# name because they do not build: `pm` routes and `owner` decides.
ADF_ALL_ROLES="$ADF_BUILD_ROLES pm owner"

# `dev|qa|product|ops|flow` — for the naming gate's regex.
adf_build_roles_alt() { printf '%s' "$ADF_BUILD_ROLES" | tr ' ' '|'; }

# A SELF-TEST, BECAUSE THIS FILE PASSED CI WITHOUT ONE.
#
# `make ci` requires every script here to ship `--self-test`, and it looks for the STRING. The
# comment above mentions `queue.sh --self-test`, so this file matched, ran nothing, exited 0 and
# printed OK. **A gate that cannot be shown to fail is not a gate** — this repository's own README
# says so, and its own suite proved it by passing a file that asserts nothing.
self_test() {
  local rc=0 r
  [ -n "$ADF_BUILD_ROLES" ] || { echo "SELF-TEST FAIL: no build roles, so the naming gate's pattern would match nothing and every branch would be refused" >&2; rc=1; }
  [ -n "$ADF_ALL_ROLES" ]   || { echo "SELF-TEST FAIL: no roles at all, so every queue would refuse" >&2; rc=1; }
  # EVERY BUILD ROLE MUST BE A ROLE. A branch prefix nothing can be asked a queue for is Issue #126
  # again: green at the gate, absent from every queue.
  for r in $ADF_BUILD_ROLES; do
    printf '%s\n' $ADF_ALL_ROLES | grep -qx "$r" \
      || { echo "SELF-TEST FAIL: '$r' may own a branch but is not a role queue.sh will answer for — a branch named after it passes the gate and reaches nobody" >&2; rc=1; }
  done
  # THE ALTERNATION MUST BE USABLE IN THE REGEX IT EXISTS FOR.
  local alt; alt=$(adf_build_roles_alt)
  printf '%s' "dev/fix/1-x" | grep -qE "^($alt)/fix/[0-9]+-[a-z0-9-]+$" \
    || { echo "SELF-TEST FAIL: the alternation '$alt' does not match a well-formed branch, so the naming gate built from it refuses everything" >&2; rc=1; }
  printf '%s' "nonrole/fix/1-x" | grep -qE "^($alt)/fix/[0-9]+-[a-z0-9-]+$" \
    && { echo "SELF-TEST FAIL: the alternation matched a role that does not exist, so the gate accepts a branch no queue routes" >&2; rc=1; }
  # SOURCING THIS FILE WITH ARGUMENTS MUST BE INERT. Driven, because reading it is what missed it:
  # a sourced file sees its CALLER's `$1`, so a dispatch on `$1` turns every consumer's own first
  # argument into a command for this file. The naming gate died on a branch name.
  local sourced_out sourced_rc=0
  sourced_out=$( bash -c '. "$1" "a-branch-name" "and-a-sha"; printf "%s" "$ADF_BUILD_ROLES"' _ "${BASH_SOURCE[0]}" 2>&1 ) || sourced_rc=$?
  if [ "$sourced_rc" -ne 0 ] || [ "$sourced_out" != "$ADF_BUILD_ROLES" ]; then
    echo "SELF-TEST FAIL: sourcing this file while the caller had its own arguments did not simply define the lists (rc=$sourced_rc, got: $sourced_out). A sourced file inherits \$1 from its caller, so anything that dispatches on it hijacks every consumer's arguments — this took down the naming gate." >&2
    rc=1
  fi

  [ "$rc" -eq 0 ] && echo "self-test passed: both lists are non-empty, every build role is a role a queue answers for, the alternation matches a real branch and refuses an invented one, and sourcing with the caller's arguments is inert"
  return $rc
}

# A SOURCED FILE INHERITS ITS CALLER'S POSITIONAL PARAMETERS, AND THAT BROKE THE GATE.
#
# The first version dispatched on `$1`. `check-naming.sh` sources this file and is itself called as
# `check-naming.sh "flow/feat/5-review-lifecycle" <sha>` — so `$1` here was THE BRANCH NAME, the
# `*)` arm fired, and the naming gate died with `roles.sh takes no arguments`. Green locally, red on
# CI, on the very branch adding the file.
#
# So the dispatch is on HOW THIS FILE WAS ENTERED, not on what happens to be in `$1`. Executed:
# `$0` is this file. Sourced: `$0` is the caller, and nothing below runs whatever it was passed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    --self-test) self_test; exit $? ;;
    "") echo "roles.sh is a library — source it, or pass --self-test." >&2; exit 2 ;;
    *) echo "::error::roles.sh takes no arguments other than --self-test. Got '$1'." >&2; exit 2 ;;
  esac
fi
