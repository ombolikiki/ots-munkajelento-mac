#!/bin/bash
# Elkészíti a terjeszthető alkalmazást: dist/OTS Munkajelentő Tracker.app és .zip
# Használat: ./scripts/build.sh            (ad-hoc aláírás, ingyenes)
#            SIGN_ID="Developer ID Application: Név (TEAMID)" ./scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="OTS Munkajelentő Tracker"
EXE="OTSMunkajelentoTracker"
BUNDLE_ID="hu.detkapu.ots-munkajelento-tracker"
VERSION="${VERSION:-1.5.4}"
DIST="dist"
# Az iCloud-os (Dokumentumok) mappa fájlattribútumokat tesz a csomagra, ami elrontja az aláírást,
# ezért ideiglenes mappában állítjuk össze és írjuk alá.
STAGE="$(mktemp -d)"
APP="$STAGE/$APP_NAME.app"

if [ -z "${SKIP_TESTS:-}" ]; then
  echo "→ Önellenőrző tesztek (több időzónában)"
  ./scripts/selftest.sh
fi

echo "→ Fordítás (Apple Silicon + Intel)"
# Az Xcode nélküli (Command Line Tools) környezetben nincs univerzális build,
# ezért a két architektúrát külön fordítjuk, és lipo-val egyesítjük.
for ARCH in arm64 x86_64; do
  swift build -c release --triple "$ARCH-apple-macosx14.0" --build-path ".build-$ARCH"
done
mkdir -p "$DIST"
BIN="$STAGE/$EXE-universal"
lipo -create ".build-arm64/arm64-apple-macosx/release/$EXE" ".build-x86_64/x86_64-apple-macosx/release/$EXE" -output "$BIN"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXE"
rm -f "$BIN"

echo "→ Skill (OTS Adminisztráció): a sablon ellenőrzése, csomagolás"
python3 scripts/check-skill-template.py
mkdir -p "$APP/Contents/Resources/skill"
ditto --norsrc --noextattr "skill-template/ots-adminisztracio" "$APP/Contents/Resources/skill/ots-adminisztracio"

echo "→ Használati útmutató"
python3 docs/build-guide.py "$VERSION" "docs/Használati útmutató.html"
mkdir -p "$APP/Contents/Resources/guide"
cp "docs/Használati útmutató.html" "$APP/Contents/Resources/guide/utmutato.html"
python3 docs/build-guide.py "$VERSION" "docs/Antigravity CLI útmutató.html" ANTIGRAVITY_CLI_UTMUTATO.md "Ingyenes MI-asszisztens az OTS kitöltéséhez: Antigravity CLI"
cp "docs/Antigravity CLI útmutató.html" "$APP/Contents/Resources/guide/antigravity.html"

echo "→ Ikon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
if swift scripts/make-icon.swift "$ICONSET" && iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"; then
  ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
  echo "  (az ikon nem készült el, ikon nélkül folytatom)"; ICON_KEY=""
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Az alkalmazás csak olvassa a kiválasztott naptáraid lezajlott eseményeit, hogy a munkajelentő bejegyzéseit átvegye belőlük. A naptárba nem ír.</string>
  $ICON_KEY
</dict></plist>
PLIST

xattr -cr "$APP"
echo "→ Aláírás (${SIGN_ID:-ad-hoc})"
codesign --force --deep --options runtime --entitlements scripts/OTS.entitlements --sign "${SIGN_ID:--}" "$APP"
codesign --verify --deep --strict "$APP" && echo "  aláírás rendben"

echo "→ Zip"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
rm -rf "$DIST/$APP_NAME.app" "$ZIP"
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$ZIP"
echo "Kész: $ZIP"

# Használati útmutató PDF (ha van Chrome); hiba esetén csak figyelmeztetés
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
GUIDE_PDF="$DIST/OTS Munkajelentő Tracker - Használati útmutató $VERSION.pdf"
if [ -x "$CHROME" ] && command -v timeout >/dev/null; then
  PROFILE="$(mktemp -d)"
  timeout 90 "$CHROME" --headless=new --disable-gpu --no-first-run --user-data-dir="$PROFILE" --no-pdf-header-footer \
    --virtual-time-budget=8000 --print-to-pdf="$PWD/$GUIDE_PDF" "file://$PWD/docs/Használati útmutató.html" >/dev/null 2>&1 || true
  pkill -f "$PROFILE" 2>/dev/null || true
  AGY_PDF="$DIST/OTS Munkajelentő Tracker - Antigravity CLI útmutató.pdf"
  PROFILE2="$(mktemp -d)"
  timeout 90 "$CHROME" --headless=new --disable-gpu --no-first-run --user-data-dir="$PROFILE2" --no-pdf-header-footer \
    --virtual-time-budget=8000 --print-to-pdf="$PWD/$AGY_PDF" "file://$PWD/docs/Antigravity CLI útmutató.html" >/dev/null 2>&1 || true
  pkill -f "$PROFILE2" 2>/dev/null || true
  [ -s "$AGY_PDF" ] && echo "Kész: $AGY_PDF"
  [ -s "$GUIDE_PDF" ] && echo "Kész: $GUIDE_PDF" || echo "(a PDF útmutató nem készült el)"
else
  echo "(nincs Chrome vagy timeout: a PDF útmutató kimarad, a HTML a docs/ mappában van)"
fi
echo "(Kipróbáláshoz: bontsd ki a zip-et, vagy másold ki az .app-ot: $APP)"
