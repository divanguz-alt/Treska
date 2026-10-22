import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';
import '../core/tokens.dart';
import '../data/feed_controller.dart';
import '../data/models.dart';
import '../settings_controller.dart';
import '../theme_controller.dart';
import 'diagnostics_sheet.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'widgets/pulse.dart';
import 'widgets/vehicle_marker.dart';

class MapPanel extends StatefulWidget {
  final FeedController feed;
  final ThemeController themeController;
  final SettingsController settings;
  final int mode; // kModeTram or kModeBus

  /// How much of the screen the bottom sheet covers (0..1), used to keep the
  /// zoom controls and FAB just above it.
  final double sheetFraction;

  /// Sheet height in pixels; the map's centre offset and fit padding use it.
  final double bottomInsetPx;

  const MapPanel({
    super.key,
    required this.feed,
    required this.themeController,
    required this.settings,
    required this.mode,
    this.sheetFraction = 0,
    this.bottomInsetPx = 0,
  });

  /// Starting zoom that keeps the whole nearby radius visible above the sheet.
  ///
  /// At this latitude one tile-pixel is ~3.5 m at zoom 15, so an 800 m circle
  /// needs more room than a phone screen shows once the sheet covers the lower
  /// half. Each radius step moves one zoom level: 400 m reads at 15, the default
  /// 800 m at 14, and 1200 m at 13.
  static double zoomForRadius(double radiusM) {
    if (radiusM <= 400) return 15;
    if (radiusM >= 1200) return 13;
    return 14;
  }

  /// Moves [point] south by half of [hiddenPx] so it renders at the centre of
  /// the visible map area rather than the centre of the widget.
  ///
  /// The map fills the whole screen but the sheet hides its lower part, so a
  /// user centred on the widget's geometric middle would sit behind the sheet.
  /// Static and pure so the projection maths is unit-testable.
  static LatLng shiftForSheet(LatLng point, double zoom, double hiddenPx) {
    final shiftPx = hiddenPx / 2;
    if (shiftPx <= 0) return point;

    // Web-Mercator: pixels per degree at this zoom and latitude. One world is
    // 256 * 2^zoom pixels wide and wraps 360°.
    final worldPx = 256.0 * math.pow(2, zoom);
    final latRad = point.latitude * math.pi / 180;
    final pxPerDegLon = worldPx / 360.0;
    final pxPerDegLat = pxPerDegLon / math.cos(latRad);

    // Positive latitude is north, so moving the camera down means subtracting.
    final dLat = shiftPx / pxPerDegLat;
    return LatLng(point.latitude - dLat, point.longitude);
  }

  @override
  State<MapPanel> createState() => _MapPanelState();
}

class _MapPanelState extends State<MapPanel> {
  final MapController _map = MapController();

  /// Increments per programmatic move so overlapping camera animations resolve
  /// in the order they were issued instead of stomping each other.
  int _moveId = 0;

  bool _centered = false;
  bool _followUser = true;

  List<CircleMarker> _stopCircles = const [];
  int _circlesMode = -1;
  Brightness? _circlesBrightness;

  int _tileErrors = 0;
  bool _tilesFailed = false;
  int _tileGeneration = 0;

  /// Set from [MapOptions.onMapReady]. Reading `MapController.camera` before the
  /// map has been laid out throws, so every camera read is gated on this.
  bool _mapReady = false;

