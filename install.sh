#!/usr/bin/env bash
# Install agent-dev-flow into a repository.
#
#   curl -fsSL https://raw.githubusercontent.com/VincentHanxiaoDu/agent-dev-flow/main/install.sh | bash
#
# or, from a clone:   ./install.sh [target-repo] [--protect]
#
# --protect also configures branch protection on the default branch, requiring exactly the
# contexts the installed workflow produces. Opt-in: it changes who can write to `main`.
set -euo pipefail

REPO_URL=${ADF_REPO:-https://github.com/VincentHanxiaoDu/agent-dev-flow}
REF=${ADF_REF:-main}
# --protect CONFIGURES BRANCH PROTECTION. It is opt-in and never a default: it changes who can
# write to `main`, which is a repository policy decision and not this script's to make for someone.
protect=no
args=()
for a in "$@"; do
  case "$a" in
    --protect) protect=yes ;;
    -*) echo "error: unknown option '$a'. This is a typo, not a path — refusing." >&2; exit 2 ;;
    *) args+=("$a") ;;
  esac
done
target=${args[0]:-$PWD}

[ -d "$target" ] || { echo "error: $target does not exist" >&2; exit 1; }
target=$(cd "$target" && pwd)

# --- get the framework, whether we were curled or cloned ---------------------
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")
if [ -n "$SELF_DIR" ] && [ -d "$SELF_DIR/framework" ]; then
  SRC="$SELF_DIR/framework"
  cleanup() { :; }
else
  # Piped from curl: fetch a tarball rather than requiring git.
  TMP=$(mktemp -d)
  cleanup() { rm -rf "$TMP"; }
  echo "fetching ${REPO_URL#https://github.com/} @ $REF"
  curl -fsSL "$REPO_URL/archive/refs/heads/$REF.tar.gz" | tar -xz -C "$TMP" --strip-components=1 || {
    echo "error: could not fetch the framework from $REPO_URL @ $REF." >&2
    echo "  This is a DOWNLOAD failure and NOT a statement that the framework does not exist." >&2
    exit 1; }
  SRC="$TMP/framework"
fi
trap cleanup EXIT
[ -d "$SRC" ] || { echo "error: no framework/ directory found at $SRC" >&2; exit 1; }
[ "$target" != "$(dirname "$SRC")" ] || { echo "error: refusing to install the framework into itself" >&2; exit 1; }

# .github IS IN THE MANIFEST, and it was not. The workflow that produces every required context
# was therefore never installed: the gates existed as scripts nothing ran, and the install then
# refused to print a context list because it could not find the file it had not copied. The refusal
# was right and it is how this was found.
manifest() { ( cd "$SRC" && find .claude .github scripts -type f | sed 's#^\./##' ); }

# --- what would change -------------------------------------------------------
declare -a overwrites=() news=()
while IFS= read -r f; do
  if [ ! -f "$target/$f" ]; then news+=("$f")
  elif ! cmp -s "$SRC/$f" "$target/$f"; then overwrites+=("$f"); fi
done < <(manifest)

