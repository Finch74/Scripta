#!/bin/bash
# Builds the `scripta` CLI (ScriptaCore + Sources/ScriptaCLI) with Swift Package Manager.
# Works on Linux and macOS; the GUI target (Sources/ScriptaApp) is macOS-only and not built here.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
echo "Compilazione di scripta ($CONFIG)..."
swift build -c "$CONFIG" --product scripta

BIN="$(swift build -c "$CONFIG" --show-bin-path)/scripta"
echo "Build completata con successo!"
echo "Eseguibile disponibile in: $BIN"
