import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// All colours used by the app, exposed as a [ThemeExtension] so widgets can
/// read them from `Theme.of(context)` instead of hard-coding constants.
///
/// Values come from the Claude design handoff (`design_handoff_treska_android/`,
/// section „Design tokeni“). The handoff's names are mapped onto this class:
/// `surface` → [bg], `surfC` → [panelAlt], `surfCH` → [panel], `ink` → [text],
/// `ink2` → [textDim], `outline` → [border], `outlineV` → [borderStrong],
/// `primary` → [accent] / [primary], `primaryC` → [primaryContainer].
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

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;

  final Color tram;
  final Color onTram;
  final Color bus;
  final Color onBus;

  final Color danger;
  final Color ok;
  final Color warn;
  final Color live;
  final Color liveContainer;
  final Color onLiveContainer;

  final Color inverse;
  final Color onInverse;

  /// Vector map style (MapLibre style JSON). When set, the map draws vector
  /// tiles from it and the raster fields below are only the fallback for a
  /// style that fails to load. Empty: raster only.
  final String mapStyleUrl;

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

  /// True when the dark map tiles already read as "dark" and need no filter.
  final bool tileIsDark;

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
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.tram,
    required this.onTram,
    required this.bus,
    required this.onBus,
    required this.danger,
    required this.ok,
    required this.warn,
    required this.live,
    required this.liveContainer,
    required this.onLiveContainer,
    required this.inverse,
    required this.onInverse,
    this.mapStyleUrl = '',
    required this.tileUrl,
    required this.tileSubdomains,
    this.tileLabelsUrl = '',
    required this.tileAttribution,
    this.tileMaxNativeZoom = 19,
    this.tileIsDark = false,
  });

  bool get isDark => brightness == Brightness.dark;

  static const dark = ZetColors(
    brightness: Brightness.dark,
    bg: ZetPalette.darkSurface,
    panel: ZetPalette.darkSurfaceContainerHigh,
    panelAlt: ZetPalette.darkSurfaceContainer,
    border: ZetPalette.darkOutline,
    borderStrong: ZetPalette.darkOutlineVariant,
    accent: ZetPalette.darkPrimary,
    accentDim: Color(0xFF6B93C9),
    textHi: ZetPalette.darkPrimary,
    text: ZetPalette.darkInk,
    textDim: ZetPalette.darkInk2,
    primary: ZetPalette.darkPrimary,
    onPrimary: ZetPalette.darkOnPrimary,
    primaryContainer: ZetPalette.darkPrimaryContainer,
    onPrimaryContainer: ZetPalette.darkOnPrimaryContainer,
    tram: Color(0xFF92C1FD),
    onTram: Color(0xFF031D44),
    bus: Color(0xFFF2AD73),
    onBus: Color(0xFF401A01),
    danger: Color(0xFFFD7468),
    ok: Color(0xFF6FD087),
    warn: Color(0xFFF2B966),
    live: Color(0xFFFD7468),
    liveContainer: Color(0xFF5A2520),
    onLiveContainer: Color(0xFFFEDBD6),
    inverse: Color(0xFFE1E5EA),
    onInverse: Color(0xFF1C222B),
    // OpenFreeMap: free, no key, no request limit, apps allowed with credit.
    mapStyleUrl: 'https://tiles.openfreemap.org/styles/dark',
    // Fallback: Esri's dark canvas. Labels are a separate reference layer,
    // stacked on top by the map panel.
    tileUrl: 'https://server.arcgisonline.com/ArcGIS/rest/services/'
        'Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}',
    tileLabelsUrl: 'https://server.arcgisonline.com/ArcGIS/rest/services/'
        'Canvas/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
    tileSubdomains: [],
    tileAttribution: '© Esri, HERE, Garmin, © OpenStreetMap contributors',
    tileMaxNativeZoom: 16,
    tileIsDark: true,
  );

  static const light = ZetColors(
    brightness: Brightness.light,
    bg: ZetPalette.lightSurface,
    panel: ZetPalette.lightSurfaceContainerHigh,
    panelAlt: ZetPalette.lightSurfaceContainer,
    border: ZetPalette.lightOutline,
    borderStrong: ZetPalette.lightOutlineVariant,
    accent: ZetPalette.lightPrimary,
    accentDim: Color(0xFF5B7FAF),
    textHi: ZetPalette.lightPrimary,
    text: ZetPalette.lightInk,
    textDim: ZetPalette.lightInk2,
    primary: ZetPalette.lightPrimary,
    onPrimary: ZetPalette.lightOnPrimary,
    primaryContainer: ZetPalette.lightPrimaryContainer,
    onPrimaryContainer: ZetPalette.lightOnPrimaryContainer,
    tram: Color(0xFF1D5AB0),
    onTram: Color(0xFFFCFCFC),
    bus: Color(0xFFB55422),
    onBus: Color(0xFFFCFCFC),
    danger: Color(0xFFC0281B),
    ok: Color(0xFF1B9247),
    warn: Color(0xFF9D5300),
    live: Color(0xFFD02C2A),
    liveContainer: Color(0xFFFFDEDA),
    onLiveContainer: Color(0xFF901114),
    inverse: Color(0xFF282E38),
    onInverse: Color(0xFFEBEFF4),
    mapStyleUrl: 'https://tiles.openfreemap.org/styles/positron',
    // Fallback: plain OpenStreetMap raster tiles.
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
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? tram,
    Color? onTram,
    Color? bus,
    Color? onBus,
    Color? danger,
    Color? ok,
    Color? warn,
    Color? live,
    Color? liveContainer,
    Color? onLiveContainer,
    Color? inverse,
    Color? onInverse,
    String? mapStyleUrl,
    String? tileUrl,
    String? tileLabelsUrl,
    List<String>? tileSubdomains,
    String? tileAttribution,
    int? tileMaxNativeZoom,
    bool? tileIsDark,
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
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      tram: tram ?? this.tram,
      onTram: onTram ?? this.onTram,
      bus: bus ?? this.bus,
      onBus: onBus ?? this.onBus,
      danger: danger ?? this.danger,
      ok: ok ?? this.ok,
      warn: warn ?? this.warn,
      live: live ?? this.live,
      liveContainer: liveContainer ?? this.liveContainer,
      onLiveContainer: onLiveContainer ?? this.onLiveContainer,
      inverse: inverse ?? this.inverse,
      onInverse: onInverse ?? this.onInverse,
      mapStyleUrl: mapStyleUrl ?? this.mapStyleUrl,
      tileUrl: tileUrl ?? this.tileUrl,
      tileLabelsUrl: tileLabelsUrl ?? this.tileLabelsUrl,
      tileSubdomains: tileSubdomains ?? this.tileSubdomains,
      tileAttribution: tileAttribution ?? this.tileAttribution,
      tileMaxNativeZoom: tileMaxNativeZoom ?? this.tileMaxNativeZoom,
      tileIsDark: tileIsDark ?? this.tileIsDark,
    );
  }

  @override
  ZetColors lerp(ThemeExtension<ZetColors>? other, double t) {
    if (other is! ZetColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return ZetColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: l(bg, other.bg),
      panel: l(panel, other.panel),
      panelAlt: l(panelAlt, other.panelAlt),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      accent: l(accent, other.accent),
      accentDim: l(accentDim, other.accentDim),
      textHi: l(textHi, other.textHi),
      text: l(text, other.text),
      textDim: l(textDim, other.textDim),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      primaryContainer: l(primaryContainer, other.primaryContainer),
      onPrimaryContainer: l(onPrimaryContainer, other.onPrimaryContainer),
      tram: l(tram, other.tram),
      onTram: l(onTram, other.onTram),
      bus: l(bus, other.bus),
      onBus: l(onBus, other.onBus),
      danger: l(danger, other.danger),
      ok: l(ok, other.ok),
      warn: l(warn, other.warn),
      live: l(live, other.live),
      liveContainer: l(liveContainer, other.liveContainer),
      onLiveContainer: l(onLiveContainer, other.onLiveContainer),
      inverse: l(inverse, other.inverse),
      onInverse: l(onInverse, other.onInverse),
      mapStyleUrl: t < 0.5 ? mapStyleUrl : other.mapStyleUrl,
      tileUrl: t < 0.5 ? tileUrl : other.tileUrl,
      tileLabelsUrl: t < 0.5 ? tileLabelsUrl : other.tileLabelsUrl,
      tileSubdomains: t < 0.5 ? tileSubdomains : other.tileSubdomains,
      tileAttribution: t < 0.5 ? tileAttribution : other.tileAttribution,
      tileMaxNativeZoom:
          t < 0.5 ? tileMaxNativeZoom : other.tileMaxNativeZoom,
      tileIsDark: t < 0.5 ? tileIsDark : other.tileIsDark,
    );
  }
}

