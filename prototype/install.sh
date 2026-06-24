#!/bin/bash
# claude-dash installer: copy scripts to ~/.claude-dash and register the daemon
# with launchd so it auto-starts at login. Run manually after you've reviewed it.
#   bash install.sh          # install + start
#   bash install.sh uninstall
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude-dash"
PLIST_SRC="$SRC/com.claude-dash.daemon.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/com.claude-dash.daemon.plist"

if [ "${1:-}" = "uninstall" ]; then
  launchctl unload "$PLIST_DEST" 2>/dev/null || true
  rm -f "$PLIST_DEST"
  echo "uninstalled (scripts in $DEST left in place; rm -rf to remove)"
  exit 0
fi

mkdir -p "$DEST"
cp "$SRC/cdash.py" "$SRC/daemon.py" "$SRC/view.py" "$DEST/"
cp "$PLIST_SRC" "$PLIST_DEST"

launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"

echo "installed. daemon registered with launchd (auto-starts at login)."
echo "  view:   python3 $DEST/view.py"
echo "  log:    tail -f $DEST/daemon.log"
echo "  stop:   launchctl unload $PLIST_DEST"
