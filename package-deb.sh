#!/bin/bash
# Builds the GTK 4 GUI `scripta-gtk` in release mode and packages it as a Debian/Ubuntu .deb
# in the project root: scripta-gtk_<version>-<revision>_<arch>.deb
#
# Steps:
#   1. Swift (to build): if `swift` is not in PATH, installs it for the current user with swiftly.
#   2. Build dependencies: if libgtk-4-dev, libwebkitgtk-6.0-dev or libpoppler-glib-dev are missing,
#      installs them with `sudo apt-get install` (disable with INSTALL_DEPS=0).
#   3. `swift build -c release --product scripta-gtk --static-swift-stdlib`.
#   4. Stages /usr/bin/scripta-gtk, the .desktop file and the icon from Resources/Linux/, the MIT license
#      and the examples, writes DEBIAN/control (Depends: the three -dev packages) and DEBIAN/postinst,
#      which installs Swift with swiftly if it is missing, then builds the .deb.
#
# Variables: VERSION (default: CFBundleShortVersionString from Resources/Info.plist), REVISION (default 1),
# MAINTAINER (default: git user.name <user.email>), INSTALL_DEPS=0 to skip the apt-get step.
# Run it as a normal user, not with sudo: swiftly and the Swift build belong in your home directory.
set -euo pipefail
cd "$(dirname "$0")"

ID="io.github.finch74.Scripta"
PKG="scripta-gtk"
BUILD_DEPS=(libgtk-4-dev libwebkitgtk-6.0-dev libpoppler-glib-dev pkg-config)
DEPENDS="libgtk-4-dev, libwebkitgtk-6.0-dev, libpoppler-glib-dev"

