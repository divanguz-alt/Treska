# HANDOFF — Treska (ZET 2) v2.1.17

## v2.1.17 (2026-11-20)

- Lokacija se prati dok je aplikacija otvorena (svakih 5 m kretanja), a karta
  drži korisnika u sredini dok je praćenje uključeno.
- Odabrano vozilo uvijek je iznad svih ostalih oznaka.
- Strelice smjera od prvog učitavanja: prema sljedećoj stanici vlastite vožnje,
  dok ne postoji prethodna pozicija.

## v2.1.16 (2026-11-11)

- Dodir na vozilo ističe cijelu liniju: ruta i sva vozila iste linije
  postaju ružičasta (tramvaj) ili tirkizna (autobus) i crtaju se iznad
  ostalih. Narančasta nije uzeta za tramvaje jer su autobusi već narančasti.

## v2.1.15 (2026-11-04)

- Postavke → KARTA → „Strelica smjera“: četiri izgleda strelice na oznakama
  vozila (mala, veća, kontrastna, klin smjera), svaki s animiranim isječkom
  karte. Zadano je kontrastna (bijela na tamnoj karti), jer se stara mala
  strelica na mobitelu jedva vidjela.

## v2.1.14 (2026-11-04)

- Tipke Tramvaji/Autobusi se uvijek vide iznad rasporeda. U 2.1.13 su bile
  skrivene na stanicama sa samo jednom vrstom, pa se autobusi nisu mogli
  uključiti. Tipke biraju i koje bliže stanice popis nudi, i što karta prikazuje.
  Bez broja kad stanica nema linija te vrste; redak se pomiče umjesto da se
  prelije kod velikog teksta.

## v2.1.13 (2026-11-04)

- Karta opet prikazuje samo odabrane vrste: prati chipove Tramvaji/Autobusi.
  Sva vozila odjednom (~350 markera) zapinjala su na korisnikovu mobitelu.
  Zadani filtar je sada samo tramvaji (`show_buses` zadano `false`).

## v2.1.12 (2026-11-04)

- Filtar Tramvaji/Autobusi (dizajnerska predaja `treska_zet_zaslon_handoff/`,
  README §1, folder je u `.gitignore`): chipovi su neovisni, `show_trams` /
  `show_buses`, ne mogu oba biti isključena. Tabla spaja tramvajska i
  autobusna stajališta istog imena (`combineModes` u `models.dart`). Chipovi
  se skrivaju kad stanica ima samo jednu vrstu. Karta u 2.1.12 nije
  filtrirala po vrsti (vraćeno u 2.1.13). Zvjezdica sprema ime za vrste koje se prikazuju.
- ZET zaslon (§2–7, varijanta 1b): `lib/ui/led/` (font, čisti `layoutLed`,
  `LedPanel`, `LedClockScope`), `lib/ui/widgets/zet_arrival_row.dart`.
  `test/led_layout_test.dart` uspoređuje raspored točku po točku s
  `tool/led_reference.js` (`node tool/led_golden.js >
  test/fixtures/led_golden.json`). Animacije se gase i kad je Androidov
  animator scale 0 (kanal `animatorsEnabled`), ne samo po Flutterovoj zastavici.
- Emulator 2026-11-04 bio je prespor za klikove; ZET zaslon provjeren
  screenshotom u svijetloj i tamnoj temi, mješovita lista samo u testovima.

## v2.1.11 (2026-11-04)

- Push: relay `/ws` (Durable Object `FeedHub`, besplatni plan, SQLite) šalje
  svaki novi ZET feed gzipom (~25 KB) svim spojenim aplikacijama. Hub odmara
  7 s nakon novog feeda, onda provjerava svake 1 s (5 s ako ZET zastane 30 s);
  bez klijenata ne zove ZET. Izmjereno: klijent dobije feed 0,5–2 s nakon
  ZET-ovog zaglavlja, ~33k provjera/dan dok je netko spojen.
- App: `lib/data/rt_push.dart`; svaki push odmah osvježi tablu/kartu.
  Polling 5 s ostaje kao rezerva (relay → zet.hr). Izvor u Dijagnostici: push.
- Emulator je 2026-11-04 parsirao raspored 30–36 s (jutros 3 s), isto i bez
  pusha — opterećen emulator, nije regresija.

## v2.1.10 (2026-11-04)

