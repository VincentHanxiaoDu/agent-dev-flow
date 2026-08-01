---
description: Tag and publish a release that product has called.
argument-hint: <version, e.g. v0.1.0>
allowed-tools: Bash, Read, Glob, Grep
---

You are executing a release. Version: $ARGUMENTS

**Product decides whether and when.** Product may run this itself, or hand it to ops — the decision
and the execution are separate acts, not necessarily separate agents. **If nobody has decided, stop
and say so.**

## 1. Check the ground

```bash
./scripts/queue.sh ops
git fetch origin && git log origin/main --oneline | head
```

State **what is still open** and let product decide whether that blocks. Do not decide it yourself.

## 2. Find out what CI actually saw

```bash
REPO=$(git config --get remote.origin.url | sed -E 's#^(https://[^/]+/|git@[^:]+:)##; s#\.git$##')
SHA=$(git rev-parse origin/main)
gh api "repos/$REPO/commits/$SHA/check-runs" --jq '.check_runs[] | "\(.conclusion)  \(.name)"'
gh api "repos/$REPO/commits/$SHA/status"     --jq '.statuses[] | "\(.state)  \(.context)"'
```

**Report what those say, by name, in the notes.** A merge commit is a different commit from the
pull-request head that was checked — different parents, different tree — so a tag can sit on a sha
CI has never examined. That happened, and nobody would have noticed without looking: three runs
against the released commit all reported `skipped`.

**If nothing ran on this sha, the release notes say that.** It is a fact about the release, not a
reason not to cut it.

**A red on the target sha is your call, and it is the common case.** A machinery failure — a gate
about the process rather than the product — does not block a release; a failing product gate does.
Say which it was, by name, in the notes.

## 3. Write the notes from evidence

- **What a person can now do that they could not before.** In their words, not commit subjects.
- **Known limitations, named.** A named defect is shippable; an unnamed one is not. Read them off
  open Issues and reviews — do not compose them from memory.
- **What produced the greens.** If no CI ran, say that.

## 4. Choose the number, and say what it is

**A release whose main path refuses is marked as one.** Set `prerelease=true` and open the notes
with what it does *not* do. The risk is not that somebody is disappointed — it is that they read a
version number and assume.

```bash
gh api ... -F prerelease=true
```

**The number is yours.** `v0.0.x` for something you would not tell a stranger to install; `v0.x.y`
once its main path works.

## 5. Tag

```bash
# Notes go in a FILE. They contain newlines, backticks and `#`; inline, the shell mangles them.
gh api -X POST "repos/$REPO/releases" -f tag_name=$ARGUMENTS -f target_commitish=main \
  -f name="..." -F body=@notes.md
```

## 6. Verify, then report

**Fetch the release back and confirm it exists.** A create call that exits 0 is not proof.

Report the tag, the URL, and what a person can do with it.

@.workflow/ops/AGENT.md
