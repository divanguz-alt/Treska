import 'package:flutter/material.dart';

/// Design tokens from the Claude handoff (`design_handoff_treska_android/`,
/// section „Razmaci, radijusi, pokret“). Kept next to the palette so screens
/// stop inventing their own numbers.
///
/// The spacing scale is 4 · 8 · 12 · 14 · 16 · 20 · 24 dp and the sheet uses a
/// 24 dp horizontal padding with 12 dp inside each row.
class ZetSpace {
  const ZetSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double row = 14;
  static const double lg = 16;
  static const double xl = 20;
  static const double sheet = 24;
  static const double xxl = 32;
}

/// Corner radii, straight from the handoff table.
class ZetRadius {
  const ZetRadius._();

  static const double chip = 8;
  static const double zoom = 12;
  static const double card = 16;
  static const double fab = 16;
  static const double etaCard = 20;
  static const double pill = 20;
  static const double sheet = 28;
  static const double search = 28;
}

/// The sheet heights the bottom sheet snaps to: collapsed, peek, half, full.
class ZetSheetHeight {
  const ZetSheetHeight._();

  /// Tall enough to show the 124 dp header (handle, modes, stop picker), the
  /// legend and a couple of departures once the picker became a dropdown.
  static const double peek = 280;
  static const double half = 520;
  static const double full = 860;
}

/// Motion: M3 emphasized-decelerate and the durations the handoff asks for.
class ZetMotion {
  const ZetMotion._();

  static const Duration quick = Duration(milliseconds: 180);
  static const Duration sheet = Duration(milliseconds: 300);
  static const Duration details = Duration(milliseconds: 220);

  static const Curve emphasized = Cubic(0.2, 0.8, 0.2, 1);
}

/// Raw palette values from the handoff. Two reasons this is separate from
/// [ZetColors]: the semantic mapping stays readable, and tests can assert the
/// exact spec numbers.
class ZetPalette {
  const ZetPalette._();

  // Light
  static const Color lightSurface = Color(0xFFF8FAFD);
  static const Color lightSurfaceContainer = Color(0xFFEDF0F6);
  static const Color lightSurfaceContainerHigh = Color(0xFFE7ECF2);
  static const Color lightInk = Color(0xFF151B24);
  static const Color lightInk2 = Color(0xFF4F5661);
  static const Color lightOutline = Color(0xFFA8AEB8);
  static const Color lightOutlineVariant = Color(0xFFDADEE5);
  static const Color lightPrimary = Color(0xFF1D5AB0);
  static const Color lightOnPrimary = Color(0xFFFCFCFC);
  static const Color lightPrimaryContainer = Color(0xFFCAE0FF);
  static const Color lightOnPrimaryContainer = Color(0xFF022659);

  // Dark
  static const Color darkSurface = Color(0xFF0E1217);
  static const Color darkSurfaceContainer = Color(0xFF171B21);
  static const Color darkSurfaceContainerHigh = Color(0xFF20242C);
  static const Color darkInk = Color(0xFFE8EBF1);
  static const Color darkInk2 = Color(0xFFA5ABB5);
  static const Color darkOutline = Color(0xFF5E646C);
  static const Color darkOutlineVariant = Color(0xFF2E333B);
  static const Color darkPrimary = Color(0xFF92C1FD);
  static const Color darkOnPrimary = Color(0xFF0A254D);
  static const Color darkPrimaryContainer = Color(0xFF1C3C6B);
  static const Color darkOnPrimaryContainer = Color(0xFFD5E6FF);
}
