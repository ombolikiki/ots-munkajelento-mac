# Prompt a windowsos Claude-nak: OTS Munkajelentő Tracker, Windows-verzió

*(Használat: másold át a Windows-gépre az egész „OTS Munkajelentő Tracker” mappát, vagy legalább ezeket: `Sources/`, `Tests/`, `skill-template/`, `docs/`, `scripts/check-skill-template.py` (és az archív `scripts/archivum/make-skill-template.py`), `README.md`, `CLAUDE.md`. Nyiss a Windows-gépen egy üres mappát („OTS Munkajelentő Tracker Windows”), tedd bele a másolatot egy `mac-forras/` almappába, indítsd ott a Claude-ot, és illeszd be az alábbi szöveget a `---` vonalak közül.)*

---

# Feladat

Készítsd el a **Windows-verzióját** az „OTS Munkajelentő Tracker” nevű, jelenleg macOS-es menüsori alkalmazásnak. A Mac-verzió forrása a `mac-forras/` mappában van (Swift/SwiftUI). **Ezt kell a viselkedésében, az adatformátumában és a szabályaiban hűen lemásolni**, nem a kódját fordítani. Magyarul kommunikálj velem (Krisztián, adventista lelkész), a felület és az útmutató is magyar legyen.

Az alkalmazás időnaplót vezet (időzítő, Pomodoro, kézi bevitel, naptár), és az adataiból tölti ki egy MI-asszisztens (Claude, ChatGPT/Codex, Antigravity CLI) az OTS 4.40 (ots.detkapu.hu) Havi munkajelentőjét, a Költségelszámolást és a gyülekezeti létszámjelentőt az **OTS Adminisztráció** nevű skillel (azonosító: `ots-adminisztracio`). A kollégáknak is kiadom, ezért **semmilyen személyes adat nem lehet benne** (név, település, gyülekezetek, saját útvonalak).

## Döntések (ezeket meghoztam, ne kérdezz rájuk)

- **Technológia: Electron + TypeScript** (React vagy egyszerű DOM, te döntesz), `electron-builder` csomagolással. Indok: egyetlen kódbázis, és a felületet (naptár, táblázatok) könnyű elkészíteni. Tauri-t ne használj.
- **A Windows-verzió ugyanazokat az adatfájlokat írja és olvassa**, mint a Mac-verzió (lásd lent: pontos formátum), hogy a skill változtatás nélkül működjön, és a fájlok gépek között másolhatók legyenek.
- Verziószám: induljon **1.0.0**-ról, a funkciókészlet a Mac **1.3.3**-ával egyezzen meg.

## Mielőtt elkezded: kérdezz meg legfeljebb ezt az 5-öt (egyszerre, egy üzenetben), és várj a válaszra

1. Intel/AMD (x64) vagy ARM Windows-gépre is kell csomag? (Alapértelmezés: mindkettő.)
2. Van-e kódaláíró tanúsítványom? (Alapértelmezés: nincs; az aláíratlan telepítőnél a SmartScreen figyelmeztet, ezt az útmutatóban le kell írni.)
3. Telepítő (NSIS `.exe`) vagy hordozható `.zip` kell? (Alapértelmezés: mindkettő.)
4. Melyik Windows-verzión próbálhatom ki? (Windows 10/11.)
5. A skillt melyik MI-asszisztensekhez kell telepíteni Windowson? (Alapértelmezés: Claude, Codex és Antigravity CLI, mint a Macen.)

Minden mást döntsd el magad a lenti leírás alapján; ha valami nincs eldöntve, válaszd a Mac-verzió viselkedését.

## Munkamódszer

1. **Először olvasd el** a `mac-forras/CLAUDE.md`-t, a `mac-forras/README.md`-t, a `mac-forras/docs/HASZNALATI_UTMUTATO.md`-t (ez a felhasználói szemmel írt, pontos leírás), majd a forráskódot, főként: `Models.swift`, `CSV.swift`, `Attendance.swift`, `AppModel.swift`, `AppModel+Insights.swift`, `Insights.swift`, `DateUtil.swift`, `OTSManual.swift`, `SkillInstaller.swift`, és a `Tests/SelfTest/main.swift` (ez adja a pontos elvárt viselkedést, 450 ellenőrzés).
2. Írj egy rövid tervet (architektúra, modulok, a Mac→Windows eltérések), és csak ezután kezdj programozni.
3. **Tesztvezérelten dolgozz:** a `Tests/SelfTest/main.swift` ellenőrzéseit portold át egységtesztekre (Vitest), és ezek legyenek zöldek a build előtt. A build ne készüljön el, ha a teszt hibás.
4. Haladj funkciónként, minden szakasz végén futtasd a teszteket, és **ellenőrizd magad** (lásd a végén: Ellenőrzés).

