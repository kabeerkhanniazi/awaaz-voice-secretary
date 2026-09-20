import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/relationship_constants.dart';
import '../models/scenario_profile.dart';
import '../models/call_record_model.dart';
import '../models/secretary_task_model.dart';
import '../services/assemblyai_service.dart';
import '../services/background_service.dart';
import '../services/call_audio_service.dart';
import '../services/websocket_service.dart';
import 'contacts_provider.dart';
import 'dashboard_provider.dart';
import 'storage_provider.dart';

enum ActiveCallStatus {
  idle,
  ringing,
  secretaryScreening,
  holding,
  masterPatched,
  callEnded,
}

class CallState {
  final ActiveCallStatus status;
  final ScenarioProfile? activeScenario;
  final List<TranscriptEntry> transcriptEntries;
  final String _legacyLiveTranscript;
  final int holdTimerSeconds;
  final String? activeDirective;
  final String? directiveStatus; // 'sending' | 'spoken' | 'failed'
  // Why the last message to the caller failed (shown only while directiveStatus is failed)
  final String? directiveError;
  final int directiveVersion;
  final DateTime? startTime;
  final String? currentCallId;
  final bool isRealCall;
  // Patch In: true once audio is flowing between this phone and the caller
  final bool bridgeLive;
  // Kabeer's voice session with his secretary: 'connecting' | 'listening' |
  // 'speaking' | 'ended' | 'error' | 'noMic', or null when not started
  final String? voiceStatus;
  final bool micMuted;
  // What the secretary last said to Kabeer, shown on the call banner
  final String? lastBriefing;
  // Confirmed by the screening secretary (CALLER_DETAILS); the name itself
  // lives in activeScenario.callerName
  final String? callerCompany;
  final String? callerReason;
  final bool urgent;
  // A message the caller left, and how to call them back (when Kabeer was unavailable)
  final String? callerMessage;
  final String? callerCallback;

  CallState({
    this.status = ActiveCallStatus.idle,
    this.activeScenario,
    this.transcriptEntries = const [],
    String liveTranscript = '',
    this.holdTimerSeconds = 0,
    this.activeDirective,
    this.directiveStatus,
    this.directiveError,
    this.directiveVersion = 0,
    this.startTime,
    this.currentCallId,
    this.isRealCall = false,
    this.bridgeLive = false,
    this.voiceStatus,
    this.micMuted = false,
    this.lastBriefing,
    this.callerCompany,
    this.callerReason,
    this.urgent = false,
    this.callerMessage,
    this.callerCallback,
  }) : _legacyLiveTranscript = liveTranscript;

  /// True until the secretary has learned the caller's name.
  bool get callerUnknown {
    final name = activeScenario?.callerName ?? '';
    return name.isEmpty || name == unknownCallerName;
  }

  /// What the caller page reports before the secretary learns the real name.
  static const String unknownCallerName = 'Web Caller';

  String get liveTranscript {
    if (transcriptEntries.isNotEmpty) {
      return transcriptEntries.map((e) => '${e.speaker}: ${e.text}').join('\n');
    }
    return _legacyLiveTranscript;
  }

  CallState copyWith({
    ActiveCallStatus? status,
    ScenarioProfile? activeScenario,
    List<TranscriptEntry>? transcriptEntries,
    String? liveTranscript,
    int? holdTimerSeconds,
    String? activeDirective,
    String? directiveStatus,
    String? directiveError,
    int? directiveVersion,
    DateTime? startTime,
    String? currentCallId,
    bool? isRealCall,
    bool? bridgeLive,
    String? voiceStatus,
    bool? micMuted,
    String? lastBriefing,
    String? callerCompany,
    String? callerReason,
    bool? urgent,
    String? callerMessage,
    String? callerCallback,
  }) {
    return CallState(
      status: status ?? this.status,
      activeScenario: activeScenario ?? this.activeScenario,
      transcriptEntries: transcriptEntries ?? this.transcriptEntries,
      liveTranscript: liveTranscript ?? _legacyLiveTranscript,
      holdTimerSeconds: holdTimerSeconds ?? this.holdTimerSeconds,
      activeDirective: activeDirective ?? this.activeDirective,
      directiveStatus: directiveStatus ?? this.directiveStatus,
      directiveError: directiveError ?? this.directiveError,
      directiveVersion: directiveVersion ?? this.directiveVersion,
      startTime: startTime ?? this.startTime,
      currentCallId: currentCallId ?? this.currentCallId,
      isRealCall: isRealCall ?? this.isRealCall,
      bridgeLive: bridgeLive ?? this.bridgeLive,
      voiceStatus: voiceStatus ?? this.voiceStatus,
      micMuted: micMuted ?? this.micMuted,
      lastBriefing: lastBriefing ?? this.lastBriefing,
      callerCompany: callerCompany ?? this.callerCompany,
      callerReason: callerReason ?? this.callerReason,
      urgent: urgent ?? this.urgent,
      callerMessage: callerMessage ?? this.callerMessage,
      callerCallback: callerCallback ?? this.callerCallback,
    );
  }
}

