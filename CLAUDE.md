# OTS Munkajelentő Tracker – fejlesztési szabályok

Menüsori Mac-alkalmazás (SwiftUI, Swift Package, Xcode nélkül). Magyarul kommunikálj a felhasználóval.

## Kötelező szabályok

1. **A dátumszámítás nem omolhat össze.** Minden `Calendar`/`Date` művelet védett legyen: nincs `!` kényszerített kicsomagolás a `Calendar`/`Date` visszatérési értékein, hibás eredménynél biztonságos tartalékra kell váltani. Kezelni kell az évhatárt, a negyedévhatárt, a szökőnapot és a nyári időszámítást. Új dátum-alapú funkcióhoz (szombatok, negyedévek, kitöltetlen napok, hét kezdőnapja, 8 órás jelzés) egységteszt kell, 2024–2035 között, minden negyedévre.
2. **Az ablak magassága sosem nőhet a képernyőnél nagyobbra**, és nincs méretváltoztató animáció (ez összeomlást okozott, lásd az 1.1.2-es javítást). A menüsori ablak természetes magasságú, a hosszú részek rögzített magasságú görgethető területet kapnak. A leválasztott ablak rögzített méretű és görgethető. Ne tegyél ScrollView-t az egész menüsori tartalom köré (az ablakot csíkká zsugorítja).
3. **Szám- és CSV-olvasás:** sosem omolhat össze hibás bemenettől (`inf`, `1e99` stb.). A hibás sorokat kihagyja, és mentés előtt másolatot készít a fájlról.
4. **A tesztek nem érinthetik a valódi adatokat.** Teszteléskor mindig állítsd be: `OTS_SUPPORT_DIR` (alkalmazásadat-mappa), `OTS_HOME` (a felhasználó könyvtára, ide kerülnek a skillek), `OTS_SKILL_SOURCE` (skill-forrás), és a `dataFile` UserDefaults-kulcsot ideiglenes mappára. Különben a futás átírja a felhasználó `beallitasok.json` és adatfájljait.
5. **Mielőtt bármit leveszel a gépről:** `rm -rf` csak szó szerinti elérési úttal fusson, változó nélkül.

## Build és kiadás

- `./scripts/selftest.sh` az önellenőrző tesztek (Xcode nélkül, több időzónában: Budapest, New York, Auckland, UTC). A `build.sh` automatikusan lefuttatja, hiba esetén megáll (kihagyás: `SKIP_TESTS=1`). Új logikához (dátum, összesítés, CSV, telepítő) írj tesztet a `Tests/SelfTest/main.swift` fájlba.
- `./scripts/screenshots.sh` az útmutató képernyőképeit készíti kitalált példaadatokkal (`docs/kepek-uj`); a tesztekhez hasonlóan nem érinti a valódi adatokat.
- `./scripts/build.sh` építi az aláírt (ad-hoc), univerzális (arm64 + x86_64) csomagot a `dist/` mappába (zip + PDF útmutató). A verzió alapértéke a `scripts/build.sh` `VERSION` sora; kiadáskor emeld, és írd be a `README.md`-be.
- **Egyetlen, közös skill van**: az „OTS Adminisztráció” (`ots-adminisztracio`). A forrása a `skill-template/ots-adminisztracio` mappa, ezt kézzel kell karbantartani (jelölők: `[[TASK:id]]`, `[[SHARED:tracker]]`, `{{#KEY}}`; helyőrzők: `{{FELHASZNALO_NEVE}}`, `{{SZEKHELY}}`, `{{GYULEKEZETEK}}`, `{{BONGESZO}}`, `{{OTS_URL}}`, `{{OTS_NEV}}`). A felhasználó és a kollégák ugyanezt telepítik az alkalmazás telepítő varázslójával; a felhasználó a telepített példányból dolgozik (`~/.claude/skills/ots-adminisztracio`), nincs külön személyes skill. Skill-módosítás a sablonban történik (nem a telepített másolatban), utána újra kell építeni az alkalmazást. A `scripts/check-skill-template.py` a build és a tesztek előtt ellenőrzi, hogy nincs benne személyes adat vagy régi név. A korábbi személyes skill (`~/.claude/skills-deaktivalt/detkapu-adminisztracio`) csak archívum, és a `scripts/archivum/make-skill-template.py` sem fut többé (futtatása felülírná a sablont).
- **Skill-frissítés:** az app a csomagolt skill lenyomatát a telepített skill jelölőfájljával (`.ots-tracker-install.json`) veti össze (`SkillInstaller.refresh`); elavultnál fejléc-ikon + értesítés + Beállítások › Skill gomb, és `SkillInstaller.updateOutdated()` a jelölőfájlban tárolt beállításokkal újratelepít (másolat a régiről). Ezért a jelölőfájl formátumát (`targets`, `tasks`, `values`) ne változtasd visszafelé nem kompatibilisen. Skill-módosításnál (a sablonban) elég újraépíteni az appot: a lenyomat megváltozik, és a felhasználóknál megjelenik a frissítés-jelzés.
- **Menüsori elem (számláló) ellenőrzése:** a `./scripts/status-item-dump.sh` elindítja a fejlesztői alkalmazást, és képpé rajzolja a menüsori elemet, valamint 40 mintát ír a szélességéről (`OTS_DUMP_STATUS_ITEM`, lásd `StatusItemDump.swift`). Tanulság (mérve): a SwiftUI `MenuBarExtra` címkéje **egy képre és egy szövegre** bomlik, a szöveget mindig a rendszer arányos számjegyű betűtípusával adja át (a `font` és a `monospacedDigit` módosítót eldobja; a szélesség másodpercenként 73–76 pont között ugrált), második kép nem fér a címkébe, és a gomb címét utólag a rendszer visszaállítja. Ezért idő látszik esetén a címke **egyetlen kép** (`MenuBarClock.make`: ikon és idő együtt, szélességazonos számjegyekkel). Ne térj vissza `Text`-hez a menüsori időnél.
- **Beállítások (1.5.4-től):** öt fül (`SettingsTab`); új kártyát a megfelelő fül `tabContent` ágába tedd. A fülsor a menüsori ablakban a görgethető terület **fölött** áll (rögzített). A menüsori ablak bezárásakor a Beállítások visszaáll a rögzítő oldalra (`menuHiddenCount`). **Javaslatok:** a javaslatlista a mező alatt, a tartalomra rátakarva jelenik meg (overlay), ezért nem növeli az ablak magasságát; a kattintás a mező területén kívül is működik (tesztelve). Új szövegmezőnél használd a `SuggestTextField`-et.
- A használati útmutató forrása `docs/HASZNALATI_UTMUTATO.md` (képek: `docs/kepek`), a build ebből készít HTML-t és PDF-et.
- A Mac-ablakot nem lehet innen kattintással kipróbálni (nincs kisegítő hozzáférés): logikát tesztprogrammal, kinézetet képpé renderelve ellenőrizz, és mondd ki, mit nem láttál élesben.

