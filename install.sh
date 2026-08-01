#!/usr/bin/env bash
# Install agent-dev-flow into a repository.
#
#   curl -fsSL https://raw.githubusercontent.com/VincentHanxiaoDu/agent-dev-flow/main/install.sh | bash
#
# or, from a clone:   ./install.sh [target-repo]
set -euo pipefail

REPO_URL=${ADF_REPO:-https://github.com/VincentHanxiaoDu/agent-dev-flow}
REF=${ADF_REF:-main}
target=${1:-$PWD}

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

manifest() { ( cd "$SRC" && find .claude scripts -type f | sed 's#^\./##' ); }

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

# --- verify, rather than assume the copy was faithful ------------------------
echo
( cd "$target" && ./scripts/check-prompts.sh ) || {
  echo "error: the installed commands do not satisfy the design. Files were written; a working" >&2
  echo "       process was not delivered. Fix the framework and re-run." >&2
  exit 1; }
( cd "$target" && ./scripts/queue.sh --self-test >/dev/null ) || {
  echo "error: queue.sh's self-test fails here. Refusing to report a successful install." >&2; exit 1; }

cat <<'EOF'

Installed and verified.

  /dev-workflow           resolve Issues into reviewed branches
  /qa-workflow            verify bugs and chores, merge, close
  /product-workflow       UAT features, close, decide to release
  /create-feature <what>  turn a description into Issues with testable criteria
  /release-version <tag>  tag and publish a release product has called

Run each in its own Claude Code session. They coordinate through GitHub Issue and PR state,
not by messaging each other — so they can all run at once.

Still to do, and this script cannot do it for you:

  1. Labels the queue reads:  type:feature  type:bug  type:chore
                              area:product  area:machinery
  2. Protect `main`, requiring these five contexts. Until then every gate is advisory:
       Build and tests
       Branch and commit convention
       Tasks complete
       Generated files not hand-authored
       Reviewed by an agent that authored none of its commits
     The set is frozen at five. A sixth is a decision for whoever owns the project.
  3. Put this project's own instructions in .workflow/<role>/AGENT.md — build commands,
     domain vocabulary, conventions. The framework half never touches those files.
EOF