class CallNotifier extends Notifier<CallState> {
  StreamSubscription<String>? _transcriptSub;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  Timer? _holdTimer;
  DateTime? _holdStartTime;
  int _holdTotalSeconds = 0;
  int _directiveVersion = 0;
  bool _isCallTerminated = false;

  final AssemblyAIService _assemblyAIService = AssemblyAIService();
  final WebSocketService _wsService = WebSocketService();
  final CallAudioService _audio = CallAudioService();
  StreamSubscription<Uint8List>? _audioSub;
  // The call Kabeer's voice session was started for (to stop it on cleanup)
  String? _voiceCallId;
  // Tasks Kabeer dictated during this call, saved when it ends
  final List<({String text, DateTime? due})> _voiceTasks = [];
  // Name last sent to the gateway as CALLER_CONTEXT (one message per name)
  String? _contextSentFor;

  @override
  CallState build() {
    _initWebSocket();
    ref.onDispose(() {
      _wsService.disconnect();
      _wsSub?.cancel();
      _transcriptSub?.cancel();
      _holdTimer?.cancel();
      _stopAudio();
    });
    return CallState();
  }

  // Gateway events carry the callId they belong to; anything for another call
  // (a second caller, or one that already ended) must not touch this one.
  bool _isForCurrentCall(Map<String, dynamic> msg) {
    final callId = msg['callId'] as String?;
    return callId != null && callId == state.currentCallId && state.status != ActiveCallStatus.idle;
  }

  void _initWebSocket() {
    final storage = ref.read(storageServiceProvider);
    _wsService.configure(url: storage.getGatewayUrl(), secret: storage.getGatewaySecret());
    // The background service keeps its own connection with the same settings
    BackgroundService.configure(
      url: WebSocketService.sanitizeUrl(storage.getGatewayUrl()),
      secret: storage.getGatewaySecret(),
    );
    _wsSub?.cancel();
    _wsSub = _wsService.messageStream.listen((msg) {
      final type = msg['type'] as String?;

      if (type == 'INCOMING_CALL') {
        final callId = msg['callId'] as String?;
        if (callId == null) return;
        // Replayed by the gateway after a reconnect: already on screen
        if (_isForCurrentCall(msg)) return;
        // A second caller must not replace the call on screen (including one that
        // is just wrapping up): they wait, and come up when this call is done
        if (state.status != ActiveCallStatus.idle) {
          final details = msg['details'];
          ref.read(waitingCallersProvider.notifier).add(WaitingCaller(
            callId: callId,
            incoming: msg,
            details: details is Map<String, dynamic> ? details : const {},
          ));
          return;
        }
        _startIncomingCall(msg);
      }
      else if (type == 'CALLER_DETAILS') {
        final callId = msg['callId'] as String?;
        if (_isForCurrentCall(msg)) {
          _applyCallerDetails(msg);
        } else if (callId != null) {
          ref.read(waitingCallersProvider.notifier).updateDetails(callId, msg);
        }
      }
      else if (type == 'TRANSCRIPT_UPDATE') {
        // C7: Structured transcripts as source of truth
        final callId = msg['callId'] as String?;
        if (_isForCurrentCall(msg)) {
          _addTranscriptEntry(msg);
        } else if (callId != null) {
          // Kept for when this caller comes up
          ref.read(waitingCallersProvider.notifier).addTranscript(callId, msg);
        }
      }
      else if (type == 'DIRECTIVE_STATE' || type == 'DIRECTIVE_FAILED') {
        if (!_isForCurrentCall(msg)) return;
        // A late report about an older directive must not overwrite the newest one
        final version = msg['version'] as num?;
        if (version != null && version != 0 && version != state.directiveVersion) return;

        if (type == 'DIRECTIVE_STATE') {
          // B3: 'injected' -> 'spoken'
          state = state.copyWith(directiveStatus: msg['state'] as String? ?? 'spoken');
        } else {
          final reason = msg['reason'] as String? ?? 'unknown';
          state = state.copyWith(
            directiveStatus: 'failed',
            // Keep what Kabeer asked for on screen; the status shows it failed
            directiveError: reason,
          );
        }
      }
      else if (type == 'SESSION_EXPIRED') {
        if (!_isForCurrentCall(msg)) return;
        // B7: Explicit 10-minute session expiry
        state = state.copyWith(
          status: ActiveCallStatus.callEnded,
          activeDirective: 'Session ended — 10 minute limit',
        );
        _finishCall(CallActionStatus.secretaryResolved);
      }
      else if (type == 'CALLER_HUNG_UP') {
        final callId = msg['callId'] as String?;
        if (_isForCurrentCall(msg)) {
          _finishCall(state.status == ActiveCallStatus.masterPatched
              ? CallActionStatus.patchedToMaster
              : CallActionStatus.secretaryResolved);
        } else if (callId != null && ref.read(waitingCallersProvider.notifier).has(callId)) {
          // A waiting caller gave up (or left a message): the gateway has the
          // record, so fetch it into the call list now
          ref.read(waitingCallersProvider.notifier).remove(callId);
          _wsService.send({'type': 'SYNC_MISSED_CALLS'});
        }
      }
      else if (type == 'BRIDGE_CONNECTED') {
        // The secretary has handed over; the caller page is streaming its mic
        if (_isForCurrentCall(msg) && state.status == ActiveCallStatus.masterPatched) {
          _startBridgeAudio();
        }
      }
      else if (type == 'MASTER_SESSION_STATE') {
        if (_isForCurrentCall(msg)) state = state.copyWith(voiceStatus: msg['state'] as String?);
      }
      else if (type == 'MASTER_TRANSCRIPT') {
        if (_isForCurrentCall(msg)) _onVoiceTranscript(msg['speaker'] as String?, msg['text'] as String? ?? '');
      }
      else if (type == 'MASTER_AUDIO_FLUSH') {
        // Kabeer talked over his secretary: drop the rest of what she was saying
        if (_isForCurrentCall(msg)) _audio.flush();
      }
      else if (type == 'MASTER_COMMAND') {
        if (_isForCurrentCall(msg)) _runVoiceCommand(msg);
      }
      else if (type == 'TAKING_MESSAGE') {
        // Nobody acted in time; the gateway had the secretary take a message
        if (_isForCurrentCall(msg)) {
          state = state.copyWith(activeDirective: 'Taking a message for you', directiveStatus: 'injected');
        }
      }
      else if (type == 'MISSED_CALLS') {
        _importMissedCalls(msg['calls'] as List? ?? const []);
      }
    });
  }