## Alapszabályok (kötelezőek)

1. **A dátumszámítás nem omolhat össze és nem téveszthet.** JavaScriptben ez különösen veszélyes:
   - `new Date("2026-10-03")` UTC-ként értelmeződik, és időzónától függően az előző napra eshet. **Soha ne használd** dátum-only szövegre. Mindig helyi időben építs dátumot (`new Date(y, m-1, d, 12)`), vagy írj saját `YYYY-MM-DD` kezelőt.
   - Nap hozzáadása: ne `+ 86_400_000` ms (a nyári időszámítás átállásnál elcsúszik), hanem `setDate(getDate()+n)` déli időponttal.
   - Kezelni kell az évhatárt, a negyedévhatárt, a szökőnapot, a nyári időszámítást, az érvénytelen dátumot (február 30., 13. hónap) → biztonságos tartalék, kivétel nélkül.
   - Új dátum-alapú funkcióhoz egységteszt kell **2024–2035 között, minden negyedévre**, és a teszteket több időzónában is futtasd (Europe/Budapest, America/New_York, Pacific/Auckland, UTC; Windowson a `TZ` környezeti változót a tesztfuttató indítása előtt állítsd be, és ellenőrizd, hogy tényleg hat, pl. `Intl.DateTimeFormat().resolvedOptions().timeZone`).
2. **Szám- és CSV-olvasás sosem omolhat össze hibás bemenettől** (`inf`, `1e99`, `NaN`, hiányzó oszlop, törött idézőjel, Excel által átírt dátum). A hibás sort kihagyja és figyelmeztet; **mentés előtt másolatot készít** a fájlról, ha az olvasáskor hibás sort talált.
3. **Az ablak sosem lehet nagyobb a munkaterületnél** (`screen.getDisplayNearestPoint(...).workArea`): a magasságot mindig korlátozd, a tartalom görgethető legyen. A Mac-verzióban ez összeomlást okozott; itt sem lehet kilógó ablak.
4. **A tesztek nem érinthetik a valódi adatokat.** Teszteléskor mindig használd az `OTS_SUPPORT_DIR` (adatmappa), `OTS_HOME` (a felhasználó könyvtára, ide kerülnek a skillek) és `OTS_SKILL_SOURCE` (skill-forrás) környezeti változókat; különben a futás átírná a felhasználó `%APPDATA%` alatti fájljait vagy `~/.claude` mappáját.
5. **Fájltörlés csak szó szerinti, ellenőrzött útvonalra** (soha ne `rm -rf` / `Remove-Item -Recurse` változóból, ellenőrizetlen útvonalra). A felhasználó adatait nem törölheted kérdés nélkül.
6. **Személyes adat nem kerülhet az alkalmazásba, a skill-sablonba vagy az útmutatóba.** A példák kitalált nevek legyenek („Kovács János”, „Székesfehérvár”, „Mór”, „Bicske”). Ne olvass a felhasználó valódi `AppData`/`.claude` mappájából. A telepített alkalmazás induláskor üres: nincs előre megadott helyszínlista.

## Adatformátum (bájtra pontosan egyezzen a Mac-verzióval)

