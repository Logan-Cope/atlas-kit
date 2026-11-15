#!/usr/bin/env bash
# ok/fail never fail, so `check && ok || fail` is safe; '~/.atlas' is a literal on purpose.
# shellcheck disable=SC2015,SC2181,SC2088
# tests/run.sh: every shell test, then the Python tests. Exit 0 only if all pass.
# Each test gets its own temp ATLAS_HOME, so nothing touches your real state.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/bin"
PASS=0 FAIL=0 CURRENT=""

ok()   { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL [$CURRENT] $*"; }
eq()   { [ "$1" = "$2" ] && ok || fail "expected '$2', got '$1'"; }
has()  { case "$1" in *"$2"*) ok ;; *) fail "output lacks '$2'"; esac; }
lacks(){ case "$1" in *"$2"*) fail "output has '$2'" ;; *) ok ;; esac; }

fresh() { # fresh <name>: new empty home for one test
  CURRENT="$1"
  TEST_HOME="$(mktemp -d)"
  export ATLAS_HOME="$TEST_HOME/atlas" ATLAS_STATE="$TEST_HOME/atlas/state"
  mkdir -p "$ATLAS_STATE"
}
with_example() { cp -R "$ROOT/examples/state/." "$ATLAS_STATE/"; }

# ---------- worklog ----------
fresh "worklog add writes one valid line"
out="$("$BIN/worklog.sh" add --project pantry --missions a,b --files x.ts "Shipped search")"
has "$out" "logged: Shipped search"
eq "$(wc -l < "$ATLAS_STATE/worklog.jsonl" | tr -d ' ')" "1"
eq "$(jq -r '.project + "|" + (.missions|join(",")) + "|" + .files[0] + "|" + .source' "$ATLAS_STATE/worklog.jsonl")" "pantry|a,b|x.ts|claude"

fresh "worklog escapes quotes, newlines and jq syntax"
"$BIN/worklog.sh" add 'He said "done"; .x = 1
second line' >/dev/null
eq "$(jq -r '.summary' "$ATLAS_STATE/worklog.jsonl")" 'He said "done"; .x = 1
second line'

fresh "worklog flag with no value exits 2 instead of hanging"
"$BIN/worklog.sh" add --project >/dev/null 2>&1; eq "$?" "2"
"$BIN/worklog.sh" add >/dev/null 2>&1; eq "$?" "2"
"$BIN/worklog.sh" add --bogus x "s" >/dev/null 2>&1; eq "$?" "2"
[ ! -s "$ATLAS_STATE/worklog.jsonl" ] && ok || fail "a rejected add still wrote"

fresh "40 concurrent worklog appends all land whole"
for i in $(seq 1 40); do "$BIN/worklog.sh" add --project p "entry $i $(printf 'x%.0s' $(seq 1 200))" >/dev/null & done; wait
eq "$(wc -l < "$ATLAS_STATE/worklog.jsonl" | tr -d ' ')" "40"
eq "$(jq -s 'length' "$ATLAS_STATE/worklog.jsonl")" "40"
eq "$(jq -r '.summary | split(" ")[1]' "$ATLAS_STATE/worklog.jsonl" | sort -n | uniq | wc -l | tr -d ' ')" "40"

fresh "worklog recent, since and last-ts read the example log"
with_example
out="$("$BIN/worklog.sh" recent 2)"
has "$out" "11-14 10:52 · pantry: Docs sprint"
eq "$(echo "$out" | wc -l | tr -d ' ')" "2"
eq "$("$BIN/worklog.sh" since 2026-11-14T00:00:00 | wc -l | tr -d ' ')" "3"
eq "$("$BIN/worklog.sh" last-ts)" "2026-11-14T10:52:36"

fresh "worklog recent on an empty log"
has "$("$BIN/worklog.sh" recent)" "(worklog empty)"

# ---------- missions ----------
fresh "mission add creates a backlog mission and prints its id"
id="$("$BIN/mission.sh" add pantry "Offline mode: v1!")"
eq "$id" "offline-mode-v1"
eq "$(jq -r '.missions[0].status' "$ATLAS_STATE/missions.json")" "backlog"
eq "$(jq -r '.updated' "$ATLAS_STATE/missions.json")" "$(date +%Y-%m-%d)"
"$BIN/mission.sh" add pantry "Offline mode: v1!" >/dev/null 2>&1; [ $? -ne 0 ] && ok || fail "duplicate id accepted"
eq "$(jq '.missions | length' "$ATLAS_STATE/missions.json")" "1"

