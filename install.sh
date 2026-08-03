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
force=no
args=()
for a in "$@"; do
  case "$a" in
    --protect) protect=yes ;;
    # OVERWRITE A FILE THIS REPOSITORY HAS CHANGED. Opt-in for the same reason --protect is: it
    # destroys work, and the refusal below exists because it did.
    --force) force=yes ;;
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

# THE FRAMEWORK'S SCRIPTS LIVE UNDER `.workflow/bin/`, NOT IN A TOP-LEVEL `scripts/`. A project with
# its own `scripts/` had a same-named file silently replaced — measured: a project's `queue.sh` was
# overwritten by the framework's, and `scripts/` is one of the most common directory names there is.
# `.workflow/` now holds both halves with the seam between them: `bin/` is the framework's and is
# replaced, `<role>/AGENT.md` is the project's and is never touched.
#
# .github IS IN THE MANIFEST, and it was not. The workflow that produces every required context
# was therefore never installed: the gates existed as scripts nothing ran, and the install then
# refused to print a context list because it could not find the file it had not copied. The refusal
# was right and it is how this was found.
# `.workflow/review-policy` IS THE PROJECT'S AND IS NEVER WRITTEN HERE. It decides whether an author
# may certify its own work, which is a policy decision belonging to whoever owns the repository — and
# a refresh that silently reverted it would restore a rule the owner had deliberately relaxed, in the
# one place where a silent revert is least acceptable. Same seam as `.workflow/<role>/AGENT.md`.
manifest() { ( cd "$SRC" && find .claude .github .workflow/bin .workflow/adf -type f -not -path "*/__pycache__/*" -not -name "*.pyc" | sed 's#^\./##' ); }

# --- what would change -------------------------------------------------------
declare -a overwrites=() news=()
while IFS= read -r f; do
  if [ ! -f "$target/$f" ]; then news+=("$f")
  elif ! cmp -s "$SRC/$f" "$target/$f"; then overwrites+=("$f"); fi
done < <(manifest)

