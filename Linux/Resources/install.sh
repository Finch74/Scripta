#!/bin/sh
# Installs Scripta (GTK) for the current user, or system-wide with PREFIX=/usr/local (as root).
#   ./install.sh               install into ~/.local
#   ./install.sh --uninstall   remove it again
set -eu
cd "$(dirname "$0")"

PREFIX="${PREFIX:-$HOME/.local}"
ID="io.github.finch74.Scripta"
BIN="$PREFIX/bin/scripta-gtk"
DESKTOP="$PREFIX/share/applications/$ID.desktop"
ICON="$PREFIX/share/icons/hicolor/256x256/apps/$ID.png"

if [ "${1:-}" = "--uninstall" ]; then
    rm -f "$BIN" "$DESKTOP" "$ICON"
    echo "Scripta rimosso da $PREFIX"
else
    install -Dm755 scripta-gtk "$BIN"
    install -Dm644 "$ID.png" "$ICON"
    # Absolute Exec path, so the launcher works even if $PREFIX/bin is not in PATH.
    mkdir -p "$(dirname "$DESKTOP")"
    sed "s|^Exec=scripta-gtk|Exec=$BIN|" "$ID.desktop" > "$DESKTOP"
    chmod 644 "$DESKTOP"
    echo "Scripta installato in $PREFIX (eseguibile: $BIN)"
fi

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$PREFIX/share/applications" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -qtf "$PREFIX/share/icons/hicolor" || true
