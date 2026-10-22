import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences that are not the theme: currently the nearby-stop radius
/// (400 / 800 / 1200 m from the design handoff's Settings screen).
///
/// Kept separate from [ThemeController] so a radius change only rebuilds the
/// widgets that listen to it, not the whole app.
class SettingsController extends ChangeNotifier {
  static const String _radiusKey = 'radius_meters';

  /// The three values the handoff offers. 800 is the default.
  static const List<double> radiusChoices = [400, 800, 1200];

  double _radiusM = 800;
  double get radiusM => _radiusM;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getDouble(_radiusKey);
      if (stored != null && radiusChoices.contains(stored)) {
        _radiusM = stored;
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
}