**Adatmappa:** `%APPDATA%\OTS Munkajelentő Tracker\` (ez a Mac `~/Library/Application Support/OTS Munkajelentő Tracker/` megfelelője). Itt van:

- `beallitasok.json` – mutató a fájlokra. Kulcsok: `dataFile` (a bejegyzések fájljának teljes útvonala), `attendanceFile` (a létszámjelentő-fájl útvonala), `format` (`"csv"`), `delimiter` (`";"`), `formatVersion` (`2`). Az alkalmazás indításkor hozza létre, ha nincs; a skill ebből találja meg az adatokat.
- `bejegyzesek.csv` – alapértelmezett bejegyzés-fájl (a felhasználó áthelyezheti, a `dataFile` követi).
- `letszamjelentesek.csv` – a bejegyzés-fájllal azonos mappában.
- Régebbi `bejegyzesek.json`: ha csak ilyen van, alakítsd át CSV-re (lásd Mac `AppModel.load`).

**CSV:** pontosvesszővel (`;`) tagolt, **UTF-8 BOM-mal** az elején, `CRLF` sorvéggel, minden mező idézőjelezhető (`"` duplázva), az idézőjeles mezőben lehet `;` és sortörés. Az első sor a fejléc. Az olvasó **fejléc alapján, rugalmasan** olvasson (oszlopsorrendtől független), és tűrje: pontosvessző helyett vessző elválasztót, `LF`/`CRLF` sorvéget, az Excel által átírt dátumot (`2026. 10. 03.`, `2026.10.03`, `10/3/2026` stb.) és időt, tizedesvesszőt, felesleges szóközöket, üres sorokat.

`bejegyzesek.csv` oszlopai, ebben a sorrendben:
`Azonosító;Dátum;Kezdés;Vége;Időtartam (mp);Időtartam (óó:pp);Indulás;Munkahely;Érkezés;Típus kód;Típus;Egység;Mennyiség;Tevékenység;Forrás`

- `Dátum`: `YYYY-MM-DD`, a kezdés helyi napja. `Kezdés`/`Vége`: `HH:mm:ss` helyi idő; üres az egész napos és az idő nélküli (csak óraszám/mennyiség) bejegyzéseknél. Ha mindkettő ki van töltve, az időtartam = `Vége` − `Kezdés` (ha a `Vége` korábbi, másnapra esik): a felhasználó a táblázatban átírhatta.
- `Egység`: `ora` | `alkalom` | `fo` | `egesz_nap`. `Mennyiség`: csak alkalom és fő esetén.
- `Forrás`: `timer` | `pomodoro` | `manual` | `calendar`. `Azonosító`: UUID.
- `Indulás`/`Érkezés`: csak az Utazás típusnál töltött; ilyenkor a `Munkahely` a Munkahely(ek) vesszővel elválasztott listája.

`letszamjelentesek.csv` oszlopai:
`Dátum;Gyülekezet;Szombatiskola gyermek;Szombatiskola felnőtt adventista;Szombatiskola felnőtt vendég;Istentisztelet gyermek;Istentisztelet felnőtt adventista;Istentisztelet felnőtt vendég`
(ugyanarra a dátumra és gyülekezetre csak egy sor; a számok 0–99 999 közé szorítva.)

**Kompatibilitási próba, kötelező:** írj egy tesztet, amely a `mac-forras/Tests/SelfTest/main.swift` CSV-szakaszainak mintafájljaival (építs ugyanilyeneket) megvizsgálja, hogy a Windows-kód által írt fájlt a Mac-formátum szabályai szerint, és a Mac-formátumú, valamint Excel által átírt fájlt a Windows-kód hibátlanul olvassa.

## Tevékenység-típusok (OTS-mezőazonosítók, ne változtasd)

| Kód | Csoport | Megnevezés | Egység |
|---|---|---|---|
| PREACHING | Gyülekezet | Istentisztelet | alkalom |
| VISITING | Gyülekezet | Látogatás (gyülekezet) | fő |
| OFFICE_WORK | Gyülekezet | Ügyintézés | óra |
| MEETING | Gyülekezet | Értekezlet | óra |
| EVANGELISATION | Misszió | Evangelizáció | alkalom |
| BIBLE_HOUR | Misszió | Bibliaóra | alkalom |
| MISSION_VISITING | Misszió | Látogatás (misszió) | fő |
| TRAINING | Továbbképzés | Résztvevő | óra |
| HELD_TRAINING | Továbbképzés | Tartott | óra |
| ADMINISTRATION | Hivatal | Adminisztráció | óra |
| PREPARING | Hivatal | Felkészülés | óra |
| TRAVEL | Egyéb | Utazás | óra |
| HOLIDAY, DAY_OFF, PUBLIC_HOLIDAY | Nem munkaidő | Szabadság, Szabadnap, Munkaszüneti nap | egész nap |

