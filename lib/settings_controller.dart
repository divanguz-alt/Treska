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

  bool isFavorite(String stopId) => _favorites.contains(stopId);

  /// Saved ids that refer to [stop]: its own id or any platform of the same
  /// stop. The board shows a stop under its nearest platform's id, which
  /// changes as the user moves, so an id-only check would make the star flicker
  /// on and off for the very same stop.
  Set<String> favoriteIdsFor(StopInfo stop, Map<String, StopInfo> stopById) {
    final out = <String>{};
    for (final id in _favorites) {
      if (id == stop.id) {
        out.add(id);
        continue;
      }
      final saved = stopById[id];
      if (saved != null && sameStopGroup(saved, stop)) out.add(id);
    }
    return out;
  }

  bool isFavoriteStop(StopInfo stop, Map<String, StopInfo> stopById) =>
      favoriteIdsFor(stop, stopById).isNotEmpty;

  /// Saves [stop], or forgets every saved platform of it.
  Future<void> toggleFavoriteStop(
      StopInfo stop, Map<String, StopInfo> stopById) async {
    final saved = favoriteIdsFor(stop, stopById);
    if (saved.isEmpty) {
      _favorites.add(stop.id);
    } else {
      _favorites.removeAll(saved);
    }
    notifyListeners();
    await _saveFavorites();
  }

  Future<void> toggleFavorite(String stopId) async {
    if (_favorites.contains(stopId)) {
      _favorites.remove(stopId);
    } else {
      _favorites.add(stopId);
    }
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