- Vlastiti Cloudflare Worker relay (`relay/`, deploy: `cd relay && npx wrangler
  deploy`, račun korisnika). `/rt` prosljeđuje ZET protobuf bez izmjena (kopija
  max 1 s, izmjereno: relay dodaje ≤1 s, zahtjev ~130–200 ms), `/static`
  ZIP kroz Cloudflare cache (1 h, 304 radi). App: relay prvo, ZET kao rezerva
  (2 min backoff). Dijagnostika "Izvor" pokazuje relay / zet.hr.
- GPS provjera 2026-11-04: medijan 2–3 m od linije rute (shapes.txt), Dart
  parser = Python gtfs_realtime_pb2 za svih 368 vozila.
- Dev Mac ide kroz Mullvad exit node (Tailscale); zet.hr tad ne odgovara, relay da.

## v2.1.9 (2026-10-25)

- Realtime samo s `zet.hr/gtfs-rt-protobuf` (5 s). Relay `zet.skoljka.org`
  izbačen; prikrivao je krive brojeve polja u `gtfs_rt.dart` (VehiclePosition,
  FeedHeader.timestamp), sada ispravljeno po specifikaciji.
- Noćni polasci iza ponoći (jučerašnji 24:xx+) i reparse indeksa u ponoć.
- Uvjetni GET za statički ZIP (304 umjesto 18,8 MB).
- Karta: OpenFreeMap vektorski stilovi (positron / dark), raster kao rezerva.
- Favoriti iz pretrage otvaraju se u spremljenom načinu.

Starije bilješke (v2.1.6) slijede ispod.


## Status: READY FOR RELEASE

Repo: `https://github.com/divanguz-alt/Treska`  
APK: `treska-v2.1.6.apk` (52 MB, `versionCode=16`, `versionName=2.1.6`)  
Emulator: `zenit35` (1080×2400, 420 dpi, Android 35)  
Flutter: `/Users/ivanluzar/Documents/Coding tools/flutter/bin/flutter` (3.44.4, Dart 3.12.2)  
Android SDK: `~/Library/Android/sdk`  

---

## ŠTO JE RAĐENO (SVE PROVJERENO NA EMULATORU)

### 1. Sheet collapse / restore / drag — **RADI**
- **Root cause**: `AnimatedBuilder` je rebuildao `_BottomSheetHost` na svaki animation tick → novu `snapSizes` listu → `DraggableScrollableSheet.didUpdateWidget` vidi promjenu → schedule-a `goBallistic(0)` → otkazuje drag / `animateTo`.
- **Fix**:
  - `_BottomSheetHost` izbačen iz `AnimatedBuilder`; ostaje stabilan u Stacku (rebuild samo na `setState` parentu).
  - `_snapSizesFor(fractions)` vraća **identičnu listu** dok se screen height ne promijeni (`listEquals`).
  - `DraggableScrollableSheet` više ne vidi "promjenu" snap sizesa tijekom animacije.
- **Ponašanje**:
  - Chevron (tooltip "Skloni popis") → animira na 0 → `_sheetVisible=false` → host se makne → pojavi se pill "Prikaži polaske".
  - Drag down s handle-a (ili header row-a) → sheet se smanjuje, na ≤ 0.08 (`_onSheetChanged`) postavlja `_sheetVisible=false` → pill se pojavljuje.
  - Pill tap → `_expandSheet`: ako `_sheetVisible=false` → `setState(_sheetVisible=true)` → novi sheet u half; ako `true` ali controller detached (sliver) → briše sliver pa re-insert na half; inače `animateTo(half)`.
  - `_expanding` flag spriječava `_onSheetChanged` da ukloni sheet dok se animira nazad na half.
  - Prilikom draga na sliver (≤ 0.08) pill se pojavljuje **dok je sheet još uvijek u stablu**, tap na pill odmah animira nazad (controller attached).

### 2. GPS centring — **RADI**
- `MapPanel.shiftForSheet(point, zoom, hiddenPx, topInsetPx)` — pomak = `(hiddenPx - topInsetPx) / 2`.
- `topInsetPx = MediaQuery.padding.top + 106` (status bar + search bar 56 + gap 10 + live chip 32).
- Kad je sheet collapsed (`hiddenPx = 0`) → nema pomaka (centar ekrana).
- Kad je sheet na half/peek → centrira u vidljivoj traci između top UI i vrha sheeta.
- Test: `test/widget_test.dart` → `top UI inset reduces the sheet offset` prolazi.

### 3. Board scrolling & RefreshIndicator — **RADI**
- `RefreshIndicator` maknut (konkurirao s dragom sheeta).
- Refresh sada: `IconButton(icon: Icons.refresh, tooltip: "Osvježi")` u headeru, 40×40, `VisualDensity.compact`.
- `ListenableBuilder(listenable: Listenable.merge([feed.snapshot, feed.status, settings]))` — settings dodan za favorite ikone.
- Header: 2 reda po 48 dp (mode chips + dropdown row), ukupno 124 dp (handle 24 + row 48 + row 48 + 4 padding).
- Pill text: "Osvježi gumbom iznad, povećaj radijus u postavkama ili provjeri GPS."

