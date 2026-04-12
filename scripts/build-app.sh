#!/usr/bin/env bash
# Baut Nomen im Release-Modus und packt das Binary in eine .app unter dist/.
#
# App-Icon: Resources/AppIcon.iconset → iconutil → AppIcon.icns (im Repo versioniert).
#
# Optional (Umgebungsvariablen):
#   NOMEN_BUNDLE_ID   — CFBundleIdentifier (Standard: app.nomen)
#   NOMEN_VERSION     — CFBundleShortVersionString (Standard: 1.0)
#   NOMEN_BUILD       — CFBundleVersion (Standard: 1)
#   NOMEN_OUT         — Ausgabeordner ohne .app (Standard: <Repo>/dist)
#
# Alle Argumente werden an `swift build` durchgereicht, z. B.:
#   ./scripts/build-app.sh --arch arm64

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Nomen"
BUNDLE_ID="${NOMEN_BUNDLE_ID:-app.nomen}"
SHORT_VERSION="${NOMEN_VERSION:-1.0}"
BUILD_NUMBER="${NOMEN_BUILD:-1}"
OUT_DIR="${NOMEN_OUT:-$ROOT/dist}"
APP_PATH="$OUT_DIR/${APP_NAME}.app"

echo "→ swift build -c release …"
swift build -c release "$@"

BIN_DIR="$(swift build -c release --show-bin-path)"
EXEC_SOURCE="$BIN_DIR/$APP_NAME"

if [[ ! -f "$EXEC_SOURCE" ]]; then
	echo "Binary nicht gefunden: $EXEC_SOURCE" >&2
	exit 1
fi

echo "→ App-Bundle: $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$EXEC_SOURCE" "$APP_PATH/Contents/MacOS/$APP_NAME"
chmod +x "$APP_PATH/Contents/MacOS/$APP_NAME"

# llama.cpp (LlamaSwift): Binary verlinkt @rpath/llama.framework — ohne Kopie startet die App nicht.
LLAMA_FW_SRC="$BIN_DIR/llama.framework"
if [[ -d "$LLAMA_FW_SRC" ]]; then
	echo "→ llama.framework → Contents/Frameworks/ …"
	mkdir -p "$APP_PATH/Contents/Frameworks"
	rm -rf "$APP_PATH/Contents/Frameworks/llama.framework"
	cp -R "$LLAMA_FW_SRC" "$APP_PATH/Contents/Frameworks/"
	EXEC_DEST="$APP_PATH/Contents/MacOS/$APP_NAME"
	if ! otool -l "$EXEC_DEST" | grep -q "@executable_path/../Frameworks"; then
		install_name_tool -add_rpath @executable_path/../Frameworks "$EXEC_DEST"
	fi
	# Nach install_name_tool ggf. Signatur erneuern (lokal / Ad-hoc).
	if command -v codesign >/dev/null 2>&1; then
		codesign --force --deep -s - "$APP_PATH/Contents/Frameworks/llama.framework" 2>/dev/null || true
		codesign --force -s - "$EXEC_DEST" 2>/dev/null || true
	fi
else
	echo "Hinweis: Kein llama.framework unter $BIN_DIR — LlamaSwift-Binary?" >&2
fi

BUNDLE_ICONSET="$ROOT/Resources/AppIcon.iconset"
HAVE_ICNS=0

if [[ -f "$BUNDLE_ICONSET/Contents.json" ]]; then
	echo "→ AppIcon.icns aus Resources/AppIcon.iconset (iconutil) …"
	iconutil -c icns "$BUNDLE_ICONSET" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
	HAVE_ICNS=1
else
	echo "Fehlt: $BUNDLE_ICONSET — bitte AppIcon.iconset ins Repo unter Resources/ legen." >&2
fi

ICON_PLIST_EXTRA=""
if [[ "$HAVE_ICNS" -eq 1 && -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]]; then
	ICON_PLIST_EXTRA='	<key>CFBundleIconFile</key>
	<string>AppIcon</string>'
fi

cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>de</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${SHORT_VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_NUMBER}</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
${ICON_PLIST_EXTRA}
</dict>
</plist>
EOF

plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null
touch "$APP_PATH"

echo "Fertig. Starten mit: open \"$APP_PATH\""
