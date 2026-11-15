#!/usr/bin/env bash
# session-start.sh: Claude Code SessionStart hook.
#
# Whatever this prints is added to the new session's context, so every session
# starts knowing what is in flight, what other sessions just finished, and
# which fleet batches are still running. It must never fail a session start,
# so every step degrades to printing nothing.

# Installed scripts live in $ATLAS_HOME/bin, so home is one level up unless set.
ATLAS_HOME="${ATLAS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ATLAS_STATE="${ATLAS_STATE:-$ATLAS_HOME/state}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="$ATLAS_STATE/missions.json"

[ -f "$M" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

echo "## Open missions"
jq -r '
  [.missions[] | select(.status == "in_progress" or .status == "blocked")]
  | sort_by(.status != "blocked")
  | if length == 0 then "  (none open)" else .[] |
      "- [\(.status | ascii_upcase)] \(.project): \(.title)"
      + (if (.blocker // "") != "" then "\n    blocked: \(.blocker)" else "" end)
      + (if (.next_action // "") != "" then "\n    next: \(.next_action)" else "" end)
    end
' "$M" 2>/dev/null

if [ -s "$ATLAS_STATE/worklog.jsonl" ]; then
  echo ""
  echo "## Recently wrapped (other sessions)"
  ATLAS_STATE="$ATLAS_STATE" "$HERE/worklog.sh" recent 4 2>/dev/null
fi

# Fleet ledgers touched in the last 2 days that still have a running or
# launching row, so a new session doesn't redo work a child already owns.
FLEET="$ATLAS_STATE/fleet"
if [ -d "$FLEET" ]; then
  live="$(find "$FLEET" -maxdepth 1 -name '*.md' -mtime -2 -exec grep -lE '\| (running|launching) \|' {} + 2>/dev/null)"
  if [ -n "$live" ]; then
    echo ""
    echo "## Fleet in flight"
    while IFS= read -r f; do
      echo "- $(basename "$f" .md): $(grep -cE '\| (running|launching) \|' "$f") task(s) running"
    done <<< "$live"
  fi
fi

echo ""
echo "Close the loop with /wrap. Plan your day with /today. Run a batch with /fleet."
exit 0
