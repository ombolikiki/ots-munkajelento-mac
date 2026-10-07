# OTS Munkajelentő Tracker (1.7.0)

Menüsori időmérő Macre (macOS 14 vagy újabb). A bejegyzéseit a „OTS Adminisztráció” skill (`ots-adminisztracio`) olvassa a Havi munkajelentőhöz és a Költségelszámoláshoz.

- **Időzítő**, **Kézi bevitel** (időponttal vagy óraszámmal), **Pomodoro** (alapértelmezett 25/5/15 perc, minden 4. pomo után hosszú szünet, a Pomodoro lapon módosítható; a félbehagyott pomo eltelt ideje is mentődik) és **Naptár** (heti nézet, húzással új bejegyzés).
- Az ablak alján a kiválasztott nap összes bejegyzése és a kitöltetlen napok (alapból e hónap elejétől, a vasárnapokat is beleértve) látszanak.
- Mezők: Munkahely, Tevékenység típusa (az OTS Havi munkajelentő oszlopai), Tevékenység.
- Látogatásnál a mennyiség **fő**, Istentiszteletnél, Evangelizációnál és Bibliaóránál **alkalom**.
- Szabadság, Szabadnap és Munkaszüneti nap a Kézi beviteleknél választható.

## Adatok

`~/Library/Application Support/OTS Munkajelentő Tracker/bejegyzesek.csv`

Pontosvesszővel tagolt UTF-8 CSV, Excelben, Numbersben és LibreOffice-ban is megnyitható. Szerkesztés után az app a következő megnyitáskor újra beolvassa. Ha a fájl hibás sorokat tartalmaz, mentés előtt biztonsági másolat készül róla (`bejegyzesek.hibas-….csv`). A régi `bejegyzesek.json` fájlt az app első indításkor átalakítja. A mappa az appban módosítható, a `beallitasok.json` (a fix `Application Support` mappában) mindig megmondja, hol van az aktuális adatfájl.

## Fejlesztés és csomagolás

```bash
swift build && .build/debug/OTSMunkajelentoTracker   # futtatás fejlesztés közben
./scripts/build.sh                                    # dist/ mappa: terjeszthető .zip (arm64 + Intel)
```

Az Xcode nem kell, a Command Line Tools elég. A `build.sh` ad-hoc aláírást használ. Apple Developer ID-val: `SIGN_ID="Developer ID Application: Név (TEAMID)" ./scripts/build.sh`.

## Útmutató a kollégáknak

1. Bontsd ki a zip-et, és húzd az **OTS Munkajelentő Tracker** alkalmazást az Alkalmazások mappába.
2. Az első indításnál a macOS figyelmeztethet, hogy az app nem ellenőrizhető. Ilyenkor: **Rendszerbeállítások › Adatvédelem és biztonság**, görgess le, és kattints a **„Mégis megnyitom”** gombra. Ez csak egyszer kell.
3. Az app a menüsorban jelenik meg (óra ikon). Kattints rá a megnyitáshoz. A fogaskerék ikonnál állíthatod be a Pomodoro időket és az indítást bejelentkezéskor.

## Licenc

A forráskód és a dokumentáció az [MIT licenc](LICENSE) alatt áll: szabadon használható, módosítható és terjeszthető, a szerzői jogi sor megtartásával, garancia nélkül.

**Kivétel:** az **Adventista jelkép** (a menüsori „Adventista jelkép” ikon, `Sources/OTSMunkajelentoTracker/LogoData.swift`) az egyház védjegye, és **nem része a licencnek**. Ha a jelkép használatával kapcsolatban az egyház jelzi, hogy nem megfelelő, a jelképet el kell távolítani.

## Verziótörténet

A legújabb verzió van elöl.

### 1.7.0

