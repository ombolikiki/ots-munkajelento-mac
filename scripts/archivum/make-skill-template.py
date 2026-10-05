#!/usr/bin/env python3
"""ARCHIVÁLT (1.3.2 óta nem fut a buildben): a kollégai sablon ma már önálló forrás (skill-template/ots-adminisztracio), egységes skill van.
A szkript csak a sablon eredeti előállításának dokumentációja; futtatása felülírná a kézzel karbantartott sablont.

A személyes Claude skillből (~/.claude/skills/detkapu-adminisztracio) kollégáknak szánt sablont készít (a sablon neve: ots-adminisztracio, "OTS Adminisztráció").

A sablonban:
- a személyes adatok helyén helyőrzők vannak ({{FELHASZNALO_NEVE}}, {{SZEKHELY}}, {{GYULEKEZETEK}}, {{BONGESZO}}),
  az OTS-oldal helyén {{OTS_URL}} és {{OTS_NEV}} (DETKapu vagy TETKapu, a telepítő kérdezi),
  amelyeket az alkalmazás telepítő ablaka tölt ki;
- a feladatonkénti sorokat [[TASK:azonosító]] jelölők veszik körül (a telepítő a nem választott feladatok sorait törli);
- a {{#NÉV}}…{{/NÉV}} részek csak akkor maradnak meg, ha az adott adat meg van adva;
- a létszámjelentő feladatban nincs kitalált számokat előíró rész: a számok mindig a felhasználótól (vagy a trackerből) jönnek;
- a `tasks.json` a feladatok jegyzéke (a telepítő ebből dolgozik, a telepített skillbe nem kerül át).

Használat: scripts/make-skill-template.py [forrás] [cél]
A build.sh minden csomagoláskor lefuttatja, így a csomagba mindig a legfrissebb skill kerül.
"""
import json, os, re, shutil, sys

def _default_src():
    # a személyes skill lehet aktív (skills), vagy deaktiválva (skills-deaktivalt): a sablon mindkettőből elkészíthető
    for c in ("~/.claude/skills/detkapu-adminisztracio", "~/.claude/skills-deaktivalt/detkapu-adminisztracio"):
        if os.path.exists(os.path.join(os.path.expanduser(c), "SKILL.md")):
            return c
    return "~/.claude/skills/detkapu-adminisztracio"
SRC = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else _default_src())
DST = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "skill-template", "ots-adminisztracio")
DST = os.path.abspath(DST)

SZ, GY, NEV, BR = "{{SZEKHELY}}", "{{GYULEKEZETEK}}", "{{FELHASZNALO_NEVE}}", "{{BONGESZO}}"
OTS_URL, OTS_NEV = "{{OTS_URL}}", "{{OTS_NEV}}"
warnings = []

# A feladatok jegyzéke. `needs`: milyen adatot kér a telepítő; `files`: a feladat fájljai; `shared`: közös fájlok, ha a feladat kell.
TASKS = [
    {"id": "havi", "name": "Havi munkajelentő", "files": ["references/havi-munkajelento.md"],
     "shared": ["references/tracker-adatforras.md"], "needs": [], "label": "Havi munkajelentő:"},
    {"id": "koltseg", "name": "Költségelszámolás", "files": ["references/koltsegelszamolas.md"],
     "shared": ["references/tracker-adatforras.md"], "needs": ["home"], "label": "Költségelszámolás:"},
    {"id": "nevsor", "name": "Gyülekezeti névsor", "files": ["references/gyulekezeti-nevsor.md"],
     "shared": [], "needs": ["congregations"], "label": "Gyülekezeti névsor:"},
    {"id": "hittan", "name": "Hittan (hitoktatás)", "files": ["references/hitoktatas.md"],
     "shared": [], "needs": ["congregations"], "label": "Hitoktatás (Hittan):"},
    {"id": "latogatottsag", "name": "Gyülekezeti látogatottság", "files": ["references/latogatottsag.md"],
     "shared": ["references/tracker-adatforras.md"], "needs": ["congregations"], "label": "Gyülekezeti látogatottság:"},
]
FILE_TO_TASK = {f: t["id"] for t in TASKS for f in t["files"]}

def sub(text, old, new, name, count=1):
    if old not in text:
        warnings.append(f"{name}: nem található: {old[:70]!r}")
        return text
    return text.replace(old, new) if count == 0 else text.replace(old, new, count)

def between(text, start, end, new, name):
    a = text.find(start)
    b = text.find(end, a + 1) if a >= 0 else -1
    if a < 0 or b < 0:
        warnings.append(f"{name}: a szakasz nem található: {start[:50]!r}")
        return text
    return text[:a] + new + text[b:]

