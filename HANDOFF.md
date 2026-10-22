# HANDOFF — Treska (ZET 2)

Last updated: 2026-10-22

## Status: feature-complete, verified on emulator

The app is built, analyzed, tested, packaged and running on the Android
emulator. Nothing is pushed to GitHub. Release APK is debug-signed (see
"Before distributing").

## What exists

Project: `/Users/ivanluzar/Documents/Claude projects/ZET 2/`
Flutter 3.44.4 / Dart 3.12.2, Android only.

| Item | Value |
| --- | --- |
| Display name | **Treska** (launcher label + `MaterialApp.title`) |
| Application id | `hr.zet.zet2` |
| Version | `2.0.0+2` |
| Min/target SDK | Flutter defaults (min 24, target 36) |
| APK | `build/app/outputs/flutter-apk/app-release.apk` (49.5 MB) |
| Emulator | AVD `zenit35`, display name changed to **zet2** |

It installs next to the old Treska and shares no data with it.

### Features (parity with ZET 1)

- Live map: trams/buses, route-colored markers, current position, 800 m circle,
  stops as a circle layer, follow-user, recenter and mode-specific filtering.
- Departure board: 5 nearest tram + 5 nearest bus stops, realtime vs schedule
  arrivals, per-mode tabs with counts.
- RT vehicle positions and stop-time updates joined with the static schedule.
- Light + dark theme (system default, persisted, menu in the map header).
- Croatian UI, monospace LED-board identity, amber accents.
- Diagnostics sheet with parse/refresh timings, entity counts, retry buttons.
- Errors surfaced as a banner + retry, not as a permanent wall of text.

### Performance architecture (short version)

Worker isolate downloads and parses GTFS once (~580 ms on the dev Mac, 5.3 s on
the emulator), keeps only today's 13.5k trips in typed arrays, and performs the
RT join (2–14 ms). The UI only receives a small immutable snapshot. Refresh is
5 s, paused in background, split across `ValueNotifier`s. Full details and
gotchas: `CLAUDE.md`.

## Verification performed

- `flutter analyze` → **No issues found**.
- `flutter test` → **9/9 passed** (geometry, countdown, formatting, theme,
  stop card in both brightnesses).
- `flutter build apk --release` → success (49.5 MB).
- Installed and launched on `emulator-5554`; no Flutter/Android exceptions.
- Debug-instrumented run confirmed the full pipeline:
  `stops=3800 trips=13532`, every 5 s `tram=5 bus=5 veh≈550 err=""`.
- First launch downloads the 18.8 MB static ZIP, parses it, then polls RT.
- Permission flow: location prompt appears once; denying falls back to Zagreb
  main station without crashing.

## Known limitations

- **GTFS-RT only publishes the next stop(s)** per trip (~670 updates for ~560
  vehicles). Most board rows therefore show scheduled times; RT rows are marked.
  This is a ZET feed limitation, same as in ZET 1.
- First launch needs network and downloads ~19 MB; static ZIP is cached 12 h and
  re-parsed on restart (5 s on the emulator, <1 s on a Mac). A binary cache of
  the parsed index would remove the re-parse, but was not needed.
- No background refresh; polling stops when the app is paused. Opening the app
  after a while shows fresh data within one tick (~1 s after resume).
- Map tiles are online (CARTO). No offline tiles.
- Emulator has no GPS fix; the fallback is intentional. Real-device GPS was not
  tested here.
- Emulator rendering is software/Impeller and reports very slow frames; do not
  judge app performance from it.
- **Release APK is signed with the debug key** (`android/app/build.gradle.kts`,
  TODO). Create a keystore + `key.properties` before sharing an installable
  build outside this machine.

## Before distributing

1. Create an upload keystore and a `key.properties`, wire it into
   `signingConfigs.release`, rebuild. Never commit the keystore or passwords.
2. Real-device run: GPS permission, tile loading, 5 s refresh, battery.
3. Optional: parsed-index disk cache; board/map widget tests.
4. Push to GitHub only after explicit confirmation from the user.

## Commands

```bash
cd "/Users/ivanluzar/Documents/Claude projects/ZET 2"
export PATH="$PATH:/Users/ivanluzar/Documents/Coding tools/flutter/bin"

flutter analyze
flutter test
flutter run -d emulator-5554
flutter build apk --release

flutter emulators --launch zenit35     # window title now "zet2"
dart run tool/parse_bench.dart /tmp/zet_static.zip
dart run tool/feed_bench.dart  /tmp/zet_static.zip /tmp/zet_rt.bin
```

Feed copies for benchmarks:

```bash
curl -A "Treska/2.0" -o /tmp/zet_static.zip https://zet.hr/gtfs-scheduled/latest
curl -A "Treska/2.0" -o /tmp/zet_rt.bin      https://zet.hr/gtfs-rt-protobuf
```

## Repo state

Git initialized, initial commit created. Remote: none. Nothing pushed.

Files worth reading first: `CLAUDE.md` (architecture + gotchas), then
`lib/data/feed_controller.dart` (UI ↔ worker protocol), `lib/data/worker.dart`,
`lib/data/feed_engine.dart`, `lib/ui/map_panel.dart`, `lib/ui/board_panel.dart`.
