# agent-dev-flow — PRD

A development process run entirely by agents. The process is the product; a host project is only
its proving ground.

This document is written **before** any code. Everything in it is a requirement, not a suggestion,
and every requirement here exists because the previous attempt failed it.

---

## 1. What went wrong last time

The previous build worked at the level of a single Issue — routing, review, verification and
closure all functioned, and reviewers found real defects in every round. It failed at the level of
the **system**, and the failures were these five. Every requirement below traces to one of them.

| # | Failure | Measured |
|---|---|---|
| **F1** | **The process audited itself instead of shipping.** Gates are code; reviewing gate code finds gate defects; fixing those spawns more. No bound. | 82 open Issues: **50 about the machinery, 9 about the product** |
| **F2** | **Backlog grew while reports said progress.** Every "N PRs merged" was true; the total rose anyway. | one day: **38 opened, 24 closed, net +14** |
| **F3** | **Only one role's prompt knew how to fan out.** `dev` had swarm instructions; `qa`, `product`, `ops` did not, so they worked one Issue at a time forever. | 3 of 4 role prompts had no parallelism |
| **F4** | **The coordinator was the scheduler.** It hand-wrote a prompt per dispatch and waited for each reply, so throughput was one agent-round at a time regardless of how many Issues were ready. | ~40 hand-written dispatches in a day |
| **F5** | **Rules described enforcement that did not exist.** `rules.md` grew to ~152 lines of prose asserting properties no script checked, and merged with no independent reader. | closure authority: 0 of 19 scripts enforced it |

**The unifying defect:** *could not see* rendering as *nothing to see* — a check that examined
nothing reporting a pass, a search whose pattern was broken returning zero, a count over milestoned
Issues blind to unmilestoned ones. It appeared at least fifteen times in one day, at every layer,
including inside the fixes for itself.

---

## 2. What this is for

**An owner states what they want. Agents deliver it, closed-loop, without the owner scheduling
anything.** The owner answers questions about *what* and *whether to release*. Everything
else — architecture, priority, sequencing, implementation — belongs to the roles.

Success is **shipped product**, not a clean process. A process with zero defects and no release has
failed.

---

## 3. Requirements

### R1 — Parallelism lives inside each role, not in the coordinator

**Every role prompt must instruct that role to pull its whole queue and fan out across it.** One
message to a role starts a swarm, not a single item.

- Each role prompt begins: *get your queue, then work every independent item in it concurrently.*
- The coordinator sends **one** message per role per round. It does not enumerate Issues, assign
  them, or wait between them.
- A role that finds five ready Issues starts five sub-agents. **No cap on width.**
- Items that touch the same file are the only ones that serialise.

> *F3, F4.* Last time only `dev` had this and the coordinator became the scheduler for everyone else.

### R2 — Prompts are fixed artefacts, never composed per dispatch

**A role's instructions live in its definition file and nowhere else.** The coordinator may pass a
focus argument; it may not pass method, standards, or procedure.

- Role prompts are checked-in files (`.claude/agents/` or `.claude/commands/`).
- A dispatch is at most: *work your queue* + optional focus.
- **If the coordinator finds itself explaining how to do the work, that text belongs in the role
  prompt.** Anything explained twice in messages is a missing line in a file.

> *F4.* Hand-written prompts drift between dispatches, cannot be reviewed, and make the coordinator
> a dependency of every unit of work.

### R3 — Whose turn it is, is derivable — never asserted

An agent must be able to compute its own queue from repository state alone. No role may depend on
being told.

- Queue = a query over Issue/PR state. One command, one answer.
- **No `owner:*` label**, no assignment message, no coordinator-maintained list. State is stored
  once.
- The board's Status is a *rendering* of that state, not a second source of it.

### R4 — Closure authority is enforced by the prompt that does the closing

The rule is **not** "only the verifier may close" stated in a document. An agent cannot evaluate
that — it has no way to know who the verifier is.

**Instead: each role's own prompt tells it what it closes.**

| Role | Its prompt says |
|---|---|
| **qa** | take pinned open bugs/chores → test → merge → **close them** |
| **product** | take pinned open features → UAT → archive → merge → **close them** |
| **dev** | resolve → open a PR → **close nothing** |
| **ops** | tag and deploy when product calls it → **close nothing** |

The routing *is* the four prompts. There is no fifth document restating it, and no gate that
re-derives it.

> *F5.* Last time a rules file asserted an enforced rule, the script that enforced it was deleted,
> and nothing noticed for hours.

### R5 — A gate must be able to fail, and must refuse rather than pass when it cannot see

Every check ships with a self-test that **drives the real entry point** and proves the check goes
red on the defect it exists for.

- A self-test that asserts a hand-written copy of the logic is not a self-test.
- **Unreadable input, a missing argument, an unresolvable base, a broken search pattern, an
  exhausted API quota → refuse (non-zero), never pass.**
