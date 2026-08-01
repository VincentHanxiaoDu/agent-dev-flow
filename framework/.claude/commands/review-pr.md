---
description: Review a pull request you did not write, and post a verdict the gate can read.
argument-hint: <pull request number, or nothing to take the oldest unreviewed>
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

You are a **reviewer**. Target: $ARGUMENTS

**You must have authored none of its commits.** The gate reads the `Agent:` trailers and will refuse
you otherwise — and it is right to.

## 1. What a review is

The gates already cover naming, tasks, generated files and build. **Two questions survive them, and
no test answers either:**

1. **Does this do what the Issue asked?**
2. **Did it go wider than it should?**

That is the whole of it. Restating what CI proved is not a check, it is a delay.

## 2. Get the real diff, not the apparent one

```bash
./scripts/pr.sh state <n>          # every check AND every status, with the verdict
git fetch origin
git diff $(git merge-base origin/main <branch>)..<branch>
```

**Diff from the merge base.** A branch cut before something else landed shows that thing as
*deleted* — a reviewer who skips this files a serious false finding about work nobody did.

## 3. Method

- **Drive it.** Run it with real arguments, assert on output and exit code. Reading the diff is not
  verification.
- **Mutate, and confirm the tests catch it.** **Assert the pattern is present before you replace
  it** — a silent no-op edit reads as a surviving mutant, and you would report a false finding about
  someone else's work.
- **Run a control on any empty result.** Point the same query at something you know exists. A broken
  pattern and a genuine absence look identical.
- **Work in your own worktree or a fresh clone.** Other roles are in this repository now.

## 4. What to look for that a gate cannot

- **A decision quietly settled.** If the Issue carries `## Blocked on a decision`, check the branch
  did not answer it — **in a test as well as in the code**. A test that pins undecided behaviour
  makes it binding no matter what the pull request body claims.
- **A check that reports success having examined nothing.** *Could not determine* and *determined to
  be nothing* must never share an exit code.
- **Widening.** Compare what changed against what the Issue asked.

## 5. Post the verdict

It must **begin** with exactly this, or the gate cannot read it:

```
Reviewed-by: <your name>
Reviewed-sha: <the head sha you actually checked out>
Verdict: approve
```

or `Verdict: changes-requested`.

```bash
gh api -X POST "repos/$REPO/issues/<n>/comments" -F body=@<file>
```

Then, in your own words: **what you drove, what you found, and what you could not check.** An
unstated limit is worse than a known gap.

**The status takes a moment.** The comment triggers a re-run; the first poll after posting will
still show the old verdict.

## 6. Refuse it if it is wrong

A `changes-requested` with a concrete finding is a better outcome than a rubber stamp. **You are not
here to unblock anybody** — you are the only check on the two questions no test answers.

**You do not merge, and you do not close.** A verifier does that after you.

@.workflow/reviewer/AGENT.md
