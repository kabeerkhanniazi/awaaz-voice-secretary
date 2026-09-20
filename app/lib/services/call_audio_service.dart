import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

/// Two-way call audio for Patch In: captures the phone mic and plays the
/// caller, both as 24 kHz PCM16 mono (the format the caller page uses).
/// Playback goes through a small native player (android/.../CallAudioPlayer.kt)
/// on the voice-call channel, where Android applies echo cancellation.
class CallAudioService {
  static const int sampleRate = 24000;
  static const MethodChannel _player = MethodChannel('awaaz/call_audio');

  // Created on first use so tests and simulated calls never touch the plugin
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _micSub;
  bool _active = false;

  bool get isActive => _active;

  /// Asks for the microphone permission if it hasn't been granted yet.
  Future<bool> ensureMicPermission() async {
    try {
      _recorder ??= AudioRecorder();
      return await _recorder!.hasPermission();
    } catch (e) {
      // No recorder plugin (e.g. tests, unsupported platform): no voice, buttons still work
      debugPrint('[CallAudio] Microphone unavailable: $e');
      return false;
    }
  }

  Future<void> start({required void Function(Uint8List chunk) onMicChunk}) async {
    if (_active) return;
    _active = true;
    try {
      await _player.invokeMethod('start', {'sampleRate': sampleRate});

      _recorder ??= AudioRecorder();
      final stream = await _recorder!.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
        androidConfig: AndroidRecordConfig(
          // Voice-call capture path, paired with the voice-call playback above
          audioSource: AndroidAudioSource.voiceCommunication,
          audioManagerMode: AudioManagerMode.modeInCommunication,
          speakerphone: true,
        ),
      ));
      _micSub = stream.listen(onMicChunk);
    } catch (e) {
      debugPrint('[CallAudio] Failed to start: $e');
      await stop();
      rethrow;
    }
  }

  /// Queues one chunk of the caller's voice for playback.
  void play(Uint8List pcm16) {
    if (!_active || pcm16.lengthInBytes < 2) return;
    _player.invokeMethod('feed', {'pcm': pcm16}).catchError((Object e) {
      debugPrint('[CallAudio] Playback feed failed: $e');
    });
  }

  /// Drops audio queued for playback (the secretary was interrupted).
  void flush() {
    if (!_active) return;
    _player.invokeMethod('flush').catchError((Object e) {
      debugPrint('[CallAudio] Playback flush failed: $e');
    });
  }

  Future<void> stop() async {
    final wasActive = _active;
    _active = false;
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await _recorder?.isRecording() ?? false) await _recorder!.stop();
    } catch (e) {
      debugPrint('[CallAudio] Recorder stop failed: $e');
    }
    if (wasActive) {
      try {
        await _player.invokeMethod('stop');
      } catch (e) {
        debugPrint('[CallAudio] Player stop failed: $e');
      }
    }
  }
}
