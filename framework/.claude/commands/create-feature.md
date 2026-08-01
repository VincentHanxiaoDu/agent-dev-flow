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
```

**Dependencies are the parent's second pass, not a sub-agent's section.** Filing simultaneously means
no sub-agent knows another's number, so it cannot name one. Add them by comment once every Issue
exists, or leave them out.

**`<scope>`** is one lowercase word for the area — `display`, `combat`, `store`. **Choose the vocabulary
once, before fanning out, and hand the list to every sub-agent** — left to themselves they produce
`ui`, `render` and `display` for the same thing. **For a small tool one shared scope for everything is
the right answer**, not a failure to distinguish.

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

**Three things first, in this order:**

```bash
REPO=$(git config --get remote.origin.url | sed -E 's#^(https://[^/]+/|git@[^:]+:)##; s#\.git$##')
gh api "repos/$REPO/labels" --jq '[.[].name]'            # a missing label 422s the whole POST
gh api "repos/$REPO/issues?state=open" --jq '.[].title'   # what is already filed
```

**Skip a capability that already has an Issue.** Run twice on one specification, this files the whole
set again — and a duplicate board is harder to clean than it was to create.

Then **one sub-agent per capability, started together. No cap on width.** Give each its capability,
the shared scope vocabulary, and the specification. **Tell each to return its Issue number and every
open question it recorded** — you cannot report on a body you did not write.

```bash
gh api -X POST "repos/$REPO/issues" -f title="$TITLE" -f body="$(cat body.md)" \
  -f 'labels[]=type:feature' -f 'labels[]=area:product'
```

**Write the body to a file first.** Every body here is multi-paragraph markdown with backticks and
`$`; inline, the shell mangles it.

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
