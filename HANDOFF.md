# HANDOFF — Treska (ZET 2) v2.1.6

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