  /// Pending post-frame re-centre, coalesced so a sheet drag (which rebuilds on
  /// every animation frame) schedules at most one move per frame instead of
  /// stacking callbacks.
  bool _recenterScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.feed.position.addListener(_onPosition);
  }

  @override
  void didUpdateWidget(MapPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Dragging the sheet changes how much map is visible, so a user who is
    // being followed has to be re-placed at the centre of the new strip —
    // raising the sheet moves them down the screen, lowering it moves them up.
    //
    // This fires on every sheet animation frame, so it is deferred and
    // coalesced, and never touches the controller until the map is ready.
    if (widget.bottomInsetPx == oldWidget.bottomInsetPx || !_followUser) {
      return;
    }
    if (!mounted || !_mapReady || _recenterScheduled) return;
    _recenterScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recenterScheduled = false;
      if (mounted && _mapReady && _followUser) _centerOnUser();
    });
  }

  @override
  void dispose() {
    widget.feed.position.removeListener(_onPosition);
    _map.dispose();
    super.dispose();
  }

  void _onPosition() {
    final pos = widget.feed.position.value;
    if (!_centered && pos.gps) {
      _centered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mapReady) _centerOnUser();
      });
    }
  }

  void _onTileError() {
    _tileErrors++;
    if (_tileErrors >= 6 && !_tilesFailed && mounted) {
      setState(() => _tilesFailed = true);
    }
  }

  void _retryTiles() {
    setState(() {
      _tileErrors = 0;
      _tilesFailed = false;
      _tileGeneration++;
    });
  }

  void _recenter() {
    setState(() => _followUser = true);
    _centerOnUser();
  }

  /// Centres the map on the user, accounting for the bottom sheet.
  ///
  /// The map widget fills the whole screen, but the sheet hides its lower part.
  /// Centring the user on the widget's geometric middle therefore parks them
  /// behind the sheet — invisible, which defeats the point of following. Shift
  /// the camera so the user lands in the middle of the *visible* strip: the
  /// offset is half the hidden height, so the camera centre moves south by
  /// `hiddenPx / 2`.
  void _centerOnUser() {
    if (!_mapReady) return;
    final pos = widget.feed.position.value;
    final target = LatLng(pos.lat, pos.lon);
    final zoom = _map.camera.zoom > 0
        ? _map.camera.zoom
        : MapPanel.zoomForRadius(widget.settings.radiusM);
    _map.move(_shiftForSheet(target, zoom), zoom, id: 'move_${_moveId++}');
  }

  /// Moves [point] south by half the sheet height, so it renders at the centre
  /// of the visible map area rather than the centre of the widget.
  LatLng _shiftForSheet(LatLng point, double zoom) =>
      MapPanel.shiftForSheet(point, zoom, widget.bottomInsetPx);

  void _zoom(double delta) {
    if (!_mapReady) return;
    final camera = _map.camera;
    final next = (camera.zoom + delta).clamp(11.0, 18.0);
    // Keep the user in the visible strip when we are following them; otherwise
    // zoom about whatever the user is looking at.
    final center = _followUser
        ? _shiftForSheet(
            LatLng(
              widget.feed.position.value.lat,
              widget.feed.position.value.lon,
            ),
            next,
          )
        : camera.center;
    _map.move(center, next, id: 'move_${_moveId++}');
  }

  List<CircleMarker> _circlesFor(
      BuildContext context, List<StopInfo> all, int mode) {
    final brightness = Theme.of(context).brightness;
    if (_circlesMode == mode &&
        _circlesBrightness == brightness &&
        _stopCircles.isNotEmpty) {
      return _stopCircles;
    }
    final colors = context.zet;
    // Handoff: idle stop is a 12 dp disc — surface fill with an ink2 ring.
    _stopCircles = [
      for (final s in all)
        if (s.serves(mode))
          CircleMarker(
            point: LatLng(s.lat, s.lon),
            radius: 5.5,
            useRadiusInMeter: false,
            color: colors.bg.withValues(alpha: 0.85),
            borderColor: colors.textDim.withValues(alpha: 0.9),
            borderStrokeWidth: 1.6,
          ),
    ];
    _circlesMode = mode;
    _circlesBrightness = brightness;
    return _stopCircles;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final bottomInset = widget.bottomInsetPx;

    return Stack(
      children: [
        RepaintBoundary(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              widget.feed.vehicles,
              widget.feed.stops,
              widget.feed.position,
              widget.settings,
            ]),
            builder: (context, _) {
              final pos = widget.feed.position.value;
              final center = LatLng(pos.lat, pos.lon);
              final vehicles = widget.feed.vehicles.value
                  .where((v) => widget.mode == kModeTram ? v.isTram : !v.isTram)
                  .toList(growable: false);
              final circles =
                  _circlesFor(context, widget.feed.stops.value, widget.mode);
              final radius = widget.settings.radiusM;

              return FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: center,
                  // The handoff's note asks for a starting zoom far enough out
                  // that the whole nearby-stop radius is on screen, which its
                  // code's fixed `15` contradicted. Pick the zoom from the
                  // radius setting instead: 800 m reads well at 14, and the
                  // wider/narrower settings step with it.
                  initialZoom: MapPanel.zoomForRadius(widget.settings.radiusM),
                  minZoom: 11,
                  maxZoom: 18,
                  backgroundColor: colors.bg,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  onPositionChanged: (camera, hasGesture) {
                    if (hasGesture && _followUser) {
                      setState(() => _followUser = false);
                    }
                  },
                  // The controller only becomes safe to read once the map has
                  // been laid out; camera reads elsewhere are gated on this.
                  onMapReady: () => _mapReady = true,
                ),
                children: [
                  TileLayer(
                    key: ValueKey('base_${colors.brightness}_$_tileGeneration'),
                    urlTemplate: colors.tileUrl,
                    subdomains: colors.tileSubdomains,
                    userAgentPackageName: 'hr.zet.zet2',
                    maxNativeZoom: colors.tileMaxNativeZoom,
                    errorTileCallback: (_, _, _) => _onTileError(),
                  ),
                  if (colors.tileLabelsUrl.isNotEmpty)
                    TileLayer(
                      key: ValueKey(
                          'labels_${colors.brightness}_$_tileGeneration'),
                      urlTemplate: colors.tileLabelsUrl,
                      subdomains: colors.tileSubdomains,
                      userAgentPackageName: 'hr.zet.zet2',
                      maxNativeZoom: colors.tileMaxNativeZoom,
                      errorTileCallback: (_, _, _) => _onTileError(),
                    ),
                  CircleLayer(circles: circles),
                  // 800 m (or 400/1200) walking radius around the user.
                  CircleLayer(circles: [
                    CircleMarker(
                      point: center,
                      radius: radius,
                      useRadiusInMeter: true,
                      color: colors.primary.withValues(alpha: 0.05),
                      borderColor: colors.primary.withValues(alpha: 0.55),
                      borderStrokeWidth: 1.5,
                    ),
                  ]),
                  MarkerLayer(
                    markers: [
                      for (final v in vehicles)
                        Marker(
                          point: LatLng(v.lat, v.lon),
                          width: 46,
                          height: 40,
                          alignment: Alignment.center,
                          child: VehicleMarkerWidget(vehicle: v),
                        ),
                    ],
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point: center,
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      child: _UserMarker(gps: pos.gps),
                    ),
                  ]),
                ],
              );
            },
          ),
        ),

        // Search bar + live chip, pinned to the top.
        Positioned(
          top: MediaQuery.of(context).padding.top + ZetSpace.sm,
          left: ZetSpace.lg,
          right: ZetSpace.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SearchBar(
                feed: widget.feed,
                themeController: widget.themeController,
                settings: widget.settings,
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _LiveChip(feed: widget.feed),
                  const SizedBox(width: ZetSpace.sm),
                  MapDiagnosticsButton(feed: widget.feed),
                ],
              ),
            ],
          ),
        ),

        // Zoom controls, above the sheet.
        Positioned(
          right: ZetSpace.xl,
          bottom: bottomInset + ZetSpace.lg + 56 + ZetSpace.md,
          child: _ZoomControls(
            onIn: () => _zoom(1),
            onOut: () => _zoom(-1),
          ),
        ),

        // Location FAB, just above the sheet.
        Positioned(
          right: ZetSpace.lg,
          bottom: bottomInset + ZetSpace.lg,
          child: _LocationFab(
            following: _followUser,
            onTap: _recenter,
          ),
        ),

        Positioned(
          left: ZetSpace.sm,
          bottom: bottomInset + ZetSpace.sm,
          child: _Attribution(colors: colors),
        ),

        if (_tilesFailed)
          Positioned(
            left: ZetSpace.xl,
            bottom: bottomInset + ZetSpace.xxl + ZetSpace.lg,
            child: _TileErrorChip(onTap: _retryTiles),
          ),
      ],
    );
  }
}

