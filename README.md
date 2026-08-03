# agent-dev-flow

**A development process run by agents, in your own repository, through GitHub.**

You state what you want. Agents file the Issues, build them, review each other, verify, merge and
release — each one finding its own work, none of them waiting to be told.

There is no coordinator. **Whose turn it is is a function of repository state**, so every role
computes its own queue and nobody schedules anybody.

---

## Install

```bash
cd your-repo
curl -fsSL https://raw.githubusercontent.com/VincentHanxiaoDu/agent-dev-flow/main/install.sh | bash -s -- . --protect
git add .github .workflow .gitignore && git commit -m "chore: install agent-dev-flow" && git push
```

`--protect` also configures branch protection and creates the labels the queues route on. It is
opt-in because it changes who can write to `main`.

The install **verifies itself** — it runs the checks in your repository and refuses to report success
if they fail. Writing files is not delivering a working process.

**Already installed once?** `/init-workflow` does all of the above in any repository. The installer
puts it in `~/.claude/commands/`.

### Then tell it about your project

```
/config-workflow
```

It reads the repository, asks you only what it could not establish — dev environment, the exact test
commands, front end, end-to-end, which build product does UAT against, what "done" means here — and
writes the answers to `.workflow/PROJECT.md`, which every role loads.

**Skipping this is expensive and quietly so.** Measured on a repository two days in: every
`AGENT.md` still read *"(empty — nothing project-specific yet)"*, so each role worked out the same
things separately, several times over.

### It will not overwrite your work

| | |
|---|---|
| `.workflow/bin/`, `.github/`, `.claude/commands/` | **the framework's.** Replaced on every install. |
| `.workflow/<role>/AGENT.md` | **yours.** Created once, never touched again. |
| `.workflow/<role>/MEMORY.md` | **the role's own.** What it has learned about your project. |
| `.workflow/PROJECT.md` | **yours.** Written by `/config-workflow`. |

Your project's build commands, domain vocabulary and local conventions go in `PROJECT.md`. If you
find yourself writing process rules there, the framework is missing something — change it there
instead.

**And an install now refuses rather than reverting you.** If you have changed a file under
`.workflow/bin/` — because your repository hit the bug first, which is the usual reason — the
installer stops and names the file instead of replacing it. Upstream the fix, then refresh;
`--force` overwrites and says it is doing so. A refresh once deleted a merged fix and left a live
fail-open on `main`.

---

## Run it

**One Claude Code window per role.** They coordinate through GitHub Issue and pull-request state, not
by messaging each other, so they all run at once.

| Window | Command | What it does |
|---|---|---|
| **product** | `/create-feature <spec>` | turns a specification into Issues with drivable criteria |
| | `/product-workflow` | UAT, merge, close, decide to release |
| **dev** | `/dev-workflow` | resolves Issues into reviewed branches |
| **qa** | `/qa-workflow` | verifies bugs and chores, merges, closes |
| *(any)* | `/config-workflow` | asks how this project is built, tested and accepted |
| *(sub-agent)* | `/review-pr <n>` | reviews a pull request its author cannot |
| **ops** | `/release-version <tag>` | tags and publishes what product called |

**You type each one once.** `/dev-workflow` and `/qa-workflow` start monitors and wake themselves
when work appears — a new Issue, a red gate, a review request, a merge. A role that finds five ready
Issues starts five sub-agents; there is no cap on width.

**Three windows is enough.** A pull request needs a review by an agent that authored none of its
commits, and the monitor routes that request to whoever qualifies — so qa reviews dev's work and vice
versa. A fourth window running `/review-pr` buys a second pair of eyes at the merge boundary, which
three windows do not have. The process says so out loud rather than pretending otherwise.

---

## What it enforces

Five checks, and the set is frozen. A sixth is a decision for whoever owns the project.