fresh "mission lifecycle: start, next, block, start, done"
id="$("$BIN/mission.sh" add trailmap "GPX import")"
"$BIN/mission.sh" start "$id" >/dev/null
eq "$(jq -r '.missions[0].status' "$ATLAS_STATE/missions.json")" "in_progress"
"$BIN/mission.sh" next "$id" "Parse <ele>" >/dev/null
eq "$(jq -r '.missions[0].next_action' "$ATLAS_STATE/missions.json")" "Parse <ele>"
"$BIN/mission.sh" block "$id" "Need a sample file" >/dev/null
eq "$(jq -r '.missions[0].status + "|" + .missions[0].blocker' "$ATLAS_STATE/missions.json")" "blocked|Need a sample file"
"$BIN/mission.sh" start "$id" >/dev/null
eq "$(jq -r '.missions[0].blocker' "$ATLAS_STATE/missions.json")" "null"
"$BIN/mission.sh" "done" "$id" >/dev/null
eq "$(jq -r '.missions[0].status' "$ATLAS_STATE/missions.json")" "done"

fresh "mission text is stored literally, never run as jq"
id="$("$BIN/mission.sh" add p "Injection check")"
"$BIN/mission.sh" next "$id" '" | .status="done" | .x="' >/dev/null
eq "$(jq -r '.missions[0].status' "$ATLAS_STATE/missions.json")" "backlog"
eq "$(jq -r '.missions[0].next_action' "$ATLAS_STATE/missions.json")" '" | .status="done" | .x="'

fresh "mission on an unknown id fails and leaves the file alone"
with_example
before="$(cksum "$ATLAS_STATE/missions.json")"
"$BIN/mission.sh" next no-such-id "x" >/dev/null 2>&1; [ $? -ne 0 ] && ok || fail "unknown id accepted"
"$BIN/mission.sh" decision no-such-id "x" >/dev/null 2>&1; [ $? -ne 0 ] && ok || fail "unknown id accepted by decision"
eq "$(cksum "$ATLAS_STATE/missions.json")" "$before"
[ ! -e "$ATLAS_STATE/missions.json.lock" ] && ok || fail "lock left behind"

fresh "20 concurrent edits to different missions all land"
for i in $(seq 1 20); do "$BIN/mission.sh" add p "m$i" >/dev/null; done
for i in $(seq 1 20); do "$BIN/mission.sh" next "m$i" "next $i" >/dev/null & done; wait
eq "$(jq '[.missions[] | select(.next_action | startswith("next "))] | length' "$ATLAS_STATE/missions.json")" "20"
eq "$(jq '.missions | length' "$ATLAS_STATE/missions.json")" "20"
[ -z "$(find "$ATLAS_STATE" -name 'missions.json.tmp.*')" ] && ok || fail "temp files left behind"

fresh "a stale lock from a crashed writer is cleared"
"$BIN/mission.sh" add p "stale" >/dev/null
mkdir "$ATLAS_STATE/missions.json.lock"
touch -t 202001010000 "$ATLAS_STATE/missions.json.lock"
"$BIN/mission.sh" next stale "after crash" >/dev/null
eq "$(jq -r '.missions[0].next_action' "$ATLAS_STATE/missions.json")" "after crash"

fresh "decision ledger appends and reads back, missions.json untouched"
with_example
before="$(cksum "$ATLAS_STATE/missions.json")"
"$BIN/mission.sh" decision gpx-import "Ship 2 of 3 formats" "Waiting blocks users who have the first two" >/dev/null
eq "$(wc -l < "$ATLAS_STATE/decisions.jsonl" | tr -d ' ')" "5"
eq "$(tail -1 "$ATLAS_STATE/decisions.jsonl" | jq -r '.project')" "trailmap"
out="$("$BIN/mission.sh" decisions gpx-import)"
has "$out" "Blocked rather than guessing"
has "$out" "Ship 2 of 3 formats"
lacks "$out" "inverted index"
eq "$(cksum "$ATLAS_STATE/missions.json")" "$before"

fresh "mission writes rebuild the dashboard"
"$BIN/mission.sh" add pantry "Dashboard follows state" >/dev/null
has "$(cat "$ATLAS_HOME/dashboard/index.html")" "Dashboard follows state"