- *Could not determine* and *determined to be nothing* are different values and must never share an
  exit code or a message.

> *The unifying defect.* This is the single most-paid-for rule in the previous build.

### R6 — The gate set is small, fixed, and frozen

**Five checks maximum**, decided once, at the start:

1. Build and tests pass
2. Branch and commit convention
3. Tasks complete / change archived
4. Generated files not hand-authored
5. Reviewed by an agent that authored none of its commits

**Adding a sixth requires the owner.** A defect in a gate is fixed only when it actually blocks a
real product change; otherwise it is recorded and deferred.

> *F1.* Unbounded gate work is what consumed the last build. The gates are plumbing; they are
> allowed to be imperfect.

### R7 — Machinery work is capped against product work

**A hard ratio: at most one machinery Issue in progress per product Issue in progress.**

- Every Issue is `area:product` or `area:machinery` at filing. No third value, no unlabelled.
- Reviews may *record* any number of findings; **a review may open at most one new Issue.** The
  rest go into one rolling debt Issue.
- The coordinator reports the ratio every round and stops dispatching machinery work when it is
  exceeded.

> *F1.* 50 machinery Issues to 9 product Issues is the failure this makes impossible.

### R8 — Every report to the owner is net, not gross

A status message states, in this order:

1. **opened vs closed** for the period, and the direction of the total
2. what shipped that a user could observe
3. what is blocked and on whom

**"N PRs merged" alone is prohibited.** Throughput is not progress when reviewing a fix generates
new findings.

> *F2.* Every individual report was true and the aggregate picture was the opposite.

### R9 — The owner is asked about *what* and *whether to ship*, never about *how*

- Escalate: requirements, scope, release decisions, and **any change to the process itself**.
- Do not escalate: architecture, priority, sequencing, implementation, tool choice.
- Every escalation is a structured question with concrete options and a stated recommendation.
- **Owner rulings are recorded verbatim, with the original wording, at the point of decision.** An
  agent may not act on its own reading of a ruling — if the reading is load-bearing, ask.

> Last time the coordinator moved five Issues out of a milestone on its own reading of a ruling, and
> it took two roles to catch it.

### R10 — No document states a rule that no mechanism enforces

- A constraint is either **enforced by a script or by a role prompt**, or it is not a rule and is
  not written as one.
- Prose about *how to work* belongs in the role prompt that does that work.
- **There is no central rules file.** The previous one reached 152 lines and merged unread because
  everyone qualified to review it was a source for it.

> *F5.*

### R11 — Every state reaches a terminal state

- Statuses are enumerated once, in one file, and every one is reachable and leaves.
- **No orphan states.** A self-test asserts every status is both entered and left by some
  transition.
- Anything that stalls surfaces in the coordinator's round report by name, with what it waits on.

---

## 4. The loop

```
owner states what they want
        │
        ▼
  product  ──── writes the Issue, area: label, acceptance criteria
        │
        ▼
  dev      ──── pulls its whole queue, swarms, one branch per Issue, opens PRs
        │
        ▼
  review   ──── an agent that authored none of the commits
        │
        ├── bug/chore ──▶ qa      : verify → merge → CLOSE
        └── feature   ──▶ product : UAT → archive → merge → CLOSE
                              │
                              ▼
                        product decides to release
                              │
                              ▼
                        ops tags and deploys
```

**One Issue, one branch, one merge, one owner at a time.** Whose turn it is is a function of state.

---

## 5. Acceptance — how we know this one worked

The build is accepted when, **without the owner scheduling anything**:

1. An Issue filed by the owner or by product routes to the right role and reaches `closed`.
2. **A release is tagged.** A process that never ships has failed regardless of its defect count.
3. Over a full working session, **closed ≥ opened**. The backlog does not grow.
4. **Product Issues outnumber machinery Issues** in the open set.
5. Each role, given one message, works its entire queue in parallel — verifiable from the
   coordinator having sent one message per role that round.
6. Every gate has a self-test that has been shown to go red.

**Criterion 2 and criterion 3 are the ones the previous build failed.** They are not negotiable and
they are not satisfied by a clean board.

---

## 6. Explicit non-goals

- **Not** a perfect gate set. Gates are plumbing.
- **Not** a complete rule corpus. If it is not enforced, it is not written.
- **Not** zero known defects at release. A *named* defect is shippable; an unnamed one is not.
- **Not** a coordinator that understands the work. It routes, reports net numbers, and escalates.

---

## 7. Open questions for the owner

These are answered before implementation starts, not during.

1. **The proving-ground project** — rebuild `oh-my-workspace` from its PRD, or a smaller one first?
   The previous host had 5,864 files and 233 Issues; a smaller target reaches criterion 2 sooner.
2. **Release cadence** — tag on every product Issue closed, or on a milestone?
3. **R7's ratio** — is 1:1 right, or should machinery work be blocked entirely until the first
   release is tagged?
