---
description: Ask the owner how this project is built, tested and accepted, and write it where every role reads it.
argument-hint: [optional area to (re)configure, e.g. "e2e" or "environments"]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
---

You are configuring **this project's half** of the process. Focus: $ARGUMENTS

## Why this exists

The framework knows how a process works. It knows nothing about **this** repository: how it is built,
how its tests are run, whether there is a front end, what an end-to-end run needs, which environment
product does UAT against, and what "done" means here.

**Measured, on a repository that had been running for two days:** every `.workflow/<role>/AGENT.md`
still read *"(empty — nothing project-specific yet)"*. So each role rediscovered the same things by
trial and error, in parallel, several times over — one of them spent a round establishing that its
test runner caches results and needs a flag to re-run, and wrote it nowhere. **Anything a role has to
work out for itself, every role works out for itself, every session.**

This command asks once and writes it where every role reads it.

## 1. Look before you ask

**Do not ask the owner what you can read.** A question whose answer is in the repository spends their
attention on something you were capable of establishing, and it makes the rest of your questions
cheaper to trust.

Establish, quietly, before the first question:

```bash
ls; git ls-files | head -100
```

- **Stack and build**: `Makefile`, `package.json` (and its `scripts`), `go.mod`, `pyproject.toml`,
  `Cargo.toml`, `pom.xml`, `build.gradle`, `*.csproj`, `mix.exs`.
- **Containers**: `Dockerfile`, `docker-compose*.y*ml`, `.devcontainer/`, `k8s/`, `helm/`.
- **Tests**: test directories and naming; the runner implied by the stack; whether a coverage
  threshold is configured anywhere.
- **Front end**: a `src/` with a framework dependency, a dev server script, a component test setup.
- **End-to-end**: `playwright.config.*`, `cypress.config.*`, `e2e/`, `tests/e2e/`, a compose file
  that stands up more than one service.
- **Environments**: `.env.example`, `config/*.y*ml` per environment, a `staging`/`preview` mention in
  CI, deploy workflows under `.github/workflows/`.
- **CI**: what `.github/workflows/*.yml` actually runs — that is the real bar, whatever anyone says.

**Then drive the one thing you are least sure of.** If you believe `make test` is the command, run
it. A configuration written from a guess is worse than none: every role will trust it.

## 2. Ask what you could not establish

**`AskUserQuestion`, batched — not one question at a time.** Every option carries what it costs.
**Lead with what you found**, so the owner is confirming rather than composing:

> "This looks like a Go module with `make ci` running build, vet and test, and a `docker-compose.yml`
> standing up Postgres. There is no e2e directory and no front end I can find."

Cover these, and **skip any the repository already answers unambiguously**:

| Area | What you need out of it |
|---|---|
| **Dev environment** | How a role gets a working tree it can run: bare toolchain, `docker compose up`, a devcontainer. What has to be running before tests pass. |
| **Build & unit tests** | The exact commands. **The one CI runs, not the one that ought to work.** |
| **Test flags that matter** | Cache-defeating flags, race detectors, seeds, timeouts, what makes a suite flaky here. |
| **Front end** | Is there one; how it is run; whether it is tested, and with what. |
| **End-to-end** | Whether e2e exists, what stands it up, how long it takes, and **whether a role is expected to run it before handing work on or only in CI**. |
| **Environments** | What exists (local / test / staging / prod), how each is reached, and which are safe to write to. |
| **UAT environment** | **Which build product does UAT against — is it the test environment, a branch build, or a local worktree?** Say it explicitly; this is the question most often left implicit and it decides what a product verdict is worth. |
| **Definition of done** | What must be true beyond green CI: coverage, docs, migrations, a changelog, a screenshot. |
| **Domain vocabulary** | Words that mean something specific here and that a newcomer gets wrong. |
| **Danger** | What must never be run against real data; which commands are irreversible. |

**Ask about the front end and e2e even when you found none** — absence and "we have not got to it
yet" are different answers, and the second one is a thing a role should not invent.

**A question the owner declines to answer is a real outcome.** Write `not decided` and say what a
role should do when it hits that — not a guess dressed as a fact.

## 3. Write it where every role reads it

**`.workflow/PROJECT.md` — shared by every role.** Created here, owned by this project, and never
touched by an install:

```markdown
# How this project is built, tested and accepted

_Written by `/config-workflow` on <date>. Re-run it when any of this changes._

## Dev environment
## Build and unit tests
## Front end
## End to end
## Environments
## UAT — which build product accepts against
## Definition of done
## Vocabulary
## Never do this here
```

**Commands go in as commands, copy-pasteable, with what they need running first.** Prose about a
command is not a command, and a role that has to reconstruct it will reconstruct it differently.

**Say which of these you drove and which the owner told you.** A role reading this needs to know
which lines are verified and which are reported — they are different kinds of fact and the second
kind is where the surprises live.

**Then the role-specific remainder goes in `.workflow/<role>/AGENT.md`** — what qa needs and dev does
not, product's acceptance conventions, ops' deploy specifics. **Keep it small.** Anything true for
every role belongs in `PROJECT.md`, said once.

**What does NOT belong in either:** how the process works. That is the framework's half, and if you
find yourself restating it, the framework is missing something — change it there.

## 4. Re-running this

**It is safe to re-run and it must stay that way.** Read what is there, ask about what has changed or
is missing, and **preserve anything you are not changing** — including hand-written additions the
owner made. Never silently replace a section whose content you did not ask about.

**Say what you changed** at the end, section by section. A configuration that quietly moved is one
nobody can trust.