| Gate | |
|---|---|
| **Build and tests** | your `make ci`. **Tests present and no `ci` target is a failure**, not a pass. |
| **Branch name and commit convention** | `<role>/<type>/<issue>-<slug>`, subjects under 72 characters, an `Agent:` trailer, and **no closing keyword** — closing belongs to whoever verified the work. |
| **Tasks complete** | every OpenSpec task ticked, and on a spec-driven project a change openspec can actually archive. |
| **Generated files not hand-authored** | `openspec/specs/**` changes through archiving, not editing. |
| **Reviewed by an agent that authored none of its commits** | independence derived from the `Agent:` trailers — **except a commit that changes nothing outside `openspec/`**, which confers no authorship. Product must archive onto the branch before merging, and without that exemption it authors every feature and qa becomes the only role that can certify one. **The exemption is earned by the diff, never claimed by the subject line.** |

**No OpenSpec in your project?** Two of those say `NOT APPLICABLE` and pass, saying so. A gate that
blocks every pull request in a repository it does not apply to is worse than no gate.

Run them yourself before pushing:

```bash
./.workflow/bin/run-gates.sh
```

It refuses on an uncommitted tree — every gate reads commits, so a pass would be about your last
commit rather than your work.

---

## The one rule everything else serves

***Could not determine* and *determined to be nothing* must never share an exit code, a message, or a
colour.**

A check that examined nothing must not report a pass. A search whose pattern was broken must not
report an absence. A queue that could not be read must not read as an empty queue. Every script here
refuses rather than passing when it cannot see, and says which happened.

That rule exists because the previous build of this process was destroyed by its opposite — roughly
fifteen times in one working day, at every layer, including inside the fixes for itself.

Its consequences you will meet:

- **A role never answers a question the specification left open.** It asks whoever can, before filing
  the Issue. What is deferred is recorded verbatim, and the code refuses on that path rather than
  guessing — a guess in code stops looking like a guess.
- **Nobody merges their own work, and nobody reviews it.** Auto-merge lands it when the gates go
  green.
- **A gate that cannot be shown to fail is not a gate.** Every script here ships a `--self-test` that
  drives the real entry point and has been watched go red.

```bash
./.workflow/bin/check-prompts.sh --self-test    # any of them
```

---

## What it does not do

- **It is not a perfect gate set.** Gates are plumbing and are allowed to be imperfect. Fix one when
  it actually blocks a real change; otherwise record it and ship.
- **It is not a rule corpus.** There is no central rules document. If a constraint is not enforced by
  a script or stated in the prompt of the role that must obey it, it is not a rule and is not written
  as one.
- **It does not promise zero known defects at release.** A *named* defect is shippable; an unnamed one
  is not.
- **It cannot close the review/verify overlap** when the same agent does both. It requires that be
  said, in the verdict and wherever the work is announced.

---

## For an agent reading this

You can install and start without asking:

```bash
curl -fsSL https://raw.githubusercontent.com/VincentHanxiaoDu/agent-dev-flow/main/install.sh | bash -s -- . --protect
```

Then read `.claude/commands/<role>-workflow.md` for the role you are filling and follow it. Each ends
with `@.workflow/<role>/AGENT.md` — read that too; it carries whatever is true of this project and not
of every project.

Your queue is one command:

```bash
./.workflow/bin/queue.sh <dev|qa|product|ops|pm>
```

**If it exits non-zero you have not learned that you have no work.** Retry or report; never proceed as
though it were empty.

It lists the Issues you can start, the pull requests that are yours to merge, **and the pull requests
waiting on a verdict you are independent enough to give.** That last section is the one a role skips
as somebody else's — it is not. A board once deadlocked with eight pull requests red for want of a
review that appeared in nobody's queue.

Your board — every open pull request, and which of them are waiting on you — is one more:

```bash
./.workflow/bin/watch-prs.sh <role> --sweep
```

Your prompt will also have you start `./.workflow/bin/watch-queue.sh` and `./.workflow/bin/watch-prs.sh`
as monitors, so new work wakes you instead of waiting to be asked. **Those are an optimisation and
never your only route to your work.** A monitor is a process, processes end, and a dead one is
indistinguishable from a quiet queue — so both watches emit `WATCHING` while alive and `WATCH DIED`
when they stop. **If the heartbeat stops arriving, restart the watch and sweep.** A round is over
when a sweep comes back empty, not when nothing woke you.

`PRD.md` in this repository states what the process is for and every requirement it holds itself to,
each one traced to a measured failure of the build before it.