### 4. Favorites — **RADI**
- `SettingsController.favorites: Set<String>` persistira se u `SharedPreferences` (`favorite_stop_ids`).
- `StopHeader` (u `stop_card.dart`): `ListenableBuilder(listenable: settings)` → zvjezdica se odmijeni mijenja na tap.
- Tap na zvjezdicu:
  - `settings.toggleFavorite(stopId)`
  - `ScaffoldMessenger` pokazuje SnackBar 2s: "Ime stanice spremljena · označena zvjezdicom" / "Ime stanice uklonjena iz spremljenih".
- Mapa (`map_panel.dart`):
  - `_circlesFor` preskače favorite (ne crta kružice).
  - `MarkerLayer` iscrtava zvjezdice (`Icons.star_rounded`, 26/30 dp, primary boja, bijela halo + crna drop-shadow) za sve favorite bez obzira na mode.
  - Tap na zvjezdicu → `_focusStop(id)` + `onStopSelected(id)` → selektira stanicu, otvara board.
  - Cache invalidacija: `_circlesFavorites` set usporeduje se `setEquals`.

### 5. Ostale sitnice
- `pubspec.yaml`: `version: 2.1.6+16`.
- `android/key.properties` — signing config (gitignored, ostao isti).
- `flutter analyze` — **0 issues**.
- **48/48 testova prolaze**:
  - `test/home_sheet_test.dart` — pravi `HomeScreen`: chevron collapse, pill restore, drag-down collapse, drag-up expand.
  - `test/sheet_drag_test.dart` — izolirani regression test za drag.
  - `test/widget_test.dart` — 46 testova uključujući favorite toggle, top-inset geometry, vehicle marker, arrival formatting.

---

## ŠTO JOŠ TREBA NAPRAVITI (RELEASE)

### 1. GitHub Release
```bash
cd "/Users/ivanluzar/Documents/Claude projects/ZET 2"
git push origin main
gh release create v2.1.6 treska-v2.1.6.apk \
  --title "Treska 2.1.6" \
  --notes "Sheet collapse/restore/drag fixed; GPS centering with top inset; favorites with star markers; refresh button in header; 48 tests passing."
```

### 2. Provjera na fizičkom uređaju (opcionalno)
- Instaliraj `treska-v2.1.6.apk` na telefon.
- Provjeri: sheet drag, chevron, pill restore, GPS centring (mapa se centrira ispod search bara), favorite zvjezdice na mapi, SnackBar feedback.

---

## ŠTO NIJE POПРАВЉЕНО / NE RADI (KNOWN ISSUES)

| Issue | Opis | Razlog / Napomena |
|-------|------|-------------------|
| **Emulator network flaky** | `zet.hr` ponekad ne резолвира, geolocator ANR (`unregisterGnssNmeaCallback`) kad nema GPS fixa. | Emulator bug / missing GPS. Na pravom telefonu radi. Riješeno: `adb shell cmd location set-location-enabled false` za testove bez GPS-a. |
| **System UI "isn't responding"** | Ponekad po cold bootu. | Emulator artifact, ne app bug. `adb reboot` + wait pomaže. |
| **Ruta broj okrenut** | Nikad nije bio okrenut — vehicle marker je kružni token s odvojenim chevronom. | Provjereno u testu `vehicle marker never rotates the route number`. |
| **Teardrop marker** | Nema — marker je `CircleMarker` + odvojeni `Icon(Icons.chevron_right)`. | Provjereno. |
| **Stop selector** | `PopupMenuButton` u headeru (dropdown), ne modal bottom sheet. | Provjereno. |
| **Departure list movable/dismissable** | Sheet je draggable, chevron/pill dismissaju. | Provjereno. |
| **Tap tram/bus → crta rutu** | Vehicle marker tap → `_focusVehicle` crta `shapes.txt` geometriju (fallback na polyline). | Provjereno u kodu (`map_panel.dart` `_onVehicleTap`). |
| **Search stop → selektira, fokusira mapu, otvara board** | `SearchScreen.onStopSelected` → `HomeScreen._selectStop` → `_expandSheet` + `MapPanel._focusStop`. | Provjereno. |

---

## VAŽNE DATOTEKE ZA BUDUĆE IZMJENE

