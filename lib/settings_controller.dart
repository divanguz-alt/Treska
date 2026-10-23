import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> toggleFavorite(String stopId) async {
    if (_favorites.contains(stopId)) {
      _favorites.remove(stopId);
    } else {
      _favorites.add(stopId);
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_favoritesKey, _favorites.toList());
    } catch (_) {}
  }
}
