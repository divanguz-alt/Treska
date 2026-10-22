import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';

/// Route badge drawn on the map.
///
/// The badge itself points the way the vehicle is moving: a capsule stretched
/// along the bearing with a tapered tip on the leading edge, rotated so the
/// sharp end leads. A shape that leans where the vehicle is going reads at a
/// glance far better than a small triangle tacked onto a round badge — the
/// outline alone carries the direction.
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
    final badgeColor = estimated ? fill.withValues(alpha: 0.55) : fill;

    final wide = label.length > 2;
    // Body is the badge's short axis; the nose adds length along the bearing.
    final bodyW = isTram ? (wide ? 36.0 : 30.0) : (wide ? 34.0 : 26.0);
    const bodyH = 22.0;
    // Pointing only makes sense once ZET reports a bearing; a stationary or
    // bearing-less vehicle gets a plain capsule/square instead of a random tip.
    final points = vehicle.isMoving;
    final noseLen = points ? 9.0 : 0.0;

    final canvasW = bodyW + noseLen + 6;
    final canvasH = bodyH + 6;

    final shape = SizedBox(
      width: bodyW + noseLen,
      height: bodyH,
      child: CustomPaint(
        painter: _BadgePainter(
          color: badgeColor,
          ring: estimated ? colors.bg.withValues(alpha: 0.5) : colors.bg,
          isTram: isTram,
          nose: noseLen,
          shadow: Colors.black.withValues(alpha: 0.3),
        ),
        child: Padding(
          // Shift the label back by the nose so the number stays centred in the
          // body rather than drifting toward the tip.
          padding: EdgeInsets.only(right: noseLen),
          child: Center(
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
        ),
      ),
    );

    return Tooltip(
      message: vehicle.headsign.isEmpty
          ? label
          : '$label → ${vehicle.headsign}',
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: canvasW,
        height: canvasH,
        child: Center(
          child: points
              // Bearing is degrees clockwise from north; a canvas rotation is
              // clockwise from east, so subtract 90° to align the nose.
              ? Transform.rotate(
                  angle: (vehicle.bearing - 90) * math.pi / 180,
                  child: shape,
                )
              : shape,
        ),
      ),
    );
  }
}

/// Draws the badge: a capsule (tram) or rounded square (bus) body with an
/// optional tapered nose on the right edge, which is the direction of travel
/// before rotation.
class _BadgePainter extends CustomPainter {
  final Color color;
  final Color ring;
  final bool isTram;
  final double nose;
  final Color shadow;

  const _BadgePainter({
    required this.color,
    required this.ring,
    required this.isTram,
    required this.nose,
    required this.shadow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bodyW = size.width - nose;
    final h = size.height;
    final r = isTram ? h / 2 : 5.0;

    final path = Path();
    // Start at the body's top-left corner region and walk clockwise.
    path.moveTo(r, 0);
    path.lineTo(bodyW - r, 0);
    // Top-right shoulder.
    if (nose > 0) {
      // Taper from the shoulder out to the tip, then back to the lower shoulder.
      path.lineTo(bodyW, h * 0.12);
      path.lineTo(size.width, h / 2);
      path.lineTo(bodyW, h * 0.88);
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

    canvas.drawShadow(path, shadow, 2, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_BadgePainter old) =>
      old.color != color ||
      old.ring != ring ||
      old.isTram != isTram ||
      old.nose != nose;
}