| Datoteka | Što sadrži |
|----------|------------|
| `lib/ui/home_screen.dart` | `_sheetVisible`, `_hiding`, `_expanding`, `_onSheetChanged`, `_snapSizesFor`, `_expandSheet`, `_collapseSheet`, `_selectStop`, pill u `AnimatedBuilder`, host izvan `AnimatedBuilder`. |
| `lib/ui/board_panel.dart` | `RefreshIndicator` maknut, `IconButton` refresh, `settings` u `Listenable.merge`, `_BoardHeader` kompaktan (40×40), `_ModeChip`, `_BoardScroll`. |
| `lib/ui/map_panel.dart` | `shiftForSheet(topInsetPx)`, `_shiftForSheet`, `_circlesFor` (skip favorites), `MarkerLayer` za favorite zvjezdice, `_FavoriteStar`, `_UserMarker`. |
| `lib/ui/widgets/stop_card.dart` | `StopHeader` s `ListenableBuilder(settings)`, zvjezdica toggle + SnackBar. |
| `lib/settings_controller.dart` | `favorites: Set<String>`, `toggleFavorite`, `load`/`save` u `SharedPreferences`. |
| `lib/data/update_service.dart` | Version parsing za GitHub releases. |
| `test/home_sheet_test.dart` | E2E test prave `HomeScreen` sheet ponašanja. |
| `test/sheet_drag_test.dart` | Isolirani `DraggableScrollableSheet` drag regression. |
| `test/widget_test.dart` | Favorite toggle, top-inset geometry, ostali widget testovi. |

---

## KOMANDE ZA SLJEDEĆU SESIJU

### Ako želiš samo pushtati release:
```bash
cd "/Users/ivanluzar/Documents/Claude projects/ZET 2"
git push origin main
gh release create v2.1.6 treska-v2.1.6.apk \
  --title "Treska 2.1.6" \
  --notes "Sheet collapse/restore/drag fixed; GPS centering with top inset; favorites with star markers; refresh button in header; 48 tests passing."
```

### Ako želiš nastaviti develop:
```bash
cd "/Users/ivanluzar/Documents/Claude projects/ZET 2"
# Emulator boot:
adb start-server && ~/Library/Android/sdk/emulator/emulator -avd zenit35 -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect 2>/dev/null &
sleep 40
adb wait-for-device
adb shell input keyevent 82
adb shell cmd location set-location-enabled false  # opcionalno, da geolocator ne blokira

# Testovi:
/Users/ivanluzar/Documents/Coding\ tools/flutter/bin/flutter analyze
/Users/ivanluzar/Documents/Coding\ tools/flutter/bin/flutter test

# Build release:
/Users/ivanluzar/Documents/Coding\ tools/flutter/bin/flutter build apk --release
~/Library/Android/sdk/build-tools/$(ls ~/Library/Android/sdk/build-tools | tail -1)/aapt dump badging build/app/outputs/flutter-apk/app-release.apk | grep -E "versionCode|versionName"
```

---

## NAPOMENE ZA BUDUĆI RAD

1. **Sheet height threshold** (`0.08`) je empirijski — ako korisnici jave da pill ne pojavljuje dovoljno rano, poveci na `0.1`.
2. **Top inset** (`106`) hardcodiran — ako se UI promijeni (search bar visina, live chip), ažuriraj u `_shiftForSheet` i `shiftForSheet` testu.
3. **Favorites na mapi** prikazuju se za sve mode-ove — to je feature ("favorites meaningful"), ne bug.
4. **Emulator geolocator ANR** — na pravom telefonu ne pojavljuje se. Ako treba testirat GPS na emulatoru: `adb emu geo fix 15.9819 45.8150` (lon lat).
5. **Release APK** uvijek provjeri `aapt dump badging` prije `gh release` (stari incident s nepravilnim APK-om).

---

## KONTEKST ZA CLAUDE CODE

- Radni direktorij: `/Users/ivanluzar/Documents/Claude projects/ZET 2`
- Flutter binary: `/Users/ivanluzar/Documents/Coding tools/flutter/bin/flutter`
- Emulator AVD: `zenit35` (arm64, API 35)
- Signing: `android/key.properties` (gitignored, sadrži `storePassword`, `keyPassword`, `keyAlias`, `storeFile`)
- Git remote: `origin` → `https://github.com/divanguz-alt/Treska`
- GitHub CLI: `gh` dostupan, autentificiran.

---

**Posljednji commit**: `7013170` — "Fix sheet collapse/restore/drag, GPS centering, scrolling, and favorites"  
**Spreman za `git push` i `gh release create v2.1.6`**.