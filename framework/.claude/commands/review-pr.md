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
REPO=$(git config --get remote.origin.url | sed -E 's#^(https://[^/]+/|git@[^:]+:)##; s#\.git$##')
gh api "repos/$REPO/pulls/<n>"                     # body, head sha, branch — the Issue is in `Closes #N`
gh api "repos/$REPO/issues/<n>/comments"           # prior reviews and the author's replies
./scripts/pr.sh state <n>                          # every check AND every status, with the verdict
```

**Establish your own independence before anything else** — the gate will refuse you, but finding
out from a red status wastes the whole review:

```bash
git log --format='%b' $(git merge-base origin/main <branch>)..<branch> | grep '^Agent:'
```

**Diff from the merge base, not the tip:**

```bash
git diff origin/main..<branch>                                   # WRONG
git diff $(git merge-base origin/main <branch>)..<branch>        # right
```

The wrong one is the one that comes naturally, and on a branch cut before something else landed it
shows that thing as **deleted** — a serious false finding about work nobody did.

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
- **And the inverse: a settled criterion left unpinned.** On a branch that mostly refuses, the
  blocked path and the working path can satisfy the same assertions — both non-zero, both empty on
  stdout — so the criterion the branch exists for is untested and deleting it changes nothing.
  **Mutate the settled behaviour away and see whether anything goes red.** This is the dominant
  failure mode on such a branch, and it is not the pinning one.
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

**An issue comment, not a GitHub review.** The gate reads issue comments; a formal review posted
through the reviews API is invisible to it and you get a red with no explanation.

**Your `Reviewed-by:` name shares a namespace with the `Agent:` trailers.** The gate compares them
literally, so a name matching one of the authors refuses you.

Then, in your own words: **what you drove, what you found, and what you could not check.** An
unstated limit is worse than a known gap.

**Then poll until the status reflects your verdict.** The comment triggers a re-run and the first
poll still shows the old one.

- **approve** → the status must go green. A reviewer that posts and leaves has left it looking red.
- **changes-requested** → the status stays red, and the description must say *changes requested*.
  If it still says *no current review*, **your comment was not parsed** — check the header block.

## 6. If it is stacked on another pull request

**Verify the shared commit by sha, not by diff** — `git rev-parse <parent-branch>@{u}` against the
commit in this branch. "Byte-identical, will fast-forward" is a claim like any other.

**Review the delta and say so.** The merge base is still `main`, so the diff carries the parent's
work; narrowing to the delta is legitimate, and stating that you did is what makes it legitimate.

**Nobody reviews the combination.** Each gate certifies one head against `main`. If the merged
behaviour is where an interaction would sit, say so — the verifier is the only one who can drive it.

## 7. If this is a re-review

**Read the prior review and the author's reply, then verify the earlier finding yourself.** A fix
note is a claim. Unaddressed items from the previous reviewer carry forward unless you have checked
them.

## 8. Refuse it if it is wrong

A `changes-requested` **with a stated remedy** is a better outcome than a rubber stamp — a finding
that names the fix is one commit away from closed; one that only names the problem is a negotiation.

**A concern that is neither blocking nor nothing goes in the prose**, named as accepted. The verdict
is binary and most findings are not. **You are not
here to unblock anybody** — you are the only check on the two questions no test answers.

**You do not merge, and you do not close.** A verifier does that after you.

@.workflow/reviewer/AGENT.md
