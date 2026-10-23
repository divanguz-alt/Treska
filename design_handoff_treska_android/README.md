# Handoff: Treska — Android aplikacija (ZET uživo)

## Pregled
Treska je Android aplikacija za praćenje ZET tramvaja i autobusa u Zagrebu uživo, po uzoru na zet.skoljka.org. Glavni ekran je karta preko cijelog ekrana s vozilima koja se kreću. Ispod karte je bottom sheet s dolascima na najbližu stanicu. Backend i feedovi vozila i dolazaka rade se odvojeno, a ovaj paket pokriva **samo UI/dizajn**.

## O datotekama
Datoteke u `reference/` su **dizajn reference izrađene u HTML-u**: prototipovi koji pokazuju izgled i ponašanje, ne produkcijski kod. Zadatak je **ponovno izraditi ovaj dizajn u nativnoj Android aplikaciji**:
- **Kotlin + Jetpack Compose + Material 3** (`androidx.compose.material3`)
- Karta: **MapLibre Android** ili **osmdroid** s OpenStreetMap podlogom
- Ikone: **Material Symbols Rounded** (`androidx.compose.material:material-icons-extended` ili vektorski resursi)

Prototip se otvara u browseru: `reference/Treska v2.dc.html`. Uz njega mora biti `support.js` u istoj mapi, a potreban je internet zbog fontova, Leafleta i podloge karte. Podaci u prototipu su simulirani, a logika simulacije služi samo kao primjer oblika podataka.

## Vjernost
**High-fidelity.** Boje, tipografija, razmaci, radijusi i interakcije su konačni. Izradi UI što vjernije, koristeći Material 3 komponente gdje postoje.

## Ekrani

### 1. Karta + dolasci (glavni ekran)
Okvir prototipa: 412 × 915 dp (Pixel 8/9). Edge-to-edge: karta ide ispod status bara i gesture trake.

**Slojevi (odozdo prema gore):**
1. **Karta**: cijeli ekran. OSM podloga. Light tema: `saturate(.55) brightness(1.03)`. Dark tema: ista podloga s `invert(1) hue-rotate(180deg) brightness(.92) contrast(.82) saturate(.45)` ili, bolje, prava tamna podloga (npr. MapLibre dark stil). Početni zoom **15**, min 11, max 18. Centar je odabrana stanica, pomaknut prema gore za pola visine sheeta minus 60 dp, da stanica bude vidljiva iznad sheeta.
2. **Scrim pod status barom**: visina 36 dp, linearni gradijent `scrim` → transparent.
3. **Search bar** (M3 SearchBar): top 44 dp, lijevo/desno 16 dp, visina 56, radijus 28, boja `surfCH`, sjena (elevation 3). Sadržaj: ikona `search` 24 dp u boji `ink`, placeholder „Traži stanicu ili liniju” (16 sp, `ink2`), desno dva icon buttona 48 × 48: `dark_mode`/`light_mode` (mijenja temu) i `settings` (otvara Postavke).
4. **Chip „Uživo”**: 10 dp ispod search bara. Visina 32, radijus 8, `surfCH`. Zelena točka 8 dp (`ok`) s pulse animacijom (scale 1→2.6, opacity .85→0, 2 s, ponavlja se), tekst „Uživo” (`ink`) + „176 tramvaja · 348 autobusa” (`ink2`), 13 sp medium, tabularne znamenke.
5. **Zoom kontrola**: desno 20 dp, 84 dp iznad vrha sheeta. Kartica 48 dp širine, radijus 12, `surfCH`. Dva gumba visine 44 (`add`, `remove`) s razdjelnikom 1 dp (`outlineV`).
6. **FAB lokacija**: M3 FAB 56 × 56, radijus 16, `primaryC` / ikona `my_location` u `onPrimaryC`. Desno 16 dp, 16 dp iznad vrha sheeta (najviše na 640 dp). Kad se sheet pomiče, FAB i zoom ga prate: animacija `bottom`, 300 ms, cubic-bezier(.2,.8,.2,1).
7. **Bottom sheet**: M3 standard bottom sheet, radijus 28 gore, `surface`. Tri visine: **peek 200**, **half 520** (zadano), **full 860 dp**. Ručka 32 × 4, `outline`, u zoni visine 28. Povlačenje ide na najbližu visinu, a tap na ručku ide redom peek → half → full → peek.
8. **Gesture traka**: Android sistemska, sheet ima 30 dp donjeg paddinga.

