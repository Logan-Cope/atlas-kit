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

# 2. State: never overwrite a state file that already exists.
if [ ! -f "$ATLAS_HOME/state/missions.json" ]; then
  if [ "$example" = 1 ]; then
    (cd "$SRC/examples/state" && find . -type f) | while IFS= read -r f; do
      [ -e "$ATLAS_HOME/state/$f" ] && continue
      mkdir -p "$(dirname "$ATLAS_HOME/state/$f")"
      cp "$SRC/examples/state/$f" "$ATLAS_HOME/state/$f"
    done
  else
    printf '{"updated":"","missions":[]}\n' > "$ATLAS_HOME/state/missions.json"
  fi
fi
mkdir -p "$ATLAS_HOME/state/fleet"

# shell-quoted, so a path with spaces or & still works as a command
shq() { python3 -c 'import shlex, sys; print(shlex.quote(sys.argv[1]))' "$1"; }

# 3. Skills. They name ~/.atlas; point them at ATLAS_HOME if it lives elsewhere.
mkdir -p "$CLAUDE_DIR/skills"
for dir in "$SRC"/skills/*/; do
  name="$(basename "$dir")"
  dest="$CLAUDE_DIR/skills/$name"
  rendered="$(mktemp)"
  if [ "$ATLAS_HOME" = "$HOME/.atlas" ]; then
    cp "$dir/SKILL.md" "$rendered"
  else
    python3 -c 'import sys; s, o, h = sys.argv[1:]; open(o, "w").write(open(s).read().replace("~/.atlas", h))' \
      "$dir/SKILL.md" "$rendered" "$(shq "$ATLAS_HOME")"
  fi
  if [ -e "$dest" ] && [ "$force" = 0 ] && ! cmp -s "$rendered" "$dest/SKILL.md"; then
    echo "skip skill $name: $dest exists (use --force to overwrite)"
    rm -f "$rendered"
    continue
  fi
  mkdir -p "$dest"
  mv "$rendered" "$dest/SKILL.md"
  chmod 644 "$dest/SKILL.md"
  echo "skill /$name -> $dest"
done

# 4. Dashboard
python3 "$ATLAS_HOME/bin/build-dashboard.py" --state "$ATLAS_HOME/state" \
  --out "$ATLAS_HOME/dashboard/index.html" >/dev/null

# 5. SessionStart hook
cmd="$(shq "$ATLAS_HOME/bin/session-start.sh")"
if [ "$hook" = 1 ]; then
  settings="$CLAUDE_DIR/settings.json"
  [ -e "$settings" ] || echo '{}' > "$settings"
  jq empty "$settings" 2>/dev/null || {
    echo "install: $settings is not valid JSON; hook not added. Add it by hand:" >&2
    jq -n --arg cmd "$cmd" '{hooks: {SessionStart: [{hooks: [{type: "command", command: $cmd}]}]}}' >&2
    exit 1
  }
  cp "$settings" "$settings.bak.$(date +%Y%m%d%H%M%S)"
  tmp="$(mktemp)"
  # Idempotent: drop any earlier copy of this hook, then add it once.
  jq --arg cmd "$cmd" '
    .hooks.SessionStart = (
      ((.hooks.SessionStart // []) | map(select(([.hooks[]?.command] | index($cmd)) | not)))
      + [{hooks: [{type: "command", command: $cmd}]}]
    )' "$settings" > "$tmp" || { rm -f "$tmp"; echo "install: jq failed; $settings unchanged" >&2; exit 1; }
  # Write through the file rather than replacing it, so a symlinked
  # settings.json (dotfiles) stays a symlink and keeps its permissions.
  cat "$tmp" > "$settings"
  rm -f "$tmp"
  echo "hook added to $settings (backup saved next to it)"
else
  echo ""
  echo "Add this to $CLAUDE_DIR/settings.json, or re-run with --hook:"
  jq -n --arg cmd "$cmd" '{hooks: {SessionStart: [{hooks: [{type: "command", command: $cmd}]}]}}'
fi

echo ""
echo "Installed to $ATLAS_HOME. Dashboard: $ATLAS_HOME/dashboard/index.html"