echo "agent-dev-flow -> $target"
[ ${#news[@]} -eq 0 ]       || { echo; echo "new (${#news[@]}):";       printf '  + %s\n' "${news[@]}"; }
[ ${#overwrites[@]} -eq 0 ] || { echo; echo "replaced (${#overwrites[@]}):"; printf '  ~ %s\n' "${overwrites[@]}"; }

# THE FRAMEWORK OWNS .claude/ AND OVERWRITES IT WITHOUT ASKING. That is safe only because a project
# never edits those files: everything project-specific goes in .workflow/<role>/AGENT.md, which this
# script creates once and never touches again. The previous build had no such seam, so a project's
# local additions lived in framework files and an upgrade silently deleted them.
while IFS= read -r f; do
  mkdir -p "$target/$(dirname "$f")"
  cp "$SRC/$f" "$target/$f"
done < <(manifest)
chmod +x "$target"/scripts/*.sh

# --- the project's own half, created once and then left alone ----------------
for role in dev qa product ops; do
  d="$target/.workflow/$role"
  mkdir -p "$d"
  [ -f "$d/AGENT.md" ] && { echo "  = .workflow/$role/AGENT.md (kept)"; continue; }
  cat > "$d/AGENT.md" <<EOF
# Project-specific instructions for the $role role

**This file is yours. The installer creates it once and never overwrites it.** Everything in
\`.claude/commands/\` belongs to the framework and is replaced on every install, so anything you add
there is lost — put it here instead.

What belongs here: this project's build and test commands, its domain vocabulary, conventions a
newcomer would get wrong, and anything the $role role needs that is true of this project and not of
every project.

What does not: how the process works. That is the framework's half, and if you find yourself
restating it here, the framework is missing something — change it there.

_(empty — nothing project-specific yet)_
EOF
  echo "  + .workflow/$role/AGENT.md"
done

printf 'ref=%s\n' "$REF" > "$target/.agent-dev-flow"

# --- what has to be committed, and what does not -----------------------------
# ONLY CI NEEDS TO BE IN THE REPOSITORY. GitHub Actions runs the workflow and the gate scripts from
# the repository, so those must be committed. `.claude/commands/` is read by a person's Claude Code
# session and by nothing else — no job references it — and `.workflow/` is the project's own notes.
# Both are re-created by re-running this installer, so a machine without them is one command away.
#
# The default is to ignore them, because committing a prompt file makes it look like a reviewed
# artefact of this project when it is a replaced-on-every-install copy of the framework's.
if [ -f "$target/.gitignore" ] && grep -q '^\.claude/commands/' "$target/.gitignore"; then
  :
else
  {
    printf '\n# agent-dev-flow: local, not part of this project.\n'
    printf '# Re-created by re-running the installer. CI reads neither.\n'
    printf '.claude/commands/\n'
    printf '.agent-dev-flow\n'
  } >> "$target/.gitignore"
  echo "  + .gitignore entries for .claude/commands/ (local only)"
fi

# --- the labels the queue routes on --------------------------------------------------------
# CREATED HERE, BECAUSE A MISSING LABEL IS AN INVISIBLE ISSUE. The queue routes on `type:` and the
# product/machinery ratio counts `area:` — an Issue carrying neither is in no role's queue and in no
# count, so it is not merely unrouted, it is unseen. Asking a person to paste five API calls is a
# step that gets skipped, and what it costs is silent.
label() { # label <name> <colour> <description>
  gh api -X POST "repos/$SLUG/labels" -f name="$1" -f color="$2" -f description="$3" >/dev/null 2>&1 && echo "  + label $1" && return 0
  # Already there is success. Anything else is not, and must say so rather than look like success.
  gh api "repos/$SLUG/labels/$1" >/dev/null 2>&1 && { echo "  = label $1 (exists)"; return 0; }
  echo "  ! label $1 COULD NOT BE CREATED" >&2; return 1
}

lrc_ok=no
SLUG=$(cd "$target" && git config --get remote.origin.url 2>/dev/null | sed -E 's#^(https://[^/]+/|git@[^:]+:)##; s#\.git$##' || echo "")
echo
if [ -z "$SLUG" ]; then
  echo "no 'origin' remote here, so the labels were NOT created. They are not optional — an Issue"
  echo "with no type: label is in no role's queue, and one with no area: label is in no count."
  echo "Add a remote and re-run this installer, or create them by hand."
elif ! command -v gh >/dev/null 2>&1; then
  echo "gh is not installed, so the labels were NOT created. See above for why they matter."
else
  echo "labels on $SLUG:"
  lrc=0
  label type:feature   0E8A16 "A capability a person can use" || lrc=1
  label type:bug       D73A4A "Something does not do what it says" || lrc=1
  label type:chore     BFD4F2 "Work with no user-visible change" || lrc=1
  label area:product   0E8A16 "The thing being built" || lrc=1
  label area:machinery FBCA04 "Gates, CI, tooling — not the product" || lrc=1
  [ "$lrc" -eq 0 ] && lrc_ok=yes
  [ "$lrc" -eq 0 ] || {
    echo "  at least one label could not be created — most likely 'gh auth login' has not been run," >&2
    echo "  or this token cannot write to $SLUG. The install itself succeeded; routing will not work" >&2
    echo "  until these exist." >&2
  }
fi

# --- verify, rather than assume the copy was faithful ------------------------
echo
( cd "$target" && ./scripts/check-prompts.sh ) || {
  echo "error: the installed commands do not satisfy the design. Files were written; a working" >&2
  echo "       process was not delivered. Fix the framework and re-run." >&2
  exit 1; }
( cd "$target" && ./scripts/queue.sh --self-test >/dev/null ) || {
  echo "error: queue.sh's self-test fails here. Refusing to report a successful install." >&2; exit 1; }

# THE REQUIRED CONTEXTS ARE READ FROM THE INSTALLED WORKFLOW, never restated here. They were
# restated once, and the copy named a fifth context no job produced — anyone following those
# instructions would have protected `main` on a check that never arrives, and every pull request
# would have waited on it forever. A list that can drift from the thing it describes will.
CONTEXTS=$(sed -n 's/^    name: /       /p' "$target/.github/workflows/gates.yml" 2>/dev/null || echo "")
[ -n "$CONTEXTS" ] || {
  echo "error: could not read the job names from the installed workflow, so the list of required" >&2
  echo "       contexts cannot be printed. Refusing to guess: a wrong list protects main on a check" >&2
  echo "       that never arrives, and every pull request then waits forever." >&2
  exit 1; }

cat <<EOF

Required contexts, read from the workflow just installed:

$CONTEXTS
EOF

if [ "$protect" = yes ]; then
  echo
  if [ -z "$SLUG" ]; then
    echo "error: --protect needs an 'origin' remote to know which repository to protect." >&2; exit 1
  elif ! command -v gh >/dev/null 2>&1; then
    echo "error: --protect needs gh." >&2; exit 1
  else
    # THE CONTEXT LIST IS THE ONE READ FROM THE WORKFLOW, not a second copy. Protecting `main` on a
    # context no job produces is worse than not protecting it: every pull request waits forever on
    # a check that never arrives, and the reason is invisible from the pull request page.
    ctx_json=$(printf '%s\n' "$CONTEXTS" | sed 's/^ *//' | grep -v '^$' | jq -R . | jq -sc .)
    branch=$(cd "$target" && git symbolic-ref --short HEAD 2>/dev/null || echo main)
    echo "protecting $SLUG@$branch on the contexts above"
    # strict=false is deliberate: branches are NOT required to be up to date with main. Requiring it
    # serialises every merge behind a rebase, and the recovery for a genuine conflict is that the
    # verifier merges one branch and returns the other — not that everyone rebases constantly.
    if printf '{"required_status_checks":{"strict":false,"contexts":%s},"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null}' "$ctx_json" \
       | gh api -X PUT "repos/$SLUG/branches/$branch/protection" --input - >/dev/null 2>&1; then
      # VERIFIED BY READING IT BACK. A PUT that exits 0 is not proof the policy is in place.
      got=$(gh api "repos/$SLUG/branches/$branch/protection" --jq '[.required_status_checks.contexts[]] | length' 2>/dev/null || echo 0)
      want=$(printf '%s\n' "$CONTEXTS" | grep -cv '^$')
      if [ "$got" -eq "$want" ]; then
        echo "  protected: $got required contexts, confirmed by reading the policy back"
      else
        echo "  ! the policy was written but reads back with $got contexts, not $want — check it by hand" >&2
      fi
    else
      echo "  ! could not protect $branch. Most likely this token lacks admin on the repository," >&2
      echo "    or the repository is on a plan without branch protection. The install itself" >&2
      echo "    succeeded; the gates are advisory until this is done." >&2
    fi
  fi
fi

cat <<'EOF'

Installed and verified.

  /dev-workflow           resolve Issues into reviewed branches
  /qa-workflow            verify bugs and chores, merge, close
  /product-workflow       UAT features, close, decide to release
  /create-feature <what>  turn a description into Issues with testable criteria
  /release-version <tag>  tag and publish a release product has called

Run each in its own Claude Code session. They coordinate through GitHub Issue and PR state,
not by messaging each other — so they can all run at once.

COMMIT ONLY WHAT CI RUNS:

    git add .github scripts .workflow && git commit -m "chore: install agent-dev-flow" && git push

  .github/ and scripts/  CI runs them from the repository, so they must be committed.
  .workflow/             yours; commit it if your team should share it, ignore it if not.
  .claude/commands/      gitignored by default — read by your Claude Code session and by no job.
                         Re-running the installer re-creates it on any machine.

EOF

# LIST ONLY WHAT WAS NOT DONE. Repeating a step this run just completed trains the reader to skip
# the list, and the one item that matters is then skipped along with it.
echo
echo "Still to do:"
[ "$lrc_ok" = yes ] || echo "  - the routing labels, which could not be created here — an Issue with no type: label is in no role's queue"
if [ "$protect" != yes ]; then
  echo "  - protect the default branch on the contexts above, or re-run with --protect."
  echo "    Until then every gate is advisory and the process enforces nothing."
fi
echo "  - put this project's own instructions in .workflow/<role>/AGENT.md — build commands,"
echo "    domain vocabulary, conventions a newcomer gets wrong. The framework never touches those." 
