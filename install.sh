#!/usr/bin/env bash
# Installs Sticky Agent Tasks: builds the binary, registers Claude Code hooks so
# every prompt/turn shows up as a note, and sets it to launch at login.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/sticky-tasks"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
PLIST="$HOME/Library/LaunchAgents/com.sticky.agenttasks.plist"

echo "› Building release binary…"
( cd "$ROOT" && swift build -c release >/dev/null )
mkdir -p "$BIN_DIR"
cp -f "$ROOT/.build/release/StickyTasks" "$BIN"
echo "  installed $BIN"

echo "› Registering Claude Code hooks in $SETTINGS …"
mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
BIN="$BIN" python3 - "$SETTINGS" <<'PY'
import json, os, sys
path = sys.argv[1]
binp = os.environ["BIN"]
with open(path) as f:
    cfg = json.load(f)
hooks = cfg.setdefault("hooks", {})

def ensure(event, arg):
    cmd = f'"{binp}" record --event {arg}'
    entries = hooks.setdefault(event, [])
    # Drop any prior sticky-tasks entry so re-running is idempotent.
    for e in entries:
        e.get("hooks", [])[:] = [h for h in e.get("hooks", []) if "sticky-tasks record" not in h.get("command", "")]
    entries[:] = [e for e in entries if e.get("hooks")]
    entries.append({"hooks": [{"type": "command", "command": cmd}]})

ensure("UserPromptSubmit", "start")
ensure("Stop", "stop")
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
print("  hooks updated")
PY

echo "› Installing login agent $PLIST …"
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.sticky.agenttasks</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
PLISTEOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo
echo "✓ Done. The panel is running now and will relaunch at login."
echo "  New prompts in any Claude Code session will appear on the right edge."
echo "  Uninstall: ./uninstall.sh"
