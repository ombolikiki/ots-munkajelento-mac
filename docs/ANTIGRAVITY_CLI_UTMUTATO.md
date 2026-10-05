# Ingyenes MI-asszisztens az OTS kitöltéséhez: Antigravity CLI

OTS Munkajelentő Tracker kiegészítő útmutató · Mac (macOS 12 vagy újabb) · 2026. októberi állapot

> **Röviden:** ha nincs előfizetésed Claude-ra vagy ChatGPT-re, az OTS-t a **Google ingyenes Antigravity CLI** (`agy`) nevű asszisztensével is kitöltetheted az **OTS Adminisztráció** skill segítségével. Személyes Google-fiók elég hozzá, kártya nem kell. **Kipróbáltuk: az asszisztens látja és olvassa az OTS-t, és kattint rajta.** Mint minden asszisztensnél, a lezárás előtt itt is nézd át az eredményt, és ne engedd lezárni a lapot, amíg át nem néztél mindent.

> **Fontos:** a Google **Gemini CLI** nevű korábbi eszköze 2026. június 18-tól személyes fiókkal már nem használható (a bejelentkezéskor „This client is no longer supported” hibát ír). Az utódja az Antigravity CLI. Ha régi leírásban Gemini CLI-t látsz, azt ne telepítsd.

## 1. Mikor érdemes ezt használni?

- Nincs fizetős MI-előfizetésed, és az ingyenes Claude Chat nem tud böngészőt vezérelni (az OTS kitöltéséhez ez kell).
- Szívesen dolgozol a Terminálban pár parancs erejéig.
- Ha ez nem neked való, használd az OTS Munkajelentő Tracker **Kézi felvitel az OTS-be** ablakát (a főablak fejlécében a táblázat ikon). Ehhez semmilyen MI-szolgáltatás nem kell: az adataidat naptárban, felsorolásban és az OTS táblázatának megfelelő oszlopokban látod, és kattintásra a vágólapra másolhatod őket.

## 2. Mi kell hozzá?

| Mi | Megjegyzés |
|---|---|
| **OTS Munkajelentő Tracker** (1.3.3 vagy újabb) | A hónap adataival. A skillt innen telepíted, és az asszisztens az adatokat is ebből olvassa. |
| **Google-fiók** | Személyes fiók, amivel be tudsz jelentkezni az Antigravity CLI-be. |
| **Google Chrome** | A böngészővezérléshez. |
| **macOS 12 (Monterey) vagy újabb** | Intel és Apple Silicon Macen is megy. |
| **Internetkapcsolat** | A telepítéshez és a használathoz. |
| **OTS-hozzáférés** | A saját OTS-felhasználóddal be tudsz jelentkezni (DETKapu vagy TETKapu). |

Az Antigravity ingyenes csomagja személyes fiókkal elérhető, **heti kerettel** (a pontos mennyiséget a Google nem közli, a terhelés és a feladat bonyolultsága függvénye). Egy havi munkajelentő kitöltése nagyobb feladat; ha elfogy a heti keret, a következő hétig kell várni, vagy a Kézi felvitel ablakot használd.

Node.js-re **nincs szükség**.

## 3. Egyszeri beállítás (kb. 15 perc)

### 3.1. Az Antigravity CLI telepítése

Nyisd meg a **Terminált** (Launchpad › Egyéb › Terminál, vagy Spotlight: „Terminal”), és illeszd be:

```
curl -fsSL https://antigravity.google/cli/install.sh | bash
```

Ezt a parancsot az OTS Munkajelentő Tracker skill-telepítője is megmutatja, és a **Másolás** gombbal a vágólapra teheted.

A telepítő a Google hivatalos szkriptje: letölti a programot, ellenőrzi a letöltés SHA512-ellenőrző összegét, majd az `agy` nevű programot a `~/.local/bin` mappába másolja. A végén kiegészíti a `~/.bash_profile` és `~/.profile` fájlt egy sorral, amely a `~/.local/bin` mappát a PATH-ba teszi. A szkript végén ezt látod: „Antigravity CLI installed successfully”.

Ellenőrzés: nyiss egy **új Terminál-ablakot**, és írd be:

```
agy --version
```

Ha „command not found” hibát kapsz, add hozzá a PATH-hoz, majd nyiss új ablakot:

