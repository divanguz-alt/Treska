import 'package:flutter/services.dart';

/// ZET's official ticket app. Treska shows departures; tickets are bought
/// there, so the map links to it instead of duplicating the purchase flow.
class MojZet {
  /// Android package, as linked from zet.hr's Moj ZET page.
  static const String package = 'com.zetmobile';

  static const MethodChannel _channel = MethodChannel('hr.zet.zet2/updates');

  /// Opens Moj ZET, or its Play Store page when it is not installed. False
  /// when neither could be opened (or off Android).
  static Future<bool> open() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('openApp', {'package': package});
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
