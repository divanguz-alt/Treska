import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';
import '../data/feed_controller.dart';
import '../data/models.dart';
import '../theme_controller.dart';
import 'diagnostics_sheet.dart';
import 'widgets/pulse.dart';
import 'widgets/vehicle_marker.dart';

class MapPanel extends StatefulWidget {
  final FeedController feed;
  final ThemeController themeController;
  final int mode; // kModeTram or kModeBus

  const MapPanel({
    super.key,
    required this.feed,
    required this.themeController,
    required this.mode,
  });

  @override
  State<MapPanel> createState() => _MapPanelState();
}

class _MapPanelState extends State<MapPanel> {
  final MapController _map = MapController();

  bool _centered = false;
  bool _followUser = true;

  List<CircleMarker> _stopCircles = const [];
  int _circlesMode = -1;
  Brightness? _circlesBrightness;

  @override
  void initState() {
    super.initState();
    widget.feed.position.addListener(_onPosition);
  }

  @override
  void dispose() {
    widget.feed.position.removeListener(_onPosition);
    _map.dispose();
    super.dispose();
  }

  void _onPosition() {
    final pos = widget.feed.position.value;
    final center = LatLng(pos.lat, pos.lon);
    if (!_centered && pos.gps) {
      _centered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _map.move(center, 14.5);
      });
    }
  }

  void _recenter() {
    final pos = widget.feed.position.value;
    setState(() => _followUser = true);
    _map.move(LatLng(pos.lat, pos.lon), 14.5);
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
    final dark = colors.isDark;
    final fill = dark
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.22);
    final border = dark
        ? Colors.white.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.45);

    _stopCircles = [
      for (final s in all)
        if (s.serves(mode))
          CircleMarker(
            point: LatLng(s.lat, s.lon),
            radius: 3.4,
            useRadiusInMeter: false,
            color: fill,
            borderColor: border,
            borderStrokeWidth: 1,
          ),
    ];
    _circlesMode = mode;
    _circlesBrightness = brightness;
    return _stopCircles;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;

    return Stack(
      children: [
        RepaintBoundary(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              widget.feed.vehicles,
              widget.feed.stops,
              widget.feed.position,
            ]),
            builder: (context, _) {
              final pos = widget.feed.position.value;
              final center = LatLng(pos.lat, pos.lon);
              final vehicles = widget.feed.vehicles.value
                  .where((v) => widget.mode == kModeTram ? v.isTram : !v.isTram)
                  .toList(growable: false);
              final circles =
                  _circlesFor(context, widget.feed.stops.value, widget.mode);

              return FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 14.5,
                  minZoom: 10,
                  maxZoom: 19,
                  backgroundColor: colors.bg,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  onPositionChanged: (camera, hasGesture) {
                    if (hasGesture && _followUser) {
                      setState(() => _followUser = false);
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: colors.tileUrl,
                    subdomains: colors.tileSubdomains,
                    userAgentPackageName: 'hr.zet.zet2',
                    retinaMode: MediaQuery.devicePixelRatioOf(context) > 1.5,
                    maxNativeZoom: 19,
                  ),
                  CircleLayer(circles: circles),
                  MarkerLayer(
                    markers: [
                      for (final v in vehicles)
                        Marker(
                          point: LatLng(v.lat, v.lon),
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          child: VehicleMarkerWidget(vehicle: v),
                        ),
                    ],
                  ),
                  CircleLayer(circles: [
                    CircleMarker(
                      point: center,
                      radius: 800,
                      useRadiusInMeter: true,
                      color: colors.accent.withValues(alpha: 0.05),
                      borderColor: colors.accent.withValues(alpha: 0.28),
                      borderStrokeWidth: 1,
                    ),
                  ]),
                  MarkerLayer(markers: [
                    Marker(
                      point: center,
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      child: _UserMarker(gps: pos.gps),
                    ),
                  ]),
                ],
              );
            },
          ),
        ),

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _MapHeader(
            feed: widget.feed,
            themeController: widget.themeController,
          ),
        ),

        Positioned(
          left: 8,
          bottom: 8,
          child: _MapButton(
            icon: _followUser ? Icons.my_location : Icons.location_searching,
            onTap: _recenter,
            tooltip: 'Centriraj na moju lokaciju',
          ),
        ),

        Positioned(
          right: 8,
          bottom: 8,
          child: _Legend(mode: widget.mode),
        ),
      ],
    );
  }
}