# ---------- session start hook ----------
fresh "session-start briefs open missions, wraps and live fleet batches"
with_example
touch "$ATLAS_STATE/fleet/2026-11-14-docs-sprint.md"
out="$("$BIN/session-start.sh")"
has "$out" "[BLOCKED] trailmap: Import GPX tracks"
has "$out" "blocked: No public sample file"
has "$out" "[IN_PROGRESS] pantry: Scale recipes"
lacks "$out" "Let the recipe list work offline"
lacks "$out" "elevation profile under each route"
has "$out" "## Recently wrapped"
has "$out" "2026-11-14-docs-sprint: 2 task(s) running"
eq "$(echo "$out" | grep -n 'BLOCKED' | cut -d: -f1)" "2"

fresh "session-start leaves out fleet ledgers older than 2 days"
with_example
touch -t 202001010000 "$ATLAS_STATE/fleet/2026-11-14-docs-sprint.md"
lacks "$("$BIN/session-start.sh")" "Fleet in flight"

fresh "session-start with no state prints nothing and exits 0"
rm -rf "$ATLAS_STATE"
out="$("$BIN/session-start.sh")"; eq "$?" "0"; eq "$out" ""

# ---------- install ----------
fresh "install puts scripts, skills and a dashboard in place"
export CLAUDE_CONFIG_DIR="$TEST_HOME/claude"
"$ROOT/install.sh" --example >/dev/null
[ -x "$ATLAS_HOME/bin/mission.sh" ] && ok || fail "mission.sh not installed"
eq "$(jq '.missions | length' "$ATLAS_HOME/state/missions.json")" "8"
for s in wrap today fleet; do [ -f "$CLAUDE_CONFIG_DIR/skills/$s/SKILL.md" ] && ok || fail "skill $s missing"; done
has "$(cat "$CLAUDE_CONFIG_DIR/skills/wrap/SKILL.md")" "$ATLAS_HOME/bin/worklog.sh"
lacks "$(cat "$CLAUDE_CONFIG_DIR/skills/wrap/SKILL.md")" "~/.atlas"
has "$(cat "$ATLAS_HOME/dashboard/index.html")" "Mission control"

fresh "install --hook is idempotent and keeps existing settings"
export CLAUDE_CONFIG_DIR="$TEST_HOME/claude"
mkdir -p "$CLAUDE_CONFIG_DIR"
echo '{"model":"x","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"other.sh"}]}]}}' > "$CLAUDE_CONFIG_DIR/settings.json"
"$ROOT/install.sh" --hook >/dev/null
"$ROOT/install.sh" --hook >/dev/null
s="$CLAUDE_CONFIG_DIR/settings.json"
eq "$(jq -r '.model' "$s")" "x"
eq "$(jq '[.hooks.SessionStart[].hooks[].command] | length' "$s")" "2"
eq "$(jq --arg c "$ATLAS_HOME/bin/session-start.sh" '[.hooks.SessionStart[].hooks[] | select(.command == $c)] | length' "$s")" "1"
eq "$(jq '.missions | length' "$ATLAS_HOME/state/missions.json")" "0"

fresh "install never overwrites existing state or a different skill"
export CLAUDE_CONFIG_DIR="$TEST_HOME/claude"
mkdir -p "$CLAUDE_CONFIG_DIR/skills/wrap"
echo "mine" > "$CLAUDE_CONFIG_DIR/skills/wrap/SKILL.md"
"$BIN/mission.sh" add p "keep me" >/dev/null
out="$("$ROOT/install.sh" --example)"
has "$out" "skip skill wrap"
eq "$(cat "$CLAUDE_CONFIG_DIR/skills/wrap/SKILL.md")" "mine"
eq "$(jq -r '.missions[0].id' "$ATLAS_HOME/state/missions.json")" "keep-me"

fresh "install --example keeps a leftover worklog when missions.json is missing"
export CLAUDE_CONFIG_DIR="$TEST_HOME/claude"
echo '{"ts":"2026-01-01T00:00:00","project":"mine","summary":"real entry"}' > "$ATLAS_STATE/worklog.jsonl"
"$ROOT/install.sh" --example >/dev/null
has "$(cat "$ATLAS_STATE/worklog.jsonl")" "real entry"
eq "$(wc -l < "$ATLAS_STATE/worklog.jsonl" | tr -d ' ')" "1"

