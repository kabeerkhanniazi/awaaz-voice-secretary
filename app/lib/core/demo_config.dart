import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// The judges' demo build.
///
/// Built with `--dart-define=AWAAZ_DEMO_GATEWAY=wss://<demo gateway>`, the app
/// talks to a gateway running with DEMO_MODE=1: no secret, and this install gets
/// its own line. Its link (`https://<demo gateway>/?line=CODE`) rings this phone
/// and no other, so several judges can try it at once. A normal build leaves
/// [gateway] empty and none of this applies.
class DemoConfig {
  static const String gateway = String.fromEnvironment('AWAAZ_DEMO_GATEWAY');
  static bool get enabled => gateway.isNotEmpty;

  static const String _keyLine = 'awaaz_demo_line';
  // No 0/O or 1/I, so the code survives being read aloud or retyped
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String _line = '';

  /// This install's line code; empty outside the demo build.
  static String get line => _line;

  /// The link that rings this phone: open it on another device and press Call.
  static String get callLink {
    final base = gateway
        .replaceFirst(RegExp(r'^wss://'), 'https://')
        .replaceFirst(RegExp(r'^ws://'), 'http://')
        .replaceAll(RegExp(r'/+$'), '');
    return '$base/?line=$_line';
  }

  /// Loads the line code, creating it on first launch. Call once at startup.
  static Future<void> load(SharedPreferences prefs) async {
    if (!enabled) return;
    var code = prefs.getString(_keyLine) ?? '';
    if (code.length < 6) {
      final random = Random.secure();
      code = List.generate(6, (_) => _alphabet[random.nextInt(_alphabet.length)]).join();
      await prefs.setString(_keyLine, code);
    }
    _line = code;
  }
}