echo "agent-dev-flow -> $target"
[ ${#news[@]} -eq 0 ]       || { echo; echo "new (${#news[@]}):";       printf '  + %s\n' ${news[@]+"${news[@]}"}; }
[ ${#overwrites[@]} -eq 0 ] || { echo; echo "replaced (${#overwrites[@]}):"; printf '  ~ %s\n' ${overwrites[@]+"${overwrites[@]}"}; }

# --- A REFRESH MUST NOT SILENTLY REVERT A FIX THE TARGET REPOSITORY MADE ------
#
# THIS IS THE MOST EXPENSIVE DEFECT THIS INSTALLER HAS HAD, and it fired repeatedly. Measured:
#
#   - A refresh deleted a merged fix. `pr-authors.sh` went from 332 lines to 264 with all three
#     `return 3` sites gone, `queue.sh` lost its author-lookup fix entirely, four machinery tests
#     went red, and `main` carried a LIVE FAIL-OPEN for the time it took somebody to notice. The
#     reviewer of the original fix had written "a refresh that reintroduces either defect turns the
#     repo red" — and it did, within minutes.
#   - Measured again later, larger: the framework's own copies were 1,179 lines BEHIND the
#     repository running them. Every fail-open fixed downstream existed only downstream, and this
#     script would have replaced all of it without a word.
#
# The old behaviour printed `replaced (N)` and copied anyway. That line is true and it is not a
# control: it names files, not consequences, and it appears identically whether the target's copy is
# an old framework version or a fix somebody made this morning.
#
# THE TWO CASES ARE DISTINGUISHABLE, AND `.agent-dev-flow` IS WHAT DISTINGUISHES THEM. It records the
# framework sha this repository was last installed from. So:
#   - target's copy == that sha's copy  ->  the target never touched it. An ordinary upgrade. Silent.
#   - target's copy != that sha's copy  ->  the target CHANGED it. That change is the thing at risk,
#                                           and it is not this script's to discard.
#
# WITHOUT GIT — a curl install with no clone — the sha cannot be resolved, so the distinction cannot
# be made. It then refuses on ANY difference rather than guessing, which is the same rule this
# framework applies everywhere else: could not determine is not determined to be nothing.
declare -a modified=()
old_sha=""
[ -f "$target/.agent-dev-flow" ] && old_sha=$(sed -n 's/^sha=//p' "$target/.agent-dev-flow" | head -1)
# `${a[@]+"${a[@]}"}`, NOT `"${a[@]}"`. Under `set -u` bash 3.2 — which is what macOS ships — an
# EMPTY array expands to an unbound-variable error, so this died on the one path that matters most:
# a first install, where nothing is being overwritten at all. It printed the whole plan and then
# copied nothing, with a zero exit code.
for f in ${overwrites[@]+"${overwrites[@]}"}; do
  keep=yes
  if [ -n "$SELF_DIR" ] && [ -n "$old_sha" ] && [ "$old_sha" != unknown ] \
     && git -C "$SELF_DIR" cat-file -e "$old_sha" 2>/dev/null; then
    if git -C "$SELF_DIR" show "$old_sha:framework/$f" 2>/dev/null | cmp -s - "$target/$f"; then
      keep=no   # untouched since it was installed — an ordinary upgrade
    fi
  fi
  # AN `if`, NOT `[ ... ] && ...`. Under `set -e` a trailing false command makes the LOOP return
  # non-zero, and on the last iteration that ends the script — an installer that silently stops
  # having printed a plan it did not carry out.
  if [ "$keep" = yes ]; then modified+=("$f"); fi
done

if [ ${#modified[@]} -ne 0 ] && [ "$force" != yes ]; then
  echo
  echo "REFUSING TO INSTALL. ${#modified[@]} file(s) this repository has CHANGED would be replaced:"
  printf '  ! %s\n' ${modified[@]+"${modified[@]}"}
  echo
  echo "  These differ from the copy this repository was installed with, so the difference is work"
  echo "  done HERE — very likely a fix made because this repository hit the bug. Replacing it is a"
  echo "  silent revert, and it has produced a live fail-open on a protected branch before."
  echo
  echo "  See exactly what would be lost:"
  for f in ${modified[@]+"${modified[@]}"}; do echo "    diff \"$target/$f\" \"$SRC/$f\""; done
  echo
  echo "  UPSTREAM THE FIX FIRST — that is the only outcome where it survives the NEXT refresh too."
  echo "  Then re-run this. If you have already done that, or the change is genuinely disposable:"
  echo "    $0 $target --force"
  exit 1
fi
[ ${#modified[@]} -eq 0 ] || {
  echo
  echo "--force: REPLACING ${#modified[@]} file(s) this repository had changed. This is a revert:"
  printf '  ! %s\n' ${modified[@]+"${modified[@]}"}
}

# THE FRAMEWORK OWNS .claude/ AND OVERWRITES IT WITHOUT ASKING. That is safe only because a project
# never edits those files: everything project-specific goes in .workflow/<role>/AGENT.md, which this
# script creates once and never touches again. The previous build had no such seam, so a project's
# local additions lived in framework files and an upgrade silently deleted them.
while IFS= read -r f; do
  mkdir -p "$target/$(dirname "$f")"
  cp "$SRC/$f" "$target/$f"
done < <(manifest)
chmod +x "$target"/.workflow/bin/*.sh

# --- the project's own half, created once and then left alone ----------------
for role in dev qa product ops reviewer; do
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

**Run \`/config-workflow\` rather than filling this in by hand.** It reads the repository, asks the
owner what it could not establish, and writes the shared half into \`.workflow/PROJECT.md\`.

_(empty — nothing project-specific yet)_
EOF
  echo "  + .workflow/$role/AGENT.md"
done

# --- each role's own memory, created once and then left alone -----------------
# A ROLE THAT CANNOT REMEMBER REDISCOVERS THE SAME THING EVERY SESSION, AND SO DOES EVERY OTHER ROLE.
# Measured: a verifier spent a round establishing that the project's test runner caches results and
# needs a flag to re-run, and wrote it nowhere — so the finding died with the session. Multiply by
# three roles and every restart.
#
# SEPARATE FROM AGENT.md ON PURPOSE. AGENT.md is configuration, written by `/config-workflow` and by
# people; MEMORY.md is written by the role itself, mid-round. One file for both means an agent
# appending a note rewrites the configuration it was handed, which is the failure this seam exists
# to prevent — one level in from the seam between the framework and the project.
for role in dev qa product ops reviewer; do
  d="$target/.workflow/$role"
  [ -f "$d/MEMORY.md" ] && { echo "  = .workflow/$role/MEMORY.md (kept)"; continue; }
  cat > "$d/MEMORY.md" <<EOF
# What the $role role has learned about this project

**This file is yours, and the installer never overwrites it.** Write to it the moment you learn
something that cost you time and would cost the next round the same time — how this project actually
behaves, where the traps are, and what you tried that did not work.

Not here: work state (that is Issues and pull requests), decisions (those are \`[owner-ruling]\` on
the Issue), project configuration (that is \`.workflow/PROJECT.md\`), or how the process works.

Newest first. Date every entry.

**Correcting this file is the part that makes it safe to believe.** It is loaded at the top of every
round so you do not re-derive what is in it — so a false entry is one you act on confidently, and no
gate reads prose. The moment you find an entry is false, fix it or delete it, then continue; not at
the end of the round, because you are the only one who knows. When the wrongness is the lesson,
record what misled you as well as what is true.

_(empty — nothing learned yet)_
EOF
  echo "  + .workflow/$role/MEMORY.md"
done

# --- the shared, project-owned answer to "how is this thing built and tested" --
# WRITTEN BY `/config-workflow`, STUBBED HERE so that every role prompt's `@.workflow/PROJECT.md`
# resolves from the first session rather than reading as a missing file. A stub that says it is empty
# is an answer; a missing file is a role guessing.
if [ ! -f "$target/.workflow/PROJECT.md" ]; then
  cat > "$target/.workflow/PROJECT.md" <<'EOF'
# How this project is built, tested and accepted

**NOT CONFIGURED YET — run `/config-workflow`.**

Until it is, no role knows how to build this project, how to run its tests, what an end-to-end run
needs, or which build product accepts against. Every role will work that out separately, and they
will not all reach the same answer.

Nothing below this line is established. Do not treat an empty section as "there is nothing to do".
EOF
  echo "  + .workflow/PROJECT.md (stub — run /config-workflow)"
fi

# THE SHA IS RECORDED, NOT JUST THE BRANCH. I fixed the same defect in the framework three times
# and each time the repository under test still carried the old copy, because a manual refresh is a
# step that gets skipped and nothing said so. `ref=main` is true forever and answers nothing.
FW_SHA=$( { [ -n "$SELF_DIR" ] && git -C "$SELF_DIR" rev-parse HEAD 2>/dev/null; } \
          || gh api "repos/${REPO_URL#https://github.com/}/commits/$REF" --jq .sha 2>/dev/null \
          || echo unknown )
printf 'ref=%s\nsha=%s\n' "$REF" "$FW_SHA" > "$target/.agent-dev-flow"

# --- the bootstrap command, installed once at the USER level ------------------
# CHICKEN AND EGG: `/init-workflow` lives in `.claude/commands/`, which does not exist until this
# script has run. Installing it into the project only would make it useless for the one job it has.
# At the user level it is available in every repository, so the first setup is a curl and every one
# after it is a slash command.
#
# NEVER OVERWRITTEN. If a person has edited theirs, that edit is theirs to keep — this is the same
# seam as .workflow/, one level out.
USER_CMDS="${HOME}/.claude/commands"
if [ -f "$SRC/.claude/commands/init-workflow.md" ]; then
  mkdir -p "$USER_CMDS"
  if [ -f "$USER_CMDS/init-workflow.md" ]; then
    echo "  = ~/.claude/commands/init-workflow.md (kept)"
  else
    cp "$SRC/.claude/commands/init-workflow.md" "$USER_CMDS/init-workflow.md"
    echo "  + ~/.claude/commands/init-workflow.md — /init-workflow now works in any repository"
  fi
fi

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
( cd "$target" && ./.workflow/bin/check-prompts.sh ) || {
  echo "error: the installed commands do not satisfy the design. Files were written; a working" >&2
  echo "       process was not delivered. Fix the framework and re-run." >&2
  exit 1; }
( cd "$target" && ./.workflow/bin/queue.sh --self-test >/dev/null ) || {
  echo "error: queue.sh's self-test fails here. Refusing to report a successful install." >&2; exit 1; }

# READ FROM THE WORKFLOW'S OWN DECLARATION, not from its job names. Job names were the first
# source, and they are the WRONG source: a job's name and the context it publishes are different
# strings, so renaming one job protected `main` on "Review gate ran" — green whenever the job
# executes — while the verdict was required by nothing, and a pull request merged with its review
# red. check-contexts.sh proves every declared context is really produced.
#
# An earlier version restated the list by hand, and that copy named a context no job produced — anyone following those
# instructions would have protected `main` on a check that never arrives, and every pull request
# would have waited on it forever. A list that can drift from the thing it describes will.
CONTEXTS=$(sed -n '/# BEGIN REQUIRED CONTEXTS/,/# END REQUIRED CONTEXTS/p' "$target/.github/workflows/gates.yml" 2>/dev/null \
           | sed -n 's/^#   /       /p' || echo "")
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
      # ONLY A TRUE MERGE COMMIT, BECAUSE THAT IS WHAT THE NAMING GATE EXEMPTS. check-naming.sh
      # skips GitHub's own merge commit by PARENT COUNT — the only reliable signal — and judges
      # everything else. GitHub's squash and rebase buttons produce SINGLE-parent commits whose
      # message is composed by GitHub and carries no `Agent:` trailer, so the gate judges them and
      # the default branch goes red on a commit nobody wrote and nobody can amend. That happened:
      # two pull requests were squashed and `main`'s naming gate failed with "has no 'Agent:'
      # trailer" on GitHub's own commit. Turning the buttons off is the fix, because telling every
      # agent not to press them is not one.
      if gh api -X PATCH "repos/$SLUG" -F allow_squash_merge=false -F allow_rebase_merge=false \
           -F allow_merge_commit=true >/dev/null 2>&1; then
        echo "  merge method: merge commits only (squash and rebase disabled — the naming gate"
        echo "                exempts a merge commit by its two parents, and nothing else)"
      else
        echo "  ! could not disable squash/rebase merging. Merge with a MERGE COMMIT only:" >&2
        echo "    a squash or rebase merge writes a single-parent commit with no 'Agent:' trailer" >&2
        echo "    and reddens the default branch's naming gate." >&2
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
  /config-workflow        tell it how THIS project is built, tested and accepted — run this first
  /create-feature <what>  turn a description into Issues with testable criteria
  /release-version <tag>  tag and publish a release product has called

Run each in its own Claude Code session. They coordinate through GitHub Issue and PR state,
not by messaging each other — so they can all run at once.

COMMIT ONLY WHAT CI RUNS:

    git add .github .workflow && git commit -m "chore: install agent-dev-flow" && git push

  .github/ and .workflow/bin/   CI runs them from the repository, so they must be committed.
                                bin/ is the framework's half and is replaced every install.
  .workflow/<role>/AGENT.md     yours. Created once and never overwritten.
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
if [ ! -d "$target/openspec" ]; then
  echo "  - OPTIONAL: run 'openspec init --tools claude .' if you want spec-driven changes."
  echo "    Two gates read openspec/ and both pass, saying NOT APPLICABLE, while it is absent."
  echo "    With it, dev writes a change per Issue and product archives before the merge."
fi
echo "  - RUN /config-workflow. It reads this repository, asks you only what it could not work out"
echo "    — dev environment, the exact test commands, front end, end-to-end, which build product"
echo "    accepts against, what 'done' means here — and writes .workflow/PROJECT.md, which every"
echo "    role loads. Skip it and each role works the same things out separately, several times." 
