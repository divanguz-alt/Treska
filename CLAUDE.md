# Treska (ZET 2)

Zagreb public transport in real time: live map of trams/buses plus a departure
board for the nearest stops. Successor to `ZET 1/zet_app`, same visual language
(monospace, amber on near-black LED-board panels), now with a light theme and a
completely rebuilt data pipeline.

## Quick start

```bash
export PATH="$PATH:/Users/ivanluzar/Documents/Coding tools/flutter/bin"
flutter pub get
flutter run                     # device or emulator
flutter test                    # unit + widget tests
flutter analyze
flutter build apk --release     # build/app/outputs/flutter-apk/app-release.apk
```

App id: `hr.zet.zet2`, label **Treska**, version: see `pubspec.yaml`. It installs next
to the old Treska and does not share its data.

## Architecture

```
lib/
  main.dart              runApp only
  app.dart               MaterialApp, light/dark theme selection, AnnotatedRegion
  theme_controller.dart  ThemeMode persistence (SharedPreferences, system default)
  core/theme.dart        ZetColors ThemeExtension, buildZetTheme, zetSystemOverlay
  data/
    models.dart          immutable UI models + geometry/format helpers
    zip.dart             streaming ZIP reader + byte-level line/CSV helpers
    gtfs_static.dart     compact static GTFS index (parse ~580 ms, ~20 MB)
    gtfs_rt.dart         hand-written GTFS-Realtime protobuf reader
    update_service.dart  GitHub Releases check + APK download/install
    feed_engine.dart     static+RT join: nearby stops, arrivals, vehicles
    worker.dart          background isolate: download, parse, RT polling
    feed_controller.dart UI-facing ValueNotifiers + lifecycle + 5 s poll loop
    location_service.dart geolocator wrapper with cache and fallback
  ui/
    home_screen.dart     map (top) + board (bottom), shared pulse ticker
    map_panel.dart       FlutterMap, vehicles, stops, header, legend, age chip
    board_panel.dart     tram/bus tabs, loading/error/empty states
    diagnostics_sheet.dart
    settings_screen.dart theme, data controls, self-update
    widgets/             arrival_row, stop_card, vehicle_marker, pulse,
                         timer_builder
test/                    models + theme + widget + RT/wire tests
tool/                    dev benchmarks (not shipped)
```

### Why the worker isolate

`stop_times.txt` is **112 MB uncompressed** (1.7 M rows). ZET 1 decoded it into
a single Dart `String` (UTF-16 → ~224 MB), built millions of small objects and
then re-filtered everything on the UI isolate every 2 seconds. That is the lag.

ZET 2:

1. `lib/data/zip.dart` walks the ZIP central directory and inflates each entry
   with `RawZLibFilter(raw: true)` in 256 KB chunks. The parser consumes bytes
   line by line; the full file is never a `String`.
2. Only trips running **today** are kept (`calendar.txt` + `calendar_dates.txt`):
   typically 13.5k of 98.9k trips / 228k of 1.7M stop-time rows. Yesterday's
   trips that run past midnight (GTFS 24:00+, e.g. night trams 31-34) are
   kept too, shifted onto today's service day (`carryTripIdx`).
3. Storage is typed arrays: per-trip `Int32List` patterns and per-stop sorted
   `Int32List` departure pairs. No maps/objects per row.
4. `FeedEngine` lives in the worker isolate together with `StaticData`. The UI
   isolate only receives an immutable `FeedSnapshot` of ~5 stops × 10 arrivals
   plus the vehicle list.
5. Refresh is **5 s**, guarded against overlap and paused when the app is not
   visible.
6. The index is rebuilt from the cached ZIP when the service day changes
   (local midnight), so the board never runs yesterday's timetable against
   today's clock.

Measured on the author's machine (Dart VM, real ZET feed):

| Step | Result |
| --- | --- |
| Static parse (18.8 MB ZIP → 228k rows) | **580 ms** |
| One realtime join (600 STU, ~500 vehicles) | **2–14 ms** |
| Poll interval | 5 s |
| Stream update cadence | ~10 s |
| Stop-time rows in memory | 228 646 |

### UI performance rules

- One `AnimationController` for the whole screen (`PulseScope`), not one per row.
- No `MaskFilter.blur` on markers; solid shapes + a 3 px shadow.
- Stops are a single `CircleLayer`, not ~700 widgets.
- `ValueNotifier`s split by concern: map listens to vehicles/stops/position,
  board to `snapshot`, header to `status`. A board update never rebuilds the map.
- `RepaintBoundary` around the map and around each stop card.
- Only the selected board list is built (no `TabBarView` with two live lists).

### Realtime semantics

- A board row is `realtime` when a GTFS-RT `stop_time_update` resolves for that
  stop (direct `stop_id`, else `stop_sequence` → static pattern).
- Times: absolute departure → absolute arrival → schedule + delay.
- A trip-level delay (the last `stop_time_update.delay` of that trip) shifts **every later scheduled row of
  that trip**, marked `≈ procjena` / `ArrivalSource.estimated`. This is how the
  board stays honest about a vehicle that is already 3 minutes late further down
  the line.
- Vehicle positions: VehiclePosition GPS → current RT stop → static schedule.
  Bearing: RT bearing (ZET publishes none today), else previous position of
  the same route, else bearing to the next stop.
- Vehicles with **no GPS fix at all** are placed from the timetable, flagged
  `estimated`, drawn dimmed with an outer ring, and documented by the `PROCJENA`
  legend entry — they never read as measured positions.
- A scheduled row is hidden when an RT row of the same route+headsign is within
  ±180 s (avoids duplicate rows when platforms are merged). Unlike ZET 1, other
  departures of that route stay visible.
