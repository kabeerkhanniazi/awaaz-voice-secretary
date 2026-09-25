import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/demo_config.dart';

class BackgroundServiceStatus {
  final bool standby;
  final bool notificationsAllowed;
  final bool fullScreenAllowed;

  const BackgroundServiceStatus({
    this.standby = false,
    this.notificationsAllowed = false,
    this.fullScreenAllowed = false,
  });
}

/// Android foreground service (android/.../AwaazService.kt):
/// - standby: rings with a full-screen call alert when someone calls while the
///   app is closed;
/// - in-call: keeps the microphone working with the screen off.
/// Every call is a no-op where the service doesn't exist (tests, other platforms).
class BackgroundService {
  static const MethodChannel _channel = MethodChannel('awaaz/service');

  /// Mirrors the gateway address and secret (and, in the demo build, this
  /// install's line) for the service's own connection.
  static Future<void> configure({required String url, required String secret}) =>
      _call('configure', {'url': url, 'secret': secret, 'line': DemoConfig.line});

  static Future<void> setStandby(bool enabled) => _call('setStandby', {'enabled': enabled});

  /// Owner settings as last sent to the gateway (see syncOwnerSettings), so
  /// the service can re-send them when it registers on its own.
  static Future<void> setOwnerSettings(String json) => _call('setOwnerSettings', {'json': json});

  static Future<void> startCall(String caller) => _call('startCall', {'caller': caller});

  static Future<void> stopCall() => _call('stopCall');

  static Future<void> cancelIncomingAlert() => _call('cancelIncoming');

  static Future<void> openFullScreenSettings() => _call('openFullScreenSettings');

  static Future<BackgroundServiceStatus> status() async {
    final result = await _call<Map<Object?, Object?>>('status');
    if (result == null) return const BackgroundServiceStatus();
    return BackgroundServiceStatus(
      standby: result['standby'] == true,
      notificationsAllowed: result['notificationsAllowed'] == true,
      fullScreenAllowed: result['fullScreenAllowed'] == true,
    );
  }

  static Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (e) {
      debugPrint('[BackgroundService] $method unavailable: $e');
      return null;
    }
  }
}
