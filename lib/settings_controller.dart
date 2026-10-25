import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/models.dart';

/// User preferences that are not the theme.
class SettingsController extends ChangeNotifier {
  static const String _radiusKey = 'radius_meters';
  static const String _favoritesKey = 'favorite_stop_ids';

  /// The three values the handoff offers. 800 is the default.
  static const List<double> radiusChoices = [400, 800, 1200];

  double _radiusM = 800;
  double get radiusM => _radiusM;

  final Set<String> _favorites = <String>{};
  Set<String> get favorites => _favorites;

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
    final legacy = [for (final f in _favorites) if (!_isKey(f)) f];
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

  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_favoritesKey, _favorites.toList());
    } catch (_) {}
  }
}
