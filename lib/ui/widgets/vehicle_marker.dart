import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';

/// Route badge drawn on the map.
///
/// Direction is carried by the badge's *outline*: a capsule stretched along the
/// bearing with a tapered tip on the leading edge, so the shape itself leans
/// where the vehicle is going. Only the shape rotates — the route number stays
/// upright, because a number rotated past 90° reads upside-down on a map and is
/// genuinely unreadable (this was a real defect: the whole badge used to
/// rotate together with its label).
///
/// Trams stay a capsule and buses a squarer body, so the two modes are still
/// distinguishable by silhouette and not only by colour. Three-digit lines get
/// extra width so the number never shrinks.
///
/// Deliberately avoids `MaskFilter.blur` (ZET 1 used a blurred glow per vehicle,
/// which forces a `saveLayer` per marker). A solid ring reads the same on a
/// phone screen and costs a fraction of the GPU time.
class VehicleMarkerWidget extends StatelessWidget {
  final Vehicle vehicle;

  const VehicleMarkerWidget({super.key, required this.vehicle});

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

    final wide = label.length > 2;
    // Body is the badge's short axis; the tip adds length along the bearing.
    final bodyW = isTram ? (wide ? 34.0 : 28.0) : (wide ? 32.0 : 24.0);
    const bodyH = 20.0;
    // Pointing only makes sense once ZET reports a bearing; a stationary or
    // bearing-less vehicle gets a plain capsule/square instead of a random tip.
    final points = vehicle.isMoving;
    final tip = points ? 7.0 : 0.0;

    // Canvas holds the shape plus room for the tip at any rotation, so a
    // north/south bearing never clips the nose against the marker bounds.
    final canvas = math.max(bodyW, bodyH + tip) + 8;

    final shapeW = bodyW + tip;
    const shapeH = bodyH;

    return Tooltip(
      message: vehicle.headsign.isEmpty
          ? label
          : '$label → ${vehicle.headsign}',
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: canvas,
        height: canvas,
        child: Center(
          child: SizedBox(
            width: shapeW,
            height: shapeH,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Rotate the plain filled outline to the bearing. `bearing` is
                // degrees clockwise from north while a canvas rotation is
                // clockwise from east, hence the -90°.
                if (points)
                  Transform.rotate(
                    angle: (vehicle.bearing - 90) * math.pi / 180,
                    child: CustomPaint(
                      size: Size(shapeW, shapeH),
                      painter: _BadgePainter(
                        color: estimated
                            ? fill.withValues(alpha: 0.55)
                            : fill,
                        ring: estimated
                            ? colors.bg.withValues(alpha: 0.5)
                            : colors.bg,
                        isTram: isTram,
                        tip: tip,
                      ),
                    ),
                  )
                else
                  CustomPaint(
                    size: Size(shapeW, shapeH),
                    painter: _BadgePainter(
                      color: estimated ? fill.withValues(alpha: 0.55) : fill,
                      ring: estimated
                          ? colors.bg.withValues(alpha: 0.5)
                          : colors.bg,
                      isTram: isTram,
                      tip: 0,
                    ),
                  ),
                // The label is a sibling of the rotating shape, so it never
                // turns: no bearing can render the number upside-down.
                // Offset it back by half the tip so it sits in the body.
                Padding(
                  padding: EdgeInsets.only(right: tip),
                  child: Text(
                    label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ink.withValues(alpha: estimated ? 0.75 : 1),
                      fontSize: wide ? 11 : 12,
                      fontWeight: FontWeight.w700,
                      height: 1,
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

/// Draws the badge body: a capsule (tram) or rounded square (bus) with an
/// optional tip on the right edge, which is the direction of travel before the
/// outline is rotated. The tip is deliberately shorter than the body is tall so
/// it reads as a pointed nose rather than a spike.
class _BadgePainter extends CustomPainter {
  final Color color;
  final Color ring;
  final bool isTram;
  final double tip;

  const _BadgePainter({
    required this.color,
    required this.ring,
    required this.isTram,
    required this.tip,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bodyW = size.width - tip;
    final h = size.height;
    final r = isTram ? h / 2 : 4.0;

    final path = Path();
    path.moveTo(r, 0);
    path.lineTo(bodyW - r, 0);
    if (tip > 0) {
      // Taper from the shoulders to a rounded point, so the nose is smooth
      // rather than a triangle stuck onto the capsule.
      path.quadraticBezierTo(bodyW, 0, bodyW + tip * 0.7, h * 0.35);
      path.quadraticBezierTo(size.width, h * 0.5, size.width, h * 0.5);
      path.quadraticBezierTo(size.width, h * 0.5, bodyW + tip * 0.7, h * 0.65);
      path.quadraticBezierTo(bodyW, h, bodyW, h);
    } else {
      path.arcToPoint(
        Offset(bodyW, r),
        radius: Radius.circular(r),
        clockwise: true,
      );
    }
    path.lineTo(bodyW - r, h);
    path.arcToPoint(
      Offset(0, h - r),
      radius: Radius.circular(r),
      clockwise: true,
    );
    path.lineTo(0, r);
    path.arcToPoint(
      Offset(r, 0),
      radius: Radius.circular(r),
      clockwise: true,
    );
    path.close();

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.28), 1.5, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
  }

  @override
  bool shouldRepaint(_BadgePainter old) =>
      old.color != color ||
      old.ring != ring ||
      old.isTram != isTram ||
      old.tip != tip;
}
