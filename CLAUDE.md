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

App id: `hr.zet.zet2`, label **Treska**, version `2.0.0+2`. It installs next
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
    rt_socket.dart       streaming vehicle feed (wss relay), REST fallback
    wire_feed.dart       relay JSON -> RtFeed (delta coords, per-vehicle delay)
    feed_engine.dart     static+RT join: nearby stops, arrivals, vehicles
    worker.dart          background isolate: download, parse, RT polling/socket
    feed_controller.dart UI-facing ValueNotifiers + lifecycle + 5 s poll loop
    location_service.dart geolocator wrapper with cache and fallback
  ui/
    home_screen.dart     map (top) + board (bottom), shared pulse ticker
    map_panel.dart       FlutterMap, vehicles, stops, header, legend, age chip
    board_panel.dart     tram/bus tabs, loading/error/empty states
    diagnostics_sheet.dart
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
   typically 13.5k of 98.9k trips / 228k of 1.7M stop-time rows.
3. Storage is typed arrays: per-trip `Int32List` patterns and per-stop sorted
   `Int32List` departure pairs. No maps/objects per row.
4. `FeedEngine` lives in the worker isolate together with `StaticData`. The UI
   isolate only receives an immutable `FeedSnapshot` of ~5 stops × 10 arrivals
   plus the vehicle list.
5. Refresh is **5 s**, guarded against overlap and paused when the app is not
   visible.
6. A WebSocket client (`rt_socket.dart`) pushes each new vehicle snapshot into
   the worker as soon as the relay publishes it, so positions are not limited to
   the poll cadence.

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
- A trip-level delay (per-vehicle `reportDelays` from the stream, or the last
  `stop_time_update.delay` from protobuf) shifts **every later scheduled row of
  that trip**, marked `≈ procjena` / `ArrivalSource.estimated`. This is how the
  board stays honest about a vehicle that is already 3 minutes late further down
  the line.
- Vehicle positions: streaming fix → VehiclePosition GPS → current RT stop →
  static schedule. Bearing: RT bearing (`directionDegrees`), else previous
  position of the same route, else bearing to the next stop.
- Vehicles with **no GPS fix at all** are placed from the timetable, flagged
  `estimated`, drawn dimmed with an outer ring, and documented by the `PROCJENA`
  legend entry — they never read as measured positions.
- A scheduled row is hidden when an RT row of the same route+headsign is within
  ±180 s (avoids duplicate rows when platforms are merged). Unlike ZET 1, other
  departures of that route stay visible.
- Max 5 merged stops per mode, 10 arrivals per stop, 2 per route+headsign.

### Streaming vs polling

Two sources feed the engine and they are complementary:

| Source | Cadence | Provides |
| --- | --- | --- |
| `wss://zet.skoljka.org/ws-v4?appUpdates=1` | ~10 s | vehicle fixes, per-vehicle delay |
| `https://zet.hr/gtfs-rt-protobuf` (REST) | 5 s poll | `stop_time_update` predictions |

`FeedEngine._merge` prefers streamed fixes for positions and keeps the protobuf
predictions, deduplicating by trip id. The relay also multiplexes news and
app-version notices on the same socket; those are ignored. If the socket is quiet
for 45 s the worker silently falls back to REST for vehicles too — the relay is a
speed-up, never a hard dependency.

`FeedStats` carries the feed header time and the newest fix time, so the header
chip (`◉ SADA` / `◉ N min`) and the diagnostics `STAROST PODATAKA` row always
report the real age, including time spent with no data at all. The chip is driven
by `TimerBuilder` (1 s) so it keeps counting up on a stalled feed.

## Data sources

```
https://zet.hr/gtfs-scheduled/latest   ~18.8 MB ZIP, cached 12 h on device
https://zet.hr/gtfs-rt-protobuf        ~85 KB protobuf, polled every 5 s
wss://zet.skoljka.org/ws-v4            streamed vehicle snapshots, ~10 s
```

The static ZIP is re-downloaded after 4 h in a running app; the manual
`RASPORED` button forces a re-download at any time.

User-Agent sent: `Treska/2.0 (Flutter; ZET timetable)`.

Measured upstream behaviour (2026-10-22, 13 samples at 5 s): the feed header
moves every ~10 s, and the vehicle fixes inside it are ~2–12 s behind the header.
The relay offers no interpolation — it forwards ZET's raw fixes, so Treska shows
the same positions with an explicit age rather than faking smoothness.

Benchmarks use downloaded copies:

```bash
curl -A "Treska/2.0" -o /tmp/zet_static.zip https://zet.hr/gtfs-scheduled/latest
curl -A "Treska/2.0" -o /tmp/zet_rt.bin      https://zet.hr/gtfs-rt-protobuf
dart run tool/parse_bench.dart /tmp/zet_static.zip
dart run tool/feed_bench.dart  /tmp/zet_static.zip /tmp/zet_rt.bin
```

The protobuf reader is validated against Python `gtfs_realtime_pb2`:
883 entities / 551 trip updates / 332 vehicles / 600+ stop-time updates — exact
match.

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
