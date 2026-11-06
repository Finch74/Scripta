# RPM spec for ScriptaGTK, the GTK 4 front end of Scripta.
# Build it with ./package-rpm.sh, which creates the source tarball and passes the version.
#
# Swift is not a BuildRequires: on most systems it comes from swiftly (in the user's home), not from
# an RPM, so rpmbuild could not see it. %%build uses `swift` from PATH, or the path in %%{swift}
# (rpmbuild --define "swift /path/to/swift").

%{!?version_override: %global version_override 1.0}
%{!?swift: %global swift swift}

# The Swift toolchain produces no usable debuginfo for find-debuginfo; build-id links of a single
# static-stdlib binary would only cause conflicts.
%global debug_package %{nil}
%global _build_id_links none

%global app_id io.github.finch74.Scripta

Name:           scripta-gtk
Version:        %{version_override}
Release:        1%{?dist}
Summary:        Editor di sceneggiature (Fountain), prosa (Markdown) e fumetti
License:        MIT
URL:            https://github.com/Finch74/Scripta
Source0:        %{name}-%{version}.tar.gz

ExclusiveArch:  x86_64 aarch64

BuildRequires:  gtk4-devel
BuildRequires:  webkitgtk6.0-devel
BuildRequires:  poppler-glib-devel
BuildRequires:  pkgconf-pkg-config
BuildRequires:  gcc
BuildRequires:  binutils

# The shared-library Requires are generated automatically from the binary; these make them explicit.
Requires:       gtk4
Requires:       webkitgtk6.0
Requires:       poppler-glib
Requires:       hicolor-icon-theme

%description
Scripta è un editor di scrittura per sceneggiature in formato Fountain,
prosa in Markdown e script per fumetti e graphic novel, con evidenziazione,
outline navigabile, analisi dei personaggi, statistiche ed esportazione PDF.

Interfaccia grafica nativa GTK 4. Software libero con licenza MIT.

%prep
%autosetup -n %{name}-%{version}

%build
command -v %{swift} >/dev/null || {
    echo "Swift non trovato: installalo (https://www.swift.org/install/) o usa --define 'swift /percorso/swift'." >&2
    exit 1
}
# --static-swift-stdlib: the binary must not depend on the Swift runtime of the build machine
# (a swiftly toolchain lives in ~/.local/share/swiftly, a path that does not exist on other systems).
%{swift} build -c release --product %{name} --static-swift-stdlib -j %{_smp_build_ncpus}

%install
BIN="$(%{swift} build -c release --show-bin-path)/%{name}"
install -Dm755 "$BIN" %{buildroot}%{_bindir}/%{name}
strip --strip-unneeded %{buildroot}%{_bindir}/%{name}
# Exec=scripta-gtk resolves through PATH, and /usr/bin is always in it: the .desktop is used as is.
install -Dm644 Resources/Linux/%{app_id}.desktop %{buildroot}%{_datadir}/applications/%{app_id}.desktop
install -Dm644 Resources/Linux/%{app_id}.png %{buildroot}%{_datadir}/icons/hicolor/256x256/apps/%{app_id}.png

%check
command -v desktop-file-validate >/dev/null && \
    desktop-file-validate %{buildroot}%{_datadir}/applications/%{app_id}.desktop || :

# Installs Swift with swiftly if it is missing. rpm runs this as root, so the install is done for the
# user who ran `sudo dnf`/`sudo rpm` (SUDO_USER) or the graphical installer (PKEXEC_UID), in their home;
# with neither, for root. `runuser -l` gives that user's HOME and login profile, so a previous swiftly
# install is found. A failure (e.g. no network) is only reported, never fatal: a failing %%post would
# leave the transaction in error. Desktop database and icon cache are refreshed by Fedora's file triggers.
%post
TARGET_USER="root"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    TARGET_USER="$SUDO_USER"
elif [ -n "${PKEXEC_UID:-}" ]; then
    TARGET_USER="$(getent passwd "$PKEXEC_UID" | cut -d: -f1)"
fi

if ! command -v runuser >/dev/null 2>&1; then
    echo "scripta-gtk: runuser non disponibile, controllo di Swift saltato." >&2
elif runuser -l "$TARGET_USER" -c 'command -v swift >/dev/null 2>&1 || [ -x "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/bin/swift" ]'; then
    echo "scripta-gtk: Swift già presente per l'utente $TARGET_USER."
elif ! command -v curl >/dev/null 2>&1; then
    echo "scripta-gtk: Swift non trovato e curl non installato. Installa curl, poi Swift (https://www.swift.org/install/)." >&2
else
    echo "scripta-gtk: Swift non trovato, installazione con swiftly per l'utente $TARGET_USER..."
    if runuser -l "$TARGET_USER" -c '
        dir="$(mktemp -d)" && cd "$dir" || exit 1
        curl -fsSLO https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz && \
        tar zxf swiftly-$(uname -m).tar.gz && \
        ./swiftly init --quiet-shell-followup --assume-yes
        status=$?
        cd / && rm -rf "$dir"
        exit $status
    '; then
        echo "scripta-gtk: Swift installato. Apri un nuovo terminale per averlo nel PATH."
    else
        echo "scripta-gtk: installazione di Swift non riuscita. Installalo da https://www.swift.org/install/" >&2
    fi
fi
exit 0

%files
%license LICENSE
%doc README.md Examples
%{_bindir}/%{name}
%{_datadir}/applications/%{app_id}.desktop
%{_datadir}/icons/hicolor/256x256/apps/%{app_id}.png

%changelog
* Fri Nov 06 2026 Finch74 <noreply@github.com> - 1.0-1
- Primo pacchetto RPM di ScriptaGTK.
