# Treska — primjena dizajna iz `design_handoff_treska_android/`

Uzimam **samo dizajn** iz handoffa (paleta, tipografija, raspored, ikone, veličine).
Backend, podaci i logika ostaju postojeći Flutter data sloj (GTFS + REST + WS).
Ne radim Kotlin/Compose prepisivanje i ne radim `FakeTransitRepository`.

## 1. Paleta — `lib/core/theme.dart`
Zamjena amber/neon identiteta ZET plavom iz handoffa (tablica boja, sekcija „Design tokeni“).

| Token | Light | Dark | Gdje se koristi |
|---|---|---|---|
| surface / bg | `#F8FAFD` | `#0E1217` | pozadina, sheet |
| surfC (panelAlt) | `#EDF0F6` | `#171B21` | hover, kartice, uvučene plohe |
| surfCH (panel) | `#E7ECF2` | `#20242C` | search bar, chipovi, panel |
| ink / text | `#151B24` | `#E8EBF1` | primarni tekst |
| ink2 / textDim | `#4F5661` | `#A5ABB5` | sekundarni tekst |
| outline (border) | `#A8AEB8` | `#5E646C` | obrub chipova, ručka |
| outlineV (borderStrong) | `#DADEE5` | `#2E333B` | razdjelnici |
| primary / accent | `#1D5AB0` | `#92C1FD` | ZET plava, akcent |
| onPrimary | `#FCFCFC` | `#0A254D` | tekst na primary |
| primaryC | `#CAE0FF` | `#1C3C6B` | FAB, aktivni filter |
| onPrimaryC | `#022659` | `#D5E6FF` | tekst na primaryC |
| tram | `#1D5AB0` | `#92C1FD` | tram badge |
| tramInk | `#FCFCFC` | `#031D44` | tekst na tram |
| bus | `#B55422` | `#F2AD73` | bus badge |
| busInk | `#FCFCFC` | `#401A01` | tekst na bus |
| live | `#D02C2A` | `#FD7468` | Stiže / DOLAZI |
| liveC / onLiveC | `#FFDEDA` / `#901114` | `#5A2520` / `#FEDBD6` | „Stiže“ pilula |
| ok | `#1B9247` | `#6FD087` | Uživo / na vrijeme |
| warn | `#9D5300` | `#F2B966` | kasni |
| inverse / onInverse | `#282E38` / `#EBEFF4` | `#E1E5EA` / `#1C222B` | snackbar |

- `ZetColors` dobiva: `primary`, `onPrimary`, `primaryContainer`, `onPrimaryContainer`,
  `tramInk`, `busInk`, `live`, `liveContainer`, `onLiveContainer`, `warn`, `ok`,
  `inverse`, `onInverse`, `surfaceContainer`, `surfaceContainerHigh`, `outline`, `outlineVariant`.
- `buildZetTheme` gradi pravi Material 3 `ColorScheme` iz tih vrijednosti.
  Dynamic color **isključen** (nije ni uključen).
- `TransitColors`-ekvivalent = postojeći `ZetColors` extension (ostaje `context.zet`).
- Tipografija: zadržavam mono (LED identitet) kao u ostatku app, ali veličine/težine
  prilagođavam handoffu (ETA 24, naziv stanice 22, linija 18, chip 14, sekundarno 13, legenda 12).

## 2. Karta — `lib/ui/map_panel.dart`
- OSM podloga (light) ostaje; dark = postojeći Esri dark (handoff dopušta pravu tamnu podlogu).
- **Scrim** gradijent pod status barom (36 dp, `surface` → transparent).
- **Zoom kontrole** desno: kartica 48 dp, radijus 12, `surfaceContainerHigh`, `+`/`−`.
- **FAB lokacija** 56×56, radijus 16, `primaryContainer`, ikona `my_location`.
- Chip **„Uživo“** ispod search bara: zelena pulsirajuća točka + „Uživo“ + broj tramvaja/autobusa.
- Zadržavam postojeću dijagnostiku (i), postavke (zubčanik) i živi „SADA / N min“ chip —
  on je informativniji od pukog „Uživo“, pa ga spajam u „Uživo“ chip.
- Markeri: tram = pilula (radijus 11), bus = zaobljeni kvadrat (radijus 5), 22 dp visine,
  2 dp `surface` obrub, boje tram/bus + odgovarajući ink.
- Radius krug 800 m u `primary` 5 % + isprekidani obrub.
- Korisnik: plava točka 14 dp u halo krugu.

