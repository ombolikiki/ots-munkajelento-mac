#!/bin/bash
# Fejlesztői ellenőrzés: elindítja a fejlesztői (debug) alkalmazást, és képpé rajzolja a menüsori elemet (kattintás és kisegítő
# hozzáférés nélkül), 40 mintával a szélességéről. Így mérhető, hogy a menüsori számláló (idő) ugrál-e.
# A valódi adatokhoz nem nyúl: ideiglenes adatmappa (OTS_SUPPORT_DIR, OTS_HOME), a csomagolt skill csak olvasva.
# Használat: ./scripts/status-item-dump.sh [eltelt másodperc a számlálón, alapból 754]
# Kimenet: a mappa kiírva (status.txt: a minták, status-1.png: a menüsori elem képe).
# Megjegyzés: a futás rövid időre egy ikont tesz a menüsorodba.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
swift build >/dev/null
WORK="$(mktemp -d)"
mkdir -p "$WORK/support" "$WORK/home"
NOW="$(date +%s)"
defaults write OTSMunkajelentoTracker timer.start -float "$((NOW - ${1:-754}))"
OTS_SUPPORT_DIR="$WORK/support" OTS_HOME="$WORK/home" OTS_SKILL_SOURCE="$ROOT/skill-template/ots-adminisztracio" \
  OTS_DUMP_STATUS_ITEM="$WORK/status" OTS_DUMP_DELAY=13 timeout 60 .build/debug/OTSMunkajelentoTracker >"$WORK/out.log" 2>&1 || true
defaults delete OTSMunkajelentoTracker timer.start
echo "Mappa: $WORK"
grep -E "^gomb|^különböző" "$WORK/status.txt" || cat "$WORK/status.txt"
