import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';

/// Route badge drawn on the map.
///
/// Handoff spec: a tram is a 22 dp pill (radius 11), a bus a 22 dp rounded
/// square (radius 5), both with a 2 dp `surface` ring and the route number in
/// the matching "on" colour. Three-digit lines get extra width.
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
    // Dim them and mark the ring so they never read as live positions.
    final estimated = vehicle.estimated;
    final badgeColor = estimated ? fill.withValues(alpha: 0.55) : fill;

    final wide = label.length > 2;
    final width = isTram ? (wide ? 36.0 : 30.0) : (wide ? 36.0 : 26.0);
    final radius = isTram ? 11.0 : 5.0;
    final fontSize = wide ? 11.0 : 12.0;

    return Tooltip(
      message: vehicle.headsign.isEmpty
          ? label
          : '$label → ${vehicle.headsign}',
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: 46,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (vehicle.isMoving)
              Transform.rotate(
                angle: vehicle.bearing * math.pi / 180,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: CustomPaint(
                    size: const Size(13, 8),
                    painter: _ArrowPainter(badgeColor),
                  ),
                ),
              ),
            Container(
              width: width,
              height: 22,
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: estimated
                      ? colors.bg.withValues(alpha: 0.5)
                      : colors.bg,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink.withValues(alpha: estimated ? 0.75 : 1),
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final Color color;
  const _ArrowPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height * 0.72)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}