- A felhasználó **saját kategóriákat** vehet fel (kód: `EGYEDI_` + ékezetek nélküli nagybetűs név, ütközésnél `_2`, `_3`…; egység: óra/alkalom/fő). Ezek **nem kerülnek az OTS-be**, nem számítanak bele az OTS-óraösszegbe és a Munkahely-listákba.
- A beépített kategóriák elrejthetők a legördülő menüből, de a nevük nem módosítható.
- A kategóriáknak **színük** van (alapértelmezés csoportonként: Gyülekezet kék, Misszió zöld, Továbbképzés lila, Hivatal narancs, Nem munkaidő rózsaszín, Egyéni türkiz, Egyéb szürke), kategóriánként felülírható a Beállításokban (16 színminta + `#RRGGBB` mező; ne használj rendszer-színválasztó ablakot, a Mac-en az nem működött, ezért lett 1.3.2-ben beépített színválasztó). A szín a naptárban, a napi listában és a kézi felviteli ablakban jelenik meg.

## Üzleti szabályok (a Mac-tesztek ezeket rögzítik)

- **Összesítés:** 1 fő vagy 1 alkalom = **1 óra** az összegben; az egész napos típus 0 óra; a saját kategória nem számít az OTS-összegbe.
- **Napi 8 óra:** csak hétfőtől péntekig elvárás (beállítható érték). Piros pont, ha a múltbeli nap nem éri el; narancs, ha a mai nap még folyamatban; zöld pipa, ha megvan. Szabadság/szabadnap/munkaszüneti nap, szombat, vasárnap és a jövő mentes.
- **Jövőbeli bejegyzés nem hozható létre** (se jövőbeli nap, se a mai nap jövőbeli időpontja).
- **Pomodoro:** a leállítás ≥30 mp esetén menti a részidőt; a Pomodoro-bejegyzéseket a skill/kézi felvitel **naponta típusonként először összegzi, és csak a napi összeget kerekíti felfelé** egész órára (soha nem pomónként).
- **Utazás:** kötelező mező az Indulás, a Munkahely(ek), az Érkezés (alapértéke a székhely) és a Tevékenység. **Oda-vissza** jelölő: bejelölve az Érkezés az Indulás (A - B - A), a jelölés megmarad. A Tevékenység csak az Utazásnál kötelező, máshol opcionális; a Költségelszámolás Tevékenysége kizárólag az Utazás bejegyzésekből jön. A Költségelszámolás útvonala: `Indulás - Munkahely1 - Munkahely2 - Érkezés`, az üres Indulás/Érkezés helyén a székhely, az egymás melletti azonos pontok összevonva; több útvonal ugyanazon a napon ` ; `-vel egy sorban.
- **Kitöltetlen napok:** beállítható időszak (utolsó 7/14/30 nap, előző hónap, e hónap); a vasárnap is számít; a szabadság/szabadnap/munkaszüneti nap kitöltöttnek számít. **Hosszú kihagyás:** ha N (alap 7) egymást követő kitöltetlen nap van, a tálcaikon emlékeztető ikonra vált, és piros sáv jelenik meg.
- **Gyülekezeti létszámjelentő:** negyedévenként a **második és hetedik szombaton** (a negyedév első napjától számolt szombatok közül). Példák: 2026-07-11, 2026-08-15, 2026-10-10, 2026-11-14, 2027-01-09, 2027-02-13. A Beállításokban kapcsolható, a gyülekezetek regisztrálhatók (sorrend állítható, duplikáció nagy-/kisbetű-függetlenül tiltott). Az esedékes napon űrlap jelenik meg gyülekezetenként (Szombatiskola és Istentisztelet × gyermek/felnőtt adventista/felnőtt vendég); lemaradásnál a kitöltetlen napok között külön jelzés.
- **Naptár:** idősávos heti nézet; a munkanap kezdete/vége beállítható (alap 7–20), a sávon kívüli bejegyzést jelzés mutatja; a hét kezdőnapja hétfő vagy vasárnap; húzással kijelölt idősáv → új bejegyzés; a mai napon a jövő nem jelölhető ki.

## Funkciók (az 1.3.3 teljes készlete)

