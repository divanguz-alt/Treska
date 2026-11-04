import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/models.dart';
import 'ui/led/led_palette.dart';
import 'ui/widgets/vehicle_marker.dart';

/// User preferences that are not the theme.
class SettingsController extends ChangeNotifier {
  static const String _radiusKey = 'radius_meters';
  static const String _favoritesKey = 'favorite_stop_ids';
  static const String _showTramsKey = 'show_trams';
  static const String _showBusesKey = 'show_buses';
  static const String _zetDisplayKey = 'zet_display_enabled';
  static const String _zetColorKey = 'zet_display_color';
  static const String _zetMarqueeKey = 'zet_display_marquee';
  static const String _vehicleArrowKey = 'vehicle_arrow';

  /// The three values the handoff offers. 800 is the default.
  static const List<double> radiusChoices = [400, 800, 1200];

  double _radiusM = 800;
  double get radiusM => _radiusM;

  final Set<String> _favorites = <String>{};
  Set<String> get favorites => _favorites;

  bool _showTrams = true;
  bool _showBuses = false;

  /// Board and map filter, global and remembered. Never both off. Trams only
  /// by default: the map gets slow with every vehicle on it.
  bool get showTrams => _showTrams;
  bool get showBuses => _showBuses;

  /// [kModeTram] / [kModeBus] bits the filter lets through.
  int get shownModes =>
      (_showTrams ? kModeTram : 0) | (_showBuses ? kModeBus : 0);

  bool _zetDisplay = false;
  String _zetColor = LedPalette.auto;
  bool _zetMarquee = true;

  /// „ZET zaslon“: arrival rows drawn as the LED sign on the vehicle.
  bool get zetDisplay => _zetDisplay;

  /// „Boja zaslona“ option id, see [LedPalette.options].
  String get zetColor => _zetColor;

  /// „Pomicanje dugih natpisa“.
  bool get zetMarquee => _zetMarquee;

  void setZetDisplay(bool value) =>
      _setBool(_zetDisplayKey, value, _zetDisplay, (v) => _zetDisplay = v);

  void setZetMarquee(bool value) =>
      _setBool(_zetMarqueeKey, value, _zetMarquee, (v) => _zetMarquee = v);

  VehicleArrow _vehicleArrow = VehicleArrow.fallback;

  /// „Strelica smjera“ on the map's vehicle badges.
  VehicleArrow get vehicleArrow => _vehicleArrow;

  void setVehicleArrow(VehicleArrow arrow) {
    if (arrow == _vehicleArrow) return;
    _vehicleArrow = arrow;
    notifyListeners();
    _save((p) => p.setString(_vehicleArrowKey, arrow.id));
  }

  void setZetColor(String id) {
    if (id == _zetColor || !LedPalette.isKnown(id)) return;
    _zetColor = id;
    notifyListeners();
    _save((p) => p.setString(_zetColorKey, id));
  }

  void _setBool(
    String key,
    bool value,
    bool current,
    void Function(bool) assign,
  ) {
    if (value == current) return;
    assign(value);
    notifyListeners();
    _save((p) => p.setBool(key, value));
  }

