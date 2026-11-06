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

# --- Gestione Icona (.png -> .icns) ---
if [ -f "icon_scripta.png" ]; then
    ICONSET="build/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    
    # Genera le varie dimensioni richieste da macOS per l'iconset
    sips -z 16 16     icon_scripta.png --out "$ICONSET/icon_16x16.png" >/dev/null 2>&1
    sips -z 32 32     icon_scripta.png --out "$ICONSET/icon_16x16@2x.png" >/dev/null 2>&1
    sips -z 32 32     icon_scripta.png --out "$ICONSET/icon_32x32.png" >/dev/null 2>&1
    sips -z 64 64     icon_scripta.png --out "$ICONSET/icon_32x32@2x.png" >/dev/null 2>&1
    sips -z 128 128   icon_scripta.png --out "$ICONSET/icon_128x128.png" >/dev/null 2>&1
    sips -z 256 256   icon_scripta.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null 2>&1
    sips -z 256 256   icon_scripta.png --out "$ICONSET/icon_256x256.png" >/dev/null 2>&1
    sips -z 512 512   icon_scripta.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null 2>&1
    sips -z 512 512   icon_scripta.png --out "$ICONSET/icon_512x512.png" >/dev/null 2>&1
    sips -z 1024 1024 icon_scripta.png --out "$ICONSET/icon_512x512@2x.png" >/dev/null 2>&1

    # Compila la cartella iconset in un file .icns
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
fi

# Quick Look extension: compila attingendo dai nuovi moduli ScriptaCore e ScriptaApp
OPT=$([ "$CONFIG" = "release" ] && echo "-O" || echo "-Onone")
swiftc $OPT -swift-version 6 -parse-as-library -module-name ScriptaQuickLook \
    -target arm64-apple-macos15.0 \
    Sources/ScriptaCore/Parsing/*.swift \
    Sources/ScriptaCore/Export/*.swift \
    Sources/ScriptaApp/Export/ContentTypes.swift \
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

echo "Creato $APP con successo e icona integrata!"
