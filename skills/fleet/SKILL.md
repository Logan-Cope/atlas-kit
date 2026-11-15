---
name: fleet
description: Run several independent tasks at once as separate Claude Code sessions, with this session as the orchestrator. It writes a task table with pass/fail checks, starts one child session per task, tracks them in a ledger, judges the evidence each child returns, sends back anything not actually done, and reports. Use when handed more than one independent task ("spin these up", "run these in parallel", "a session for each"), or one job big enough to split. Not for a single small task, and not for dependent steps in the same files.
---

# /fleet: one orchestrator, many sessions

You are the orchestrator. You plan, launch, judge and report. Children do the work. Don't do a task's work yourself, except to re-run a cheap check while judging.

## 1. Shape the work

Write the task table before launching anything. Every row needs:

- **Task:** one outcome, stated as the result.
- **Done when:** checks that come back pass or fail: a test command, a file with given content, a URL that returns 200, a PR with green CI. If you can't write one, the task isn't ready. Split it or ask.
- **Evidence:** what the child returns, usually each command with its real output.
- **Lane:** Local, Cloud or Subagent (next section).
- **Owns:** the files or folders this task may write. Two children writing the same file overwrite each other, so owned sets never overlap. Sequence tasks that need the same files.
- **Model:** the strongest model for judgment-heavy work, a cheaper one for mechanical work.

Launch without asking unless a task sends something outward (an email, a post, a payment, a message to a person). Those children draft to a file and stop; the user sends.

## 2. Pick the lane

| Lane | Use when | How |
|---|---|---|
| **Local** (default) | The work needs local files, the state folder, local skills or credentials | `claude --bg --name fleet-<batch>-<task> --model <model> "<brief>"` from the working folder. It runs under the background supervisor and survives the terminal closing |
| **Cloud** | Code work inside one GitHub repo that should keep going with the laptop closed | A cloud session on that repo. It starts from a fresh clone, so it sees only what's committed, and it ends with a PR |
| **Subagent** | Anything under about 15 minutes | The Agent tool in this session, in the background. No new session |

A new session spends tens of thousands of tokens on setup before doing anything. Don't start one for a two-minute task.

## 3. Write the brief

The brief is everything the child knows:

```
You are one session in a fleet. Batch: <batch>. Task: <task>.

Goal: <outcome and why it matters, 2-3 sentences>
Context: <files to read first, decisions already made>
You own: <files/folders you may write>. Leave everything else alone.
  Change shared state only through ~/.atlas/bin/mission.sh and worklog.sh.
Done when: <the pass/fail checks>
Don't: <out of scope>. Draft any outward message to a file; never send it.

When finished:
1. Run every done-when check and keep the real output.
2. Run /wrap.
3. Write ~/.atlas/state/fleet/<batch>/<task>-report.md (Cloud: make it your final reply):
   FLEET <batch> <task>
   STATUS: done | partial | blocked
   EVIDENCE: <each check: command -> real output; paths; PR link>
   FOR YOU: <decisions or blockers only, or "none">
```

## 4. Launch

- Write the ledger first, at `~/.atlas/state/fleet/<batch>.md`: a line naming the orchestrator and who asked, then one table:

  `| Task | Lane | Model | Owns | Done when | Session | Status | Evidence |`

  Status is exactly one of `launching`, `running`, `done (verified)`, `partial`, `blocked`. The session-start hook counts `launching` and `running` rows to show "Fleet in flight" in every new session, so keep those words exact.
- Start every independent task in one message (parallel Bash calls), then fill in session ids from `claude agents --json --all` (`sessionId`) and set Status to `running`.
- Run at most 4 Local children at once and queue the rest. Keep the tree two levels deep.
- Set a wake-up instead of polling by hand: a background Bash loop that exits when any named child reaches `done`, `failed` or `stopped`, or is waiting for input:

  ```
  until claude agents --json --all | python3 -c "import json,sys; w=set(sys.argv[1:]); sys.exit(0 if any(e.get('name') in w and (e.get('state') in ('done','failed','stopped','blocked') or e.get('status')=='waiting') for e in json.load(sys.stdin)) else 1)" fleet-<batch>-<task-a> fleet-<batch>-<task-b>; do sleep 20; done
  ```

## 5. Judge the evidence, not the claim

- Read each report. Re-run what's cheap yourself: open the file, run the test, curl the URL, read the PR's checks.
- "Tests pass" with no output is not done.
- If the work isn't done, send it back with the specific gap: `claude --bg --resume <sessionId> "<the gap>"`. It keeps the conversation. Each resume makes a new session id; update the ledger.
- After two send-backs on the same task, mark it `blocked` and move on.
- Update the ledger every time a status changes. If your own session restarts, rebuild the picture from the ledger plus `claude agents --json --all` before doing anything else.

## 6. Finish

1. Report to whoever asked. Decisions and blockers first, ranked. Then one line per task: status and evidence.
2. Run one `/wrap` for the batch.
3. Leave the child sessions in place so the user can open any of them.
