#!/usr/bin/env python3
"""The watches: what changed on the board, and proof that the watching is still happening.

BEING WOKEN IS AN OPTIMISATION. IT IS NEVER HOW A ROLE FINDS OUT WHAT IS WAITING ON IT. A monitor is
a process, processes end, and the one thing a dead process cannot do is tell you it is dead. This
has happened: a watcher died three times in one session, and the role it served sat idle believing
its board was clear while pull requests piled up behind it.

So three things are non-negotiable here and each was paid for:

  WATCHING   a heartbeat on the first poll and every tenth after it. Not noise — it is the only
             evidence the watch is still standing. Silence otherwise means "no work" and "I am
             dead" with the same number of characters.
  LOOKUP FAILED  a poll that could not be answered says so. An expired token and a quiet queue look
             identical otherwise, and a role that cannot tell them apart sits idle believing it is
             finished.
  HOLDING    below the budget reserve the watch stands down and says when it resumes. A third
             state, distinct from a failed lookup and from a quiet board: alive, deliberately idle.

EVERY TERMINAL STATE IS EMITTED, NOT ONLY THE GOOD ONE. A watch that announced success alone would
be silent through the failure it exists to catch, and silence is indistinguishable from
still-running.

Usage: watch.py prs <role> [interval]     watch.py prs <role> --sweep
       watch.py queue <role> [interval]
       watch.py all <role> [interval]     supervises both
       watch.py --self-test
"""

from __future__ import annotations

import os
import sys
import time
from dataclasses import dataclass, field

import budget as budget_mod
import pr as pr_mod
import queue as queue_mod
import verdicts as vmod
from gh import Client, LookupFailure, resolve_repo

# 300s, NOT 60, AND THE NUMBER IS MEASURED. One poll of both watches costs a role about 52 API calls
# on a six-pull-request board, so three roles at 60s is ~9360 calls/hour against a limit of 5000 —
# 1.9x over, before any agent does any work of its own. Nothing on a review board moves on a
# sixty-second timescale.
DEFAULT_INTERVAL = 300
HEARTBEAT_EVERY = 10


@dataclass
class Emitter:
    """Announce each distinct fact once.

    THE KEY IS state|number|detail AND THE DETAIL MATTERS. A MERGED event carries main's colour, and
    that line carries main's SHA — so the same event at two different main shas is two different
    keys, and **when main moves, every recently-merged pull request re-emits**. Measured: merging
    one pull request moved main and the watch immediately replayed twelve merges it had already
    reported in the same process, then was stopped for volume.

    That is recorded here rather than fixed here: the flood is triggered by MERGING, the one act the
    role is there to perform, so a quiet board stays quiet and a working board silences its own
    watch at the moment it most needs to see whether main went red. See Issue #32.
    """

    seen: set[tuple] = field(default_factory=set)
    out = sys.stdout

    def emit(self, state: str, number: int, title: str, detail: str = "") -> bool:
        key = (state, number, detail)
        if key in self.seen:
            return False
        self.seen.add(key)
        line = f"{state} #{number}  {title}" + (f"  —  {detail}" if detail else "")
        print(line, flush=True)
        return True

    def say(self, line: str) -> None:
        print(line, flush=True)


def pr_events(client: Client, repo: str, role: str, em: Emitter) -> None:
    """One pass over every open pull request. The same code the monitor runs, which is why `--sweep`
    cannot drift from it — a fallback that differs from the thing it backs up is worse than none."""
    prs = client.paginate(f"repos/{repo}/pulls?state=open")
    for p in prs:
        num, ref, sha = p["number"], p["head"]["ref"], p["head"]["sha"]
        title = (p.get("title") or "")[:52]
        st = pr_mod.read_state(client, repo, num)

        if st.code == pr_mod.CONFLICT:
            em.emit("CONFLICT", num, title, f"[{ref}] rebase — no gate can run on this head")
            continue
        if st.code == pr_mod.RED:
            em.emit("FAILING", num, title, f"[{ref}] {st.brief}")
            continue

        verdicts = vmod.parse(client.paginate(f"repos/{repo}/issues/{num}/comments"))
        latest = [v for v in verdicts if v.sha == sha]
        if any(v.is_changes for v in latest):
            who = " ".join(sorted({v.role for v in latest if v.is_changes}))
            em.emit("CHANGES", num, title, f"[{ref}] refused by {who}")
            continue
        if not latest:
            # NEEDS-REVIEW IS ADDRESSED TO THE AUTHOR NOW, not to whoever is listening. The review
            # is dispatched by whoever built the branch and held across rounds; two roles reviewing
            # one branch against two standards is the ping-pong that cost eleven verdicts.
            owner = ref.split("/")[0]
            detail = f"[{ref}] built by {owner} — {owner} dispatches its reviewer"
            em.emit("NEEDS-REVIEW", num, title, detail)
            continue
        if st.code == pr_mod.GREEN:
            em.emit("READY", num, title, f"[{ref}] green and reviewed")


