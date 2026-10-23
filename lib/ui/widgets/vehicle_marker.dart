import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';

/// Route badge drawn on the map.
///
/// A circular token with the line number, plus a small detached arrow on its
/// leading edge showing where the vehicle is heading. The arrow is painted
/// inside the canvas at the bearing, so the badge itself never tilts: a round
/// token reads the same from every angle and the digits stay upright.
///
/// The previous version stretched the whole badge into a teardrop with a
/// tapered nose. It was hard to read at a glance and looked like a map pin,
/// not a vehicle. A disc plus a compass-like arrow states direction without
/// deforming the number's container.
///
/// Deliberately avoids `MaskFilter.blur` (ZET 1 used a blurred glow per vehicle,
/// which forces a `saveLayer` per marker). A solid ring reads the same on a
/// phone screen and costs a fraction of the GPU time.
class VehicleMarkerWidget extends StatelessWidget {
  final Vehicle vehicle;

  /// Draws a halo around the badge, used for the vehicle selected on the map.
  final bool selected;

  const VehicleMarkerWidget({
    super.key,
    required this.vehicle,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final isTram = vehicle.isTram;
    final label = vehicle.routeShortName;
    final fill = isTram ? colors.tram : colors.bus;
    final ink = isTram ? colors.onTram : colors.onBus;

    // Vehicles ZET never sent a GPS fix for are placed from the timetable.
    // Dim them so they never read as live positions.
    final estimated = vehicle.estimated;

    // Slightly larger disc for trams, whose two-digit numbers are the norm.
    final radius = isTram ? 15.0 : 13.5;
    // Arrow only when ZET actually reported a bearing; a stationary vehicle
    // would otherwise point at a random street.
    final points = vehicle.isMoving;

    // The arrow reaches `radius + gap + length` from the centre; keep square
    // bounds large enough that no bearing clips it.
    final half = radius + 12;
    final side = half * 2 + 2;

    return Tooltip(
      message: vehicle.headsign.isEmpty
          ? label
          : '$label → ${vehicle.headsign}',
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: side,
        height: side,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(side, side),
              painter: _BadgePainter(
                fill: estimated ? fill.withValues(alpha: 0.62) : fill,
                ring: colors.bg,
                ink: ink,
                radius: radius,
                bearing: points ? vehicle.bearing : 0,
                showArrow: points,
                selected: selected,
              ),
            ),
            // The label is a sibling of the painted shape, so nothing can
            // rotate the digits: no bearing renders the number upside-down.
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Text(
                label,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink.withValues(alpha: estimated ? 0.8 : 1),
                  fontSize: label.length > 2 ? 10.5 : 12,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the circular badge and, at the bearing, a detached arrow.
class _BadgePainter extends CustomPainter {
  final Color fill;
  final Color ring;
  final Color ink;
  final double radius;
  final double bearing;
  final bool showArrow;
  final bool selected;

  const _BadgePainter({
    required this.fill,
    required this.ring,
    required this.ink,
    required this.radius,
    required this.bearing,
    required this.showArrow,
    required this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final disc = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));

    canvas.drawShadow(disc, Colors.black.withValues(alpha: 0.32), 2, false);
    canvas.drawPath(disc, Paint()..color = fill);
    canvas.drawPath(
      disc,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    if (selected) {
      canvas.drawCircle(
        center,
        radius + 4.5,
        Paint()
          ..color = fill.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    if (showArrow) {
      // `bearing` is degrees clockwise from north; the arrow is authored
      // pointing east (+x), so −90° maps it to north.
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate((bearing - 90) * math.pi / 180);
      _paintArrow(canvas);
      canvas.restore();
    }
  }

  /// A compact chevron with a concave back, floating just off the disc so it
  /// reads as a direction cue rather than as part of the badge.
  void _paintArrow(Canvas canvas) {
    final base = radius + 3.5;
    final tip = base + 7;
    final path = Path()
      ..moveTo(base, -4.2)
      ..quadraticBezierTo(base + 3.6, -2.4, tip, 0)
      ..quadraticBezierTo(base + 3.6, 2.4, base, 4.2)
      ..quadraticBezierTo(base + 2.2, 0, base, -4.2)
      ..close();

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.28), 1.5, false);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(_BadgePainter old) =>
      old.fill != fill ||
      old.ring != ring ||
      old.ink != ink ||
      old.radius != radius ||
      old.bearing != bearing ||
      old.showArrow != showArrow ||
      old.selected != selected;
}