## Üzleti szabályok (ne változtasd kérés nélkül)

- A Tevékenység csak az Utazásnál kötelező, máshol opcionális. A Költségelszámolás Tevékenysége kizárólag az Utazás bejegyzésekből jön (az app kézi felvitel ablakában és a skillben is).
- Utazás (1.5.0-tól): két mező, **Kiindulás** (egy hely) és **Cél** (egy vagy több hely, vesszővel; mindegyik lehet `Település` vagy `Település, utca házszám`). Az **Oda-vissza** pipa alapból bejelölt (a munka után visszatértem a Kiindulásra): útvonal `Kiindulás - Cél(ek) - Kiindulás`; kikapcsolva egyirányú: `Kiindulás - Cél(ek)`. A **Munkahely** választógomb jelöli, hogy a Kiindulás vagy a Cél (alapból a Cél) volt a munkahely. CSV: `Indulás` = Kiindulás, `Munkahely` = a Cél helyei (az útvonal köztes pontjai), `Érkezés` = oda-vissza útnál a Kiindulás, egyirányúnál a Cél utolsó helye (így a skill és a webapp változtatás nélkül helyes útvonalat kap); ha a Kiindulás volt a munkahely, az opcionális `Munkahely helye` oszlop értéke `indulás` (ilyenkor az OTS Munkahelye az Indulás). A pontos cím az `Indulás cím` / `Cím` (a Cél helyeié) oszlopba kerül, az OTS-be a település megy.
- **Hétvége és szabadnap (1.5.6-tól):** szombaton és vasárnap nincs napi óraszám (bármilyen bejegyzés elég), de az **üres szombat és vasárnap jelez** (piros pont, kitöltetlen napok listája). A skill az üres napra (hétköznap, szombat, **vasárnap is**) `!!!`-t ír; a szabadnapot a Szabadnap bejegyzés jelöli (`SZABADNAP`). A skill **nem egészíti ki** a sorokat 8 órára. Havonta legfeljebb annyi SZABADNAP és annyi MUNKASZÜNETI NAP lehet, ahány hét van a hónapban (`Insights.weeksInMonth`); átlépéskor az app figyelmeztet.
- **Kilométeróra (1.6.0-tól):** az Utazás bejegyzésnek opcionális `Induló km` / `Érkező km` (CSV-oszlopok a végén, `Entry.startKm/endKm`); az űrlapon mindig látszik, nem kötelező; az induló az előző út végállásával előtöltött; az érkező > induló, az induló ≥ az előző út végállása (különben nem rögzíthető). Oda-vissza útnál az állások az egész körútra vonatkoznak. A havi összes km az ablak alján csak a `km.track` beállítással látszik. A Költségelszámolás **útonként egy sor** (OTS „Naponta több sor”); a skill a trackerből veszi az Ind. km / Érk. km értéket, ha megvan, egyébként a Google Maps adja.
- Időzítő (1.5.0-tól): indítás előtt és futás közben is megadható a Kezdés (legfeljebb a mai nap elejéig, jövőbeli nem lehet); az idő onnantól számolódik.
- A leválasztott ablak szélességben és magasságban átméretezhető (a tartalom követi); a menüsori ablak mérete rögzített/természetes magasságú.

