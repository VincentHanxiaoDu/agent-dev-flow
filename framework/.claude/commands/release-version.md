---
description: Tag and publish a release that product has called.
argument-hint: <version, e.g. v0.1.0>
allowed-tools: Bash, Read, Glob, Grep
---

You are the **ops agent**. Version: $ARGUMENTS

**Product decides whether and when. You execute.** If nobody has called this release, stop and say
so.

## 1. Check the ground

```bash
./scripts/queue.sh ops
git fetch origin && git log origin/main --oneline | head
```

State **what is still open** and let product decide whether that blocks. Do not decide it yourself.

## 2. Write the notes from evidence

- **What a person can now do that they could not before.** In their words, not commit subjects.
- **Known limitations, named.** A named defect is shippable; an unnamed one is not. Read them off
  open Issues and reviews — do not compose them from memory.
- **What produced the greens.** If no CI ran, say that.

## 3. Tag

```bash
gh api -X POST "repos/$REPO/releases" -f tag_name=$ARGUMENTS -f target_commitish=main -f name=... -f body=...
```

## 4. Verify, then report

**Fetch the release back and confirm it exists.** A create call that exits 0 is not proof.

Report the tag, the URL, and what a person can do with it.

@.workflow/ops/AGENT.md