fresh "install --hook refuses a settings.json that isn't JSON"
export CLAUDE_CONFIG_DIR="$TEST_HOME/claude"
mkdir -p "$CLAUDE_CONFIG_DIR"
printf '{ "model": "x", // a comment\n}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
before="$(cksum "$CLAUDE_CONFIG_DIR/settings.json")"
out="$("$ROOT/install.sh" --hook 2>&1)"; [ $? -ne 0 ] && ok || fail "bad settings accepted"
lacks "$out" "hook added"
eq "$(cksum "$CLAUDE_CONFIG_DIR/settings.json")" "$before"
[ -z "$(find "$CLAUDE_CONFIG_DIR" -name 'settings.json.tmp.*')" ] && ok || fail "temp file left behind"

fresh "install --hook keeps a symlinked settings.json a symlink"
export CLAUDE_CONFIG_DIR="$TEST_HOME/claude"
mkdir -p "$CLAUDE_CONFIG_DIR" "$TEST_HOME/dotfiles"
echo '{"model":"x"}' > "$TEST_HOME/dotfiles/settings.json"
ln -s "$TEST_HOME/dotfiles/settings.json" "$CLAUDE_CONFIG_DIR/settings.json"
"$ROOT/install.sh" --hook >/dev/null
[ -L "$CLAUDE_CONFIG_DIR/settings.json" ] && ok || fail "symlink replaced by a file"
eq "$(jq '.hooks.SessionStart | length' "$TEST_HOME/dotfiles/settings.json")" "1"

fresh "install works with spaces and & in ATLAS_HOME, and the hook runs"
export ATLAS_HOME="$TEST_HOME/my home & co/.atlas" ATLAS_STATE="$TEST_HOME/my home & co/.atlas/state"
export CLAUDE_CONFIG_DIR="$TEST_HOME/claude"
"$ROOT/install.sh" --hook >/dev/null
has "$(cat "$CLAUDE_CONFIG_DIR/skills/wrap/SKILL.md")" "'$ATLAS_HOME'/bin/worklog.sh"
hookcmd="$(jq -r '.hooks.SessionStart[-1].hooks[0].command' "$CLAUDE_CONFIG_DIR/settings.json")"
has "$(env -u ATLAS_HOME -u ATLAS_STATE HOME="$TEST_HOME/nohome" sh -c "$hookcmd" 2>&1)" "## Open missions"
lacks "$("$ROOT/install.sh" 2>&1)" "skip skill"
unset CLAUDE_CONFIG_DIR

# ---------- review fixes ----------
fresh "mission decision rebuilds the dashboard"
"$BIN/mission.sh" add p "Decide things" >/dev/null
"$BIN/mission.sh" decision decide-things "Chose plain files" "No server to run" >/dev/null
has "$(cat "$ATLAS_HOME/dashboard/index.html")" "Chose plain files"

fresh "mission ids never end in a dash"
id="$("$BIN/mission.sh" add p "Thirty nine characters of title text ab cd")"
eq "${id%-}" "$id"

fresh "worklog add rejects an unquoted multi-word summary"
"$BIN/worklog.sh" add --project p fixed the bug >/dev/null 2>&1; eq "$?" "2"
[ ! -s "$ATLAS_STATE/worklog.jsonl" ] && ok || fail "partial summary written"

fresh "one corrupt worklog line doesn't hide the others"
with_example
echo '{"ts": 5, "broken' >> "$ATLAS_STATE/worklog.jsonl"
"$BIN/worklog.sh" add --project p "after the bad line" >/dev/null
out="$("$BIN/worklog.sh" recent 3)"
has "$out" "Docs sprint: pantry README"
has "$out" "after the bad line"

fresh "with only ATLAS_STATE set, the dashboard goes next to the state"
export ATLAS_HOME="$TEST_HOME/unused" ATLAS_STATE="$TEST_HOME/proj/state"
mkdir -p "$ATLAS_STATE"
"$BIN/mission.sh" add p "Where does it go" >/dev/null
[ -f "$TEST_HOME/proj/dashboard/index.html" ] && ok || fail "dashboard not next to state"
[ ! -e "$TEST_HOME/unused" ] && ok || fail "wrote under ATLAS_HOME"

# ---------- python ----------
CURRENT="python dashboard tests"
python3 -m unittest discover -s "$ROOT/tests" -p 'test_*.py' && ok || fail "unittest failed"

echo ""
echo "shell assertions: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
