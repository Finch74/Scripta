#!/bin/bash
# Builds the `scripta` CLI in release mode for Linux and packages it, together with Examples/,
# into build/Scripta-Linux-<arch>.zip.
#
# On Linux it uses the local Swift toolchain. On any other system (e.g. macOS) it builds inside
# the official Swift Docker image for linux/amd64, producing Scripta-Linux-x86_64.zip.
# The Swift runtime and Foundation are linked statically, so the binary needs no Swift install.
#
# Variables: SWIFT_IMAGE (default swift:6.0), USE_DOCKER=1 to force Docker on Linux too.
set -euo pipefail
cd "$(dirname "$0")"

SWIFT_IMAGE="${SWIFT_IMAGE:-swift:6.0}"
# Separate scratch path, so the Linux build never mixes with the macOS one in .build/.
SCRATCH=".build-linux"
BUILD_CMD="swift build -c release --product scripta --static-swift-stdlib --scratch-path $SCRATCH"

if [ "$(uname -s)" = "Linux" ] && [ "${USE_DOCKER:-0}" != "1" ]; then
    ARCH="$(uname -m)"
    $BUILD_CMD
else
    command -v docker >/dev/null || { echo "Docker è necessario per compilare per Linux da $(uname -s)." >&2; exit 1; }
    ARCH="x86_64"
    docker run --rm --platform linux/amd64 -v "$PWD":/src -w /src "$SWIFT_IMAGE" $BUILD_CMD
fi

BIN="$SCRATCH/release/scripta"
NAME="Scripta-Linux-$ARCH"
STAGING="build/$NAME"
ZIP="build/$NAME.zip"

rm -rf "$STAGING" "$ZIP"
mkdir -p "$STAGING"
cp "$BIN" "$STAGING/scripta"
chmod 755 "$STAGING/scripta"
cp -R Examples "$STAGING/Examples"

command -v zip >/dev/null || { echo "Il comando 'zip' non è installato (es. sudo apt install zip)." >&2; exit 1; }
(cd build && zip -qr -X "$NAME.zip" "$NAME")
rm -rf "$STAGING"

echo "Creato $ZIP ($(du -h "$ZIP" | cut -f1))"