## Ingyenes MI-megoldás

- A Gemini CLI magánszemélyeknek megszűnt (2026-06-18). Az ingyenes út az Antigravity CLI (`agy`): a skillt **`~/.agents/skills`** alól tölti be (kipróbálva; a dokumentációban megadott `~/.gemini/antigravity-cli/skills` mappából nem), az asztali program `~/.gemini/config/skills` alól. A Codex ugyanazt a mappát használja. A telepítő erre épül (`SkillTarget.antigravity`). Kipróbálva (felhasználó): az Antigravity CLI és a ChatGPT Codex is látja és olvassa az OTS-t, és kattint rajta; mindkettő ingyenes, a telepítő mindkettőt „Ingyenes” jelzéssel mutatja.
- Útmutató: `docs/ANTIGRAVITY_CLI_UTMUTATO.md` (a build HTML-t és PDF-et készít belőle, és az appba is bekerül).

## Webalkalmazás (`web/`, Windows/Chrome)

- Telepíthető asztali PWA (Windows/Chrome; **mobil nézet nincs**), sima JavaScript, függőség nélkül; a natív app funkcióival, automatikus mentéssel az adatmappába (File System Access API) és skill-telepítő varázslóval; részletek: `web/README.md`. Tesztek: `cd web && node --test test/*.test.js` (négy időzónában is futtasd). A szabályok (dátum, CSV-formátum, Tevékenység csak az Utazásnál kötelező, oda-vissza út, 1 fő/alkalom = 1 óra) megegyeznek a Mac-alkalmazáséval; a CSV-formátumot nem szabad eltérően módosítani. Még nincs benne: a naptárintegráció (lásd Gyűjtött teendők).

## Licenc

- A tároló MIT licenc alatt áll (`LICENSE`, 2026). Az Adventista jelkép (`LogoData.swift`, menüsori alapikon) az egyház védjegye, **nem része a licencnek**; ha az egyház jelzi, hogy nem megfelelő, el kell távolítani, és semleges alapikont kell adni. Személyes adat (név, rendszám, gyülekezetek) a tárolóba nem kerülhet: a `scripts/check-skill-template.py` a skill-sablont ellenőrzi.

## Adatformátum

- Bejegyzések: `bejegyzesek.csv` (pontosvesszővel tagolt, UTF-8 BOM). A skill a `beallitasok.json`-ból tudja, hol van. Visszafelé kompatibilisnek kell maradnia.

## Gyűjtött teendők

- **Naptárintegráció (döntések 2026-10-05):** a naptáresemények jelölési szabálya a `docs/NAPTAR_JELOLESEK.md` (közös a Mac-alkalmazásban és a webappban). Mac-alkalmazás: 1.4.0, EventKit, egy irányú (`docs/1.4.0-tervezett-valtozasok.md`), amíg a felhasználó nem jelzi, ne valósítsd meg. Webapp: Windows/Chrome, Google és Outlook naptár, helyi CSV-írás, részletes skill-telepítési leírás (`web/TERV.md`). Telefonos alkalmazás nem készül (a naptár váltja ki).

- Az 1.3.3 (Antigravity CLI a Gemini CLI helyett) és az 1.3.2 (beépített színválasztó, mert a `ColorPicker` rendszerpanel a menüsori ablakból nem működik: ne használj ilyet) és az 1.3.1 (kézi felvitel az OTS-be, kategóriaszínek) megvalósítva; logikája `OTSManual.swift`, felülete `OTSManualView.swift`, tesztek a SelfTest „Kézi felvitel” szakaszai.
- Az 1.3.0 változtatásai: `docs/1.3.0-tervezett-valtozasok.md` (megvalósítva). A következő verzióhoz a felhasználó új ötleteit gyűjtsd egy új ilyen fájlba, és amíg nem jelzi, hogy készüljön el, ne valósítsd meg.