  /// "Call back Maria Lopez (0300 1234567): wants to confirm Friday's review".
  static String? followUpFor({String? name, String? reason, String? message, String? callback}) {
    final what = message ?? reason;
    if (what == null && callback == null) return null;
    final who = name ?? 'the caller';
    final how = callback != null ? ' ($callback)' : '';
    return 'Call back $who$how${what != null ? ': $what' : ''}';
  }

  /// Calls that ended while this phone wasn't there to log them (app closed,
  /// offline). Adds them to the call list with a call-back task, then confirms
  /// each to the gateway so they aren't sent again.
  void _importMissedCalls(List calls) {
    final dashboard = ref.read(dashboardProvider.notifier);
    final known = ref.read(dashboardProvider).callLogs.map((c) => c.id).toSet();
    for (final raw in calls) {
      if (raw is! Map) continue;
      final callId = raw['callId'] as String?;
      if (callId == null) continue;
      // The call on screen is logged by _finishCall (with the full summary)
      if (callId == state.currentCallId && state.status != ActiveCallStatus.idle) continue;
      if (!known.contains(callId)) {
        final details = (raw['details'] as Map?)?.cast<String, dynamic>() ?? const {};
        String? field(String key) {
          final value = (details[key] as String?)?.trim();
          return (value == null || value.isEmpty) ? null : value;
        }

        final name = field('name');
        final started = DateTime.tryParse(raw['startedAt'] as String? ?? '');
        final ended = DateTime.tryParse(raw['endedAt'] as String? ?? '') ?? DateTime.now();
        final followUp = followUpFor(
          name: name,
          reason: field('reason'),
          message: field('message'),
          callback: field('callback'),
        );
        final transcript = [
          for (final t in (raw['transcript'] as List? ?? const []))
            if (t is Map && t['text'] is String)
              TranscriptEntry(speaker: t['speaker'] as String? ?? 'Caller', text: t['text'] as String, timeOffset: ''),
        ];

        dashboard.addCallLog(CallRecordModel(
          id: callId,
          callerName: name ?? CallState.unknownCallerName,
          phoneNumber: field('callback') ?? '',
          relationship: name == null
              ? RelationshipCategory.unknown
              : ref.read(contactsProvider.notifier).resolveRelationship(name),
          timestamp: ended.toLocal(),
          durationSeconds: started == null ? 1 : ended.difference(started).inSeconds.clamp(1, 36000),
          sentimentScore: 0,
          lemurSummary: field('message') != null
              ? 'Left a message: ${field('message')}'
              : (field('reason') ?? 'Called while you were away.'),
          transcript: transcript,
          actionStatus: CallActionStatus.secretaryResolved,
          extractedActionItem: followUp,
        ));
        if (followUp != null) {
          dashboard.addTask(SecretaryTaskModel(
            id: const Uuid().v4(),
            callRecordId: callId,
            callerName: name ?? '',
            actionItem: followUp,
            priority: details['urgent'] == true ? TaskPriority.high : TaskPriority.medium,
            createdAt: ended.toLocal(),
          ));
        }
      }
      _wsService.send({'type': 'CALL_LOGGED', 'callId': callId});
    }
  }