[ "$(uname -s)" = "Linux" ] || { echo "package-deb.sh va eseguito su Linux (Debian/Ubuntu)." >&2; exit 1; }
command -v dpkg-deb >/dev/null || { echo "dpkg-deb non trovato: serve un sistema Debian/Ubuntu." >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || echo "Attenzione: eseguito come root, swiftly verrebbe installato in /root." >&2

# The About dialog shows the license embedded in License.swift: it must match LICENSE exactly.
diff -q <(sed '1,/^let licenseText = """$/d; /^"""$/,$d' Sources/ScriptaGTK/License.swift) LICENSE >/dev/null || {
    echo "Sources/ScriptaGTK/License.swift non corrisponde a LICENSE: aggiornalo prima di creare il pacchetto." >&2
    exit 1
}

# --- 1. Swift ----------------------------------------------------------------------------------------
ensure_swift() {
    # A previous swiftly install may simply not be in this shell's PATH yet.
    local env_sh="${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
    if ! command -v swift >/dev/null && [ -f "$env_sh" ]; then
        set +u; . "$env_sh"; set -u
        hash -r
    fi
    command -v swift >/dev/null && return

    echo "Swift non trovato: installazione con swiftly..."
    local dir
    dir="$(mktemp -d)"
    (
        cd "$dir"
        curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz && \
        tar zxf swiftly-$(uname -m).tar.gz && \
        ./swiftly init --quiet-shell-followup
    )
    rm -rf "$dir"
    # Sourced here, not in the subshell above, so `swift` is in PATH for the rest of this script.
    set +u; . "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"; set -u
    hash -r
    command -v swift >/dev/null || { echo "Installazione di Swift non riuscita." >&2; exit 1; }
}
ensure_swift
echo "Swift: $(swift --version 2>&1 | head -n1)"

# --- 2. Build dependencies ---------------------------------------------------------------------------
missing=()
for p in "${BUILD_DEPS[@]}"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || missing+=("$p")
done
if [ ${#missing[@]} -gt 0 ]; then
    if [ "${INSTALL_DEPS:-1}" = "1" ]; then
        echo "Installazione delle dipendenze di compilazione: ${missing[*]}"
        SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
        $SUDO apt-get update
        $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
    else
        echo "Dipendenze mancanti: ${missing[*]} (sudo apt install ${missing[*]})" >&2
        exit 1
    fi
fi

# --- 3. Release build --------------------------------------------------------------------------------
echo "Compilazione di $PKG (release)..."
# --static-swift-stdlib: the binary must not depend on the Swift runtime of this build machine
# (a swiftly toolchain lives in ~/.local/share/swiftly, a path that does not exist on other systems).
swift build -c release --product "$PKG" --static-swift-stdlib
BIN="$(swift build -c release --show-bin-path)/$PKG"

# --- 4. .deb layout ----------------------------------------------------------------------------------
VERSION="${VERSION:-$(sed -n '/CFBundleShortVersionString/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' Resources/Info.plist)}"
VERSION="${VERSION:-1.0}"
REVISION="${REVISION:-1}"
ARCH="$(dpkg --print-architecture)"
if [ -z "${MAINTAINER:-}" ]; then
    MAINTAINER="$(git config user.name 2>/dev/null || echo Finch74) <$(git config user.email 2>/dev/null || echo noreply@github.com)>"
fi

ROOT="build/deb/${PKG}_${VERSION}-${REVISION}_${ARCH}"
DEB="${PKG}_${VERSION}-${REVISION}_${ARCH}.deb"
DOC="$ROOT/usr/share/doc/$PKG"
rm -rf "$ROOT" "$DEB"

install -Dm755 "$BIN" "$ROOT/usr/bin/$PKG"
strip --strip-unneeded "$ROOT/usr/bin/$PKG"
# Exec=scripta-gtk resolves through PATH, and /usr/bin is always in it: the .desktop is used as is.
install -Dm644 "Resources/Linux/$ID.desktop" "$ROOT/usr/share/applications/$ID.desktop"
install -Dm644 "Resources/Linux/$ID.png" "$ROOT/usr/share/icons/hicolor/256x256/apps/$ID.png"
install -d "$DOC/examples"
install -m644 Examples/* "$DOC/examples/"
install -m644 LICENSE "$DOC/LICENSE"

# Machine-readable copyright file; "Expat" is Debian's name for the MIT license. The license text is
# taken from LICENSE (without its title and copyright lines) and indented as the format requires.
{
    printf '%s\n' \
        "Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/" \
        "Upstream-Name: Scripta" \
        "Source: https://github.com/Finch74/Scripta" \
        "" \
        "Files: *" \
        "Copyright: 2026 Finch74" \
        "License: Expat" \
        ""  \
        "License: Expat"
    sed '1,/^Copyright/d' LICENSE | sed '1{/^$/d;}' | sed 's/^$/./; s/^/ /'
} > "$DOC/copyright"
printf '%s (%s-%s) unstable; urgency=medium\n\n  * Release %s.\n\n -- %s  %s\n' \
    "$PKG" "$VERSION" "$REVISION" "$VERSION" "$MAINTAINER" "$(date -R)" | gzip -9n > "$DOC/changelog.Debian.gz"
chmod 644 "$DOC/copyright" "$DOC/changelog.Debian.gz"

install -d "$ROOT/DEBIAN"
cat > "$ROOT/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION-$REVISION
Architecture: $ARCH
Maintainer: $MAINTAINER
Installed-Size: $(du -sk --exclude=DEBIAN "$ROOT" | cut -f1)
Depends: $DEPENDS
Section: editors
Priority: optional
Homepage: https://github.com/Finch74/Scripta
Description: Editor di sceneggiature (Fountain), prosa (Markdown) e fumetti
 Scripta è un editor di scrittura per sceneggiature in formato Fountain,
 prosa in Markdown e script per fumetti e graphic novel, con evidenziazione,
 outline navigabile, analisi dei personaggi, statistiche ed esportazione PDF.
 .
 Interfaccia grafica nativa GTK 4. Software libero con licenza MIT.
EOF

# postinst: installs Swift with swiftly if it is missing. dpkg runs it as root, so the install is done
# for the user who ran `sudo apt`/`sudo dpkg` (SUDO_USER) or the graphical installer (PKEXEC_UID),
# in their home; with neither, for root. `runuser -l` gives that user's HOME and login profile, so a
# previous swiftly install is found. A failure (e.g. no network) is only reported, never fatal: it must
# not leave the package half-configured. Desktop database and icon cache are refreshed by dpkg triggers.
cat > "$ROOT/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e

if [ "$1" = "configure" ]; then
    TARGET_USER="root"
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        TARGET_USER="$SUDO_USER"
    elif [ -n "${PKEXEC_UID:-}" ]; then
        TARGET_USER="$(getent passwd "$PKEXEC_UID" | cut -d: -f1)"
    fi

    if runuser -l "$TARGET_USER" -c 'command -v swift >/dev/null 2>&1 || [ -x "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/bin/swift" ]'; then
        echo "scripta-gtk: Swift già presente per l'utente $TARGET_USER."
    elif ! command -v curl >/dev/null 2>&1; then
        echo "scripta-gtk: Swift non trovato e curl non installato. Installa curl, poi Swift (https://www.swift.org/install/)." >&2
    else
        echo "scripta-gtk: Swift non trovato, installazione con swiftly per l'utente $TARGET_USER..."
        if runuser -l "$TARGET_USER" -c '
            dir="$(mktemp -d)" && cd "$dir" || exit 1
            curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz && \
            tar zxf swiftly-$(uname -m).tar.gz && \
            ./swiftly init --quiet-shell-followup && \
            . "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" && \
            hash -r
            status=$?
            cd / && rm -rf "$dir"
            exit $status
        '; then
            echo "scripta-gtk: Swift installato. Apri un nuovo terminale per averlo nel PATH."
        else
            echo "scripta-gtk: installazione di Swift non riuscita. Installalo da https://www.swift.org/install/" >&2
        fi
    fi
fi

exit 0
POSTINST
chmod 755 "$ROOT/DEBIAN/postinst"

dpkg-deb --build --root-owner-group -Zxz "$ROOT" "$DEB"
rm -rf "build/deb"
echo "Creato $DEB ($(du -h "$DEB" | cut -f1))"
command -v lintian >/dev/null && { lintian --tag-display-limit 0 "$DEB" || true; }
echo "Installazione: sudo apt install ./$DEB"