/// Required credit for the tile provider.
class _Attribution extends StatelessWidget {
  final ZetColors colors;
  const _Attribution({required this.colors});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.bg.withValues(alpha: 0.66),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Text(
            colors.isDark ? '© Esri · OSM' : '© OpenStreetMap',
            style: TextStyle(
              fontSize: 9,
              color: colors.textDim,
              ),
          ),
        ),
      ),
    );
  }
}

class _TileErrorChip extends StatelessWidget {
  final VoidCallback onTap;
  const _TileErrorChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ZetRadius.chip),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: ZetSpace.md, vertical: ZetSpace.sm),
        decoration: BoxDecoration(
          color: colors.bg.withValues(alpha: 0.94),
          border: Border.all(color: colors.danger.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(ZetRadius.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 14, color: colors.danger),
            const SizedBox(width: 6),
            Text(
              'Karta se ne učitava',
              style: TextStyle(
                fontSize: 13,
                color: colors.danger,
                ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.refresh, size: 14, color: colors.danger),
          ],
        ),
      ),
    );
  }
}

/// Blue dot with a halo; dimmed when there is no GPS fix.
class _UserMarker extends StatelessWidget {
  final bool gps;
  const _UserMarker({required this.gps});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final dot = colors.primary;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dot.withValues(alpha: 0.20),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dot.withValues(alpha: gps ? 1 : 0.5),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

/// M3 search bar (looks only) — tapping it opens the full search screen.
class _SearchBar extends StatelessWidget {
  final FeedController feed;
  final ThemeController themeController;
  final SettingsController settings;

