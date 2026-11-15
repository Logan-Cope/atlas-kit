---
name: wrap
description: Close the loop on a finished unit of work. Appends one line to the shared worklog, moves the mission through mission.sh, and records the reason for any real decision, so every other Claude Code session sees what just got done. Use at a task boundary, when the user says "wrap", "close the loop" or "log this", or on your own after shipping something a future session would care about. Not for trivial edits, pure reading, or steps inside a task.
---

# /wrap: close the loop

Several sessions share one state folder. They can't see each other's chats, so the worklog and the missions file are the only way one session learns what another did. Keep this fast: it's a checkpoint, not a report.

## Does this clear the bar?

Wrap when the work left something behind that a future session would care about:
- something shipped: code, a doc, a skill, an asset
- a decision that sticks
- an event in the world: a message sent, an account created, a payment made
- a mission moved, blocked or finished
- a real bug or gotcha found

Don't wrap trivial edits, pure reading, a question answered with no change, or steps inside a task. One wrap per unit of work, at the end. If nothing clears the bar, say so in one line and stop.

## Steps

1. Write the summary: one concrete line on what changed and why it matters, with a number if there is one. Not a list of tool calls.
2. Find the project, the mission id(s) it moved (`~/.atlas/bin/mission.sh list`) and the key files.
3. Append to the worklog:
   ```
   ~/.atlas/bin/worklog.sh add --project <p> --missions <id1,id2> --files <f1,f2> --source claude "<summary>"
   ```
   Use `--source manual` when the user typed `/wrap` themselves.
4. Move the mission. Never edit `missions.json` by hand; `mission.sh` locks and swaps the file so a concurrent session can't lose your change.
   - still going: `mission.sh next <id> "<next action>"`
   - finished: `mission.sh done <id>`
   - stuck: `mission.sh block <id> "<reason>"`
   - new piece of work: `mission.sh add <project> "<title>"`, then `mission.sh next` on the id it prints
5. If the work embodied a real decision, or a mission changed status, record why:
   ```
   ~/.atlas/bin/mission.sh decision <id> "<what was decided>" "<why>"
   ```
   The next action gets overwritten every wrap. The decision ledger is append-only, so the reason survives. Skip this for routine progress.
6. Confirm in one line: what you logged, which mission moved, and whether you recorded a decision.

## Rules

- The worklog and the decision ledger are append-only. Never edit or delete a past line.
- A headline, not a transcript.
- Unsure whether it clears the bar? It probably doesn't.