  /// Kabeer's voice session: his secretary briefs him through the phone and
  /// his spoken instructions come back as MASTER_COMMANDs (see master-session.js
  /// on the gateway). Starts automatically for every real incoming call.
  Future<void> startVoiceSession() async {
    final callId = state.currentCallId;
    if (!state.isRealCall || callId == null) return;
    if (!await _audio.ensureMicPermission()) {
      state = state.copyWith(voiceStatus: 'noMic');
      return;
    }
    // The call may have ended while the permission dialog was open
    if (state.currentCallId != callId || state.status == ActiveCallStatus.idle) return;
    try {
      await _ensureAudio();
    } catch (e) {
      state = state.copyWith(voiceStatus: 'error');
      return;
    }
    if (state.currentCallId != callId || state.status == ActiveCallStatus.idle) {
      _stopAudio();
      return;
    }
    _voiceCallId = callId;
    _wsService.keepAliveInBackground = true;
    _wsService.send({'type': 'MASTER_SESSION_START', 'callId': callId});
    state = state.copyWith(voiceStatus: 'connecting');
  }

  /// Name, company, reason and urgency confirmed by the screening secretary.
  void _applyCallerDetails(Map<String, dynamic> details) {
    final scenario = state.activeScenario;
    if (scenario == null) return;
    String? field(String key) {
      final value = (details[key] as String?)?.trim();
      return (value == null || value.isEmpty) ? null : value;
    }

    final name = field('name');
    final company = field('company');
    final reason = field('reason');
    final contact = name == null ? null : ref.read(contactsProvider.notifier).findContact(name);
    final relationship = name == null
        ? scenario.relationship
        : (contact?.relationship ?? RelationshipCategory.unknown);

    // Tell Kabeer's secretary session who this is to him, once per name
    if (contact != null && state.isRealCall && state.currentCallId != null && _contextSentFor != name) {
      _contextSentFor = name;
      _wsService.send({
        'type': 'CALLER_CONTEXT',
        'callId': state.currentCallId,
        'relationship': contact.relationship.displayName,
        'company': ?contact.company,
        'note': ?contact.customNotes,
      });
    }

    state = state.copyWith(
      activeScenario: ScenarioProfile(
        title: scenario.title,
        callerName: name ?? scenario.callerName,
        phoneNumber: scenario.phoneNumber,
        relationship: relationship,
        dialogOpening: scenario.dialogOpening,
        dialogueIntent: reason ?? scenario.dialogueIntent,
        sentimentScore: scenario.sentimentScore,
        lemurSummary: reason ?? scenario.lemurSummary,
        extractedActionItem: scenario.extractedActionItem,
        recommendedResponse: scenario.recommendedResponse,
      ),
      callerCompany: company,
      callerReason: reason,
      urgent: details['urgent'] == true ? true : null,
      callerMessage: field('message'),
      callerCallback: field('callback'),
    );
  }

  void _onVoiceTranscript(String? speaker, String text) {
    if (text.isEmpty) return;
    if (speaker == 'Secretary') {
      state = state.copyWith(lastBriefing: text);
      return;
    }
    // Kabeer's own words go into the call record
    final elapsed = DateTime.now().difference(state.startTime ?? DateTime.now()).inSeconds;
    final entry = TranscriptEntry(
      speaker: 'Master',
      text: text,
      timeOffset: '${elapsed ~/ 60}:${(elapsed % 60).toString().padLeft(2, '0')}',
    );
    state = state.copyWith(transcriptEntries: [...state.transcriptEntries, entry]);
  }

  // Voice commands run the same code as the banner buttons
  void _runVoiceCommand(Map<String, dynamic> msg) {
    switch (msg['command']) {
      case 'connect':
        acceptAndPatch();
      case 'hold':
        holdCall(((msg['minutes'] as num?)?.toInt() ?? 2) * 60);
      case 'relay':
        final message = msg['message'] as String? ?? '';
        if (message.isNotEmpty) sendCustomDirective(message);
      case 'task':
        final text = msg['task'] as String? ?? '';
        if (text.isEmpty) return;
        final task = (text: text, due: DateTime.tryParse(msg['due'] as String? ?? ''));
        if (msg['replacesPrevious'] == true && _voiceTasks.isNotEmpty) {
          _voiceTasks[_voiceTasks.length - 1] = task;
        } else {
          _voiceTasks.add(task);
        }
      case 'end':
        endCall();
    }
  }

