---
name: today
description: Start the day from the shared state. Reads the open missions, the latest wraps from every session, running fleet batches and the decision ledger, then recommends the single first move and two or three focus items. Use on "what's on today", "where are we", "catch me up", "what should I work on", "what's first", or at the start of a working session.
---

# /today: where things stand and what to do first

Talk the user through their day. Lead with one recommendation, keep it short, and let them drill in. Don't dump the files.

## Gather (local files only, so it never stalls)

1. The real date: run `date '+%A, %Y-%m-%d'` and use that string. Never work out the weekday yourself.
2. Open missions: `~/.atlas/bin/mission.sh list`, focusing on `in_progress` and `blocked`.
3. Recent wraps from every session: `~/.atlas/bin/worklog.sh recent 8`.
4. Fleet batches still running: any `~/.atlas/state/fleet/*.md` with a `running` or `launching` row.
5. Only when the user asks about one mission: its reasons, `~/.atlas/bin/mission.sh decisions <id>`.

## Deliver

- One line on the shape of the day: what's moving, what's stuck.
- **First move:** the single highest-leverage thing, with one line of why. This matters most, so it goes first.
- Then two or three focus items, one line each.
- **Needs you vs. waiting on others:** separate what the user can act on from what's blocked elsewhere, so they don't chase what they can't move.
- **Don't let it slip:** anything with a near deadline.
- End by naming two or three real missions they can ask about ("say *walk me through gpx-import*").

## Rules

- A recommendation, not an inventory.
- Read, don't write. `/today` never changes state; `/wrap` does that.
- If a file is missing, say what's missing in one line and work from what's there.