def queue_events(role: str, em: Emitter, run_queue=None) -> None:
    """New Issues in this role's queue."""
    if run_queue is None:
        repo = resolve_repo()
        board = queue_mod.Board(client=Client(), repo=repo)
        lines = queue_mod.role_queue(board, role)
    else:
        lines = run_queue(role)
    for line in lines:
        s = line.strip()
        if s.startswith("#") and "  " in s:
            num_txt = s[1:].split()[0].rstrip(":")
            if num_txt.isdigit():
                em.emit("NEW", int(num_txt), s.split(None, 1)[1][:60] if " " in s else "")


def loop(kind: str, role: str, interval: int, *, once: bool = False,
         client_factory=Client, sleeper=time.sleep) -> int:
    em = Emitter()
    polls = 0
    while True:
        polls += 1
        # THE WORK COMES BEFORE THE WATCHING. Below the reserve this stops polling and waits: a role
        # that cannot call the API cannot review, merge or close anything, and a watch still
        # spending budget while that is true has inverted its own purpose.
        try:
            client = client_factory()
            code, msg = budget_mod.check(client)
            if code == 1:
                em.say(msg)
                if once:
                    return 0
                sleeper(interval)
                continue
        except LookupFailure as e:
            em.say(f"LOOKUP FAILED: {e.reason}")
            if once:
                return 1
            sleeper(interval)
            continue

        try:
            repo = resolve_repo()
            if kind == "prs":
                pr_events(client, repo, role, em)
            else:
                queue_events(role, em)
        except LookupFailure as e:
            # A FAILED POLL EMITS AND DOES NOT END THE WATCH. A transient outage must wake the role,
            # not kill the thing that would have told it.
            em.say(f"LOOKUP FAILED: {e.reason}")
            if once:
                return 1
        else:
            if once:
                return 0

        if polls == 1 or polls % HEARTBEAT_EVERY == 0:
            em.say(f"WATCHING {kind} for {role} — poll {polls}, every {interval}s")
        sleeper(interval)


def main(argv: list[str]) -> int:
    if argv and argv[0] == "--self-test":
        return _self_test()
    if len(argv) < 2:
        print("usage: watch.py prs|queue|all <role> [interval] [--sweep]", file=sys.stderr)
        return 2
    kind, role = argv[0], argv[1]
    if role not in ("dev", "qa", "product", "ops", "flow", "pm"):
        print(f"::error::'{role}' is not a role.", file=sys.stderr)
        return 2
    sweep = "--sweep" in argv
    interval = DEFAULT_INTERVAL
    for a in argv[2:]:
        if a.isdigit():
            interval = int(a)
    if kind == "all":
        return _supervise(role, interval)
    if kind not in ("prs", "queue"):
        print(f"::error::'{kind}' is not a watch. One of: prs queue all", file=sys.stderr)
        return 2
    return loop(kind, role, interval, once=sweep)


def _supervise(role: str, interval: int) -> int:
    """ONE MONITOR, NOT TWO. A role told to start two is repeatedly observed running one, and WHICH
    half it lost is the part nobody notices: keep the queue watch and new Issues still arrive, so
    everything looks fine while every red gate goes unheard."""
    import subprocess
    here = os.path.dirname(os.path.abspath(__file__))
    procs = {}
    restarts = {"prs": 0, "queue": 0}
    for kind in ("prs", "queue"):
        procs[kind] = subprocess.Popen(
            [sys.executable, os.path.join(here, "watch.py"), kind, role, str(interval)])
    try:
        while True:
            time.sleep(5)
            for kind, p in list(procs.items()):
                if p.poll() is not None:
                    restarts[kind] += 1
                    print(f"WATCH RESTARTED {kind} (exit {p.returncode}) — restart "
                          f"#{restarts[kind]}", flush=True)
                    procs[kind] = subprocess.Popen(
                        [sys.executable, os.path.join(here, "watch.py"), kind, role, str(interval)])
    except KeyboardInterrupt:
        for p in procs.values():
            p.terminate()
        return 0


def _self_test() -> int:
    import subprocess as sp
    from pathlib import Path
    here = Path(__file__).resolve().parent
    r = sp.run(["uv", "run", "--isolated", "--no-project", "--with", "pytest",
                "pytest", str(here / "tests"), "-q"],
               capture_output=True, text=True, cwd=here, check=False)
    if r.returncode == 0:
        print("self-test passed: a failed poll emits and does not end the watch, unknown roles "
              "refuse, an item is announced once, the heartbeat arrives, every terminal state is "
              "emitted including the failing ones, and a sweep exits")
        return 0
    print(r.stdout or r.stderr, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
