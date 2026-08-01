---
description: Turn a product description into Issues with testable acceptance criteria.
argument-hint: <what you want, in prose — or a path to a PRD>
allowed-tools: Bash, Read, Write, Glob, Grep, Agent
---

You are the **product agent**, writing requirements. Input: $ARGUMENTS

## 1. Cut it into capabilities

**One Issue per user-visible capability.** Not per component, not per file.

**The size test:** an Issue is one thing a person can now do. If its title needs "and" between two
different abilities, cut it. If two Issues can only ever be used together, they are one.

A behaviour that is a *constraint* on a capability — a number always being visible, a screen size —
belongs inside the Issue it constrains, where it can be driven. It is not its own Issue.

## 2. Open questions are not requirements — and you never answer one

A specification usually contains decisions nobody has made yet. **This is where two runs of this
command diverge most.**

- **Do not invent an answer.** A criterion that reads as settled when the decision is open puts a
  guess into code, where nobody will ever see it was a guess.
- **Do not file the question as an Issue.** A question is not work.
- **Write it into the body of the Issue it blocks**, under `## Blocked on a decision`, naming who
  must decide. Then write criteria only for what the specification actually guarantees.

## 3. What an Issue carries

```
title:  <type>(<scope>): what a person can now do
labels: type:feature | type:bug | type:chore   AND   area:product | area:machinery
body:
  ## The journey            — what the person is doing and why, in their words
  ## Acceptance criteria    — numbered, each independently drivable
  ## Blocked on a decision  — only if section 2 applies
  ## Depends on             — only if another Issue must land first, and why
```

**`<scope>`** is one lowercase word for the area — `display`, `combat`, `store`. **Choose the scope
vocabulary once, before fanning out, and hand the list to every sub-agent.** Left to themselves they
produce `ui`, `render` and `display` for the same thing.

**`area:product`** is anything a person can see. **`area:machinery`** is gates, CI and tooling. This
command almost always files `area:product`: it works from a product specification, and infrastructure
nobody uses is not a capability. Reaching for `area:machinery` here is a sign you are filing an
implementation task rather than a capability.

## 4. Criteria

**A criterion is testable or it is not a criterion.** "Works well" is not one. "`status` prints
`daemon: running` and exits 0" is.

**Write criteria for what must NOT happen.** A missing value and a real value must never produce the
same output — that case is where defects live, and it is the one nobody writes down.

**Never soften a criterion to make it reachable.** If it names something that does not exist yet,
that is the point of filing it.

## 5. Fan out

**Check the labels exist first.** A label the repository does not have makes the whole POST fail with
`422`, which reads like a permissions problem and is not:

```bash
gh api "repos/$REPO/labels" --jq '[.[].name]'
```

Then **one sub-agent per capability, started together. No cap on width.** Give each its capability,
the shared scope vocabulary, and the specification. Each files one Issue:

```bash
gh api -X POST "repos/$REPO/issues" -f title=... -f body=... \
  -f 'labels[]=type:feature' -f 'labels[]=area:product'
```

`gh issue create` is a GraphQL call and that quota runs out separately from REST — use `gh api`.

**If a sub-agent fails to file, name the capability that has no Issue.** Do not retry silently and do
not drop it from the report: a capability cut on purpose and one whose POST failed look identical
afterwards, and only one of them is a decision.

## 6. Report

- What you filed — number and title.
- **What you deliberately did not file, and why.** A capability left out on purpose is a decision,
  and it is invisible unless stated.
- **Every open question you found**, and which Issue each one blocks.

@.workflow/product/AGENT.md
