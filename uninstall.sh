#!/usr/bin/env bash
# Removes the login agent, the hooks, and the installed binary.
set -euo pipefail

BIN="$HOME/.local/bin/sticky-tasks"
SETTINGS="$HOME/.claude/settings.json"
PLIST="$HOME/Library/LaunchAgents/com.sticky.agenttasks.plist"

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
pkill -f "$BIN" 2>/dev/null || true
rm -f "$BIN"

if [ -f "$SETTINGS" ]; then
  python3 - "$SETTINGS" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)
for event in list(cfg.get("hooks", {})):
    entries = cfg["hooks"][event]
    for e in entries:
        e.get("hooks", [])[:] = [h for h in e.get("hooks", []) if "sticky-tasks record" not in h.get("command", "")]
    cfg["hooks"][event] = [e for e in entries if e.get("hooks")]
    if not cfg["hooks"][event]:
        del cfg["hooks"][event]
if cfg.get("hooks") == {}:
    del cfg["hooks"]
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
PY
fi
echo "✓ Uninstalled Sticky Agent Tasks."
