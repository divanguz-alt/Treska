import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';

/// How the direction of travel is drawn next to a vehicle's badge
/// (Postavke → „Strelica smjera“).
enum VehicleArrow {
  /// The original small chevron, same colour as the badge.
  small('small', 'Mala strelica', 'Dosadašnja, najdiskretnija'),

  /// A triangle about twice the size, same colour as the badge.
  big('big', 'Veća strelica', 'Ista boja, dvostruko veća'),

  /// A large triangle in white (dark theme) or ink (light theme).
  contrast(
    'contrast',
    'Kontrastna strelica',
    'Bijela na tamnoj karti, '
        'tamna na svijetloj',
  ),

  /// A translucent beam behind the badge, like a torch.
  beam('beam', 'Klin smjera', 'Prozirni snop iza oznake, najuočljiviji');

  final String id;
  final String label;
  final String subtitle;
  const VehicleArrow(this.id, this.label, this.subtitle);

  static const VehicleArrow fallback = VehicleArrow.contrast;

  static VehicleArrow? byId(String? id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }
}

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

  /// How the direction of travel is drawn.
  final VehicleArrow arrow;

  /// Same line as the vehicle tapped on the map: drawn in the line
  /// highlight colour instead of the mode colour.
  final bool highlighted;

  const VehicleMarkerWidget({
    super.key,
    required this.vehicle,
    this.selected = false,
    this.arrow = VehicleArrow.fallback,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final isTram = vehicle.isTram;
    final label = vehicle.routeShortName;
    final fill = highlighted
        ? (isTram ? colors.tramHi : colors.busHi)
        : (isTram ? colors.tram : colors.bus);
    final ink = highlighted
        ? (isTram ? colors.onTramHi : colors.onBusHi)
        : (isTram ? colors.onTram : colors.onBus);

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
                arrow: arrow,
                contrast: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : colors.text,
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
  final VehicleArrow arrow;
  final Color contrast;

  const _BadgePainter({
    required this.fill,
    required this.ring,
    required this.ink,
    required this.radius,
    required this.bearing,
    required this.showArrow,
    required this.selected,
    required this.arrow,
    required this.contrast,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // The beam sits under the badge; every other arrow on top of it.
    final beam = showArrow && arrow == VehicleArrow.beam;
    if (beam) _rotated(canvas, center, _paintBeam);
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

    if (showArrow && !beam) {
      _rotated(
        canvas,
        center,
        arrow == VehicleArrow.small ? _paintArrow : _paintTriangle,
      );
    }
  }

  /// Runs [paint] in a frame where +x points along the bearing.
  void _rotated(Canvas canvas, Offset center, void Function(Canvas) paint) {
    // `bearing` is degrees clockwise from north; arrows are authored pointing
    // east (+x), so −90° maps them to north.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate((bearing - 90) * math.pi / 180);
    paint(canvas);
    canvas.restore();
  }

  /// [VehicleArrow.big] and [VehicleArrow.contrast]: a triangle about twice
  /// the size of the small chevron, just off the disc.
  void _paintTriangle(Canvas canvas) {
    final base = radius + 2.5;
    final tip = base + 13;
    final contrasting = arrow == VehicleArrow.contrast;
    final path = Path()
      ..moveTo(base, -8.5)
      ..lineTo(tip, 0)
      ..lineTo(base, 8.5);
    if (contrasting) {
      path.quadraticBezierTo(base + 3.5, 0, base, -8.5);
    }
    path.close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.3), 1.5, false);
    canvas.drawPath(path, Paint()..color = contrasting ? contrast : fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = contrasting ? 2 : 1.8,
    );
  }

  /// [VehicleArrow.beam]: a translucent 50° wedge reaching past the disc.
  void _paintBeam(Canvas canvas) {
    final reach = radius + 19;
    const half = 25 * math.pi / 180;
    final path = Path()
      ..moveTo(0, 0)
      ..arcTo(
        Rect.fromCircle(center: Offset.zero, radius: reach),
        -half,
        2 * half,
        false,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = fill.withValues(alpha: 0.42));
    canvas.drawPath(
      path,
      Paint()
        ..color = fill.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
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
      old.selected != selected ||
      old.arrow != arrow ||
      old.contrast != contrast;
}