def skill_md(t):
    n = "SKILL.md"
    # név, cím, OTS-oldal (DETKapu vagy TETKapu: a telepítő tölti ki)
    t = sub(t, "name: detkapu-adminisztracio", "name: ots-adminisztracio", n)
    t = sub(t, "description: DETKAPU Adminisztráció - adminisztrációs feladatok az OTS 4.40 rendszerben (https://ots.detkapu.hu/, Hetednapi Adventista Egyház Dunamelléki Egyházterület).",
            f"description: OTS Adminisztráció - adminisztrációs feladatok az OTS 4.40 rendszerben ({OTS_URL}, Hetednapi Adventista Egyház, {OTS_NEV}).", n)
    t = sub(t, "vagy a DETKAPU felületén", f"vagy a {OTS_NEV} felületén", n)
    t = sub(t, "# DETKAPU Adminisztráció", "# OTS Adminisztráció", n)
    t = sub(t, "Az OTS 4.40 (https://ots.detkapu.hu/) webes rendszerben", f"Az OTS 4.40 ({OTS_URL}) webes rendszerben", n)
    t = sub(t, "1. Nyisd meg az OTS-t, és kérd meg", f"1. Nyisd meg az OTS-t ({OTS_URL}, {OTS_NEV}), és kérd meg", n)
    t = sub(t, "Győr, Tata, Tatabánya\")", GY + "\")", n)
    t = sub(t, "- Felhasználó: Ömböli Krisztián. Gyülekezetek: Győr, Tata, Tatabánya.",
            f"- Felhasználó: {NEV}.{{{{#GYULEKEZETEK}}}} Gyülekezetek: {GY}.{{{{/GYULEKEZETEK}}}}"
            f"{{{{#SZEKHELY}}}} Székhely (a költségelszámolás útvonalainak kiindulópontja): {SZ}.{{{{/SZEKHELY}}}}", n)
    t = sub(t, "- Böngészőként a beépített Claude böngészőpanelt használd (`mcp__Claude_Browser__*`).", f"- {BR}", n)
    out = []
    for line in t.split("\n"):
        task = None
        m = re.search(r"\(references/([\w\-]+\.md)\)", line)
        if line.startswith("|") and m:
            task = FILE_TO_TASK.get("references/" + m.group(1))
        else:
            for tk in TASKS:
                if line.startswith("- " + tk["label"]):
                    task = tk["id"]
        # a közös fájlra mutató táblázatsor/szakasz kezelése külön (nincs feladathoz kötve)
        out.append(f"[[TASK:{task}]]{line}[[/TASK]]" if task else line)
    t = "\n".join(out)
    # a közös adatforrás-szakasz csak akkor marad, ha valamelyik adatot használó feladat kell
    t = re.sub(r"(## Az OTS Munkajelentő Tracker adatai\n\n)(.*?)(\n\n## Bővítés)",
               lambda m: "[[SHARED:tracker]]" + m.group(1) + m.group(2) + "[[/SHARED]]" + m.group(3), t, flags=re.S)
    return t

def latogatottsag(t):
    n = "latogatottsag.md"
    t = sub(t, "mindhárom gyülekezetre (Győr, Tata, Tatabánya)", f"minden gyülekezetre ({GY})", n)
    t = sub(t, "- **Nincsenek valós adatok.** Csak körülbelüli számokat írunk be.",
            "- A létszámokat a felhasználó adja meg (lásd lent). Soha ne írj be kitalált vagy becsült számot.", n)
    t = sub(t, "írd be a 3 adatot.", "írd be a felhasználótól (vagy a trackerből) kapott 3 adatot.", n, 0)
    t = sub(t, "5. Az első néhány alkalommal kérdezz rá a felhasználónál, hogy az adatok megfelelőek-e. Később automatikusan lépj tovább.",
            "5. Mentés előtt mutasd meg a felhasználónak a beírt adatokat, és kérj megerősítést.", n)
    # tartalék működés (kitalált számok) helyett: kérdezz rá
    t = between(t, "## Létszámok gyülekezetek szerint (tartalék", "## Tudnivalók",
        "## Ha a trackerben nincs adat\n\nHa az adott dátumra és gyülekezetre nincs létszám a trackerben, **kérdezd meg a felhasználót** gyülekezetenként, dátumonként és szekciónként "
        "(Szombatiskola / Istentisztelet; gyermek / felnőtt adventista / felnőtt vendég), és várd meg a választ. **Soha ne írj be kitalált vagy becsült számot.**\n\n", n)
    t = sub(t, "- Ha az adott dátumra és gyülekezetre nincs sor a fájlban, használd az alábbi tartalék működést.",
            "- Ha az adott dátumra és gyülekezetre nincs sor a fájlban, kérdezd meg a felhasználót (lásd lent).", n)
    t = re.sub(r"- A Győr 2025\. I\. negyedéves lap volt[^\n]*\n", "", t)
    return t

