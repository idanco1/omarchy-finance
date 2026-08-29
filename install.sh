#!/usr/bin/env bash
# Install the idanco.finance plugin into the Omarchy shell on this machine.
set -euo pipefail

PLUGIN_ID="idanco.finance"
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
CONF_DIR="$HOME/.config/omarchy/finance"

# Copy (not symlink): the shell's file watcher and QML cache invalidation
# only track real files under ~/.config/omarchy/plugins/.
if [ -L "$DEST" ]; then rm "$DEST"; fi
mkdir -p "$DEST"
cp -f "$SRC/manifest.json" "$SRC/BarWidget.qml" "$SRC/Panel.qml" "$SRC/Model.js" "$DEST/"
mkdir -p "$DEST/bin"
cp -f "$SRC/bin/finance-fetch" "$DEST/bin/finance-fetch"
echo "Synced plugin files to $DEST"

mkdir -p "$CONF_DIR"
if [ ! -f "$CONF_DIR/config.json" ]; then
  cp "$SRC/config.example.json" "$CONF_DIR/config.json"
  chmod 600 "$CONF_DIR/config.json"
  echo "Created $CONF_DIR/config.json — add your IBKR Flex token + query id there."
fi

chmod +x "$SRC/bin/finance-fetch"

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
sleep 1
if omarchy plugin enable "$PLUGIN_ID" --yes >/dev/null 2>&1 \
   || omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1 \
   || omarchy-shell shell enablePlugin "$PLUGIN_ID" '{}' >/dev/null 2>&1; then
  echo "Plugin enabled. The pill appears in the bar (right section)."
else
  echo "Could not enable automatically; run: omarchy plugin enable $PLUGIN_ID"
fi

echo "Done. Open the popup by clicking the pill; middle-click refreshes IBKR positions."