/// No custom font family: the app inherits the device's own UI font.
///
/// The handoff specifies Roboto Flex, which is what Android already ships as the
/// system font, and its `tabular-nums` is what stops ticking numbers from
/// jittering. Hardcoding a family (or 'monospace') would override the user's
/// device font and break that match, so text styles leave the family alone and
/// only set [kTabular].
const String? kFontFamily = null;

/// Tabular figures for every number that ticks (ETA, feed age, clock times) so
/// the layout never jitters as digits change width.
const List<FontFeature> kTabular = [FontFeature.tabularFigures()];

ThemeData buildZetTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? ZetColors.dark : ZetColors.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.primaryContainer,
    onPrimaryContainer: c.onPrimaryContainer,
    secondary: c.tram,
    onSecondary: c.onTram,
    secondaryContainer: c.panelAlt,
    onSecondaryContainer: c.text,
    tertiary: c.bus,
    onTertiary: c.onBus,
    error: c.danger,
    onError: Colors.white,
    errorContainer: c.liveContainer,
    onErrorContainer: c.onLiveContainer,
    surface: c.bg,
    onSurface: c.text,
    surfaceContainer: c.panelAlt,
    surfaceContainerHigh: c.panel,
    surfaceContainerHighest: c.panel,
    onSurfaceVariant: c.textDim,
    outline: c.border,
    outlineVariant: c.borderStrong,
    inverseSurface: c.inverse,
    onInverseSurface: c.onInverse,
    scrim: Colors.black,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
  );

  return base.copyWith(
    extensions: [c],
    textTheme: base.textTheme.apply(
      bodyColor: c.text,
      displayColor: c.text,
    ),
    iconTheme: IconThemeData(color: c.textDim, size: 24),
    dividerTheme:
        DividerThemeData(color: c.borderStrong, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.primary,
      unselectedLabelColor: c.textDim,
      indicatorColor: c.primary,
      dividerColor: c.borderStrong,
      labelStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
       
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: 14,
       
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: c.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ZetRadius.sheet)),
      ),
      dragHandleColor: c.border,
      dragHandleSize: const Size(32, 4),
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZetRadius.card),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.inverse,
      contentTextStyle:
          TextStyle(color: c.onInverse, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZetRadius.chip),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.panel,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: c.text, fontSize: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZetRadius.zoom),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.panel,
      selectedColor: c.primaryContainer,
      side: BorderSide(color: c.border),
      labelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: c.text,
       
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZetRadius.chip),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
         
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZetRadius.pill),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.primary,
        side: BorderSide(color: c.border),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
         
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZetRadius.pill),
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 14),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.primaryContainer
              : c.panel,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.onPrimaryContainer
              : c.text,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: c.border)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
  );
}

/// Status bar / navigation bar styling that matches the active theme.
SystemUiOverlayStyle zetSystemOverlay(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? ZetColors.dark : ZetColors.light;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: c.bg,
    systemNavigationBarIconBrightness:
        dark ? Brightness.light : Brightness.dark,
  );
}

/// Convenience accessor so screens stay short.
extension ZetColorsX on BuildContext {
  ZetColors get zet => Theme.of(this).extension<ZetColors>()!;
}
