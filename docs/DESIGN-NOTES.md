# Design notes

Why atlas-kit is built the way it is, including the ideas that didn't survive.

## The problem

Working with several Claude Code sessions open at once, each one starts blind. One session fixes a bug another is about to fix again. A decision made in the morning is gone by the afternoon because it lived in a chat. Sessions can't read each other's conversations, so the only shared memory is whatever is written to disk. The question is what to write, when, and how to keep many writers from corrupting it.

## Wrap at the end of a unit of work, not at the end of a session

The first idea was a `Stop` hook: when a session ends, summarize it. It doesn't work, because sessions don't end. They stay open for days in a terminal tab. "Session end" is not a real event.

The trigger that does work is a finished unit of work. `/wrap` runs when something is done, either because the user says so or because the model reaches a task boundary on its own.

What counts as a unit of work took a second try. The first bar was too high (only big milestones), which meant a new skill or a real bug fix never got recorded. The bar that stuck is the **residue bar**: wrap when the work left behind something a future session would care about. A shipped skill clears it. Renaming a variable doesn't. It's about consequence, not size.

## The worklog is append-only

Every session writes to the same log. If writing meant "read the file, add a line, write the file back", two sessions doing it at once would each write back a file missing the other's line.

So the worklog is never rewritten. `worklog.sh` makes each entry one line of JSON and appends it with a single write. On a local filesystem, a small write to a file opened in append mode lands whole and in one piece, even with other writers. The tests start 40 appends at once and check that all 40 lines are there and parse.

Append-only also makes the log trustworthy as history. Nothing in it is edited after the fact, so it can answer "what happened on Tuesday" honestly.

## Missions change only through one script

Missions are different: a mission's status and next action change, so its file has to be rewritten. That makes it the one place where concurrent writers can lose work.

The rule is that nothing edits `missions.json` except `mission.sh`, and `mission.sh` does it carefully: lock, rewrite through a temp file in the same folder, atomic `mv`, unlock. The same-folder temp file matters twice: `mv` within one filesystem is an atomic rename, and sandboxed sessions are often unable to write to the system temp folder at all.

The lock earned its place in testing. With it removed, 20 sessions each updating a different mission at the same moment leave only 4 of the 20 changes in the file. With it, all 20 land. A tool that is safe only when one session runs at a time would defeat the point.

Every value is passed to jq as `--arg` and never pasted into the filter. A next action like `" | .status="done"` is stored as text, not run. There's a test for that too.

## Decisions get their own ledger

A mission's `next_action` is overwritten on every wrap. That's right for "what's next" and wrong for "why did we choose this", which gets lost the next time someone writes a next action.

So reasons go to `decisions.jsonl`, append-only like the worklog. `mission.sh decisions <id>` reads them back when someone asks why a mission stands where it does. Writing a decision doesn't touch `missions.json`, so it doesn't make a stale mission look recently updated.

## The briefing is a hook, and it never fails

`session-start.sh` runs before the user types anything. If it errored, every session would start with an error. So it degrades instead: no state folder prints nothing, no `jq` prints nothing, a broken file prints less. It shows only what changes behavior: open and blocked missions (blocked first, because those are the ones someone can unblock), the last few wraps, and fleet batches still running so a new session doesn't redo a child's work.

## Fleet: judge the evidence, not the claim

The orchestrator's job is not to trust its children. A child saying "tests pass" is a claim. A child pasting the test command and its output is evidence, and the orchestrator re-runs the cheap checks itself before writing `done (verified)` in the ledger. "Tests pass" with no output counts as not done.

The other rules all come from the same place, which is that a child session is capable but can't see the rest of the batch:

- **Done-when checks are written before launch.** If a task can't be given a pass/fail check, it isn't ready to hand off.
- **Owned files never overlap.** Two children writing one file overwrite each other, and nothing warns you.
- **Two send-backs, then blocked.** A child that misses twice is probably missing something it can't get, and a third try usually burns time without progress.
- **Outward actions are drafted, never sent.** A child can write the email; a person sends it.
- **Small tasks go to subagents.** A new session spends tens of thousands of tokens on setup, so a two-minute task doesn't get one.

## Things left out on purpose

- **A database or a server.** Plain files can be read by `cat`, diffed by git and edited by hand in an emergency. Nothing here needs a query planner.
- **A router skill that picks other skills.** Skill descriptions share a fixed slice of context. One more skill whose job is choosing skills makes that slice more crowded, not less. Fewer, better-described skills worked better.
- **An automatic summary of every tool call.** A raw activity log is easy to collect and hard to read. The worklog is useful because a session chose what mattered.
- **JavaScript in the dashboard.** It's a status page. Static HTML opens from disk, loads instantly, and has nothing to break.