  /// Flips one mode of the board filter. Returns false (and changes nothing)
  /// when that would leave both modes off.
  bool toggleShown(int mode) {
    final next = shownModes ^ mode;
    if (next == 0) return false;
    _showTrams = (next & kModeTram) != 0;
    _showBuses = (next & kModeBus) != 0;
    notifyListeners();
    _save((p) async {
      await p.setBool(_showTramsKey, _showTrams);
      await p.setBool(_showBusesKey, _showBuses);
    });
    return true;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getDouble(_radiusKey);
      if (stored != null && radiusChoices.contains(stored)) {
        _radiusM = stored;
        notifyListeners();
      }
      final favs = prefs.getStringList(_favoritesKey);
      if (favs != null) {
        _favorites
          ..clear()
          ..addAll(favs);
        notifyListeners();
      }
      final trams = prefs.getBool(_showTramsKey) ?? true;
      final buses = prefs.getBool(_showBusesKey) ?? false;
      if (trams || buses) {
        _showTrams = trams;
        _showBuses = buses;
      }
      _zetDisplay = prefs.getBool(_zetDisplayKey) ?? false;
      _zetMarquee = prefs.getBool(_zetMarqueeKey) ?? true;
      final color = prefs.getString(_zetColorKey);
      if (color != null && LedPalette.isKnown(color)) _zetColor = color;
      _vehicleArrow =
          VehicleArrow.byId(prefs.getString(_vehicleArrowKey)) ??
          VehicleArrow.fallback;
      notifyListeners();
    } catch (_) {
      // Prefs unavailable — keep the default.
    }
  }

  Future<void> setRadius(double meters) async {
    if (meters == _radiusM) return;
    _radiusM = meters;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_radiusKey, meters);
    } catch (_) {}
  }

  /// A favourite is a stop *name* in one mode, not a platform: saving
  /// „Trg dr. F. Tuđmana“ as a tram stop stars every tram platform with that
  /// name, while its bus platforms stay plain unless saved separately.
  static String favoriteKey(String name, int mode) =>
      '${mode == kModeTram ? _tramPrefix : _busPrefix}${stopGroupKey(name)}';

  static const String _tramPrefix = 'tram|';
  static const String _busPrefix = 'bus|';

  static bool _isKey(String value) =>
      value.startsWith(_tramPrefix) || value.startsWith(_busPrefix);

  bool isFavoriteStop(StopInfo stop, int mode) =>
      _favorites.contains(favoriteKey(stop.name, mode));

  /// True when the name is saved for any of the [modes] bits.
  bool isFavoriteForAny(StopInfo stop, int modes) => [
    kModeTram,
    kModeBus,
  ].any((m) => (modes & m) != 0 && isFavoriteStop(stop, m));

  /// Saves or removes the name for every mode in the [modes] bits.
  Future<void> setFavoriteFor(StopInfo stop, int modes, bool favourite) async {
    for (final m in const [kModeTram, kModeBus]) {
      if ((modes & m) == 0) continue;
      final key = favoriteKey(stop.name, m);
      favourite ? _favorites.add(key) : _favorites.remove(key);
    }
    notifyListeners();
    await _saveFavorites();
  }

  /// True when [stop] is drawn as a star on the map in [mode]: it must serve
  /// that mode and its name must be saved for it.
  bool isFavoriteOnMap(StopInfo stop, int mode) =>
      stop.serves(mode) && isFavoriteStop(stop, mode);

  /// Saved (name key, mode) pairs, for lists such as search.
  List<({String nameKey, int mode})> get favoriteEntries => [
    for (final f in _favorites)
      if (f.startsWith(_tramPrefix))
        (nameKey: f.substring(_tramPrefix.length), mode: kModeTram)
      else if (f.startsWith(_busPrefix))
        (nameKey: f.substring(_busPrefix.length), mode: kModeBus),
  ];

  Future<void> toggleFavoriteStop(StopInfo stop, int mode) async {
    final key = favoriteKey(stop.name, mode);
    if (!_favorites.remove(key)) _favorites.add(key);
    notifyListeners();
    await _saveFavorites();
  }

  /// Builds before 2.1.8 saved platform ids. Once the stop list is known, turn
  /// each into the name key of every mode its stop serves. Unknown ids are
  /// kept until a stop list resolves them.
  Future<void> migrateLegacyFavorites(Map<String, StopInfo> stopById) async {
    final legacy = [
      for (final f in _favorites)
        if (!_isKey(f)) f,
    ];
    if (legacy.isEmpty || stopById.isEmpty) return;
    var changed = false;
    for (final id in legacy) {
      final stop = stopById[id];
      if (stop == null) continue;
      _favorites.remove(id);
      for (final mode in const [kModeTram, kModeBus]) {
        if (stop.serves(mode)) _favorites.add(favoriteKey(stop.name, mode));
      }
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    await _saveFavorites();
  }

  Future<void> _save(Future<void> Function(SharedPreferences) write) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (_) {}
  }

  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_favoritesKey, _favorites.toList());
    } catch (_) {}
  }
}