  void toggleMute() {
    state = state.copyWith(micMuted: !state.micMuted);
  }

  /// Puts an INCOMING_CALL on screen.
  void _startIncomingCall(Map<String, dynamic> msg) {
    final callId = msg['callId'] as String;
    final callerName = msg['callerName'] as String? ?? CallState.unknownCallerName;
    final phoneNumber = msg['phoneNumber'] as String? ?? '';
    final topic = msg['topic'] as String? ?? 'Inbound Voice Call';

    // C7: Caller identity resolved from envelope and contacts, never from regex
    final relationship = ref.read(contactsProvider.notifier).resolveRelationship(phoneNumber);

    final incomingScenario = ScenarioProfile(
      title: 'Inbound call',
      callerName: callerName,
      phoneNumber: phoneNumber,
      relationship: relationship,
      dialogOpening: 'Connecting to AI secretary...',
      dialogueIntent: topic,
      sentimentScore: 0.0,
      lemurSummary: 'Inbound call: $topic',
      extractedActionItem: '',
      recommendedResponse: 'Screening incoming voice call.',
    );

    _handleIncomingRealCall(incomingScenario, callId);
    // A replayed call may already carry what the secretary learned
    final details = msg['details'];
    if (details is Map<String, dynamic> && details.isNotEmpty) _applyCallerDetails(details);
  }

  /// A caller who rang during the last call comes up once it's done.
  void _takeNextWaitingCaller() {
    final next = ref.read(waitingCallersProvider.notifier).takeNext();
    if (next == null) return;
    _startIncomingCall(next.incoming);
    if (next.details.isNotEmpty) _applyCallerDetails(next.details);
    for (final line in next.transcript) {
      _addTranscriptEntry(line);
    }
  }

  void _addTranscriptEntry(Map<String, dynamic> msg) {
    final speakerRaw = (msg['speaker'] as String? ?? 'Caller').toLowerCase();
    final text = msg['text'] as String? ?? '';
    if (text.isEmpty) return;

    final speaker = (speakerRaw == 'secretary' || speakerRaw == 'agent')
        ? 'Secretary'
        : (speakerRaw == 'master' ? 'Master' : 'Caller');

    final elapsed = DateTime.now().difference(state.startTime ?? DateTime.now()).inSeconds;
    final timeOffset = '${elapsed ~/ 60}:${(elapsed % 60).toString().padLeft(2, '0')}';

    // The call's summary comes from confirmed caller details, not from
    // whatever the caller said last
    state = state.copyWith(transcriptEntries: [
      ...state.transcriptEntries,
      TranscriptEntry(speaker: speaker, text: text, timeOffset: timeOffset),
    ]);
  }

  void _handleIncomingRealCall(ScenarioProfile scenario, String callId) {
    _cleanup();
    _isCallTerminated = false;
    _contextSentFor = null;
    _voiceTasks.clear();
    // The call is on screen now; stop the background ring if there was one
    BackgroundService.cancelIncomingAlert();
    state = CallState(
      status: ActiveCallStatus.secretaryScreening,
      activeScenario: scenario,
      startTime: DateTime.now(),
      currentCallId: callId,
      isRealCall: true,
    );
    // Off in settings: Kabeer starts it from the call screen instead
    if (ref.read(storageServiceProvider).getAutoVoice()) startVoiceSession();
  }

  /// Trigger an incoming call simulation manually
  void simulateCall(ScenarioProfile scenario) {
    _cleanup();
    _isCallTerminated = false;
    final callId = 'sim_${const Uuid().v4()}';
    state = CallState(
      status: ActiveCallStatus.secretaryScreening,
      activeScenario: scenario,
      startTime: DateTime.now(),
      transcriptEntries: [
        TranscriptEntry(speaker: 'Caller', text: scenario.dialogOpening, timeOffset: '0:00'),
      ],
      currentCallId: callId,
      isRealCall: false,
      callerReason: scenario.dialogueIntent,
    );
  }

  /// Master Directive 1: Patch In. The secretary tells the caller she is
  /// connecting them; when she's done, the caller page opens the audio bridge
  /// and the gateway sends BRIDGE_CONNECTED, which starts mic and speaker here.
  /// The call stays open until Kabeer hangs up or the caller does.
  Future<void> acceptAndPatch() async {
    if (!state.isRealCall || state.currentCallId == null) {
      // Simulated calls have nobody on the other end: log them as patched
      _directiveVersion++;
      state = state.copyWith(
        status: ActiveCallStatus.masterPatched,
        activeDirective: 'Connected to you',
        directiveStatus: 'sending',
        directiveVersion: _directiveVersion,
      );
      _finishCall(CallActionStatus.patchedToMaster);
      return;
    }
    if (state.status == ActiveCallStatus.masterPatched) return;
    _holdTimer?.cancel();

    if (!await _audio.ensureMicPermission()) {
      state = state.copyWith(
        directiveStatus: 'failed',
        activeDirective: 'Microphone permission is needed to talk to the caller',
      );
      return;
    }

    _directiveVersion++;
    _wsService.sendMasterDirective(
      callId: state.currentCallId!,
      action: 'patchedToMaster',
      directiveVersion: _directiveVersion,
    );
    // A screen-off during the call must not cut the caller off
    _wsService.keepAliveInBackground = true;
    state = state.copyWith(
      status: ActiveCallStatus.masterPatched,
      activeDirective: 'Connecting you',
      directiveStatus: 'sending',
      directiveVersion: _directiveVersion,
    );
  }