**Markeri na karti:**
- **Tramvaj**: pilula visine 22 dp, širina 30 (36 za troznamenkaste), radijus 11, fill `tram`, broj linije `tramInk` 12 sp weight 650, obrub 2 dp `surface`, sjena.
- **Autobus**: zaobljeni kvadrat visine 22, širina 26 (36 za troznamenkaste), radijus 5, fill `bus`, tekst `busInk`.
- **Odabrano vozilo** (u detaljima): isti marker uvećan 1.3×, z-index iznad ostalih.
- **Stanica**: krug 12 dp, fill `surface`, obrub 2 dp `ink2`. Aktivna: krug 20 dp, fill `primary`, obrub 3 dp `surface`. Tap na stanicu je odabire.
- **Korisnik**: plava točka 14 dp (#2B66E0, obrub 3 dp bijeli) unutar halo kruga 28 dp (rgba(40,100,230,.2)).
- **Radijus**: krug oko korisnika (zadano 800 m), obrub 1.5 dp `primary`, isprekidano (2, 6), fill `primary` 5 %.
- **Trasa** (u detaljima): polilinija 6 dp, boja linije (`tram` ili `bus`), opacity .9, zaobljeni krajevi.

**Sadržaj sheeta: popis**
- **Zaglavlje** (padding 0 12 10 24): naziv stanice 22 sp weight 600, letter-spacing -0.01em. Ispod: ikona `directions_walk` 18 + „81 m · 1 min hoda” 14 sp `ink2` (minute = udaljenost / 80 m, zaokruženo, najmanje 1). Desno icon button 48 `star`: kad je spremljeno, FILL 1 na `primaryC`/`onPrimaryC`, inače `ink2` bez pozadine.
- **Red chipova** (horizontalni scroll, padding 0 24 12, gap 8):
  - M3 **Filter chipovi** „Tramvaji N” i „Autobusi N” (N = broj različitih linija). Odabran: `primaryC` + ikona `check`. Neodabran: obrub `outline` + ikona `tram`/`directions_bus`. Visina 32, radijus 8, 14 sp medium. Oba su uključena po defaultu i rade nezavisno.
  - Vertikalni razdjelnik 1 dp `outline`.
  - **Obližnje stanice** kao suggestion chipovi: „Britanski trg 420 m”. Prikazuju se samo stanice unutar odabranog radijusa, bez trenutne stanice. Tap mijenja stanicu, a karta se centrira na nju.
- **Popis dolazaka**, **grupiran po liniji + smjeru** (do 12 grupa, sortirano po prvom dolasku). Redak: grid `52dp | 1fr | auto`, gap 14, padding 12, radijus 16, hover/pressed `surfC`.
  - Badge: 52 × 40, tram radijus 20 / bus radijus 10, boja linije, broj 18 sp weight 650.
  - Sredina: odredište 16 sp medium (jedan red, ellipsis). Ispod, 13 sp `ink2`: točka 7 dp + način + kašnjenje.
    - Točka: **Uživo** = puna `ok`. **Procjena** = prazan prsten `ink2`. **Raspored** = puna `outline`.
    - Kašnjenje samo za Uživo: „· kasni 3 min” (`warn`), „· 1 min ranije” / „· na vrijeme” (`ok`).
  - Desno:
    - Ako je ETA ≤ 45 s i nije raspored: pilula **„Stiže”**, visina 32, radijus 16, `liveC`/`onLiveC`, s pulsirajućom točkom `live`.
    - Inače veliki broj minuta 24 sp weight 600 + „min” 13 sp. Procjena ima prefiks „≈”. Raspored pokazuje vrijeme „19:01” u `ink2`.
    - Ispod: „zatim 9, 17 min” (sljedeća dva dolaska iste grupe; za raspored „zatim 19:05, 19:20”), 12 sp `ink2`.
  - Prazno stanje: „Nema dolazaka za odabrani filtar.”
- **Legenda** (fiksno dno, obrub gore `outlineV`, 12 sp `ink2`): „Uživo (GPS)”, „Procjena”, „Raspored” s istim točkama.

**Sadržaj sheeta: detalji dolaska** (tap na grupu; sheet ide na half; ulazna animacija translateY 10 → 0 + fade, 220 ms)
- Zaglavlje: `arrow_back` (48) · badge 56 × 44 · odredište 20 sp weight 600 · „Tramvaj · vozilo 2213” 13 sp `ink2`.
- ETA kartica: margine 0 16 12, padding 16 16 16 20, radijus 20, `surfC`. „Do stanice {naziv}” 13 sp, ETA 36 sp weight 650 (ili „Stiže” u `live`), status 13 sp medium:
  - „Uživo · kasni N min” (`warn`) / „Uživo · na vrijeme” ili „Uživo · N min ranije” (`ok`)
  - „Procjena prema zadnjoj poziciji” / „Po rasporedu, bez GPS-a” (`ink2`)
- Gumb „Podsjeti me” (M3 outlined button, visina 40, radijus 20, ikona `notifications`). Kad je uključen: filled `primary`, tekst „Uključeno”, ikona `notifications_active`. Snackbar: „Javit ćemo ti 2 minute prije dolaska linije {N}”. Podsjetnik šalje lokalnu notifikaciju kad je ETA 2 min.
- **Timeline stanica**: grid `20 | 1fr | auto`, gap 14. Tračnica 4 dp u boji linije (prošli dio na 30 % opacity). Točke 14 dp (fill `surface`, obrub 3 dp boje linije). Tvoja stanica 20 dp, puna, weight 600, sufiks „ · tvoja stanica”. Vrijeme 14 sp tabularno, ili „prošao”. Ispod zadnje prošle stanice je chip „Vozilo 2213 je ovdje” (boja linije, ikona `tram`/`directions_bus`).
- Na karti: crta se trasa, odabrano vozilo se ističe, a kamera radi fitBounds(vozilo, stanica) s paddingom (gore 120, dolje visina sheeta), najviše zoom 16.

### 2. Pretraga
Full-screen overlay, `surface`, ulaz fade + translateY 180 ms. M3 SearchBar u aktivnom stanju (56 dp, radijus 28, `surfCH`) s `arrow_back` i poljem (autofocus). Naslov sekcije 14 sp medium `primary`: „Stanice u blizini” ili „Rezultati (N)”. Redak: avatar 40 dp `surfCH` s ikonom `location_on` (spremljene: `star` FILL 1), naziv 16 sp, „Linije 1, 6, 11” 13 sp `ink2`, udaljenost desno. Filtrira se po nazivu stanice ili početku broja linije. Tap odabire stanicu i zatvara pretragu.

### 3. Postavke
Full-screen, M3 TopAppBar (64 dp) s `arrow_back` i naslovom „Postavke” 22 sp. Sekcije (naslov 14 sp medium `primary`, padding 16 24 8):
- **Izgled → Tema**: segmented button (2 opcije: „Svijetla” `light_mode` / „Tamna” `dark_mode`). Odabrana: `primaryC` + `check`. Preporuka: dodati i „Sustav” (prati sistemsku temu) kao default.
- **Karta → Radijus obližnjih stanica**: opis „Stanice unutar ovog radijusa prikazuju se u kartici.” Segmented: 400 m / 800 m / 1200 m. Mijenja krug na karti i popis chipova.
Ekran je predviđen za dodavanje novih stavki.

### Snackbar
M3 Snackbar, `inverse`/`onInverse`, radijus 8, iznad FAB-a, 2.8 s. Tekstovi: „Stanica spremljena”, „Uklonjeno iz spremljenih”, „Podsjetnik isključen”, „Linija {N} stiže za 2 minute.”

## Stanje
- `theme`: light | dark (+ preporučeno system), sprema se u DataStore
- `selectedStopId`; `favorites: Set<StopId>`; `radiusMeters`: 400 | 800 | 1200
- `filter: { tram: Boolean, bus: Boolean }`
- `sheetState`: peek | half | full
- `selectedArrivalId?` (detalji); `reminders: Set<ArrivalId>`
- `searchOpen`, `query`; `settingsOpen`
- Odabir stanice resetira detalje i diže sheet barem na half.

## Ugovor s backendom (što UI očekuje)
```kotlin
data class Vehicle(val id: String, val line: String, val type: VehicleType /* TRAM, BUS */, val lat: Double, val lng: Double, val bearing: Float?, val updatedAt: Instant)
data class Stop(val id: String, val name: String, val lat: Double, val lng: Double, val lines: List<String>)
data class Arrival(
  val id: String, val stopId: String, val line: String, val type: VehicleType, val destination: String,
  val etaSeconds: Int, val mode: ArrivalMode /* REALTIME (GPS), ESTIMATE, SCHEDULE */,
  val delayMinutes: Int /* + kasni, − ranije, samo za REALTIME */, val vehicleId: String?
)
data class TripStop(val stopId: String, val name: String, val time: Instant, val passed: Boolean)
```
- Vozila se osvježavaju svakih ~5–10 s. Markeri se animiraju interpolacijom između pozicija, bez skokova.
- ETA se lokalno odbrojava svake sekunde između osvježavanja.
- Tip vozila: linije < 100 su tramvaji, ostale autobusi (pravilo iz prototipa). Bolje je da backend šalje `type`.

## Design tokeni

### Boje
| Token | Uloga | Light | Dark |
|---|---|---|---|
| `surface` | Pozadina, bottom sheet | `#F8FAFD` | `#0E1217` |
| `surfC` | Surface container (hover, kartice) | `#EDF0F6` | `#171B21` |
| `surfCH` | Surface container high (search bar, chipovi) | `#E7ECF2` | `#20242C` |
| `scrim` | Gradijent ispod status bara | `#F8FAFD` | `#0E1217` |
| `ink` | Primarni tekst | `#151B24` | `#E8EBF1` |
| `ink2` | Sekundarni tekst | `#4F5661` | `#A5ABB5` |
| `outline` | Obrub chipova, ručka | `#A8AEB8` | `#5E646C` |
| `outlineV` | Razdjelnici | `#DADEE5` | `#2E333B` |
| `primary` | Primary (ZET plava) | `#1D5AB0` | `#92C1FD` |
| `onPrimary` | Tekst na primary | `#FCFCFC` | `#0A254D` |
| `primaryC` | Primary container (FAB, aktivni filter) | `#CAE0FF` | `#1C3C6B` |
| `onPrimaryC` | Tekst na primary container | `#022659` | `#D5E6FF` |
| `tram` | Tramvaj oznaka/badge | `#1D5AB0` | `#92C1FD` |
| `tramInk` | Tekst na tram badge | `#FCFCFC` | `#031D44` |
| `bus` | Autobus oznaka/badge | `#B55422` | `#F2AD73` |
| `busInk` | Tekst na bus badge | `#FCFCFC` | `#401A01` |
| `live` | Stiže (crvena) | `#D02C2A` | `#FD7468` |
| `liveC` | Pozadina „Stiže” pilule | `#FFDEDA` | `#5A2520` |
| `onLiveC` | Tekst „Stiže” | `#901114` | `#FEDBD6` |
| `ok` | Uživo / na vrijeme | `#1B9247` | `#6FD087` |
| `warn` | Kasni | `#9D5300` | `#F2B966` |
| `inverse` | Snackbar pozadina | `#282E38` | `#E1E5EA` |
| `onInverse` | Snackbar tekst | `#EBEFF4` | `#1C222B` |

Prototip koristi OKLCH, a hex vrijednosti su preračunate. Za Compose definiraj `lightColorScheme`/`darkColorScheme` (primary, primaryContainer, surface, surfaceContainer = surfC, surfaceContainerHigh = surfCH, outline, outlineVariant = outlineV, inverseSurface = inverse) i dodatni `TransitColors` (tram, bus, live, ok, warn) kroz `CompositionLocal`. Dynamic color (Material You) **isključi**, jer su ZET plava i boje linija dio identiteta.

### Tipografija
Font: **Roboto Flex** (Google Fonts; na Androidu može i sistemski Roboto). Sve znamenke su tabularne (`fontFeatureSettings = "tnum"`).
| Uloga | Veličina | Težina |
|---|---|---|
| Naziv stanice | 22 sp | 600 |
| Odredište u detaljima | 20 sp | 600 |
| ETA u detaljima | 36 sp | 650, ls -0.03em |
| ETA u popisu | 24 sp | 600, ls -0.02em |
| Broj linije (badge) | 18 sp | 650 |
| Odredište u popisu / tijelo | 16 sp | 500 / 400 |
| Chipovi, gumbi | 14 sp | 500 |
| Sporedni tekst | 13 sp | 400 |
| Legenda, „zatim …” | 12 sp | 400 |

### Razmaci, radijusi, pokret
- Razmaci: 4 · 8 · 12 · 14 · 16 · 20 · 24 dp. Horizontalni padding sheeta je 24 (popis 12 + 12 unutar retka).
- Radijusi: chip 8 · zoom 12 · FAB 16 · redak 16 · ETA kartica 20 · pilula 20 · sheet 28 · search 28.
- Elevation: search bar i chipovi na karti level 2–3, FAB level 3, sheet level 1 + sjena prema gore.
- Easing: cubic-bezier(.2,.8,.2,1) (M3 emphasized decelerate). Trajanja: 180–300 ms. Poštuj „Remove animations” u sistemskim postavkama.
- Touch targeti su najmanje 48 dp.

## Ikona aplikacije
Odabrana je varijanta **1a, svijetla**: bijela podloga, tramvaj sprijeda u ZET plavoj, žuta svjetla i ploča s brojem linije.
- `assets/icon/ic_launcher_foreground.svg`: adaptive foreground, 108 × 108, sadržaj unutar safe zone 66 dp
- Background boja: `#F6F9FC` (`ic_launcher_background`)
- `assets/icon/ic_launcher_monochrome.svg`: themed ikona (Android 13+), crna na prozirnom
- `assets/icon/ic_launcher_full.svg` / `ic_launcher_playstore.svg`: pune ikone s podlogom (izvezi Play Store PNG 512 × 512)
- Boje ikone: plava `#1351A6`, žuta `#F4CE23`, sjena tla `#E0E9F6`

U Android Studiju: **File → New → Vector Asset** za svaki SVG, zatim `mipmap-anydpi-v26/ic_launcher.xml` s `<background>`, `<foreground>` i `<monochrome>`.

## Karta (napomena)
Javni `tile.openstreetmap.org` ima pravila korištenja (obavezan User-Agent, nije za velik promet). Za produkciju koristi vlastiti tile server ili providera (MapTiler, Stadia, Protomaps) s OSM podacima. Atribucija „© OpenStreetMap contributors” mora biti vidljiva.

## Datoteke
- `reference/Treska v2.dc.html`: glavni interaktivni prototip (karta, sheet, detalji, pretraga, postavke). Za tokene i logiku pogledaj `THEMES`, `fmt()` i `renderVals()`.
- `reference/Treska ikone.dc.html` + `TreskaIcon.dc.html`: sve varijante ikone. Odabrana je **2a / 1a light**.
- `reference/support.js`: runtime potreban da se .dc.html otvori u browseru.
- `reference/original_light.png`, `original_dark.png`: polazni dizajn (prije redizajna), samo kao kontekst.
- `assets/icon/*.svg`: ikona za izvoz.