- **Pomodoro-munkamenet** (`AppModel` Pomodoro szakasza, `PomoSession.swift`): a pomók és a szünetek egyetlen bejegyzésként rögzülnek (`pomo.merge`, alapból be), a szünet is munkaidő. A munkamenet véget ér: Leállítás, a hosszú szünet vége, a szünet vége automatikus indítás nélkül, altatás, kilépés. Futó munkamenet alatt a mezők zároltak (a bejegyzés a munkamenet elején rögzített mezőket kapja). Éjfélen átnyúlva két bejegyzés.
- **Altatás** (`NSWorkspace.willSleepNotification`, tartaléknak a >120 s időugrás-észlelés): az altatásig eltelt idő rögzül, ébredéskor új pomo indítható. Folyamatos mentés (`pomo.session`): váratlan leállás után a következő indításkor rögzül, ami addig eltelt. Futó Pomodoro alatt `beginActivity` (nincs App Nap).
- Új teszt: „Pomodoro: munkamenet, altatás, helyreállítás” (léptethető `AppModel.clock`).
- CSV nem változott.

### 1.6.2

- **MIT licenc** (`LICENSE`); az Adventista jelkép nem része a licencnek (lásd „Licenc”).
- A skill-sablon Költségelszámolás-leírásában a példa autó-fül neve általános példa lett (a skill változott, ezért a telepített skillnél megjelenik a frissítés-jelzés).

### 1.6.1

- **Javítás: a javaslatlista (Munkahely, Kiindulás, Cél) az alatta lévő mezők fölé kerül**, és a javaslatra kattintva a mező megkapja a javaslatot (korábban az alatta lévő mező szövege a lista fölé rajzolódott, és a kattintást is az kapta, ezért a lista eltűnt, a mező pedig üresen maradt). Az űrlap sorai fentről lefelé csökkenő rétegsorrendet kapnak (`FieldsView`); teszt: „Javaslat a Munkahely mezőben (valódi űrlap)”.

### 1.6.0

