import 'dart:ui';

/// „Boja zaslona“ options (handoff README §2). `auto` picks by vehicle type;
/// it is the hook for a later per-model colour (MAN, Mercedes, Crotram).
class LedPalette {
  static const Color lime = Color(0xFFD4EF72);
  static const Color amber = Color(0xFFFFB52E);
  static const Color orange = Color(0xFFFF6A26);
  static const Color white = Color(0xFFEEF4EF);

  /// Board background, the same in both themes.
  static const Color board = Color(0xFF0A0B0A);

  static const String auto = 'auto';

  static const List<LedColorOption> options = [
    LedColorOption(auto, 'Prema vozilu', 'Tramvaj limeta, autobus jantar', [
      lime,
      amber,
    ]),
    LedColorOption('lime', 'Limeta', 'Crotram', [lime]),
    LedColorOption('amber', 'Jantar', 'Novi tramvaji i autobusi', [amber]),
    LedColorOption('orange', 'Narančasta', 'Mercedes', [orange]),
    LedColorOption('white', 'Bijela', 'MAN', [white]),
  ];

  static bool isKnown(String id) => options.any((o) => o.id == id);

  /// Lit-dot colour for a vehicle of [isTram] under option [id].
  static Color forVehicle(String id, {required bool isTram}) => switch (id) {
    'lime' => lime,
    'amber' => amber,
    'orange' => orange,
    'white' => white,
    _ => isTram ? lime : amber,
  };
}

class LedColorOption {
  final String id;
  final String label;
  final String subtitle;
  final List<Color> swatches;

  const LedColorOption(this.id, this.label, this.subtitle, this.swatches);
}
