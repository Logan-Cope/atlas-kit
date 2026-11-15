#!/usr/bin/env bash
# install.sh: put atlas-kit's scripts in $ATLAS_HOME and its skills in ~/.claude/skills.
#
#   ./install.sh            install, start with empty state, print the hook to add
#   ./install.sh --hook     also add the SessionStart hook to ~/.claude/settings.json (backed up first)
#   ./install.sh --example  start with the example state instead of empty state
#   ./install.sh --force    overwrite skills with the same names
#
# ATLAS_HOME (default ~/.atlas) and CLAUDE_CONFIG_DIR (default ~/.claude) are honored.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATLAS_HOME="${ATLAS_HOME:-$HOME/.atlas}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
hook=0 example=0 force=0
for arg in "$@"; do
  case "$arg" in
    --hook) hook=1 ;;
    --example) example=1 ;;
    --force) force=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "install: unknown option $arg" >&2; exit 2 ;;
  esac
done

for tool in jq python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "install: $tool is required" >&2; exit 1; }
done

# 1. Scripts
mkdir -p "$ATLAS_HOME/bin" "$ATLAS_HOME/state" "$ATLAS_HOME/dashboard"
cp "$SRC"/bin/*.sh "$SRC"/bin/*.py "$ATLAS_HOME/bin/"
chmod +x "$ATLAS_HOME"/bin/*

# 2. State: never touch state that already exists.
if [ ! -f "$ATLAS_HOME/state/missions.json" ]; then
  if [ "$example" = 1 ]; then
    cp -R "$SRC/examples/state/." "$ATLAS_HOME/state/"
  else
    printf '{"updated":"","missions":[]}\n' > "$ATLAS_HOME/state/missions.json"
  fi
fi
mkdir -p "$ATLAS_HOME/state/fleet"

# 3. Skills. They name ~/.atlas; point them at ATLAS_HOME if it lives elsewhere.
mkdir -p "$CLAUDE_DIR/skills"
for dir in "$SRC"/skills/*/; do
  name="$(basename "$dir")"
  dest="$CLAUDE_DIR/skills/$name"
  if [ -e "$dest" ] && [ "$force" = 0 ] && ! diff -rq "$dir" "$dest" >/dev/null 2>&1; then
    echo "skip skill $name: $dest exists (use --force to overwrite)"
    continue
  fi
  mkdir -p "$dest"
  if [ "$ATLAS_HOME" = "$HOME/.atlas" ]; then
    cp "$dir/SKILL.md" "$dest/SKILL.md"
  else
    sed "s#~/\.atlas#$ATLAS_HOME#g" "$dir/SKILL.md" > "$dest/SKILL.md"
  fi
  echo "skill /$name -> $dest"
done

# 4. Dashboard
python3 "$ATLAS_HOME/bin/build-dashboard.py" --state "$ATLAS_HOME/state" \
  --out "$ATLAS_HOME/dashboard/index.html" >/dev/null

# 5. SessionStart hook
cmd="$ATLAS_HOME/bin/session-start.sh"
if [ "$hook" = 1 ]; then
  settings="$CLAUDE_DIR/settings.json"
  [ -f "$settings" ] || echo '{}' > "$settings"
  cp "$settings" "$settings.bak.$(date +%Y%m%d%H%M%S)"
  tmp="$(mktemp "$settings.tmp.XXXXXX")"
  # Idempotent: drop any earlier copy of this hook, then add it once.
  jq --arg cmd "$cmd" '
    .hooks.SessionStart = (
      ((.hooks.SessionStart // []) | map(select(([.hooks[]?.command] | index($cmd)) | not)))
      + [{hooks: [{type: "command", command: $cmd}]}]
    )' "$settings" > "$tmp" && mv "$tmp" "$settings"
  echo "hook added to $settings (backup saved next to it)"
else
  echo ""
  echo "Add this to $CLAUDE_DIR/settings.json, or re-run with --hook:"
  jq -n --arg cmd "$cmd" '{hooks: {SessionStart: [{hooks: [{type: "command", command: $cmd}]}]}}'
fi

echo ""
echo "Installed to $ATLAS_HOME. Dashboard: $ATLAS_HOME/dashboard/index.html"