1. **Tálca-alkalmazás** (a Windows megfelelője a Mac menüsorának): értesítési területi ikon, balkattintásra a főablak a tálca fölött/mellett nyílik meg (kattintáson kívülre kattintva eltűnik, mint egy lenyíló ablak); jobbkattintásra helyi menü (Megnyitás, Leválasztott ablak, Beállítások, Kilépés); a **kilépés mindig elérhető** (ez volt az egyik fájó hiba a Mac-verzióban). Ne maradjon "szellem" példány: indításkor ha már fut egy példány, azt hozza előre (`app.requestSingleInstanceLock`).
2. **Leválasztható ablak:** külön, mozgatható, szélességben és magasságban is átméretezhető ablak (a tartalom és a naptár követi), "mindig legfelül" kapcsolóval. Kompakt és normál nézet (kisebb kijelzőn automatikusan kompakt).
3. **Négy rögzítési mód:** Időzítő (stopper), Kézi bevitel (időponttal vagy csak óraszámmal), Pomodoro (beállítható munkaidő, rövid és hosszú szünet és a hosszú szünet gyakorisága; alapértékek: 25 / 5 / 15 perc, minden 4. pomo után hosszú szünet; hang, a tálcaikon mutatja az állapotot és a hátralévő időt), Naptár. Mezők: Munkahely (mentett helyszínek listájából is választható, új helyszín megjegyződik), Tevékenység típusa, Tevékenység (szabad szöveg), Utazásnál Indulás/Érkezés, alkalom/fő típusnál Mennyiség. Mentés után a mezők kiürülnek.
4. **Napi lista** (a kiválasztott nap összes bejegyzése, törlés kétlépéses megerősítéssel), napi összesítő a 8 órás jelzéssel, kategóriaszínes sorok, színes pontok az összesítő sor végén.
5. **Kitöltetlen napok** kártya: kattintásra a naptárban/listában az adott napra ugrik (ugrás a mai napra gomb is).
6. **Kézi felvitel az OTS-be** ablak (lásd `OTSManual.swift` és `OTSManualView.swift`, ez az 1.3.1 új funkciója): Munkajelentő / Költségelszámolás / Létszámjelentő × Naptár / Felsorolás / OTS-táblázat, hónaplapozás (hónap elején az előző hónap, ha annak van adata); kattintásra vágólapra másolás; "felvittem" jelölés, amely érvényét veszti, ha a sor tartalma változik; Google Maps hivatkozás az útvonalakhoz (`https://www.google.com/maps/dir/Pont1/Pont2/…`); opcionális "A skill szabályai szerint" kapcsoló (hétköznap 8 órára kiegészítés az Ügyintézésben, `!!!` előtag ha az Ügyintézés > 4, üres hétköznap/szombat `!!!`, üres vasárnap `SZABADNAP`; szombaton nincs kiegészítés; minden szám legfeljebb 8).
7. **Beállítások:** megjelenés (világos/sötét/rendszer mód; négy színséma: kék, zöld, lila, borostyán), tálcaikonok (alap: az **Adventista jelkép** mint sablonikon, `mac-forras/Sources/OTSMunkajelentoTracker/LogoData.swift`-ben alfa-maszkos PNG-ként, base64-ben megvan; a sablonikon mindig egyszínű, a Windows tálca világos/sötét témájához igazodjon; választható még óra, stopper, homokóra stb.; Pomodoro munka/szünet és emlékeztető ikon), jelzőhangok, naptár-beállítások, emlékeztetők, székhely és helyszínek, kategóriák és színeik, létszámjelentő, adatfájl helye (módosítható), skill-telepítő, indítás bejelentkezéskor (`app.setLoginItemSettings`), használati útmutató megnyitása, **"Adatok törlése, alapállapot"** (két külön megerősítés, az "Mégse" az alapértelmezett, a törlés előtt másolat `…torles-elotti.csv`).
8. **Skill-telepítő varázsló** (6 lépés: bevezető, cél, feladatok, adatok, áttekintés, kész); lásd lent.
9. **Használati útmutató** a csomagban (HTML), a Beállításokból megnyitható; PDF is készüljön.

## Skill-telepítő Windowson

