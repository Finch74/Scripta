#!/bin/bash
# Builds the GTK 4 GUI `scripta-gtk` in release mode and packages it as a Fedora/RHEL .rpm
# in the project root: scripta-gtk-<version>-<release>.<dist>.<arch>.rpm
#
# Steps:
#   1. Swift (to build): if `swift` is not in PATH, installs it for the current user with swiftly.
#   2. Build dependencies: on an RPM-based system, missing gtk4-devel, webkitgtk6.0-devel or
#      poppler-glib-devel are installed with `sudo dnf install` (disable with INSTALL_DEPS=0).
#   3. Source tarball from the files tracked by git (working tree, so uncommitted edits are included).
#   4. rpmbuild -bb scripta-gtk.spec in a throwaway topdir (build/rpm), removed at the end.
#
# Variables: VERSION (default: CFBundleShortVersionString from Resources/Info.plist),
# INSTALL_DEPS=0 to skip the dnf step, NODEPS=1 to skip rpmbuild's BuildRequires check (automatic on
# systems without an RPM database, e.g. Debian/Ubuntu, where the -devel packages are named differently).
# Run it as a normal user, not with sudo: swiftly and the Swift build belong in your home directory.
set -euo pipefail
cd "$(dirname "$0")"

PKG="scripta-gtk"
SPEC="$PKG.spec"
BUILD_DEPS=(gtk4-devel webkitgtk6.0-devel poppler-glib-devel pkgconf-pkg-config gcc binutils)

[ "$(uname -s)" = "Linux" ] || { echo "package-rpm.sh va eseguito su Linux." >&2; exit 1; }
command -v rpmbuild >/dev/null || { echo "rpmbuild non trovato (sudo dnf install rpm-build)." >&2; exit 1; }
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
        curl -fsSLO https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz && \
        tar zxf swiftly-$(uname -m).tar.gz && \
        ./swiftly init --quiet-shell-followup --assume-yes
    )
    rm -rf "$dir"
    set +u; . "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"; set -u
    hash -r
    command -v swift >/dev/null || { echo "Installazione di Swift non riuscita." >&2; exit 1; }
}
ensure_swift
SWIFT="$(command -v swift)"
echo "Swift: $("$SWIFT" --version 2>&1 | head -n1)"

# --- 2. Build dependencies ---------------------------------------------------------------------------
RPMBUILD_OPTS=()
if [ "${NODEPS:-0}" = "1" ] || ! rpm -q rpm >/dev/null 2>&1; then
    # No RPM database (Debian/Ubuntu host): BuildRequires cannot be checked, the libraries are found
    # through pkg-config instead.
    pkg-config --exists gtk4 webkitgtk-6.0 poppler-glib || {
        echo "Librerie di sviluppo mancanti (gtk4, webkitgtk-6.0, poppler-glib)." >&2
        exit 1
    }
    RPMBUILD_OPTS+=(--nodeps)
else
    missing=()
    for p in "${BUILD_DEPS[@]}"; do
        rpm -q --whatprovides "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        if [ "${INSTALL_DEPS:-1}" = "1" ]; then
            echo "Installazione delle dipendenze di build: ${missing[*]}"
            sudo dnf install -y "${missing[@]}"
        else
            echo "Dipendenze mancanti: ${missing[*]} (sudo dnf install ${missing[*]})" >&2
            exit 1
        fi
    fi
fi

# --- 3. Source tarball -------------------------------------------------------------------------------
VERSION="${VERSION:-$(sed -n '/CFBundleShortVersionString/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' Resources/Info.plist)}"
VERSION="${VERSION:-1.0}"
TOPDIR="$PWD/build/rpm"
rm -rf "$TOPDIR"
mkdir -p "$TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Tracked files only (no .build/, no previous packages); the macOS-only parts and prebuilt
# packages are not needed to build on Linux.
git ls-files -z -- . ':!*.dmg' ':!*.deb' ':!*.rpm' ':!QuickLook' ':!Sources/ScriptaApp' \
    | tar --null -T - --transform "s,^,$PKG-$VERSION/," -czf "$TOPDIR/SOURCES/$PKG-$VERSION.tar.gz"
cp "$SPEC" "$TOPDIR/SPECS/"

# --- 4. rpmbuild -------------------------------------------------------------------------------------
echo "Compilazione di $PKG $VERSION (rpmbuild)..."
rpmbuild -bb "${RPMBUILD_OPTS[@]}" \
    --define "_topdir $TOPDIR" \
    --define "version_override $VERSION" \
    --define "swift $SWIFT" \
    "$TOPDIR/SPECS/$SPEC"

shopt -s nullglob
rpms=("$TOPDIR"/RPMS/*/"$PKG"-"$VERSION"-*.rpm)
[ ${#rpms[@]} -gt 0 ] || { echo "Nessun pacchetto prodotto." >&2; exit 1; }
for r in "${rpms[@]}"; do
    rm -f "./$(basename "$r")"
    mv "$r" .
    RPM="$(basename "$r")"
    echo "Creato $RPM ($(du -h "$RPM" | cut -f1))"
done
rm -rf "$TOPDIR"

command -v rpmlint >/dev/null && { rpmlint "$RPM" || true; }
echo "Installazione: sudo dnf install ./$RPM"