- Max 5 merged stops per mode, 10 arrivals per stop, 2 per route+headsign.

### Realtime source

Only ZET itself: `https://zet.hr/gtfs-rt-protobuf`, polled every 5 s. One
protobuf carries both VehiclePosition fixes and StopTimeUpdate predictions, as
separate entities per trip. Until 2.1.9 the app also read a third-party relay
(`zet.skoljka.org`); it was dropped because it only re-published the same ZET
fixes, and it had masked a parser bug (VehiclePosition fields read at the wrong
numbers). Field numbers in `gtfs_rt.dart` follow `gtfs-realtime.proto`; the
trip descriptor's `start_date` tells yesterday's after-midnight run apart from
today's run of the same trip id (`StaticData.tripFor`).

`FeedStats` carries the feed header time and the newest fix time, so the header
status chip and the diagnostics `Starost podataka` row always
report the real age, including time spent with no data at all. The chip is driven
by `TimerBuilder` (1 s) so it keeps counting up on a stalled feed.

## Self-update

Settings (`lib/ui/settings_screen.dart`, gear icon in the map header) checks
GitHub Releases and can install a newer build in place.

- Repository is hard-coded in `UpdateService`: `divanguz-alt/Treska`. No token;
  the public Releases API is read unauthenticated.
- `GET /repos/divanguz-alt/Treska/releases/latest` → the first `.apk` asset is
  offered. The comparison uses the decoded `versionCode` (major·10000 +
  minor·100 + patch, or an explicit `+N` in the tag) against the value Android
  reports for the installed build over the `hr.zet.zet2/updates` channel.
- Download goes to the app cache; `MainActivity` then hands it to the package
  installer through a `FileProvider` (`${applicationId}.fileprovider`, paths in
  `res/xml/file_paths.xml`). `REQUEST_INSTALL_PACKAGES` is declared; the first
  install needs the OS-level "install unknown apps" grant, and the UI offers to
  open that screen if the installer refuses.
- Publishing a release is therefore: bump `version`, `flutter build apk
  --release`, create a GitHub Release tagged `v2.0.1` with the APK attached.
  Nothing else in the app needs to change.

## Data sources

```
https://zet.hr/gtfs-scheduled/latest   ~18.8 MB ZIP, cached on device
https://zet.hr/gtfs-rt-protobuf        ~85 KB protobuf, polled every 5 s
https://tiles.openfreemap.org/styles/  vector map (positron / dark)
```

The static ZIP is fetched conditionally (`If-None-Match` / `If-Modified-Since`,
validators in `gtfs_static.zip.validators`): a cache younger than 12 h is used
at startup without a request, a running app asks every 4 h, and an unchanged
feed costs a 304 instead of 18.8 MB. The manual `RASPORED` button forces an
unconditional re-download.

Map: OpenFreeMap vector styles through `vector_map_tiles` (free, no key, apps
allowed; credit `© OpenMapTiles © OpenStreetMap`). `ZetColors.mapStyleUrl`
selects the style; set it to `''` to go back to the raster fallback
(`tileUrl`: OSM light / Esri dark), which is also used if the style fails to
load. Both OpenFreeMap styles have the theme id `default`, so the map gives
each a distinct id, otherwise the tile cache mixes light and dark tiles.

User-Agent sent: `Treska/2.0 (Flutter; ZET timetable)`.

Measured upstream behaviour (2026-10-22, 13 samples at 5 s): the feed header
moves every ~10 s, and the vehicle fixes inside it are ~2–12 s behind the header.
Treska shows these raw fixes with an explicit age rather than faking
smoothness. Most StopTimeUpdate delays are negative (median about -40 s on
2026-10-25), so "N min ranije" rows are ZET's own data, not a sign error.

Benchmarks use downloaded copies:

```bash
curl -A "Treska/2.0" -o /tmp/zet_static.zip https://zet.hr/gtfs-scheduled/latest
curl -A "Treska/2.0" -o /tmp/zet_rt.bin      https://zet.hr/gtfs-rt-protobuf
dart run tool/parse_bench.dart /tmp/zet_static.zip
dart run tool/feed_bench.dart  /tmp/zet_static.zip /tmp/zet_rt.bin
```

The protobuf reader is checked against a raw decode of the live feed (field
numbers, not just counts). `test/rt_reality_test.dart` asserts every vehicle in
`/tmp/zet_rt.bin` has a Zagreb GPS fix; reality tests run with
`flutter test --tags reality --run-skipped`.

## Theme

`ZetColors` (`ThemeExtension`) carries every colour and the map tile URL.
Dark is the original LED board; light is a paper-timetable variant with the same
layout and accent language. Default is `ThemeMode.system`; the choice is stored
under `theme_mode` in SharedPreferences and can be changed from the header
(sun/moon/auto menu).

## Gotchas

- `RawZLibFilter.processed()` must be drained completely after each `process()`,
  otherwise `InternalError: Call to Process while still processing data`.
- The protobuf reader must accept zero-length submessages (`ld()` with `len == 0`);
  bailing there truncates the feed.
- `Int32List(0)` is not `const`; empty patterns/departures are `final`.
- DepSec + tripIdx packing uses 20 bits for the trip index (13.5k trips); do not
  raise it past 1 048 575 without changing the pack format.
- `flutter` is not on PATH: prepend
  `/Users/ivanluzar/Documents/Coding tools/flutter/bin`.
- Android SDK is installed at `~/Library/Android/sdk`; an AVD named `zenit35`
  exists (`flutter emulators --launch zenit35`). The emulator has no GPS fix, so
  the app correctly falls back to Zagreb centre.