## 3. Bottom sheet — `lib/ui/board_panel.dart`
- M3 bottom sheet s ručkom, radijus 28 gore, tri visine: **peek 200 / half 520 / full 860**.
- Zaglavlje: naziv stanice 22 sp, `directions_walk` + „NN m · N min hoda“ (m/80, min 1), `star`.
- Red **filter chipova** „Tramvaji N“ / „Autobusi N“ (mijenja postojeći TRAM/BUS tab) +
  obližnje stanice kao suggestion chipovi.
- Popis dolazaka **grupiran po liniji + smjeru** (do 12 grupa, sortirano po prvom dolasku):
  badge 52×40 (tram radijus 20 / bus radijus 10), odredište, točka stanja
  (Uživo puna `ok` / Procjena prsten / Raspored puna `outline`), kašnjenje samo za Uživo,
  desno ETA 24 sp ili pilula **„Stiže“** (≤45 s), „zatim X, Y min“.
- Legenda na dnu: „Uživo (GPS)“ / „Procjena“ / „Raspored“.

## 4. Detalji dolaska — novi `lib/ui/arrival_details.dart`
- Timeline stanica, ETA kartica 36 sp, status („Uživo · kasni N min“ / „Procjena prema
  zadnjoj poziciji“ / „Po rasporedu, bez GPS-a“), trasa na karti.
- *Napomena:* za timeline trebam listu stajališta dotičnog polaska. Ako je već u
  podacima — koristim; ako nije, dodajem u worker/feed_engine. Provjeravam prije pisanja.

## 5. Pretraga — novi `lib/ui/search_screen.dart`
- Full-screen overlay, filtar po nazivu stanice ili broju linije, „Stanice u blizini“ /
  „Rezultati (N)“, redak s avatarom, linijama i udaljenošću.

## 6. Postavke — `lib/ui/settings_screen.dart`
- Uskladiti dizajn s ostatkom: nove boje, M3 top bar, radius 28/16, sekcije
  (Izgled → Tema segmented; Karta → Radijus 400/800/1200 m; Podaci; Ažuriranje).
- **Radijus** postaje stvarna postavka (novi `SettingsController`, sprema se) i mijenja
  krug na karti + filtar stanica. Prije je bio fiksno 800 m.

## 7. Ikona — `android/app/src/main/res/`
- Iz `assets/icon/*.svg` radim vector drawable:
  - `drawable/ic_launcher_foreground.xml` (plava `#1351A6`, žuta `#F4CE23`)
  - `drawable/ic_launcher_monochrome.xml`
  - `values/ic_launcher_background.xml` = `#F6F9FC`
  - `mipmap-anydpi-v26/ic_launcher.xml` + `ic_launcher_round.xml` s
    `<background><foreground><monochrome>`
- Zadržavam postojeće PNG fallbackove za stare Android verzije.

## Struktura datoteka (mijenjam / dodajem)
```
lib/core/theme.dart              [M] ZET plava paleta + M3 scheme + radii
lib/core/tokens.dart             [A] spacing/radius konstante iz handoffa
lib/settings_controller.dart     [A] radijus (400/800/1200) + buduće preference
lib/app.dart                     [M] prosljeđuje SettingsController
lib/main.dart                    [M] stvara SettingsController
lib/ui/home_screen.dart          [M] sheet s tri visine, scrim, FAB
lib/ui/map_panel.dart            [M] scrim, zoom, FAB, Uživo chip, markeri
lib/ui/board_panel.dart          [M] sheet sadržaj, grupiranje, chipovi, legenda
lib/ui/arrival_details.dart      [A] detalji + timeline
lib/ui/search_screen.dart        [A] pretraga
lib/ui/settings_screen.dart      [M] uskladi dizajn + radijus
lib/ui/widgets/vehicle_marker.dart [M] pilula/kvadrat markeri
lib/ui/widgets/stop_card.dart    [M] → grupirani redci po liniji+smjeru
lib/ui/widgets/arrival_row.dart  [M] točka stanja, „Stiže“, „zatim“
android/app/src/main/res/...     [M/A] adaptive ikona
test/*                           [M] ažurirati na novi dizajn
```

## Verifikacija (na kraju)
1. `flutter analyze` + `flutter test`.
2. Release APK → emulator (`zet2`).
3. Usporedba s `zet.skoljka.org`: broj vozila, dolasci na istoj stanici, RT/raspored.
4. Screenshot u light i dark.
5. Commit lokalno; **bez pusha** bez tvoje potvrde.
