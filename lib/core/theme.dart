import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// All colours used by the app, exposed as a [ThemeExtension] so widgets can
/// read them from `Theme.of(context)` instead of hard-coding constants.
@immutable
class ZetColors extends ThemeExtension<ZetColors> {
  final Brightness brightness;

  final Color bg;
  final Color panel;
  final Color panelAlt;
  final Color border;
  final Color borderStrong;

  final Color accent;
  final Color accentDim;
  final Color textHi;
  final Color text;
  final Color textDim;

  final Color tram;
  final Color bus;
  final Color danger;
  final Color ok;

  /// Raster tile template for the map. `{s}` is optional.
  final String tileUrl;

  /// Extra tile layer drawn on top (e.g. labels for a base map). Empty when the
  /// main layer already contains labels.
  final String tileLabelsUrl;
  final List<String> tileSubdomains;

  /// Provider credit shown on the map (required by the tile terms).
  final String tileAttribution;

  /// Highest zoom the provider serves natively; higher zooms are upscaled.
  final int tileMaxNativeZoom;

  const ZetColors({
    required this.brightness,
    required this.bg,
    required this.panel,
    required this.panelAlt,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.accentDim,
    required this.textHi,
    required this.text,
    required this.textDim,
    required this.tram,
    required this.bus,
    required this.danger,
    required this.ok,
    required this.tileUrl,
    required this.tileSubdomains,
    this.tileLabelsUrl = '',
    required this.tileAttribution,
    this.tileMaxNativeZoom = 19,
  });

  bool get isDark => brightness == Brightness.dark;

  static const dark = ZetColors(
    brightness: Brightness.dark,
    bg: Color(0xFF080808),
    panel: Color(0xFF0D0D0D),
    panelAlt: Color(0xFF111111),
    border: Color(0xFF1E1E1E),
    borderStrong: Color(0xFF2E2E2E),
    accent: Color(0xFFFFAA00),
    accentDim: Color(0xFF7A5410),
    textHi: Color(0xFFFFCC55),
    text: Color(0xFFD9D2C4),
    textDim: Color(0xFF8C7A5C),
    tram: Color(0xFF4C9DFF),
    bus: Color(0xFF4CC45A),
    danger: Color(0xFFFF5544),
    ok: Color(0xFF4CC45A),
    // Esri's dark canvas: labels are a separate reference layer, stacked on
    // top by the map panel. Both are free to use with attribution.
    tileUrl: 'https://server.arcgisonline.com/ArcGIS/rest/services/'
        'Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}',
    tileLabelsUrl: 'https://server.arcgisonline.com/ArcGIS/rest/services/'
        'Canvas/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
    tileSubdomains: [],
    tileAttribution: '© Esri, HERE, Garmin, © OpenStreetMap contributors',
    tileMaxNativeZoom: 16,
  );

  static const light = ZetColors(
    brightness: Brightness.light,
    bg: Color(0xFFF1EDE2),
    panel: Color(0xFFFFFDF8),
    panelAlt: Color(0xFFF7F2E6),
    border: Color(0xFFDCD3BF),
    borderStrong: Color(0xFFBFB298),
    accent: Color(0xFF9A5600),
    accentDim: Color(0xFF7D6647),
    textHi: Color(0xFF7A3C00),
    text: Color(0xFF1F1B15),
    textDim: Color(0xFF6A6252),
    tram: Color(0xFF1F5FBF),
    bus: Color(0xFF2A7A33),
    danger: Color(0xFFC0281B),
    ok: Color(0xFF2A7A33),
    // Plain OpenStreetMap raster tiles: free, no key, labelled.
    tileUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    tileSubdomains: [],
    tileAttribution: '© OpenStreetMap contributors',
    tileMaxNativeZoom: 19,
  );

