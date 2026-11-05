#!/bin/bash
# Builds Scripta.app (arm64, release) into ./build using Swift Package Manager,
# plus the Quick Look preview extension (Contents/PlugIns/ScriptaQuickLook.appex).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG" --arch arm64 --product ScriptaApp

# Il prodotto ScriptaApp (Package.swift) diventa l'eseguibile Scripta del bundle.
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/ScriptaApp"
APP="build/Scripta.app"
APPEX="$APP/Contents/PlugIns/ScriptaQuickLook.appex"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Scripta"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Quick Look extension: compila attingendo dai nuovi moduli ScriptaCore e ScriptaApp
OPT=$([ "$CONFIG" = "release" ] && echo "-O" || echo "-Onone")
swiftc $OPT -swift-version 6 -parse-as-library -module-name ScriptaQuickLook \
    -target arm64-apple-macos15.0 \
    Sources/ScriptaCore/Parsing/*.swift \
    Sources/ScriptaApp/Export/ContentTypes.swift \
    Sources/ScriptaApp/Export/ExportOptions.swift \
    Sources/ScriptaApp/Export/ExportTemplates.swift \
    Sources/ScriptaApp/Export/HTMLRenderer.swift \
    QuickLook/PreviewProvider.swift \
    -framework QuickLookUI \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$APPEX/Contents/MacOS/ScriptaQuickLook"
cp QuickLook/Info.plist "$APPEX/Contents/Info.plist"

plutil -lint "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist" >/dev/null
# Sign inside-out: the (sandboxed) extension first, then the app.
codesign --force --sign - --timestamp=none --entitlements QuickLook/QuickLook.entitlements "$APPEX"
codesign --force --sign - --timestamp=none "$APP"

# Register the app (document types, exported UTI) and its Quick Look extension.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
pluginkit -a "$APPEX" >/dev/null 2>&1 || true

echo "Creato $APP con successo!"
