#!/bin/bash
# A web/ mappa tartalmát a GitHub Pages tárolóba (alapból ~/Developer/ots-munkajelento) másolja, commitol és feltölti.
# Használat: ./scripts/publish-web.sh ["commit üzenet"]
# A tároló az iCloudon kívül van (a .git mappa iCloud Driveban sérülhet). Előbb a webes tesztek futnak, hiba esetén megáll.
set -euo pipefail
cd "$(dirname "$0")/.."
DEPLOY="${DEPLOY_DIR:-$HOME/Developer/ots-munkajelento}"
[ -d "$DEPLOY/.git" ] || { echo "Nincs meg a közzétételi tároló ($DEPLOY). Előbb hozd létre (lásd web/README.md)."; exit 1; }
echo "→ A skill csomag frissítése a sablonból"
python3 scripts/sync-web-skill.py
echo "→ Webes tesztek"
(cd web && node --test test/*.test.js >/dev/null) || { echo "A webes tesztek hibásak, nem töltök fel semmit."; exit 1; }
echo "→ Másolás ($DEPLOY)"
rsync -a --delete --exclude='.git' --exclude='.DS_Store' web/ "$DEPLOY/"
cd "$DEPLOY"
git add -A
if git diff --cached --quiet; then echo "Nincs változás, nincs mit feltölteni."; exit 0; fi
git commit -q -m "${1:-Frissítés}"
git push -q
echo "Kész. A GitHub Pages néhány percen belül frissül."
