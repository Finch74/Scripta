#!/bin/bash
# Builds the GTK 4 GUI `scripta-gtk` (ScriptaCore + Sources/ScriptaGTK) in release mode for Linux and
# packages it into build/Scripta-GUI-Linux-<arch>.tar.gz, with the .desktop file, the icon,
# install.sh and Examples/. With APPIMAGE=1 it also creates build/Scripta-GUI-<arch>.AppImage.
#
# On Linux it uses the local Swift toolchain and GTK 4 development files (libgtk-4-dev / gtk4-devel).
# On any other system (e.g. macOS) it builds inside a Docker image for linux/amd64: the official Swift
# image plus libgtk-4-dev, built once and cached as scripta-gtk-builder:<tag>.
# The Swift runtime and Foundation are linked statically; GTK 4 is linked dynamically and must be
# installed on the target system (it is not bundled, not even in the AppImage).
#
# Variables: SWIFT_IMAGE (default swift:6.0-noble; WebKitGTK 6.0 needs Ubuntu 24.04+), USE_DOCKER=1 to force Docker on Linux too,
# APPIMAGE=1 to build the AppImage, APPIMAGETOOL=<path> to use a local appimagetool (Linux without Docker).
set -euo pipefail
cd "$(dirname "$0")"

SWIFT_IMAGE="${SWIFT_IMAGE:-swift:6.0-noble}"
# Separate scratch path, so this build never mixes with the macOS one (.build/) or the CLI one (.build-linux/).
SCRATCH=".build-linux-gui"
BUILD_CMD="swift build -c release --product scripta-gtk --static-swift-stdlib --scratch-path $SCRATCH"
ID="io.github.finch74.Scripta"

if [ "$(uname -s)" = "Linux" ] && [ "${USE_DOCKER:-0}" != "1" ]; then
    ARCH="$(uname -m)"
    pkg-config --exists gtk4 webkitgtk-6.0 poppler-glib 2>/dev/null || {
        echo "Dipendenze non trovate: installa libgtk-4-dev libwebkitgtk-6.0-dev libpoppler-glib-dev (Debian/Ubuntu)" >&2
        echo "o gtk4-devel webkitgtk6.0-devel poppler-glib-devel (Fedora), più pkg-config." >&2
        exit 1
    }
    run_linux() { bash -c "$1"; }
else
    command -v docker >/dev/null || { echo "Docker è necessario per compilare per Linux da $(uname -s)." >&2; exit 1; }
    ARCH="x86_64"
    BUILDER_IMAGE="scripta-gtk-builder:$(echo "$SWIFT_IMAGE" | tr ':/' '--')"
    echo "Preparazione dell'immagine $BUILDER_IMAGE..."
    docker build --quiet --platform linux/amd64 --build-arg SWIFT_IMAGE="$SWIFT_IMAGE" -t "$BUILDER_IMAGE" - >/dev/null <<'EOF'
ARG SWIFT_IMAGE
FROM ${SWIFT_IMAGE}
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libgtk-4-dev libwebkitgtk-6.0-dev libpoppler-glib-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*
EOF
    run_linux() { docker run --rm --platform linux/amd64 -v "$PWD":/src -w /src "$BUILDER_IMAGE" bash -c "$1"; }
fi

echo "Compilazione di scripta-gtk ($ARCH)..."
run_linux "$BUILD_CMD"

BIN="$SCRATCH/release/scripta-gtk"
NAME="Scripta-GUI-Linux-$ARCH"
STAGING="build/$NAME"
ARCHIVE="build/$NAME.tar.gz"

rm -rf "$STAGING" "$ARCHIVE"
mkdir -p "$STAGING"
install -m 755 "$BIN" "$STAGING/scripta-gtk"
install -m 755 Resources/Linux/install.sh "$STAGING/install.sh"
install -m 644 "Resources/Linux/$ID.desktop" "Resources/Linux/$ID.png" "$STAGING/"
cp -R Examples "$STAGING/Examples"

# COPYFILE_DISABLE keeps macOS tar from adding ._ metadata files.
COPYFILE_DISABLE=1 tar -czf "$ARCHIVE" -C build "$NAME"
echo "Creato $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"

if [ "${APPIMAGE:-0}" = "1" ]; then
    APPDIR="build/$NAME.AppDir"
    APPIMAGE_FILE="build/Scripta-GUI-$ARCH.AppImage"
    rm -rf "$APPDIR" "$APPIMAGE_FILE"
    # Like `install -Dm`, which BSD install (macOS) lacks.
    put() { mkdir -p "$(dirname "$3")" && install -m "$1" "$2" "$3"; }
    put 755 Resources/Linux/AppRun "$APPDIR/AppRun"
    put 755 "$BIN" "$APPDIR/usr/bin/scripta-gtk"
    put 644 "Resources/Linux/$ID.desktop" "$APPDIR/usr/share/applications/$ID.desktop"
    put 644 "Resources/Linux/$ID.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/$ID.png"
    cp "Resources/Linux/$ID.desktop" "Resources/Linux/$ID.png" "$APPDIR/"
    ln -s "$ID.png" "$APPDIR/.DirIcon"

    TOOL="${APPIMAGETOOL:-}"
    if [ -z "$TOOL" ]; then
        TOOL="$SCRATCH/appimagetool-$ARCH.AppImage"
        if [ ! -x "$TOOL" ]; then
            echo "Download di appimagetool..."
            curl -fsSL -o "$TOOL" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage"
            chmod 755 "$TOOL"
        fi
    fi
    # Extract-and-run: no FUSE needed (Docker containers usually lack it).
    run_linux "APPIMAGE_EXTRACT_AND_RUN=1 ARCH=$ARCH '$TOOL' --no-appstream '$APPDIR' '$APPIMAGE_FILE'"
    rm -rf "$APPDIR"
    echo "Creato $APPIMAGE_FILE ($(du -h "$APPIMAGE_FILE" | cut -f1))"
fi

rm -rf "$STAGING"
