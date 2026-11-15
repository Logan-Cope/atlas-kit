#!/usr/bin/env bash
# mission.sh: the only way anything changes missions.json.
#
# Every write takes a lock, rewrites the file through a temp file next to it,
# and swaps it in with mv, so a reader never sees half a file and two sessions
# editing at once both land. Each change restamps `updated` and rebuilds the
# dashboard, so the dashboard never shows stale state.
#
# Usage:
#   mission.sh list
#   mission.sh add <project> "<title>"          new backlog mission, prints its id
#   mission.sh start <id>                       -> in_progress
#   mission.sh done  <id>                       -> done
#   mission.sh block <id> "<reason>"            -> blocked, with the reason
#   mission.sh next  <id> "<next action>"       set the next action
#   mission.sh decision <id> "<what>" ["<why>"] append to the decision ledger
#   mission.sh decisions <id>                   read a mission's decisions
set -euo pipefail

# Installed scripts live in $ATLAS_HOME/bin, so home is one level up unless set.
ATLAS_HOME="${ATLAS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ATLAS_STATE="${ATLAS_STATE:-$ATLAS_HOME/state}"
M="$ATLAS_STATE/missions.json"
D="$ATLAS_STATE/decisions.jsonl"
LOCK="$M.lock"
DASHBOARD="$(dirname "$ATLAS_STATE")/dashboard/index.html"   # next to the state it shows
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
today="$(date '+%Y-%m-%d')"

die() { echo "mission: $*" >&2; exit 1; }

ensure_file() {
  mkdir -p "$ATLAS_STATE"
  [ -f "$M" ] || printf '{"updated":"","missions":[]}\n' > "$M"
}

# mkdir is atomic on every filesystem, and macOS ships without flock(1).
lock() {
  local tries=0
  until mkdir "$LOCK" 2>/dev/null; do
    tries=$((tries + 1))
    # A lock older than a minute belongs to a crashed writer; clear it.
    if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
      rmdir "$LOCK" 2>/dev/null || true
    fi
    [ "$tries" -lt 400 ] || die "could not get $LOCK after 20s; remove it if no session is writing"
    sleep 0.05
  done
  trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
}

# write <jq filter> [jq args...]: apply a filter to missions.json under the lock.
write() {
  local filter="$1"; shift
  local tmp
  tmp="$(mktemp "$M.tmp.XXXXXX")"   # same directory, so mv is an atomic rename
  chmod 644 "$tmp"                    # mktemp makes 0600; keep the file readable as before
  if jq --arg today "$today" "$@" "$filter | .updated = \$today" "$M" > "$tmp"; then
    mv "$tmp" "$M"
  else
    rm -f "$tmp"; die "jq failed; missions.json unchanged"
  fi
}

exists() { jq -e --arg id "$1" 'any(.missions[]; .id == $id)' "$M" >/dev/null; }

rebuild_dashboard() {
  python3 "$HERE/build-dashboard.py" --state "$ATLAS_STATE" \
    --out "$DASHBOARD" >/dev/null 2>&1 || true
}

# set_fields <id> <jq object>: merge fields into one mission.
set_fields() {
  local id="$1"; shift
  local obj="$1"; shift
  lock
  exists "$id" || die "unknown mission: $id"
  write "(.missions[] | select(.id == \$id)) |= (. + $obj + {updated: \$today})" --arg id "$id" "$@"
}

cmd="${1:-list}"; shift || true
ensure_file
case "$cmd" in
  list)
    jq -r '.missions[] | "  \(.status | ascii_upcase | .[0:11])\t\(.project)/\(.id)\n\t\t\(.title)"' "$M" ;;
  add)
    project="${1:?usage: mission.sh add <project> \"<title>\"}"
    title="${2:?usage: mission.sh add <project> \"<title>\"}"
    id="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//' | cut -c1-40 | sed 's/-*$//')"
    [ -n "$id" ] || die "title needs at least one letter or digit"
    lock
    ! exists "$id" || die "mission already exists: $id"
    write '.missions += [{id: $id, title: $t, project: $p, status: "backlog",
                          next_action: "", blocker: null, updated: $today}]' \
      --arg id "$id" --arg t "$title" --arg p "$project"
    rebuild_dashboard; echo "$id" ;;
  start) set_fields "${1:?id}" '{status: "in_progress", blocker: null}'; rebuild_dashboard; echo "started $1" ;;
  done)  set_fields "${1:?id}" '{status: "done", blocker: null}';        rebuild_dashboard; echo "done $1" ;;
  block)
    set_fields "${1:?id}" '{status: "blocked", blocker: $why}' --arg why "${2:?reason}"
    rebuild_dashboard; echo "blocked $1" ;;
  next)
    set_fields "${1:?id}" '{next_action: $txt}' --arg txt "${2:?text}"
    rebuild_dashboard; echo "next set on $1" ;;
  decision)
    # Separate ledger, append-only like the worklog. It never touches
    # missions.json, so recording a reason doesn't change `updated`.
    id="${1:?id}"; what="${2:?what}"; why="${3:-}"
    exists "$id" || die "unknown mission: $id"
    project="$(jq -r --arg id "$id" '.missions[] | select(.id == $id) | .project' "$M")"
    line="$(jq -cn --arg ts "$(date '+%Y-%m-%dT%H:%M:%S')" --arg id "$id" --arg p "$project" \
      --arg w "$what" --arg y "$why" '{ts: $ts, mission: $id, project: $p, decision: $w, why: $y}')"
    printf '%s\n' "$line" >> "$D"
    rebuild_dashboard; echo "decision logged on $id" ;;
  decisions)
    id="${1:?id}"
    [ -s "$D" ] || { echo "  (no decisions logged)"; exit 0; }
    jq -r --arg id "$id" 'select(.mission == $id)
      | "  \(.ts[0:10])  \(.decision)" + (if .why != "" then "\n              why: \(.why)" else "" end)' "$D" ;;
  *) die "unknown command: $cmd (list|add|start|done|block|next|decision|decisions)" ;;
esac
