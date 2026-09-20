import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'storage_service.dart';

enum GatewayStatus { disconnected, connecting, connected, authFailed }

class WebSocketService with WidgetsBindingObserver {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;

  WebSocketService._internal() {
    WidgetsBinding.instance.addObserver(this);
  }

  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  // Binary frames: the caller's voice during Patch In (PCM16, 24 kHz, mono)
  final StreamController<Uint8List> _audioController = StreamController<Uint8List>.broadcast();

  /// While true (a Patch In call is live), backgrounding the app does not drop
  /// the connection, so a screen-off doesn't cut the caller off.
  bool keepAliveInBackground = false;

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isManuallyDisconnected = false;
  // Set when the gateway rejects the secret: retrying can't help until the
  // settings change, so automatic reconnects stop.
  bool _authFailed = false;
  int _retryAttempt = 0;
  Timer? _reconnectTimer;

  /// Connected means registered with the gateway, not just socket-open.
  final ValueNotifier<GatewayStatus> status = ValueNotifier(GatewayStatus.disconnected);
  String? lastError;

  bool get isConnected => _isConnected;
  String _serverUrl = StorageService.defaultGatewayUrl;
  String _authSecret = '';

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<Uint8List> get audioStream => _audioController.stream;
  String get wsUrl => _serverUrl;

  /// Applies saved settings and (re)connects.
  void configure({required String url, required String secret}) {
    _serverUrl = sanitizeUrl(url);
    _authSecret = secret.trim();
    reconnect();
  }

  void setAuthSecret(String secret) {
    _authSecret = secret.trim();
    reconnect();
  }

  /// Set server URL with sanitized rules (B8)
  void setServerUrl(String rawUrl) {
    _serverUrl = sanitizeUrl(rawUrl);
    reconnect();
  }

  /// B8 URL Resolution:
  /// 1. If user typed explicit scheme (ws:// or wss://), honor it.
  /// 2. localhost, *.local, or private IP range -> ws:// with given port (default 3000).
  /// 3. Anything else -> wss:// with no explicit port.
  /// 4. Rejects mixed content.
  static String sanitizeUrl(String input) {
    var raw = input.trim();
    if (raw.isEmpty) return StorageService.defaultGatewayUrl;

    // 1. Explicit scheme honoring
    if (raw.startsWith('ws://') || raw.startsWith('wss://')) {
      return raw.replaceAll(RegExp(r'/+$'), '');
    }
    if (raw.startsWith('http://')) {
      final without = raw.substring('http://'.length).replaceAll(RegExp(r'/+$'), '');
      return 'ws://$without';
    }
    if (raw.startsWith('https://')) {
      final without = raw.substring('https://'.length).replaceAll(RegExp(r'/+$'), '');
      return 'wss://$without';
    }

    var clean = raw.replaceAll(RegExp(r'/+$'), '');
    String host = clean;
    String? port;

    if (clean.contains(':')) {
      final parts = clean.split(':');
      host = parts[0];
      port = parts.length > 1 ? parts[1] : null;
    }

    // 2. Localhost, *.local, or private IP range
    final isLocalhost = host == 'localhost' || host == '127.0.0.1';
    final isLocalDomain = host.endsWith('.local');
    final isPrivate = _isPrivateIp(host);

    if (isLocalhost || isLocalDomain || isPrivate) {
      final p = port ?? '3000';
      return 'ws://$host:$p';
    }

    // 3. Cloud / public host -> wss:// with no explicit port
    return 'wss://$host';
  }

  static bool _isPrivateIp(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map((e) => int.tryParse(e)).toList();
    if (octets.any((e) => e == null || e < 0 || e > 255)) return false;

    if (octets[0] == 10) return true;
    if (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31) return true;
    if (octets[0] == 192 && octets[1] == 168) return true;
    if (octets[0] == 127) return true;
    return false;
  }

