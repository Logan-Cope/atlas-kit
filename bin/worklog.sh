#!/usr/bin/env bash
# worklog.sh: the append-only "what got done" log shared by every session.
#
# One JSON line per finished unit of work. Sessions only ever append, so two
# sessions writing at the same moment can't overwrite each other.
#
# Usage:
#   worklog.sh add [--project P] [--missions a,b] [--files f,g] [--source claude|manual] "summary"
#   worklog.sh recent [N]       last N entries, human readable (default 5)
#   worklog.sh since <ISO-ts>   raw JSON lines strictly newer than ts
#   worklog.sh last-ts          timestamp of the newest entry (empty if none)
set -u

# Installed scripts live in $ATLAS_HOME/bin, so home is one level up unless set.
ATLAS_HOME="${ATLAS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ATLAS_STATE="${ATLAS_STATE:-$ATLAS_HOME/state}"
LOG="$ATLAS_STATE/worklog.jsonl"

die() { echo "worklog: $*" >&2; exit 2; }

cmd="${1:-recent}"; shift || true
case "$cmd" in
  add)
    project="" missions="" files="" source="claude"
    while [ $# -gt 0 ]; do
      case "$1" in
        --project|--missions|--files|--source)
          [ $# -ge 2 ] || die "$1 needs a value"
          case "$1" in
            --project)  project="$2" ;;
            --missions) missions="$2" ;;
            --files)    files="$2" ;;
            --source)   source="$2" ;;
          esac
          shift 2 ;;
        --) shift; break ;;
        -*) die "unknown flag $1" ;;
        *) break ;;
      esac
    done
    summary="${1:-}"
    [ -n "$summary" ] || die "a summary is required"
    [ $# -le 1 ] || die "quote the summary: got $# words, expected one argument"
    ts="$(date '+%Y-%m-%dT%H:%M:%S')"
    line="$(jq -cn --arg ts "$ts" --arg p "${project:-general}" --arg s "$summary" \
      --arg m "$missions" --arg f "$files" --arg src "$source" \
      '{ts:$ts, project:$p, summary:$s,
        missions: ($m | split(",") | map(select(length > 0))),
        files:    ($f | split(",") | map(select(length > 0))),
        source:$src}')" || { echo "worklog: jq failed" >&2; exit 1; }
    mkdir -p "$(dirname "$LOG")" || exit 1
    # One small write() to a file opened with O_APPEND lands whole, even with
    # other sessions appending at the same time. That is the whole design.
    if printf '%s\n' "$line" >> "$LOG"; then
      echo "logged: $summary"
    else
      echo "worklog: append to $LOG failed" >&2; exit 1
    fi
    ;;
  recent)
    n="${1:-5}"
    [ -s "$LOG" ] || { echo "  (worklog empty)"; exit 0; }
    # Parse line by line and skip any that aren't valid entries, so one bad
    # line can't hide the rest of the log.
    tail -n "$n" "$LOG" | jq -rR '
      fromjson? | select(type == "object" and (.ts | type) == "string")
      | "  \(.ts[5:16] | sub("T"; " ")) · \(.project): \(.summary)"
        + (if ((.missions // []) | length) > 0 then " [\(.missions | join(","))]" else "" end)'
    ;;
  since)
    ts="${1:?usage: worklog.sh since <ISO-ts>}"
    [ -f "$LOG" ] || exit 0
    jq -cR --arg t "$ts" 'fromjson? | select(type == "object" and (.ts | type) == "string" and .ts > $t)' "$LOG"
    ;;
  last-ts)
    [ -s "$LOG" ] || exit 0
    tail -n 1 "$LOG" | jq -r '.ts // empty'
    ;;
  *) echo "usage: worklog.sh add|recent|since|last-ts" >&2; exit 2 ;;
esac