A Mac-verzió `SkillInstaller.swift` logikáját kövesd, a sablon a `mac-forras/skill-template/ots-adminisztracio/` (ez már személyes adat nélküli; a sablon az egyetlen, közös forrás (nincs külön személyes skill), a `scripts/archivum/make-skill-template.py` archív, ne futtasd; a sablont csomagold az alkalmazásba kész erőforrásként). Jelölők: `[[TASK:id]]…[[/TASK]]` (feladat), `[[SHARED:tracker]]…[[/SHARED]]` (közös szakasz), `{{#KEY}}…{{/KEY}}` (feltételes), helyőrzők: `{{FELHASZNALO_NEVE}}`, `{{SZEKHELY}}`, `{{GYULEKEZETEK}}`, `{{BONGESZO}}`, `{{OTS_URL}}`, `{{OTS_NEV}}`. A telepítő a „Adataid” lépésben megkérdezi az **OTS-oldalt**: DETKapu (`https://ots.detkapu.hu/`) vagy TETKapu (`https://ots.tetkapu.hu/`), ebből töltődik az `OTS_URL` és az `OTS_NEV`. Az **Antigravity CLI** célnál „Ingyenes” jelzés kell; nincs `settings.json`-beállítás (a böngészőt a felhasználó a `/browser` paranccsal kapcsolja be). Régi, a Gemini CLI-hez telepített másolatot (jelölőfájllal) cseréld le másolat mellett. A korábbi `detkapu-adminisztracio` néven telepített skillt (ha jelölőfájlja van) cseréld le másolat mellett; a jelölés nélkülihez ne nyúlj. A `tasks.json` sorolja fel a feladatokat (havi, koltseg, nevsor, hittan, latogatottsag). Telepítéskor: sablon renderelése a kijelölt feladatokkal → átmeneti mappába → ellenőrzés (nincs megmaradt jelölő, érvényes `SKILL.md` frontmatter) → meglévő telepítés mentése `…\skill-mentesek\<időbélyeg>` alá → csere. A telepítést egy `.ots-tracker-install.json` jelölőfájl és SHA256-ujjlenyomat jelzi (naprakész / elavult / idegen telepítés). **Idegen (kézzel telepített) skillt csak megerősítés után, másolattal írhat felül.**

Célmappák Windowson (a `%USERPROFILE%` a felhasználó könyvtára, `OTS_HOME` felülírhatja):
- Claude: `%USERPROFILE%\.claude\skills\ots-adminisztracio`
- ChatGPT/Codex: `%USERPROFILE%\.agents\skills\ots-adminisztracio`
- **Antigravity CLI (`agy`, ingyenes):** `%USERPROFILE%\.agents\skills\ots-adminisztracio` (a Codexszel közös mappa; ha mindkettő ki van jelölve, csak egyszer másol). Macen kipróbálva: az `agy` onnan tölti be a skillt (a dokumentált `.gemini\antigravity-cli\skills` mappából nem); Windowson ezt újra ellenőrizd. Az `agy` telepítője Windowson: `irm https://antigravity.google/cli/install.ps1 | iex` (a program a `%LOCALAPPDATA%\agy\bin` mappába kerül); a telepítő mutassa, hogy az `agy` telepítve van-e. A Gemini CLI magánszemélyeknek megszűnt (2026-06-18), ne építs rá.

**Fontos Windows-eltérés:** a sablon `references/tracker-adatforras.md` fájlja a Mac-útvonalat (`~/Library/Application Support/OTS Munkajelentő Tracker/beallitasok.json`) írja. A Windows-telepítő a renderelt fájlban cserélje ezt `%APPDATA%\OTS Munkajelentő Tracker\beallitasok.json` útvonalra (az alapértelmezett fájl is: `%APPDATA%\OTS Munkajelentő Tracker\bejegyzesek.csv`), és az "(Mac)" megjegyzést vegye ki. Írj tesztet arra, hogy a telepített szövegben nem maradt Mac-útvonal. Az eszköz-specifikus szöveg (böngésző) a Mac-verzióhoz hasonlóan működjön. Ellenőrizd Windowson a hivatalos dokumentációban (webes keresés), hogy az egyes MI-eszközök Windowson ténylegesen hol keresik a skilleket; ha eltér a fentitől, javítsd, és jelezd nekem.

## Csomagolás és kiadás

- `electron-builder`: NSIS telepítő és hordozható zip, a kért architektúrákra; az alkalmazás neve "OTS Munkajelentő Tracker", ikon: az Adventista jelkép alapú app-ikon (`.ico`, több méretben; a Mac-ikon generáló szkriptje `mac-forras/scripts/make-icon.swift` mintaként szolgál).
- Aláíratlan build: az útmutatóban írd le, hogyan lépjen túl a SmartScreen figyelmeztetésen ("További információ" → "Futtatás mindenképpen"), és hogy ez normális egy aláíratlan, belső használatú programnál.
- A `build` parancs: tesztek → csomag → útmutató (HTML/PDF) egy lépésben, hiba esetén megáll.
- Használati útmutató: a `mac-forras/docs/HASZNALATI_UTMUTATO.md` alapján, Windowsra igazítva (tálca a menüsor helyett, `%APPDATA%` az útvonalakban, a SmartScreen, a Windows-os telepítés). A képernyőképeket az alkalmazásból készítsd, kitalált példaadatokkal (a Mac-verzió `Tests/Screenshots/main.swift` mintáját követve), ne a Mac-képeket másold.

