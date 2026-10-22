import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';

/// Small circular badge with the route number and an optional direction arrow.
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
    final color = vehicle.isTram ? colors.tram : colors.bus;
    final label = vehicle.routeShortName;
    final fontSize = label.length > 2 ? 9.0 : (label.length > 1 ? 11.0 : 12.0);

    return Tooltip(
      message: vehicle.headsign.isEmpty
          ? label
          : '$label → ${vehicle.headsign}',
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: 42,
        height: 42,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (vehicle.isMoving)
              Transform.rotate(
                angle: vehicle.bearing * math.pi / 180,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: CustomPaint(
                    size: const Size(14, 9),
                    painter: _ArrowPainter(color),
                  ),
                ),
              ),
            Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
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
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  fontFamily: kMono,
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