  /// Ends a patched call from the phone: the caller page hangs up too.
  void hangUp() {
    if (state.isRealCall && state.currentCallId != null) {
      _directiveVersion++;
      _wsService.sendMasterDirective(
        callId: state.currentCallId!,
        action: 'hangup',
        directiveVersion: _directiveVersion,
      );
    }
    _finishCall(CallActionStatus.patchedToMaster);
  }

  // Starts the phone's mic and speaker once per call. Where the mic goes is the
  // gateway's decision: Kabeer's secretary, or the caller after Patch In.
  Future<void> _ensureAudio() async {
    if (_audio.isActive) return;
    // Foreground service with the microphone type first, so the call keeps
    // working if the screen turns off
    await BackgroundService.startCall(state.activeScenario?.callerName ?? '');
    await _audio.start(onMicChunk: (chunk) {
      if (!state.micMuted) _wsService.sendBinary(chunk);
    });
    _audioSub?.cancel();
    _audioSub = _wsService.audioStream.listen(_audio.play);
  }

  Future<void> _startBridgeAudio() async {
    final callId = state.currentCallId;
    try {
      await _ensureAudio();
    } catch (e) {
      state = state.copyWith(directiveStatus: 'failed', activeDirective: 'Could not start call audio: $e');
      return;
    }
    // The call may have ended while the audio hardware was starting
    if (state.status != ActiveCallStatus.masterPatched || state.currentCallId != callId) {
      _stopAudio();
      return;
    }
    // The secretary has stepped out; Kabeer must be audible to the caller
    _voiceCallId = null;
    state = state.copyWith(
      bridgeLive: true,
      micMuted: false,
      voiceStatus: 'ended',
      activeDirective: 'On the call',
      directiveStatus: 'spoken',
    );
  }

  void _stopAudio() {
    if (_voiceCallId != null) {
      _wsService.send({'type': 'MASTER_SESSION_STOP', 'callId': _voiceCallId});
      _voiceCallId = null;
    }
    _audioSub?.cancel();
    _audioSub = null;
    _wsService.keepAliveInBackground = false;
    if (_audio.isActive) {
      unawaited(_audio.stop());
      BackgroundService.stopCall();
    }
  }

