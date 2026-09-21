import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../core/demo_config.dart';
import '../models/call_record_model.dart';

/// Post-call analysis through the gateway (/api/analyze-call).
class AssemblyAIService {
  AssemblyAIService();

  /// Returns {summary, actionItem, sentimentScore}; falls back to a plain
  /// excerpt when the gateway can't be reached.
  Future<Map<String, dynamic>> analyzeRealCallTranscript({
    required String gatewayUrl,
    required List<TranscriptEntry> transcript,
    String? authSecret,
    Map<String, dynamic>? callerDetails,
  }) async {
    try {
      final httpUrl = gatewayUrl
          .replaceFirst(RegExp(r'^ws:\/\/'), 'http://')
          .replaceFirst(RegExp(r'^wss:\/\/'), 'https://');
      final uri = Uri.parse('$httpUrl/api/analyze-call');

      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (authSecret != null && authSecret.isNotEmpty) 'X-Awaaz-Secret': authSecret,
          // The demo gateway has no secret; it accepts a registered line instead
          if (DemoConfig.line.isNotEmpty) 'X-Awaaz-Line': DemoConfig.line,
        },
        body: jsonEncode({
          'transcript': transcript.map((t) => t.toJson()).toList(),
          'caller': ?callerDetails,
        }),
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}

    // Fallback if gateway is unreachable or offline
    final text = transcript.where((t) => t.speaker == 'Caller').map((t) => t.text).join(' ');
    final preview = text.isNotEmpty ? text.substring(0, min(text.length, 140)) : 'Call completed.';
    return {
      'summary': preview,
      'actionItem': null,
      'sentimentScore': 0.0,
    };
  }
}