  @override
  ZetColors copyWith({
    Brightness? brightness,
    Color? bg,
    Color? panel,
    Color? panelAlt,
    Color? border,
    Color? borderStrong,
    Color? accent,
    Color? accentDim,
    Color? textHi,
    Color? text,
    Color? textDim,
    Color? tram,
    Color? bus,
    Color? danger,
    Color? ok,
    String? tileUrl,
    String? tileLabelsUrl,
    List<String>? tileSubdomains,
    String? tileAttribution,
    int? tileMaxNativeZoom,
  }) {
    return ZetColors(
      brightness: brightness ?? this.brightness,
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      panelAlt: panelAlt ?? this.panelAlt,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      accent: accent ?? this.accent,
      accentDim: accentDim ?? this.accentDim,
      textHi: textHi ?? this.textHi,
      text: text ?? this.text,
      textDim: textDim ?? this.textDim,
      tram: tram ?? this.tram,
      bus: bus ?? this.bus,
      danger: danger ?? this.danger,
      ok: ok ?? this.ok,
      tileUrl: tileUrl ?? this.tileUrl,
      tileLabelsUrl: tileLabelsUrl ?? this.tileLabelsUrl,
      tileSubdomains: tileSubdomains ?? this.tileSubdomains,
      tileAttribution: tileAttribution ?? this.tileAttribution,
      tileMaxNativeZoom: tileMaxNativeZoom ?? this.tileMaxNativeZoom,
    );
  }

  @override
  ZetColors lerp(ThemeExtension<ZetColors>? other, double t) {
    if (other is! ZetColors) return this;
    return ZetColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: Color.lerp(bg, other.bg, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelAlt: Color.lerp(panelAlt, other.panelAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDim: Color.lerp(accentDim, other.accentDim, t)!,
      textHi: Color.lerp(textHi, other.textHi, t)!,
      text: Color.lerp(text, other.text, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      tram: Color.lerp(tram, other.tram, t)!,
      bus: Color.lerp(bus, other.bus, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      ok: Color.lerp(ok, other.ok, t)!,
      tileUrl: t < 0.5 ? tileUrl : other.tileUrl,
      tileLabelsUrl: t < 0.5 ? tileLabelsUrl : other.tileLabelsUrl,
      tileSubdomains: t < 0.5 ? tileSubdomains : other.tileSubdomains,
      tileAttribution: t < 0.5 ? tileAttribution : other.tileAttribution,
      tileMaxNativeZoom:
          t < 0.5 ? tileMaxNativeZoom : other.tileMaxNativeZoom,
    );
  }
}

/// Monospace is the visual identity of the app (LED board / timetable).
const String kMono = 'monospace';

ThemeData buildZetTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? ZetColors.dark : ZetColors.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: brightness == Brightness.dark ? const Color(0xFF1A1000) : Colors.white,
    secondary: c.tram,
    onSecondary: Colors.white,
    error: c.danger,
    onError: Colors.white,
    surface: c.panel,
    onSurface: c.text,
    surfaceContainerHighest: c.panelAlt,
    outline: c.border,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    splashFactory: InkSparkle.splashFactory,
    fontFamily: kMono,
    visualDensity: VisualDensity.standard,
  );

  return base.copyWith(
    extensions: [c],
    textTheme: base.textTheme.apply(
      bodyColor: c.text,
      displayColor: c.text,
      fontFamily: kMono,
    ),
    iconTheme: IconThemeData(color: c.textDim, size: 20),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    tabBarTheme: TabBarThemeData(
      labelColor: c.accent,
      unselectedLabelColor: c.textDim,
      indicatorColor: c.accent,
      dividerColor: c.border,
      labelStyle: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.2,
        fontFamily: kMono,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: 11,
        fontFamily: kMono,
        letterSpacing: 1.2,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        side: BorderSide(color: c.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.panelAlt,
      contentTextStyle: TextStyle(color: c.text, fontFamily: kMono, fontSize: 12),
      behavior: SnackBarBehavior.floating,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.panel,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: c.text, fontFamily: kMono, fontSize: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.border),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
  );
}

/// Status bar / navigation bar styling that matches the active theme.
SystemUiOverlayStyle zetSystemOverlay(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor:
        dark ? const Color(0xFF0D0D0D) : const Color(0xFFF1EDE2),
    systemNavigationBarIconBrightness:
        dark ? Brightness.light : Brightness.dark,
  );
}

/// Convenience accessor so screens stay short.
extension ZetColorsX on BuildContext {
  ZetColors get zet => Theme.of(this).extension<ZetColors>()!;
}
