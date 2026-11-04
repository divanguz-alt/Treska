import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import 'vehicle_marker.dart';

/// „Strelica smjera“ picker: the four arrow styles side by side, each on a
/// small map cut-out where a tram and a bus drive round a block, so the
/// arrow is seen turning through every direction. One controller drives all
/// four; with animations off the vehicles stand still mid-turn.
class VehicleArrowPicker extends StatefulWidget {
  final VehicleArrow value;
  final ValueChanged<VehicleArrow> onChanged;

  const VehicleArrowPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<VehicleArrowPicker> createState() => _VehicleArrowPickerState();
}

class _VehicleArrowPickerState extends State<VehicleArrowPicker>
    with SingleTickerProviderStateMixin {
  /// One lap of the block.
  static const Duration lap = Duration(seconds: 10);

  late final AnimationController _lap = AnimationController(
    vsync: this,
    duration: lap,
    value: 0.08,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _lap.stop();
      _lap.value = 0.08;
    } else if (!_lap.isAnimating) {
      _lap.repeat();
    }
  }

  @override
  void dispose() {
    _lap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final a in VehicleArrow.values)
        _ArrowCard(
          arrow: a,
          selected: a == widget.value,
          lap: _lap,
          onTap: () => widget.onChanged(a),
        ),
    ];
    return Column(
      children: [
        for (var i = 0; i < cards.length; i += 2) ...[
          if (i > 0) const SizedBox(height: ZetSpace.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cards[i]),
              const SizedBox(width: ZetSpace.md),
              Expanded(child: cards[i + 1]),
            ],
          ),
        ],
      ],
    );
  }
}

class _ArrowCard extends StatelessWidget {
  final VehicleArrow arrow;
  final bool selected;
  final Animation<double> lap;
  final VoidCallback onTap;

  const _ArrowCard({
    required this.arrow,
    required this.selected,
    required this.lap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final radius = BorderRadius.circular(ZetRadius.card);
    return Semantics(
      button: true,
      selected: selected,
      label: '${arrow.label}. ${arrow.subtitle}',
      excludeSemantics: true,
      child: Material(
        color: colors.panel,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected ? colors.primary : colors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(ZetRadius.card - 4),
                  child: SizedBox(
                    height: 116,
                    child: RepaintBoundary(
                      child: _MapCutout(arrow: arrow, lap: lap),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: selected ? colors.primary : colors.textDim,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          arrow.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Text(
                    arrow.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: colors.textDim,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A few streets and a block that a tram and a bus drive round.
class _MapCutout extends StatelessWidget {
  final VehicleArrow arrow;
  final Animation<double> lap;

  const _MapCutout({required this.arrow, required this.lap});

  static const _tram = Vehicle(
    routeShortName: '6',
    routeType: kRouteTypeTram,
    lat: 0,
    lon: 0,
    bearing: 90,
    headsign: 'Sopot',
  );
  static const _bus = Vehicle(
    routeShortName: '109',
    routeType: 3,
    lat: 0,
    lon: 0,
    bearing: 90,
    headsign: 'Dubrava',
  );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final block = _block(size);
        final metric = block.computeMetrics().first;
        return CustomPaint(
          painter: _StreetsPainter(block: block, dark: dark),
          child: AnimatedBuilder(
            animation: lap,
            builder: (context, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                _onBlock(metric, lap.value, _tram),
                _onBlock(metric, lap.value + 0.5, _bus),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The loop the vehicles follow, clockwise.
  static Path _block(Size size) {
    final rect = Rect.fromLTRB(30, 26, size.width - 30, size.height - 26);
    return Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(24)));
  }

  Widget _onBlock(PathMetric metric, double t, Vehicle v) {
    final at = metric.getTangentForOffset(metric.length * (t % 1))!;
    final dir = at.vector;
    // Screen y points down: bearing is clockwise from north (up).
    var bearing = math.atan2(dir.dx, -dir.dy) * 180 / math.pi;
    if (bearing <= 1) bearing += 360; // ~0° would read as „not moving“.
    const side = 56.0;
    return Positioned(
      left: at.position.dx - side / 2,
      top: at.position.dy - side / 2,
      width: side,
      height: side,
      child: VehicleMarkerWidget(
        vehicle: Vehicle(
          routeShortName: v.routeShortName,
          routeType: v.routeType,
          lat: 0,
          lon: 0,
          bearing: bearing,
          headsign: v.headsign,
        ),
        arrow: arrow,
      ),
    );
  }
}

/// Map-like background: land, two cross streets and the block's street,
/// in roughly the colours of the light and dark map styles.
class _StreetsPainter extends CustomPainter {
  final Path block;
  final bool dark;

  const _StreetsPainter({required this.block, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final land = dark ? const Color(0xFF1B1F26) : const Color(0xFFEDEBE6);
    final street = dark ? const Color(0xFF2D333D) : const Color(0xFFFFFFFF);
    final edge = dark ? const Color(0xFF262B33) : const Color(0xFFD9D5CD);
    canvas.drawRect(Offset.zero & size, Paint()..color = land);

    final cross = Path()
      ..moveTo(0, size.height * 0.5)
      ..lineTo(size.width, size.height * 0.5)
      ..moveTo(size.width * 0.5, 0)
      ..lineTo(size.width * 0.5, size.height);
    for (final p in [cross, block]) {
      canvas.drawPath(
        p,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = p == block ? 11 : 7,
      );
      canvas.drawPath(
        p,
        Paint()
          ..color = street
          ..style = PaintingStyle.stroke
          ..strokeWidth = p == block ? 9 : 5,
      );
    }
  }

  @override
  bool shouldRepaint(_StreetsPainter old) =>
      old.dark != dark || old.block != block;
}