  /// Master Directive 2: Keep caller on polite hold for N seconds (C6 wall-clock timer)
  void holdCall(int seconds) {
    _holdTimer?.cancel();
    _directiveVersion++;
    // Simulated calls exist only on the phone; the gateway doesn't know them
    final minutes = (seconds / 60).ceil().clamp(1, 30);
    if (state.isRealCall && state.currentCallId != null) {
      _wsService.sendMasterDirective(
        callId: state.currentCallId!,
        action: 'holding',
        holdMinutes: minutes,
        directiveVersion: _directiveVersion,
      );
    }
    _holdStartTime = DateTime.now();
    _holdTotalSeconds = seconds;

    state = state.copyWith(
      status: ActiveCallStatus.holding,
      holdTimerSeconds: seconds,
      activeDirective: 'Asked to hold for $minutes min',
      directiveStatus: 'sending',
      directiveVersion: _directiveVersion,
    );

    _holdTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (state.status != ActiveCallStatus.holding) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(_holdStartTime ?? DateTime.now()).inSeconds;
      final remaining = _holdTotalSeconds - elapsed;

      if (remaining <= 0) {
        timer.cancel();
        if (state.status == ActiveCallStatus.holding) {
          acceptAndPatch();
        }
      } else if (remaining != state.holdTimerSeconds) {
        state = state.copyWith(holdTimerSeconds: remaining);
      }
    });
  }

  /// Master Directive 3: Custom voice/text instruction to Secretary (B3 versioned)
  void sendCustomDirective(String directiveText) {
    _directiveVersion++;
    // Simulated calls exist only on the phone; the gateway doesn't know them
    if (state.isRealCall && state.currentCallId != null) {
      _wsService.sendMasterDirective(
        callId: state.currentCallId!,
        action: 'custom',
        spokenDirective: directiveText,
        directiveVersion: _directiveVersion,
      );
    }

    final elapsed = DateTime.now().difference(state.startTime ?? DateTime.now()).inSeconds;
    final timeOffset = '${elapsed ~/ 60}:${(elapsed % 60).toString().padLeft(2, '0')}';
    final masterEntry = TranscriptEntry(
      speaker: 'Master',
      text: directiveText,
      timeOffset: timeOffset,
    );

    state = state.copyWith(
      activeDirective: directiveText,
      directiveStatus: 'sending',
      directiveVersion: _directiveVersion,
      transcriptEntries: [...state.transcriptEntries, masterEntry],
    );
  }

  /// Ends the call and files it as spam: the secretary still says a polite
  /// goodbye, and no follow-up task is created.
  void markSpamAndEnd() {
    _directiveVersion++;
    // Simulated calls exist only on the phone; the gateway doesn't know them
    if (state.isRealCall && state.currentCallId != null) {
      _wsService.sendMasterDirective(
        callId: state.currentCallId!,
        action: 'declined',
        directiveVersion: _directiveVersion,
      );
    }
    _voiceTasks.clear();
    state = state.copyWith(
      status: ActiveCallStatus.callEnded,
      activeDirective: 'Marked as spam',
      directiveStatus: 'sending',
      directiveVersion: _directiveVersion,
    );
    _finishCall(CallActionStatus.declinedSpam);
  }

  /// Ends the call by voice ("end the call"): the secretary says goodbye and the
  /// caller page hangs up. Tasks Kabeer dictated are saved with the call record.
  void endCall() {
    if (state.status == ActiveCallStatus.masterPatched) {
      hangUp();
      return;
    }
    _directiveVersion++;
    if (state.isRealCall && state.currentCallId != null) {
      _wsService.sendMasterDirective(
        callId: state.currentCallId!,
        action: 'declined',
        directiveVersion: _directiveVersion,
      );
    }
    state = state.copyWith(
      status: ActiveCallStatus.callEnded,
      activeDirective: 'Call ended by Kabeer',
      directiveStatus: 'sending',
      directiveVersion: _directiveVersion,
    );
    _finishCall(CallActionStatus.heldAndDeferred);
  }

  /// C5: Terminal-State Idempotency & C8 Real-call intelligence
  Future<void> _finishCall(CallActionStatus actionStatus) async {
    if (_isCallTerminated) return;
    _isCallTerminated = true;

    // Tasks Kabeer dictated beat anything guessed from the transcript
    final dictatedTasks = List.of(_voiceTasks);
    _voiceTasks.clear();

    _cleanup();

    final scenario = state.activeScenario;
    if (scenario != null) {
      final callId = state.currentCallId ?? const Uuid().v4();
      final duration = DateTime.now().difference(state.startTime ?? DateTime.now()).inSeconds;

      List<TranscriptEntry> callTranscripts = List.from(state.transcriptEntries);
      if (callTranscripts.isEmpty) {
        callTranscripts = [
          TranscriptEntry(speaker: 'Secretary', text: 'Call screened with AI Secretary', timeOffset: '0:02'),
          if (state.activeDirective != null)
            TranscriptEntry(speaker: 'Master', text: state.activeDirective!, timeOffset: '0:05'),
        ];
      }

      String summary = scenario.lemurSummary;
      String? actionItem = scenario.extractedActionItem;
      double sentiment = scenario.sentimentScore;

      // C8: Real-call intelligence path via Gateway
      if (state.isRealCall) {
        final analysis = await _assemblyAIService.analyzeRealCallTranscript(
          gatewayUrl: _wsService.wsUrl,
          transcript: callTranscripts,
          authSecret: ref.read(storageServiceProvider).getGatewaySecret(),
          callerDetails: {
            if (!state.callerUnknown) 'name': scenario.callerName,
            'company': ?state.callerCompany,
            'reason': ?state.callerReason,
          },
        );
        summary = analysis['summary'] as String? ?? summary;
        actionItem = analysis['actionItem'] as String? ?? actionItem;
        sentiment = (analysis['sentimentScore'] as num?)?.toDouble() ?? sentiment;
      }
      if (dictatedTasks.isNotEmpty) {
        actionItem = dictatedTasks.map((t) => t.text).join('; ');
      } else if (state.callerMessage != null || state.callerCallback != null) {
        // The caller left a message: calling them back is the follow-up
        actionItem = followUpFor(
              name: state.callerUnknown ? null : scenario.callerName,
              reason: state.callerReason,
              message: state.callerMessage,
              callback: state.callerCallback,
            ) ??
            actionItem;
      }

      // 1. Create Call Record with structured transcript
      final record = CallRecordModel(
        id: callId,
        callerName: scenario.callerName,
        phoneNumber: scenario.phoneNumber,
        relationship: scenario.relationship,
        timestamp: DateTime.now(),
        durationSeconds: duration > 0 ? duration : 1,
        sentimentScore: sentiment,
        lemurSummary: summary,
        transcript: callTranscripts,
        actionStatus: actionStatus,
        extractedActionItem: actionItem,
      );

      // Replaces a copy imported as a missed call while this one was wrapping up
      ref.read(dashboardProvider.notifier).deleteCallLog(callId);
      ref.read(dashboardProvider.notifier).addCallLog(record);

      // 2. Add Secretary Tasks: one per task Kabeer dictated, otherwise the
      // commitment detected in the transcript
      if (dictatedTasks.isNotEmpty) {
        for (final task in dictatedTasks) {
          ref.read(dashboardProvider.notifier).addTask(SecretaryTaskModel(
            id: const Uuid().v4(),
            callRecordId: callId,
            callerName: scenario.callerName,
            actionItem: task.text,
            priority: TaskPriority.high,
            createdAt: DateTime.now(),
            dueDate: task.due,
          ));
        }
      } else if (actionItem.isNotEmpty && actionStatus != CallActionStatus.declinedSpam) {
        final task = SecretaryTaskModel(
          id: const Uuid().v4(),
          callRecordId: callId,
          callerName: scenario.callerName,
          actionItem: actionItem,
          priority: sentiment < -0.3 ? TaskPriority.high : TaskPriority.medium,
          createdAt: DateTime.now(),
        );
        ref.read(dashboardProvider.notifier).addTask(task);
      }

      // Logged here, so the gateway won't offer it later as a missed call
      if (state.isRealCall) _wsService.send({'type': 'CALL_LOGGED', 'callId': callId});
    }

    // Delay reset slightly to let animations complete
    final endedCallId = state.currentCallId;
    Future.delayed(const Duration(seconds: 2), () {
      // Another call may already be on screen
      if (state.currentCallId != endedCallId) return;
      _cleanup();
      state = CallState(status: ActiveCallStatus.idle);
      _takeNextWaitingCaller();
    });
  }

  void _cleanup() {
    _transcriptSub?.cancel();
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdStartTime = null;
    _stopAudio();
  }
}

