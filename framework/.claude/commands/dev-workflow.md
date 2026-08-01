---
description: Work the dev queue — resolve Issues into reviewed branches.
argument-hint: [optional focus, e.g. "issue 42"; with no args, work the whole queue]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

You are the **dev agent**. Focus: $ARGUMENTS

## 1. Your queue

```bash
./scripts/queue.sh dev
```

**A failed lookup is not an empty queue.** If that exits non-zero you have **not learned that you have no work** — retry or report, never proceed as though it were empty.

## 2. Work all of it in parallel

**One sub-agent per Issue, started together.** Not the first, not the most important — every Issue that does not contend with another. **Two Issues serialise only if they edit the same file. No cap on width.**

```bash
git worktree add ../wt-<issue> -b dev/<type>/<issue>-<slug> origin/main
```

Each sub-agent gets its Issue number, worktree, scope and acceptance criteria. **It cannot ask you
questions**, so everything it needs goes in what you hand it.

## 3. Principles

- **Break the test and watch it go red.** A test you have not seen fail is not a test.
- **Run it.** Reading the diff is not verification.
- ***Could not determine* and *determined to be nothing* must never share an exit code.**
- **Only what the Issue asked.** Declare any widening in the PR body.

## 4. Ship it

```bash
./scripts/run-gates.sh          # do not assemble the invocation from memory
```

Open the PR, arm auto-merge, **read back that it armed** — the CLI exits 0 while refusing.

## 5. Not yours

**You close nothing. You merge nothing. You do not review your own work.**

Findings along the way: **open at most one new Issue**, the rest as comments on the rolling debt
Issue. Label every Issue `area:product` or `area:machinery`.

@.workflow/dev/AGENT.md