```
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

### 3.2. Első indítás és bejelentkezés

Írd be a Terminálba:

```
agy
```

1. Az első indításnál a program színsémát és megjelenítési módot kérdez: válaszd, ami tetszik.
2. Megnyílik a böngésző, jelentkezz be a **Google-fiókoddal** és engedélyezd a hozzáférést. API-kulcsot nem kell megadnod.
3. Ha a Terminálban megjelenik a beszélgetés mezője, a bejelentkezés sikerült. A `/quit` paranccsal kiléphetsz.

Az `agy` a háttérben magától frissíti magát.

### 3.3. A skill telepítése

1. Nyisd meg az **OTS Munkajelentő Trackert**.
2. **Beállítások › Skill telepítése…**
3. A második lépésben jelöld be az **Antigravity CLI (agy)** célt (mellette az „Ingyenes” jelzés áll). A telepítő megmutatja, hogy az `agy` telepítve van-e a gépen.
4. Jelöld ki a feladatokat, amiket szeretnél (például Havi munkajelentő, Költségelszámolás).
5. Az „Adataid” lépésben válaszd ki, hogy a **DETKapu** (ots.detkapu.hu) vagy a **TETKapu** (ots.tetkapu.hu) oldalon dolgozol-e, majd add meg a nevedet, a székhelyedet és a gyülekezeteidet, és telepíts.

A telepítő a skillt a `~/.agents/skills/ots-adminisztracio` mappába másolja. Ez az a mappa, ahonnan az `agy` betölti (a Codex is innen olvas, ezért ha mindkettőt kéred, egyszer másol). Egy meglévő skill felülírása előtt másolatot készít. Ha korábban Gemini CLI-hez telepítettél skillt az alkalmazásból, azt a telepítő eltávolítja (előtte másolatot ment).

### 3.4. Ellenőrzés

Indítsd el az `agy`-t, és kérdezd meg:

```
Sorold fel a skilleket név szerint.
```

A válaszban látnod kell az `ots-adminisztracio` nevet (az `agy-customizations` és az `antigravity-guide` beépített skillek mellett). Ha nem látszik, lépj ki (`/quit`), és indítsd újra az `agy`-t.

## 4. Havi használat

1. Győződj meg róla, hogy az **OTS Munkajelentő Trackerben** a hónap adatai rendben vannak (a kitöltetlen napok címkéi segítenek).
2. Nyisd meg a Terminált, és indítsd az asszisztenst az első kéréssel (csak olvas, semmit nem módosít):

```
agy -i "Használd az ots-adminisztracio skillt. Kapcsold be a böngészőt (/browser), nyisd meg az OTS-t, és csak listázd a Határidők oldalon lévő feladatokat. Semmit ne zárj le, ne töltsél ki és ne módosíts."
```

3. **Az első böngészőhívásnál engedélyt kér.** Ez normális, és több engedélykérdés is jöhet (böngésző megnyitása, oldal olvasása, műveletek). **Olvasd el mindet**, és csak azt engedélyezd, ami az OTS megnyitásához és a Határidők olvasásához kell.
4. Megnyílik egy Chrome-ablak az OTS-szel. **Jelentkezz be benne saját magad.** A jelszavadat soha ne írd be a Terminálba, és az asszisztens sem kérheti el.
5. Az asszisztens kiolvassa a Határidőket, és felsorolja őket. Ha nincs egy sem, azt jelzi (ilyenkor nincs teendő).
6. Ha van határidő, kérheted a feladatot: „Kezdjük a Havi munkajelentővel.” A skill **minden lezárás előtt megáll és megerősítést kér**. Nézd át a táblázatot az OTS-ben (a `!!!`-lal jelölt sorokat javítsd), és csak ezután engedd tovább.

## 5. Amire figyelj

- **Mi lett kipróbálva:** 2026. októberében, Macen, `agy` 1.2.16-tal az asszisztens látta és olvasta az OTS-t, és kattintott rajta. A feladatok teljes végigvitelénél (kitöltés, lezárás) kövesd figyelemmel, mit csinál.
- **Sok engedélykérdés lesz.** Ne használd a `--dangerously-skip-permissions` kapcsolót, amely minden engedélyt automatikusan megad: az OTS-ben visszavonhatatlan műveletek (lezárás) is vannak.
- **Megerősítések a lezárás előtt.** A skill így van megírva, hogy lezárás előtt mindig megáll. Ha ezt valaha kihagyná, szakítsd meg (Ctrl + C), és ne engedd tovább.
- **Heti keret.** Ha elfogy, a következő hétig vársz, vagy a Kézi felvitel ablakot használod.
- **Adatvédelem.** A skill gyülekezeti névsorral is dolgozhat. Mielőtt tagnevekkel használod, olvasd el a Google adatkezelési feltételeit az ingyenes Antigravity használatról, és dönts a saját felelősségedre.
- **Soha ne adj meg jelszót** a Terminálban vagy az asszisztensnek.
- **Az Antigravity asztali program** (grafikus felület) is használható, de a skill betöltése ott más mappából történik (`~/.gemini/config/skills`), és a kezelése bonyolultabb; a parancssoros `agy` az egyszerűbb út.

## 6. Hibaelhárítás

| Mi történik | Mit tegyél |
|---|---|
| `agy: command not found` | Nyiss új Terminál-ablakot. Ha így sem megy, add hozzá a PATH-hoz (lásd a 3.1. pontot). |
| „This client is no longer supported for Gemini Code Assist” | Ez a régi **Gemini CLI** hibája. Ne azt használd: telepítsd az Antigravity CLI-t (3.1. pont). |
| Az `agy` nem látja a skillt | Ellenőrizd, hogy a `~/.agents/skills/ots-adminisztracio/SKILL.md` megvan-e. Ha nincs, futtasd újra a skill-telepítést az alkalmazásból (Antigravity CLI cél). Utána lépj ki (`/quit`), és indítsd újra az `agy`-t. |
| Nem indul a böngésző | Írd be: `/browser`, és engedélyezd. Győződj meg róla, hogy a Chrome telepítve van. |
| Az OTS-be nem jelentkezik be | Jelentkezz be kézzel a megnyílt Chrome-ablakban. Az asszisztens a te bejelentkezett munkameneted használja. |
| Elfogyott a heti keret | Várj a következő hétig, vagy vidd fel az adatokat a **Kézi felvitel az OTS-be** ablakkal. |
| Az asszisztens rossz értéket ír | Szakítsd meg (Ctrl + C), ne zárj le semmit, javítsd az OTS-ben kézzel, és szólj a fejlesztőnek, hogy mi történt. |

---

*Ez az útmutató az OTS Munkajelentő Tracker kiegészítője. Az Antigravity a Google terméke; a beállításai és feltételei változhatnak, ilyenkor a [hivatalos dokumentáció](https://antigravity.google/docs/getting-started) az irányadó.*