final callProvider = NotifierProvider<CallNotifier, CallState>(CallNotifier.new);

/// A caller who rang while Kabeer was busy with another call. The screening
/// secretary is already talking to them; they come up when the current call ends.
class WaitingCaller {
  final String callId;
  final Map<String, dynamic> incoming; // the INCOMING_CALL message
  final Map<String, dynamic> details;  // what the secretary has learned so far
  final List<Map<String, dynamic>> transcript; // TRANSCRIPT_UPDATEs so far
  final DateTime since;

  WaitingCaller({
    required this.callId,
    required this.incoming,
    this.details = const {},
    this.transcript = const [],
    DateTime? since,
  }) : since = since ?? DateTime.now();

  String get name {
    final name = (details['name'] as String?)?.trim() ?? '';
    return name.isEmpty ? 'Unknown caller' : name;
  }

  String? get reason {
    final reason = (details['reason'] as String?)?.trim() ?? '';
    return reason.isEmpty ? null : reason;
  }

  WaitingCaller withDetails(Map<String, dynamic> update) {
    final merged = {...details};
    update.forEach((key, value) {
      if (value is String && value.trim().isEmpty) return;
      if (value == null || key == 'type' || key == 'callId') return;
      merged[key] = value;
    });
    return WaitingCaller(callId: callId, incoming: incoming, details: merged, transcript: transcript, since: since);
  }

  WaitingCaller withLine(Map<String, dynamic> line) => WaitingCaller(
        callId: callId,
        incoming: incoming,
        details: details,
        transcript: [...transcript, line].take(200).toList(),
        since: since,
      );
}

class WaitingCallersNotifier extends Notifier<List<WaitingCaller>> {
  @override
  List<WaitingCaller> build() => const [];

  bool has(String callId) => state.any((c) => c.callId == callId);

  void add(WaitingCaller caller) {
    if (has(caller.callId)) return;
    state = [...state, caller];
  }

  void updateDetails(String callId, Map<String, dynamic> details) {
    state = [for (final c in state) c.callId == callId ? c.withDetails(details) : c];
  }

  void addTranscript(String callId, Map<String, dynamic> line) {
    if (!has(callId)) return;
    state = [for (final c in state) c.callId == callId ? c.withLine(line) : c];
  }

  void remove(String callId) {
    state = state.where((c) => c.callId != callId).toList();
  }

  WaitingCaller? takeNext() {
    if (state.isEmpty) return null;
    final next = state.first;
    state = state.sublist(1);
    return next;
  }
}

final waitingCallersProvider =
    NotifierProvider<WaitingCallersNotifier, List<WaitingCaller>>(WaitingCallersNotifier.new);
