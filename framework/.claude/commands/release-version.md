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
./.workflow/bin/queue.sh ops
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

**A `skipped` check is not a pass.** Find out why it was skipped and say so by name — the review
gate is skipped on a push by design, and a gate that never ran because something broke looks
identical from the list.

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

**The two are independent axes** — the number says how finished it is, the flag says whether to
trust it yet. `v0.1.0-rc.1` with `prerelease=true` is a coherent answer, not a hedge.

## 5. Tag

```bash
# Notes go in a FILE. They contain newlines, backticks and `#`; inline, the shell mangles them.
gh api -X POST "repos/$REPO/releases" -f tag_name=$ARGUMENTS -f target_commitish=main \
  -f name="..." -F body=@notes.md
```

## 6. Verify, then report

**Fetch the release back and confirm it exists.** A create call that exits 0 is not proof.

Report the tag, the URL, and what a person can do with it.


## Sign every comment you post

**Every comment you post on an Issue or a pull request starts with `[ops]` on its own first line**,
before anything else — no bold, no heading, nothing above it.

That marker is not decoration and it is not a signature at the bottom. **`queue.sh` reads it**, with
`startswith("[<role>]")`, to work out what you have already looked at and stop offering it to you
again. A comment signed any other way — a trailing `Agent: ops`, a `[ops-agent]`, a name in prose —
is invisible to it, and the queue then tells the next agent to redo a round that is already done.

Measured on a live board: **100 comments, and `[dev]` appeared zero times**, because this rule was
stated in two of the role prompts and not in the rest. Nothing dev had said on any Issue was
attributable, and none of it could be seen by the queue.

**A review verdict carries both.** The `[ops]` marker on the first line, and the
`Reviewed-by:` / `Reviewed-sha:` / `Verdict:` block the gate parses. They answer different questions
— who is speaking, and what the verdict is — and neither substitutes for the other.

@.workflow/ops/AGENT.md