class _UserMarker extends StatelessWidget {
  final bool gps;
  const _UserMarker({required this.gps});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.danger.withValues(alpha: 0.18),
        border: Border.all(
          color: colors.danger.withValues(alpha: gps ? 0.9 : 0.45),
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.danger.withValues(alpha: gps ? 1 : 0.5),
        ),
      ),
    );
  }
}

class _MapHeader extends StatelessWidget {
  final FeedController feed;
  final ThemeController themeController;

  const _MapHeader({required this.feed, required this.themeController});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;

    return ListenableBuilder(
      listenable: Listenable.merge([feed.status, feed.snapshot]),
      builder: (context, _) {
        final status = feed.status.value;
        final snapshot = feed.snapshot.value;
        final stats = snapshot?.stats ?? const FeedStats();
        final updated = snapshot?.updatedAt;
        final stale = updated == null ||
            DateTime.now().difference(updated) > const Duration(seconds: 45);
        final label = '${stats.vehicles} vozila  ·  '
            '${stats.vehiclesTram} tram / ${stats.vehiclesBus} bus';

        return Container(
          decoration: BoxDecoration(
            color: colors.bg.withValues(alpha: 0.86),
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  PulseDot(
                    size: 6,
                    color: stale ? colors.danger : colors.accent,
                    minOpacity: 0.3,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'ZET LIVE',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      fontFamily: kMono,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.textDim,
                        letterSpacing: 0.4,
                        fontFamily: kMono,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (!status.gps)
                    _GpsChip(onTap: feed.retryLocation),
                  _ThemeButton(controller: themeController),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Dijagnostika',
                    iconSize: 18,
                    color: colors.textDim,
                    onPressed: () => showDiagnostics(context, feed),
                    icon: const Icon(Icons.info_outline),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    updated == null ? '—' : hhmmss(updated),
                    style: TextStyle(
                      fontSize: 10,
                      color: stale ? colors.danger : colors.textHi,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      fontFamily: kMono,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.staticReady
                          ? 'RT ${stats.rtArrivals} · raspored ${stats.staticTrips} polazaka'
                          : status.loading,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: colors.textDim,
                        letterSpacing: 0.2,
                        fontFamily: kMono,
                      ),
                    ),
                  ),
                  if (stale && updated != null)
                    Text(
                      'ZASTARJELO',
                      style: TextStyle(
                        fontSize: 8,
                        color: colors.danger,
                        letterSpacing: 1,
                        fontFamily: kMono,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GpsChip extends StatelessWidget {
  final VoidCallback onTap;
  const _GpsChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          border: Border.all(color: colors.borderStrong),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off, size: 10, color: colors.textDim),
            const SizedBox(width: 3),
            Text(
              'GPS?',
              style: TextStyle(
                fontSize: 8,
                color: colors.textDim,
                letterSpacing: 0.8,
                fontFamily: kMono,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeButton extends StatelessWidget {
  final ThemeController controller;
  const _ThemeButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final mode = controller.mode;
    final icon = switch (mode) {
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
      ThemeMode.system => Icons.brightness_auto,
    };

    return PopupMenuButton<ThemeMode>(
      tooltip: 'Izgled',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      initialValue: mode,
      onSelected: controller.setMode,
      icon: Icon(icon, size: 19, color: colors.textDim),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: ThemeMode.system,
          child: Text('Sustav'),
        ),
        PopupMenuItem(
          value: ThemeMode.light,
          child: Text('Svijetlo'),
        ),
        PopupMenuItem(
          value: ThemeMode.dark,
          child: Text('Tamno'),
        ),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  const _MapButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colors.panel.withValues(alpha: 0.92),
            border: Border.all(color: colors.borderStrong),
          ),
          child: Icon(icon, size: 19, color: colors.accent),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final int mode;
  const _Legend({required this.mode});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final modeColor = mode == kModeTram ? colors.tram : colors.bus;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.92),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, color: modeColor),
          const SizedBox(width: 4),
          Text(
            mode == kModeTram ? 'TRAM' : 'BUS',
            style: TextStyle(
              fontSize: 8,
              color: colors.textDim,
              letterSpacing: 0.8,
              fontFamily: kMono,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.isDark
                  ? Colors.white.withValues(alpha: 0.35)
                  : Colors.black.withValues(alpha: 0.35),
              border: Border.all(
                color: colors.isDark
                    ? Colors.white.withValues(alpha: 0.6)
                    : Colors.black.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'STAJALIŠTE',
            style: TextStyle(
              fontSize: 8,
              color: colors.textDim,
              letterSpacing: 0.8,
              fontFamily: kMono,
            ),
          ),
        ],
      ),
    );
  }
}