## Ellenőrzés (kötelező, mielőtt azt mondod, hogy kész)

Ne mondd késznek, amit nem futtattál le. A végén adj **őszinte jelentést**: mit teszteltél automatikusan (a zöld tesztek számával), mit néztél meg ténylegesen a futó alkalmazásban (képernyőképekkel), és mit nem tudtál kipróbálni.

1. Az összes portolt egységteszt zöld, **mind a négy időzónában** (Budapest, New York, Auckland, UTC), beleértve a 2024–2035 közötti negyedévekre a szombat- és esedékességi számításokat, és a hónapok napszámát (szökőév).
2. CSV: kör-teszt (írás → olvasás), Excel-átírt dátumformátumok, vesszős elválasztó, CRLF, rossz sorok, `inf`/`1e99`/`NaN`, üres fájl, hiányzó oszlop, hibás fájl esetén készül-e másolat.
3. Üzleti szabályok: a fenti tábla és szabályok minden pontjára legyen teszt, különösen a Pomodoro napi összeg kerekítése, az 1 fő = 1 óra, a saját kategória kizárása, a 8-ra kiegészítés és a `!!!` szabályok (szombati kivétel), az Utazás útvonal-összevonás, a Google Maps URL kódolása, a "felvittem" jelölés érvénytelenedése.
4. Skill-telepítő: teszt `OTS_HOME` ideiglenes mappával; a telepített `SKILL.md` frontmatterje érvényes, nincs megmaradt jelölő/helyőrző, nincs Mac-útvonal, nincs személyes adat; idegen telepítés felülírása csak megerősítéssel; csak az `.agents\skills` egyszer másol, ha Codex+Gemini.
5. **Valós futtatás:** indítsd el az alkalmazást (`OTS_SUPPORT_DIR` ideiglenes mappával), kattints végig a fő folyamatokon (bejegyzés rögzítése mindegyik módban, napi lista, kitöltetlen napok, kézi felvitel ablak mindhárom adatkörrel és nézettel, beállítások, színváltoztatás, skill-telepítő, kilépés a tálcaikon helyi menüjéből), és készíts képernyőképeket. Ellenőrizd világos és sötét módban, 100%, 125%, 150% és 200% Windows-skálázásnál, és kis felbontású (pl. 1366×768) kijelzőn, hogy az ablak nem lóg ki.
6. Keresd meg a saját hibáidat: futtass memória-/összeomlás-próbát (sok bejegyzés, gyors lapváltás, hibás fájl), és javíts mindent, amit találsz. A jelentésben sorold fel, milyen hibákat találtál és javítottál.
7. A `dist\` mappában legyen: a telepítő `.exe`, a hordozható `.zip`, a használati útmutató PDF. Ellenőrizd a csomag tartalmát: nincs benne személyes adat (keresd: „Ömböli”, „Krisztián”, „Győr”, „Tatabánya”, „Toggl”), a skill-sablon benne van, az ikon megjelenik.

## Amit ne csinálj

- Ne találj ki OTS-viselkedést: az OTS-t ebben a projektben nem te éred el, csak az adatokat készíted elő a skillnek.
- Ne nyúlj a skill (`ots-adminisztracio`) tartalmához a sablonon kívül, és ne írj külön személyes skillt: egyetlen közös skill van, a sablon.
- Ne kérj tőlem jelszót vagy bejelentkezési adatot semmihez.
- Ne tegyél az alkalmazásba hálózati hívást, telemetriát vagy automatikus frissítést; minden adat helyben marad.
- Ne bővítsd a funkciókat a leírtakon túl; ötleteidet a végén sorold fel javaslatként.

## Átadás

A munka végén: (1) rövid összefoglaló, mi készült el; (2) a tesztek eredménye számokkal; (3) mit próbáltál ki élesben, mit nem; (4) ismert hiányosságok; (5) hogyan telepítsem a kollégák gépére; (6) javaslatok.

---
