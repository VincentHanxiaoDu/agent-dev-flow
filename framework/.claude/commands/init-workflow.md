---
description: Install agent-dev-flow into this repository, protect the default branch, and commit what CI needs.
argument-hint: [--no-protect to skip branch protection]
allowed-tools: Bash, Read, Glob, Grep
---

Set this repository up to run agent-dev-flow. Options: $ARGUMENTS

## 1. Check the ground first, and refuse rather than half-install

```bash
git rev-parse --git-dir >/dev/null 2>&1 || echo "NOT A GIT REPOSITORY"
git config --get remote.origin.url || echo "NO ORIGIN REMOTE"
git status --porcelain | head
```

**No git repository, or no `origin`:** stop and say so. The labels and branch protection both need
to know which repository this is, and an install that silently skips them leaves a process that
routes nothing.

**Uncommitted changes already present:** say what they are before you add to them. The person should
know what is theirs and what this command wrote.

## 2. Install

```bash
curl -fsSL https://raw.githubusercontent.com/VincentHanxiaoDu/agent-dev-flow/main/install.sh | bash -s -- . --protect
```

Pass `--protect` unless `$ARGUMENTS` contains `--no-protect`.

**Read the output.** The installer creates the routing labels, configures branch protection on
exactly the contexts its workflow produces, and verifies both by reading them back. **If it reports
a label it could not create, or a policy that read back wrong, say so plainly** — the install
"succeeding" while routing cannot work is the failure this whole process exists to remove.

## 3. Commit only what CI runs

```bash
git add .github scripts .workflow .gitignore
git commit -m "chore: install agent-dev-flow

Agent: pm"
git push
```

- **`.github/` and `scripts/`** — GitHub Actions runs these from the repository, so they must be in it.
- **`.workflow/`** — the project's own instructions. Committed so a teammate gets them.
- **`.claude/commands/`** — deliberately *not* committed; the installer gitignores it. It is read by
  a Claude Code session and by no job, and re-running the installer recreates it anywhere.

**Do not `git add -A`.** It would sweep in whatever else is uncommitted and attribute it to this.

## 4. Confirm it is real, by asking GitHub rather than trusting the exit codes

```bash
R=$(git config --get remote.origin.url | sed -E 's#^(https://[^/]+/|git@[^:]+:)##; s#\.git$##')
gh api "repos/$R/labels" --jq '[.[].name] | map(select(startswith("type:") or startswith("area:")))'
gh api "repos/$R/branches/$(git symbolic-ref --short HEAD)/protection" --jq '.required_status_checks.contexts' 2>/dev/null || echo "NOT PROTECTED"
./scripts/queue.sh pm
```

**Five labels, five contexts, and a queue that answers.** Anything less, report it as a number — not
as "mostly fine".

If protection reads back `NOT PROTECTED`, that is usually an admin-permission or repository-plan
limitation rather than a bug. Say which you think it is, and say that **until it is set, every gate
is advisory and a red check stops nothing.**

## 5. Then tell the person what to do next

```
/create-feature <a PRD path, or what you want in prose>     turn it into Issues
/dev-workflow          in its own session — resolve Issues into reviewed branches
/qa-workflow           in its own session — verify bugs and chores, merge, close
/product-workflow      in its own session — UAT features, close, decide to release
```

Each pulls its own queue and fans out; they coordinate through GitHub state rather than by messaging
each other, so they all run at once.

**One thing this command cannot do for them:** `.workflow/<role>/AGENT.md` is created empty. It is
where this project's build commands, domain vocabulary and local conventions go — and it is the one
file the installer never overwrites. Say so, and say it is optional to start.
