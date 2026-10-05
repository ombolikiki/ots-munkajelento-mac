#!/bin/bash
# Képernyőképek készítése a használati útmutatóhoz (kitalált példaadatokkal, a valódi adatokat nem érinti).
# Használat: ./scripts/screenshots.sh   (kimenet: docs/kepek-uj, majd a szükséges képeket át kell másolni a docs/kepek mappába)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Sources/t" "$WORK/support" "$WORK/home/.claude"
python3 scripts/check-skill-template.py >/dev/null
cp Sources/OTSMunkajelentoTracker/*.swift "$WORK/Sources/t/"
sed -i '' 's/^@main//' "$WORK/Sources/t/App.swift"
cp Tests/Screenshots/main.swift "$WORK/Sources/t/main.swift"
cat > "$WORK/Package.swift" <<'PKG'
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "t", platforms: [.macOS(.v14)], targets: [.executableTarget(name: "t", path: "Sources/t")])
PKG
(cd "$WORK" && swift build 2>&1 | grep -E "error" || true)
mkdir -p docs/kepek-uj
(cd "$WORK" && OTS_SUPPORT_DIR="$WORK/support" OTS_HOME="/Users/felhasznalo" OTS_SKILL_SOURCE="$ROOT/skill-template/ots-adminisztracio" OTS_SHOTS_OUT="$ROOT/docs/kepek-uj" ./.build/debug/t)