def nevsor(t):
    n = "gyulekezeti-nevsor.md"
    t = sub(t, ": Győr, Tata, Tatabánya). TASK", ": gyülekezetenként egy-egy sor). TASK", n)
    t = sub(t, "2. Nyisd meg a **győri** névsort (duplakattintás a Győr sorra a Határidők oldalon).",
            f"2. Nyisd meg az első gyülekezet névsorát (a sorrend: {GY}; duplakattintás a sorra a Határidők oldalon).", n)
    t = re.sub(r"6\. Lépj a Határidők menüben a \*\*tatai\*\*[^\n]*\n",
               "6. Lépj a Határidők menüben a következő gyülekezet \"Gyülekezeti névsor\" feladatára, és végezd el ugyanezt a 3-5. lépésben, majd a többi gyülekezettel is.\n", t)
    t = sub(t, "- Sorrend: Győr, Tata, Tatabánya.", f"- Sorrend: {GY}.", n)
    t = sub(t, "(mindhárom névsor lezárva,", "(az összes névsor lezárva,", n)
    return t

def hitoktatas(t):
    n = "hitoktatas.md"
    t = sub(t, "Mindhárom gyülekezetre külön-külön", "Minden gyülekezetre külön-külön", n)
    t = sub(t, "2. Nyisd meg a **győri** Hittan sort (duplakattintás a Határidők oldalon).",
            f"2. Nyisd meg az első gyülekezet Hittan sorát (sorrend: {GY}; duplakattintás a Határidők oldalon).", n)
    t = re.sub(r"6\. Kezdd előről a feladatot a \*\*tatai\*\*[^\n]*\n",
               "6. Kezdd előről a feladatot a következő gyülekezet Hittan sorával (2-5. lépés), amíg minden gyülekezet sorra nem került.\n", t)
    t = sub(t, "- Sorrend: Győr, Tata, Tatabánya.", f"- Sorrend: {GY}.", n)
    t = sub(t, "(mindhárom gyülekezet Hittan lapja lezárva,", "(az összes gyülekezet Hittan lapja lezárva,", n)
    return t

def koltseg(t):
    n = "koltsegelszamolas.md"
    t = sub(t, "az autópálya használható; ha a felhasználó jelzi, hogy nincs autópálya-matricája, kerüld el",
            "az autópálya használható; ha a felhasználó jelzi, hogy nincs autópálya-matricája, kerüld el", n)
    t = t.replace("Tata - Tatabánya", "[A település] - [B település]")
    t = t.replace("Győrtől eltérő", "a székhelytől eltérő")
    t = re.sub(r"\bGyőrben\b", "a székhelyen", t)
    t = t.replace("Győr", SZ)
    return t

def havi(t):
    return t.replace("`Győr, Tata`", "`Település1, Település2`")

FILES = {
    "SKILL.md": skill_md,
    "references/latogatottsag.md": latogatottsag,
    "references/gyulekezeti-nevsor.md": nevsor,
    "references/hitoktatas.md": hitoktatas,
    "references/koltsegelszamolas.md": koltseg,
    "references/havi-munkajelento.md": havi,
}

if os.path.exists(DST):
    shutil.rmtree(DST)
for root, _, files in os.walk(SRC):
    for f in files:
        full = os.path.join(root, f)
        rel = os.path.relpath(full, SRC)
        out = os.path.join(DST, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        if f.startswith("."):
            continue
        text = open(full, encoding="utf-8").read()
        if rel in FILES:
            text = FILES[rel](text)
        open(out, "w", encoding="utf-8").write(text)

json.dump({"tasks": [{k: v for k, v in t.items() if k != "label"} for t in TASKS]},
          open(os.path.join(DST, "tasks.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)

# szivárgás-ellenőrzés: személyes adat nem maradhat a sablonban
leaks = []
for root, _, files in os.walk(DST):
    for f in files:
        text = open(os.path.join(root, f), encoding="utf-8").read()
        for bad in ("Ömböli", "Krisztián", "Győr", "Tatabánya", "Tata,", "Oláh", "Sáfrány", "Toggl", "toggl", "Claude_Browser", "ots.detkapu.hu", "DETKAPU", "detkapu-adminisztracio"):
            for m in re.finditer(re.escape(bad), text):
                leaks.append(f"{os.path.relpath(os.path.join(root, f), DST)}: {bad} ...{text[max(0, m.start()-30):m.end()+30]!r}")
# a jelölők kiegyensúlyozottsága
for root, _, files in os.walk(DST):
    for f in files:
        if f.endswith(".md"):
            text = open(os.path.join(root, f), encoding="utf-8").read()
            for tag in ("TASK", "SHARED"):
                if len(re.findall(rf"\[\[{tag}:", text)) != len(re.findall(rf"\[\[/{tag}\]\]", text)):
                    warnings.append(f"{f}: kiegyensúlyozatlan {tag} jelölők")
for w in warnings:
    print("FIGYELEM:", w)
for l in leaks:
    print("SZIVÁRGÁS:", l)
if leaks:
    sys.exit(1)
print(f"sablon kész: {DST} ({sum(len(fs) for _, _, fs in os.walk(DST))} fájl, {len(warnings)} figyelmeztetés)")