  const _SearchBar({
    required this.feed,
    required this.themeController,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final dark = colors.isDark;
    return Material(
      color: colors.panel,
      elevation: 3,
      borderRadius: BorderRadius.circular(ZetRadius.search),
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: ZetSpace.lg),
            Icon(Icons.search, size: 24, color: colors.text),
            const SizedBox(width: ZetSpace.md),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showStopSearch(
                  context,
                  feed: feed,
                  settings: settings,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Traži stanicu ili liniju',
                    style: TextStyle(
                      fontSize: 16,
                      color: colors.textDim,
                      ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: dark ? 'Svijetla tema' : 'Tamna tema',
              iconSize: 24,
              color: colors.text,
              onPressed: () => themeController
                  .setMode(dark ? ThemeMode.light : ThemeMode.dark),
              icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
            ),
            IconButton(
              tooltip: 'Postavke',
              iconSize: 24,
              color: colors.text,
              onPressed: () => showSettings(
                context,
                feed: feed,
                themeController: themeController,
                settings: settings,
              ),
              icon: const Icon(Icons.settings_outlined),
            ),
            const SizedBox(width: ZetSpace.xs),
          ],
        ),
      ),
    );
  }
}

/// „Uživo“ chip: green pulsing dot, the word, and how many vehicles are live.
class _LiveChip extends StatelessWidget {
  final FeedController feed;
  const _LiveChip({required this.feed});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return ListenableBuilder(
      listenable: feed.snapshot,
      builder: (context, _) {
        final stats = feed.snapshot.value?.stats ?? const FeedStats();
        final age = stats.feedTimestamp > 0
            ? stats.ageSecAt(DateTime.now())
            : -1;
        final stale = age > 120 || age < 0;
        final dot = stale ? colors.warn : colors.ok;
        return Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: ZetSpace.md),
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: BorderRadius.circular(ZetRadius.chip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PulseDot(size: 8, color: dot, minOpacity: 0.0),
              const SizedBox(width: ZetSpace.sm),
              Text(
                stale ? 'Zastarjelo' : 'Uživo',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.text,
                  ),
              ),
              const SizedBox(width: ZetSpace.sm),
              Text(
                '${stats.vehiclesTram} tramvaja · ${stats.vehiclesBus} autobusa',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textDim,
                  fontFeatures: kTabular,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Vertical + / − pair in one card.
class _ZoomControls extends StatelessWidget {
  final VoidCallback onIn;
  final VoidCallback onOut;
  const _ZoomControls({required this.onIn, required this.onOut});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return Material(
      color: colors.panel,
      elevation: 2,
      borderRadius: BorderRadius.circular(ZetRadius.zoom),
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: SizedBox(
        width: 48,
        child: Column(
          children: [
            _ZoomButton(icon: Icons.add, onTap: onIn),
            Container(height: 1, color: colors.borderStrong),
            _ZoomButton(icon: Icons.remove, onTap: onOut),
          ],
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ZetRadius.zoom),
      child: SizedBox(
        height: 44,
        width: 48,
        child: Icon(icon, size: 22, color: colors.text),
      ),
    );
  }
}

/// M3 FAB that recentres the map on the user.
class _LocationFab extends StatelessWidget {
  final bool following;
  final VoidCallback onTap;
  const _LocationFab({required this.following, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return Tooltip(
      message: 'Centriraj na moju lokaciju',
      child: Material(
        // Handoff: a tonal FAB — primary container at rest, primary once the
        // map is following the user.
        color: following ? colors.primary : colors.primaryContainer,
        elevation: 3,
        borderRadius: BorderRadius.circular(ZetRadius.fab),
        shadowColor: Colors.black.withValues(alpha: 0.25),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ZetRadius.fab),
          child: SizedBox(
            width: 56,
            height: 56,
            child: Icon(
              following ? Icons.my_location : Icons.location_searching,
              size: 24,
              color: following
                  ? colors.onPrimary
                  : colors.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

/// Small square info button that opens the data-diagnostics sheet.
///
/// Lives next to the live chip so diagnostics are always one tap away without
/// cluttering the board.
class MapDiagnosticsButton extends StatelessWidget {
  final FeedController feed;
  const MapDiagnosticsButton({super.key, required this.feed});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return Tooltip(
      message: 'Dijagnostika podataka',
      child: Material(
        color: colors.panel,
        elevation: 2,
        borderRadius: BorderRadius.circular(ZetRadius.chip),
        shadowColor: Colors.black.withValues(alpha: 0.18),
        child: InkWell(
          onTap: () => showDiagnostics(context, feed),
          borderRadius: BorderRadius.circular(ZetRadius.chip),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(Icons.info_outline, size: 18, color: colors.textDim),
          ),
        ),
      ),
    );
  }
}