  /// B8: Interactive connection test. Succeeds only if the gateway accepts
  /// the secret, not merely when the socket opens.
  Future<Map<String, dynamic>> testConnection(String rawUrl, {required String secret}) async {
    final resolvedUrl = sanitizeUrl(rawUrl);
    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse(resolvedUrl));
      await channel.ready.timeout(const Duration(seconds: 4));
      // Subscribe before registering so the reply can't be missed
      final reply = channel.stream
          .map((d) => jsonDecode(d.toString()) as Map<String, dynamic>)
          .firstWhere((m) => m['type'] == 'REGISTERED_SUCCESS' || m['type'] == 'AUTH_FAILED')
          .timeout(const Duration(seconds: 4));
      channel.sink.add(jsonEncode({
        'type': 'REGISTER_MOBILE',
        'authSecret': secret.trim(),
      }));
      final msg = await reply;
      final ok = msg['type'] == 'REGISTERED_SUCCESS';
      return {
        'success': ok,
        'resolvedUrl': resolvedUrl,
        'message': ok
            ? 'Connected and authenticated'
            : 'Server reachable, but it rejected the secret: ${msg['error'] ?? 'auth failed'}',
      };
    } catch (e) {
      return {
        'success': false,
        'resolvedUrl': resolvedUrl,
        'message': 'Could not connect: $e',
      };
    } finally {
      channel?.sink.close();
    }
  }

  /// C4: Single-flight guard, exponential backoff with jitter
  Future<void> connect() async {
    _isManuallyDisconnected = false;
    if (_isConnected || _isConnecting || _authFailed) return;
    _isConnecting = true;
    status.value = GatewayStatus.connecting;

    // Every callback below checks it still belongs to the current channel, so
    // events from a socket replaced by reconnect() can't clobber the new one.
    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[WebSocket] Connection failed: $e');
      channel?.sink.close();
      if (identical(_channel, channel)) _handleDisconnect();
      return;
    }

    if (!identical(_channel, channel)) {
      // Superseded by disconnect() or reconnect() while connecting
      channel.sink.close();
      return;
    }

    _isConnected = true;
    _isConnecting = false;
    _retryAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    debugPrint('[WebSocket] Connected to $wsUrl');

    channel.stream.listen(
      (data) {
        if (!identical(_channel, channel)) return;
        if (data is List<int>) {
          _audioController.add(data is Uint8List ? data : Uint8List.fromList(data));
        } else {
          _onMessage(data);
        }
      },
      onError: (error) {
        if (!identical(_channel, channel)) return;
        debugPrint('[WebSocket] Error: $error');
        _handleDisconnect();
      },
      onDone: () {
        if (!identical(_channel, channel)) return;
        debugPrint('[WebSocket] Connection closed');
        _handleDisconnect();
      },
    );

    // C2 & C4: Re-register on every successful connect
    send({
      'type': 'REGISTER_MOBILE',
      'authSecret': _authSecret,
    });
  }

  void _onMessage(dynamic data) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(data.toString()) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[WebSocket] JSON parse error: $e');
      return;
    }

    switch (json['type']) {
      case 'REGISTERED_SUCCESS':
        lastError = null;
        status.value = GatewayStatus.connected;
      case 'AUTH_FAILED':
        _authFailed = true;
        lastError = json['error'] as String? ?? 'Authentication failed';
        status.value = GatewayStatus.authFailed;
        debugPrint('[WebSocket] Gateway rejected secret: $lastError');
    }
    _messageController.add(json);
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    _channel = null;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    if (_authFailed) return;
    status.value = GatewayStatus.disconnected;
    if (_isManuallyDisconnected) return;

    // C4: Exponential backoff with jitter capped ~30s
    _retryAttempt++;
    final baseDelay = min(30.0, pow(1.5, _retryAttempt).toDouble());
    final jitter = 0.8 + (Random().nextDouble() * 0.4);
    final delaySeconds = (baseDelay * jitter).clamp(1.0, 30.0);

    debugPrint('[WebSocket] Reconnecting in ${delaySeconds.toStringAsFixed(1)}s (attempt #$_retryAttempt)...');
    _reconnectTimer = Timer(Duration(milliseconds: (delaySeconds * 1000).toInt()), () {
      if (!_isConnected && !_isConnecting && !_isManuallyDisconnected) {
        connect();
      }
    });
  }

  void reconnect() {
    disconnect();
    _authFailed = false;
    lastError = null;
    connect();
  }

  void disconnect() {
    _isManuallyDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    // Clear the reference first so the old channel's callbacks are ignored
    final channel = _channel;
    _channel = null;
    channel?.sink.close();
    _isConnected = false;
    _isConnecting = false;
    if (!_authFailed) status.value = GatewayStatus.disconnected;
  }

  void send(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(data));
    } else {
      debugPrint('[WebSocket] Cannot send, not connected');
    }
  }

  /// Delivers a gateway message as if it had arrived over the socket.
  @visibleForTesting
  void debugReceive(Map<String, dynamic> message) => _messageController.add(message);

  void sendBinary(Uint8List bytes) {
    if (_channel != null && _isConnected) _channel!.sink.add(bytes);
  }

  void sendMasterDirective({
    required String callId,
    required String action,
    String? spokenDirective,
    int? holdMinutes,
    int directiveVersion = 1,
  }) {
    send({
      'type': 'MASTER_DIRECTIVE',
      'data': {
        'callId': callId,
        'action': action,
        'spokenDirective': spokenDirective,
        'holdMinutes': ?holdMinutes,
        'directiveVersion': directiveVersion,
      },
    });
  }

  // C4: App lifecycle awareness
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && keepAliveInBackground) {
      debugPrint('[WebSocket] App backgrounded during a live call — keeping the connection');
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      debugPrint('[WebSocket] App backgrounded — disconnecting socket to prevent zombie process');
      disconnect();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('[WebSocket] App resumed — reconnecting socket');
      connect();
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disconnect();
    status.dispose();
    _messageController.close();
    _audioController.close();
  }
}