- **Kilométeróra** (`Entry.startKm/endKm`, `AppModel+Km.swift`): az Utazás űrlapon mindig látható, opcionális induló és érkező km mező; az induló az előző út végállásával előtöltve (`lastEndKm`); ellenőrzés (`kmProblem`: érkező > induló, induló ≥ előző vég); **km-javítás** a napi listában (`updateKm`, ceruza ikon); **havi összes km** az ablak alján (`monthKm`), a Beállítások › Rögzítés › Kilométeróra kapcsolóval (`km.track`).
- **Költségelszámolás: minden út külön sor** (`OTSCostRow` útonként, `rowKey` = nap#sorszám), km-állásokkal; a Google Maps gomb csak teljes km-állás nélkül.
- **CSV:** új oszlopok a végén: `Induló km`, `Érkező km` (22 oszlop; a régi fájlok olvashatók maradnak).
- **Skill:** minden Utazás külön sor (több út/nap: OTS „Naponta több sor”), az Ind. km / Érk. km a trackerből, ha megvan.

### 1.5.6

- **Hétvége:** az üres szombat és vasárnap is jelez (`Insights.targetState`: üres hétvégi nap = piros pont / a mai nap narancs; bármilyen bejegyzés vagy egész napos bejegyzés elég, hétvégén nincs napi óraszám).
- **Szabadnap egy kattintással** (`AppModel.markDayOff`, `markEmptySundaysAsDayOff`): hold ikon a kitöltetlen napok címkéjén, jobb kattintásos menü, **Vasárnapok → szabadnap** gomb. Csak üres, múltbeli napot jelöl.
- **Havi korlát figyelmeztetés** (`Insights.weeksInMonth`, `checkMonthlyLimit`): legfeljebb annyi SZABADNAP és annyi MUNKASZÜNETI NAP / hónap, ahány hét van a hónapban; átlépéskor a `notice` jelez (nem akadályoz).
- **Skill:** kikerült a 8 órára kiegészítés, a 4 órát meghaladó Ügyintézés `!!!` jelölése és a szombati kivétel; az üres vasárnap `!!!` (nem `SZABADNAP`). A Kézi felvitel kapcsolója: *Üres napok jelölése (!!!)*.

### 1.5.5

- **Javítás:** a Tevékenység típusa mezőben a javaslat elfogadása után (Enter, Tab, kattintás) üresnek látszott a mező, mert a fókusz a mezőben maradt, és a kiválasztott típus neve csak fókusz nélkül volt kirajzolva. Most elfogadás után a mező elengedi a fókuszt (`blurOnPick`), fókuszban pedig a típus neve halványan látszik. Teszt: fókuszba állított mező, szimulált kattintás a javaslatra.

### 1.5.4

- **Beállítások fülekre osztva** (Megjelenés, Rögzítés, Naptár, OTS, Adatok; `SettingsTab`, `SettingsTabBar`), az utolsó fül megmarad.
- **Újranyitáskor a rögzítő oldal:** a menüsori ablak bezárásakor (látható → eltűnt átmenet, `PanelController.menuHiddenCount`) a Beállítások visszaáll a rögzítő oldalra.
- **Javaslatok gépelés közben** (`Suggest.swift`: `SuggestTextField`, `TypeSuggestField`): helyszínek, típusok, korábbi tevékenységek; ékezet- és kisbetű-független; a lista a tartalomra takar rá (nem növeli az ablak magasságát). Beállítások › Rögzítés alatt kapcsolható (`suggest.enabled`).

### 1.5.3

- **A menüsori számláló javítása:** az 1.5.2-ben a számláló nem látszott (a menüsori elem a címkében csak egy képet fogad el). Most az ikon és az idő egyetlen képként jelenik meg (`MenuBarClock`), szélességazonos számjegyekkel; a futó alkalmazás menüsori elemén mérve a szélesség végig állandó (korábban 73–76 pont között ugrált). Mérőeszköz: `scripts/status-item-dump.sh`.

### 1.5.2

- **A menüsori számláló nem ugrál (javítás):** a menüsori elem a SwiftUI szövegét a saját, arányos számjegyű betűtípusával rajzolta újra, ezért az 1.5.1 után is mozogtak a számok. Most az időt az app maga rajzolja ki egy sablonképre (`MenuClockImage`: szélességazonos számjegyek, rögzített szélesség).

### 1.5.1

- **A menüsori számláló nem ugrál:** az időzítő és a Pomodoro ideje állandó szélességű (szélességazonos számjegyek, rögzített keret), így másodpercenként sem mozog a menüsori ikon (`MenuClockText`).

### 1.5.0

- **Skill-frissítés egy kattintással:** ha az alkalmazásba csomagolt skill újabb, mint a gépen telepített, a fejlécben ikon, értesítés és a Beállítások › Skill részben gomb jelzi; a frissítés a telepítés jelölőfájljában tárolt beállításokat használja (célok, feladatok, név, székhely, gyülekezetek, DETKapu/TETKapu), és másolatot készít a régiről (`SkillInstaller.updateOutdated`).
- **Időzítő: korábbi kezdés.** Indítás előtt megadható a Kezdés ideje (vagy −5/−10/−15/−30 perc gomb), futás közben is javítható; az idő onnantól számolódik.
- **Az Utazás űrlap újratervezve:** Kiindulás és Cél mező (a Célba több hely is írható, pontos címmel is: `Tata, Fő út 1., Mór`), „Munkahely” választógomb a két mező fölött (alapból a Cél), **Oda-vissza** pipa mellettük (alapból bejelölt: `Kiindulás - Cél(ek) - Kiindulás`; kikapcsolva egyirányú). Új, opcionális CSV-oszlop: `Munkahely helye` (`indulás`, ha a Kiindulás volt a munkahely). A CSV többi oszlopának jelentése változatlan, így a skill és a webapp tovább működik. Az 1.4.1 Érkezés-mezős és oda-vissza megoldását ez váltja fel.

### 1.4.1

- **Utazás:** az Indulás és az Érkezés mezőbe település vagy `Tata, Fő út 1.` alakú pontos cím is írható (`Indulás cím`, `Érkezés cím` CSV-oszlop); a „Teljes címet adok meg” jelölőnégyzet megszűnt. Az oda-vissza pipa az útvonal végére az Indulást teszi, az Érkezés mindig írható (a CSV-ben az Érkezés ilyenkor az Indulás, a beírt Érkezés utolsó Munkahely).

### 1.4.0

- **Naptárintegráció** (Mac Naptár, EventKit, egy irányú: naptár → app; csak olvas): a lezajlott események bejegyzésként átvétele (`CalendarParser.swift`, `CalendarStore.swift`, `CalendarSync.swift`, felület: `CalendarSyncView.swift`). A jelölési szabály: `docs/NAPTAR_JELOLESEK.md` (közös a webappal). A naptár a mérvadó (módosítás frissít, törlés töröl; kézi bejegyzéshez nem nyúl; másolat és törlésvédelem). „Átnézésre vár” ablak a hiányos és nem felismert eseményeknek.
- **Pontos címek:** új CSV-oszlopok a végén: `Cím`, `Naptár azonosító`, `Indulás cím`, `Érkezés cím` (régi fájlok olvashatók maradnak). Az Utazás Indulás és Érkezés mezőjébe település vagy `Tata, Fő út 1.` alakú pontos cím is írható (`Indulás cím`, `Érkezés cím` oszlop); az oda-vissza pipa az útvonal végére az Indulást teszi, az Érkezés mindig írható. A Google Maps útvonalba a pontos cím kerül, Apple geokódolós ellenőrzéssel (`AddressChecker.swift`), tartaléknak a település.
- **macOS 14+** (a Naptár teljes hozzáféréséhez); az aláíráshoz a `scripts/OTS.entitlements` tartozik (`com.apple.security.personal-information.calendars`).
- Tesztek: a SelfTest „Naptár…” szakaszai (értelmező 2024–2035 minden negyedévre, szinkron kitalált naptárral).

### 1.3.3

- **Antigravity CLI (`agy`) a Gemini CLI helyett**, „Ingyenes” jelzéssel a skill-telepítőben. A Google 2026. június 18-tól leállította a Gemini CLI-t magánszemélyeknek. Az `agy` a skillt az `~/.agents/skills` mappából tölti be (a Codex közös mappája); a telepítő jelzi, hogy az `agy` telepítve van-e, a régi Gemini-másolatot eltávolítja (másolattal). Új, részletes Antigravity CLI útmutató (külön PDF és beépítve). **Kipróbálva és ingyenes: az Antigravity CLI és a ChatGPT Codex is** (látja és olvassa az OTS-t, és kattint rajta); a telepítő mindkettőnél „Ingyenes” jelzést mutat.

### 1.3.2

- **Egységes skill:** egyetlen közös „OTS Adminisztráció” skill van (`skill-template/ots-adminisztracio`), amelyet mindenki (a fejlesztő is) az alkalmazás telepítőjével telepít; a korábbi külön személyes skillt megszüntettük.
- A skill új neve **OTS Adminisztráció** (`ots-adminisztracio`); a telepítő lecseréli az alkalmazás által telepített régi `detkapu-adminisztracio` skillt (másolattal).
- A telepítő megkérdezi, hogy **DETKapu** (ots.detkapu.hu) vagy **TETKapu** (ots.tetkapu.hu) oldalon dolgozol, és a skillbe a megfelelő címet írja.
- **Gemini CLI**: „Ingyenes megoldás” jelzés a telepítőben, a Gemini böngészőágensének automatikus bekapcsolása (`~/.gemini/settings.json`), beépített Gemini CLI útmutató.
- **Oda-vissza út** az Utazásnál (az Érkezés az Indulás); a Költségelszámolás tevékenysége kizárólag az Utazás bejegyzésekből jön; a Tevékenység csak az Utazásnál kötelező.
- Naptár: a napok neve és száma az oszlopuk fölé igazítva; átméretezhető leválasztott ablak (szélesség és magasság); a napi lista színes pontjainak elhelyezése javítva.
- A kategóriák színe újra állítható: a rendszer színpanelje a menüsori ablakból nem nyílt meg, helyette beépített színválasztó (16 színminta és `#RRGGBB` mező).

### 1.3.1

- **Kézi felvitel az OTS-be** (fejléc ikon, Beállítások › Skill): külön ablak a Munkajelentő, a Költségelszámolás és a Létszámjelentő adataival, naptárban, felsorolásban és az OTS táblázatának megfelelő oszlopokban; kattintásra vágólapra másol, „felvittem” jelölés, Google Maps hivatkozás az útvonalakhoz, opcionálisan a skill szabályai szerint (8-ra kiegészítés, `!!!`).
- **Kategóriák színei** (Beállítások): a naptárban, a napi listában és a kézi felviteli ablakban jelennek meg.

### 1.3.0

- **Skill-telepítő:** több célra (Claude, ChatGPT/Codex, Gemini CLI), kiválasztható feladatokkal; csak a kijelölt feladatokhoz kér adatot (név, székhely, gyülekezetek).
- **Utazás:** Indulás – Munkahely(ek) – Érkezés mezők; a Költségelszámolás ezekből számol Google Maps útvonalat.
- **Gyülekezeti létszámjelentő:** negyedévenként a második és hetedik szombaton; külön `letszamjelentesek.csv`; a skill innen olvassa a számokat.
- **Naptár:** beállítható munkanap-sáv (a sávon kívüli bejegyzések jelzése) és a hét kezdőnapja.
- **Jelzések:** napi 8 óra (piros pont), hiányos és kitöltetlen napok, hosszú kihagyás utáni emlékeztető ikon és sáv.
- **Megjelenés:** alapból az Adventista jelkép a menüsorban; négy színséma; világos, sötét és rendszer mód.
- **Stabilitás:** védett dátumszámítás egységtesztekkel (2024–2035, több időzónában), önellenőrző tesztek a build része.

### 1.2.0

- **Claude Skill telepítése** (Beállítások): a csomag tartalmazza a skillt, és egy négylépéses varázsló telepíti a `~/.claude/skills` mappába (név, székhely és gyülekezetek megadásával; meglévő skill felülírása előtt másolat készül). A csomagolt skill a személyes skillből készül a `scripts/make-skill-template.py` szkripttel a build során; személyes adat nem kerül bele, a létszámjelentő feladat pedig mindig a felhasználótól kér valós számokat.
- **Használati útmutató**: `docs/HASZNALATI_UTMUTATO.md` (forrás), a build ebből készít önálló HTML-t (az app Beállításaiból megnyitható) és PDF-et (`dist/`).
- A skill (Havi munkajelentő, Költségelszámolás) már nem külső időmérő szolgáltatásból, hanem kizárólag ennek az alkalmazásnak az adatfájljából dolgozik.

### 1.1.5

- a napi összesítőben 1 fő és 1 alkalom is 1 órának számít („Összesen: …”). A Pomodoro hátralévő ideje a menüsorban a Beállításokban kapcsolható. A skill a pomókat napi és típusonkénti összegben kerekíti fel, nem külön-külön.

### 1.1.4

- a menüsori ikonra jobb kattintásra (vagy Ctrl+kattintásra) menü jelenik meg: ablak megnyitása, a futó időzítő vagy pomo leállítása/elvetése, leválasztott ablak, kompakt nézet, menüsori ikon választása, adatfájl megjelenítése, Kilépés.

### 1.1.3

- a menüsori ablak újra a tartalom magasságát veszi fel (az 1.1.2-ben vékony csíkká zsugorodott). A hosszú napi lista és a Beállítások saját, rögzített magasságú görgethető területet kapott, így az ablak a képernyőnél nem nőhet magasabbra. Alacsony képernyőn (880 pontnál kisebb látható magasság) az ablak automatikusan kompakt.

### 1.1.2

- összeomlás-javítás (az ablak magassága a képernyőnél nem nőhet nagyobbra, a tartalom görgethető; a leválasztott ablak rögzített méretű, kézzel átméretezhető), a lapfülek teljes területe kattintható, a hibás számok a CSV-ben nem okozhatnak leállást, és a Beállításokban megerősítéssel az összes adat törölhető (alapállapot).

### 1.1.1

- ha van leválasztott ablak, a menüikonra kattintás azt hozza előre (a lenyíló ablak nem nyílik meg mellette).

### 1.1.0

- Jövőbeli napra (és a mai nap jövőbeli idejére) nem lehet bejegyzést felvenni, sem kézzel, sem a naptárban.
- A napi lista mellett „Ma” gomb ugrik a mai napra.
- Rögzítés (vagy leállítás) után az űrlap kiürül.
- A helyszínek listája automatikusan épül, és a Beállításokban szerkeszthető. A tevékenység-kategóriákhoz saját kategória adható (az `EGYEDI_` kódú bejegyzéseket a skill nem viszi át az OTS-be), a beépített OTS-kategóriák elrejthetők.
- Leválasztható, mozgatható, kitűzhető ablak (a fejléc ikonja), és kompakt nézet.
- Menüikon: Pomo közben paradicsom, szünetben csésze (mindhárom ikon cserélhető), a lejárt pomo és szünet hangja választható.
