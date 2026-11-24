#!/bin/zsh
# Builds the Fire tablet APK and the Matchbox Dashboard.app menu-bar app into ./build
#   ./scripts/build.sh            build both
#   ./scripts/build.sh --install  also copy Matchbox Dashboard.app to /Applications and launch it
#   UNIVERSAL=1 ./scripts/build.sh   Apple silicon + Intel binary (used for GitHub releases)
# (The Swift package, bundle ID, Android package and settings folder keep their original "Plinth" names.)
set -euo pipefail
ROOT="${0:A:h:h}"
OUT="$ROOT/build"
CACHE="$HOME/Library/Caches/Plinth"
mkdir -p "$OUT" "$CACHE"

echo "▸ Building Fire tablet app (APK)…"
# /Volumes/SSD is exFAT: macOS sprinkles ._ files that break Android resource merging, so build from a clean mirror.
rsync -a --delete --exclude '._*' --exclude '.gradle' --exclude 'build' "$ROOT/android/" "$CACHE/android/"
echo "sdk.dir=${ANDROID_HOME:-$HOME/Library/Android/sdk}" > "$CACHE/android/local.properties"
export JAVA_HOME="${JAVA_HOME_17:-/opt/homebrew/opt/openjdk@17}"
( cd "$CACHE/android" && ./gradlew --quiet --offline assembleDebug ) || ( cd "$CACHE/android" && ./gradlew --quiet assembleDebug )
rm -f "$OUT/Plinth.apk"
cp "$CACHE/android/app/build/outputs/apk/debug/app-debug.apk" "$OUT/MatchboxDashboard.apk"

echo "▸ Building Mac app…"
if [[ "${UNIVERSAL:-}" == 1 ]]; then   # release builds: one binary for Apple silicon and Intel
  ( cd "$ROOT/mac" && swift build -c release --arch arm64 --arch x86_64 --scratch-path "$CACHE/swift-universal" > "$CACHE/swift-build.log" 2>&1 ) || { grep -E "error" "$CACHE/swift-build.log" | head -20; echo "✗ Swift build failed (full log: $CACHE/swift-build.log)"; exit 1; }
  BIN="$CACHE/swift-universal/out/Products/Release/Plinth"
else
  ( cd "$ROOT/mac" && swift build -c release --scratch-path "$CACHE/swift" > "$CACHE/swift-build.log" 2>&1 ) || { grep -E "error" "$CACHE/swift-build.log" | head -20; echo "✗ Swift build failed (full log: $CACHE/swift-build.log)"; exit 1; }
  BIN="$CACHE/swift/release/Plinth"
fi
[[ -x "$BIN" ]] || { echo "Swift build failed"; exit 1; }

NAME="Matchbox Dashboard"
APP="$OUT/$NAME.app"
rm -rf "$APP" "$OUT/Plinth.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
rsync -a --exclude '._*' "$ROOT/web/" "$APP/Contents/Resources/web/"
cp "$OUT/MatchboxDashboard.apk" "$APP/Contents/Resources/MatchboxDashboard.apk"

ICONSET="$CACHE/AppIcon.iconset"
rm -rf "$ICONSET"
swift "$ROOT/scripts/make-icon.swift" "$ICONSET" 2>/dev/null && iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>com.plinth.mac</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>Matchbox Dashboard serves the info display to your Fire tablet on your local network.</string>
  <key>NSBonjourServices</key><array><string>_plinth._tcp</string></array>
</dict></plist>
PLIST
find "$APP" -name '._*' -delete 2>/dev/null || true
xattr -cr "$APP"
codesign --force --deep --sign - "$APP" >/dev/null
echo "✓ $APP"
echo "✓ $OUT/MatchboxDashboard.apk"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x "$NAME" 2>/dev/null || true
  # Retire the copy installed under the old name (moved to the Trash, not deleted).
  if [[ -d /Applications/Plinth.app ]]; then
    pkill -x Plinth 2>/dev/null || true; sleep 1
    mv /Applications/Plinth.app "$HOME/.Trash/Plinth $(date +%H%M%S).app"
  fi
  rm -rf "/Applications/$NAME.app" && cp -R "$APP" /Applications/
  open "/Applications/$NAME.app" --args --open-manager
  echo "✓ Installed to /Applications and launched"
fi
