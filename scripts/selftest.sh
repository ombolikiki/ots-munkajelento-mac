#!/bin/bash
# Önellenőrző tesztek futtatása (Xcode nélkül). Több időzónában is lefut.
# Használat: ./scripts/selftest.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Sources/t" "$WORK/support" "$WORK/home"
# a skill-sablon ellenőrzése (ez az egyetlen, közös skill-forrás; kézzel karbantartott)
python3 scripts/check-skill-template.py >/dev/null || { echo "A skill-sablon ellenőrzése hibás:"; python3 scripts/check-skill-template.py; exit 1; }
cp Sources/OTSMunkajelentoTracker/*.swift "$WORK/Sources/t/"
sed -i '' 's/^@main//' "$WORK/Sources/t/App.swift"
cp Tests/SelfTest/main.swift "$WORK/Sources/t/main.swift"
cat > "$WORK/Package.swift" <<'PKG'
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "t", platforms: [.macOS(.v14)], targets: [.executableTarget(name: "t", path: "Sources/t")])
PKG
(cd "$WORK" && swift build 2>&1 | grep -E "error|warning: unre" || true)
FAIL=0
for TZNAME in Europe/Budapest America/New_York Pacific/Auckland UTC; do
  echo "=== Időzóna: $TZNAME"
  if ! (cd "$WORK" && OTS_NO_HEIGHT_CLAMP=1 OTS_SUPPORT_DIR="$WORK/support" OTS_HOME="$WORK/home" OTS_SKILL_SOURCE="$ROOT/skill-template/ots-adminisztracio" TZ="$TZNAME" ./.build/debug/t); then FAIL=1; fi
done
# Kisebb és nagyobb kijelzők szimulálása (látható magasság pontban). A tesztek a végső magasságkorlát nélkül futnak
# (OTS_NO_HEIGHT_CLAMP), így a becslések pontosságát mérik: az ablak ezeken sem nőhet a képernyőnél magasabbra.
for VH in 700 800 860 1000 1300; do
  echo "=== Kijelző látható magassága: $VH pont"
  if ! (cd "$WORK" && OTS_NO_HEIGHT_CLAMP=1 OTS_VISIBLE_HEIGHT="$VH" OTS_SUPPORT_DIR="$WORK/support" OTS_HOME="$WORK/home" OTS_SKILL_SOURCE="$ROOT/skill-template/ots-adminisztracio" TZ="Europe/Budapest" ./.build/debug/t); then FAIL=1; fi
done
if [ "$FAIL" -ne 0 ]; then echo "A TESZTEK HIBÁSAK"; exit 1; fi
echo "Minden teszt rendben."
