import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/caller_trust.dart';
import '../core/constants/relationship_constants.dart';
import '../models/scenario_profile.dart';
import '../models/call_record_model.dart';
import '../models/secretary_task_model.dart';
import '../services/assemblyai_service.dart';
import '../services/background_service.dart';
import '../services/call_audio_service.dart';
import '../services/websocket_service.dart';
import 'contacts_provider.dart';
import 'owner_provider.dart';
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
  // How to reach the caller, as they confirmed it to the secretary
  final String? callbackNumber;
  final String? callbackEmail;
  final String? bestTime;
  // Who the caller really is, as far as the phone can tell (see caller_trust.dart)
  final CallerTrust trust;
  final String? deviceId;     // the caller page's anonymous browser id
  final String? linkToken;    // the personal link it came through, if any
  final bool staleLink;       // a link that matches no current contact
  // Set when the gateway didn't ring (Kabeer away, or a "never ring" contact):
  // 'away' | 'unavailable'
  final String? quiet;

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
    this.callbackNumber,
    this.callbackEmail,
    this.bestTime,
    this.trust = const CallerTrust(),
    this.deviceId,
    this.linkToken,
    this.staleLink = false,
    this.quiet,
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
    String? callbackNumber,
    String? callbackEmail,
    String? bestTime,
    CallerTrust? trust,
    String? deviceId,
    String? linkToken,
    bool? staleLink,
    String? quiet,
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
      callbackNumber: callbackNumber ?? this.callbackNumber,
      callbackEmail: callbackEmail ?? this.callbackEmail,
      bestTime: bestTime ?? this.bestTime,
      trust: trust ?? this.trust,
      deviceId: deviceId ?? this.deviceId,
      linkToken: linkToken ?? this.linkToken,
      staleLink: staleLink ?? this.staleLink,
      quiet: quiet ?? this.quiet,
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
  // The name the caller gave (a claim), and the last CALLER_CONTEXT sent
  String? _claimedName;
  String? _contextSignature;

  @override
  CallState build() {
    _initWebSocket();
    // Keep the gateway's view of Kabeer current: availability, personal links
    // and blocked browsers decide, per call, who is verified and whether to ring
    ref.listen(contactsProvider, (_, _) => syncOwnerSettings());
    ref.listen(ownerProvider, (_, _) => syncOwnerSettings());
    ref.onDispose(() {
      _wsService.disconnect();
      _wsSub?.cancel();
      _transcriptSub?.cancel();
      _holdTimer?.cancel();
      _stopAudio();
    });
    return CallState();
  }

  /// Sends availability, personal links and blocked browsers to the gateway, and
  /// hands the same to the background service so it can re-send them itself
  /// if the gateway restarts while the app is closed.
  void syncOwnerSettings() {
    final message = ownerSettingsMessage(ref.read(ownerProvider), ref.read(contactsProvider), DateTime.now());
    _wsService.send(message);
    BackgroundService.setOwnerSettings(jsonEncode(message));
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

      if (type == 'REGISTERED_SUCCESS') {
        syncOwnerSettings();
        return;
      }
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
  static String? followUpFor({
    String? name,
    String? reason,
    String? message,
    String? callback,
    String? number,
    String? email,
  }) {
    final what = message ?? reason;
    if (what == null && callback == null && number == null && email == null) return null;
    final who = name ?? 'the caller';
    final gist = what != null ? ': $what' : '';
    // A confirmed number or email makes the task something you can act on
    if (number != null) return 'Call back $who ($number)$gist';
    if (email != null) return 'Email $who ($email)$gist';
    final how = callback != null ? ' ($callback)' : '';
    return 'Call back $who$how$gist';
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

        final started = DateTime.tryParse(raw['startedAt'] as String? ?? '');
        final ended = DateTime.tryParse(raw['endedAt'] as String? ?? '') ?? DateTime.now();
        final verified = raw['verified'];
        final device = raw['device'] as String?;
        // Same rules as a live call: only a personal link verifies the name
        final trust = assessCaller(
          claimedName: field('name'),
          linkToken: verified is Map ? verified['token'] as String? : null,
          deviceId: device,
          contacts: ref.read(contactsProvider),
          history: ref.read(dashboardProvider).callLogs,
        );
        final name = trust.contact?.name ?? field('name');
        final number = field('callbackNumber');
        final email = field('callbackEmail');
        final followUp = followUpFor(
          name: name,
          reason: field('reason'),
          message: field('message'),
          callback: field('callback'),
          number: number,
          email: email,
        );
        final transcript = [
          for (final t in (raw['transcript'] as List? ?? const []))
            if (t is Map && t['text'] is String)
              TranscriptEntry(speaker: t['speaker'] as String? ?? 'Caller', text: t['text'] as String, timeOffset: ''),
        ];

        dashboard.addCallLog(CallRecordModel(
          id: callId,
          callerName: name ?? CallState.unknownCallerName,
          phoneNumber: number ?? '',
          relationship: trust.contact?.relationship ?? RelationshipCategory.unknown,
          timestamp: ended.toLocal(),
          durationSeconds: started == null ? 1 : ended.difference(started).inSeconds.clamp(1, 36000),
          sentimentScore: 0,
          lemurSummary: field('message') != null
              ? 'Left a message: ${field('message')}'
              : (field('reason') ?? 'Called while you were away.'),
          transcript: transcript,
          actionStatus: CallActionStatus.secretaryResolved,
          extractedActionItem: followUp,
          callbackNumber: number,
          callbackEmail: email,
          bestTime: field('bestTime'),
          callerMessage: field('message'),
          deviceId: (device ?? '').isEmpty ? null : device,
          trust: trust.level.name,
          trustNote: trust.note,
        ));
        if (followUp != null) {
          dashboard.addTask(SecretaryTaskModel(
            id: const Uuid().v4(),
            callRecordId: callId,
            callerName: name ?? '',
            actionItem: followUp,
            priority: details['urgent'] == true ? TaskPriority.high : TaskPriority.medium,
            createdAt: ended.toLocal(),
            phoneNumber: number,
            email: email,
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

    // What the caller says their name is: a claim, checked in _refreshTrust
    final name = field('name');
    if (name != null) _claimedName = name;
    final reason = field('reason');

    state = state.copyWith(
      activeScenario: ScenarioProfile(
        title: scenario.title,
        callerName: scenario.callerName,
        phoneNumber: scenario.phoneNumber,
        relationship: scenario.relationship,
        dialogOpening: scenario.dialogOpening,
        dialogueIntent: reason ?? scenario.dialogueIntent,
        sentimentScore: scenario.sentimentScore,
        lemurSummary: reason ?? scenario.lemurSummary,
        extractedActionItem: scenario.extractedActionItem,
        recommendedResponse: scenario.recommendedResponse,
      ),
      callerCompany: field('company'),
      callerReason: reason,
      urgent: details['urgent'] == true ? true : null,
      callerMessage: field('message'),
      callerCallback: field('callback'),
      callbackNumber: field('callbackNumber'),
      callbackEmail: field('callbackEmail'),
      bestTime: field('bestTime'),
    );
    _refreshTrust();
  }

  /// Works out who this caller really is (see caller_trust.dart), shows it, and
  /// tells Kabeer's secretary so she briefs him the same way. Only a personal
  /// link verifies anyone; a claimed name never borrows a contact's relationship.
  void _refreshTrust() {
    final scenario = state.activeScenario;
    if (!state.isRealCall || scenario == null) return;
    final trust = assessCaller(
      claimedName: _claimedName,
      linkToken: state.linkToken,
      staleLink: state.staleLink,
      deviceId: state.deviceId,
      contacts: ref.read(contactsProvider),
      history: ref.read(dashboardProvider).callLogs,
    );
    final contact = trust.contact;
    state = state.copyWith(
      trust: trust,
      activeScenario: ScenarioProfile(
        title: scenario.title,
        // A verified caller is shown by the name Kabeer saved; anyone else by
        // the name they gave
        callerName: contact?.name ?? _claimedName ?? scenario.callerName,
        phoneNumber: scenario.phoneNumber,
        relationship: contact?.relationship ?? RelationshipCategory.unknown,
        dialogOpening: scenario.dialogOpening,
        dialogueIntent: scenario.dialogueIntent,
        sentimentScore: scenario.sentimentScore,
        lemurSummary: scenario.lemurSummary,
        extractedActionItem: scenario.extractedActionItem,
        recommendedResponse: scenario.recommendedResponse,
      ),
    );
    final callId = state.currentCallId;
    if (callId == null) return;
    final message = trust.contextMessage(callId);
    final signature = jsonEncode(message);
    if (signature != _contextSignature) {
      _contextSignature = signature;
      _wsService.send(message);
    }
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
    final verified = msg['verified'];

    final incomingScenario = ScenarioProfile(
      title: 'Inbound call',
      callerName: callerName,
      phoneNumber: phoneNumber,
      // Worked out in _refreshTrust, from a personal link and nothing else
      relationship: RelationshipCategory.unknown,
      dialogOpening: 'Connecting to AI secretary...',
      dialogueIntent: topic,
      sentimentScore: 0.0,
      lemurSummary: 'Inbound call: $topic',
      extractedActionItem: '',
      recommendedResponse: 'Screening incoming voice call.',
    );

    _handleIncomingRealCall(
      incomingScenario,
      callId,
      deviceId: msg['device'] as String?,
      linkToken: verified is Map ? verified['token'] as String? : null,
      staleLink: msg['staleLink'] == true,
      quiet: msg['quiet'] as String?,
    );
    _refreshTrust();
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

  void _handleIncomingRealCall(
    ScenarioProfile scenario,
    String callId, {
    String? deviceId,
    String? linkToken,
    bool staleLink = false,
    String? quiet,
  }) {
    _cleanup();
    _isCallTerminated = false;
    _claimedName = null;
    _contextSignature = null;
    _voiceTasks.clear();
    // The call is on screen now; stop the background ring if there was one
    BackgroundService.cancelIncomingAlert();
    state = CallState(
      status: ActiveCallStatus.secretaryScreening,
      activeScenario: scenario,
      startTime: DateTime.now(),
      currentCallId: callId,
      isRealCall: true,
      deviceId: (deviceId ?? '').isEmpty ? null : deviceId,
      linkToken: linkToken,
      staleLink: staleLink,
      quiet: quiet,
    );
    // Quiet calls (Kabeer away, or a "never ring" contact) are the secretary's:
    // no voice session unless he opens one himself. Off in settings: he always
    // starts it from the call screen.
    if (quiet == null && ref.read(storageServiceProvider).getAutoVoice()) startVoiceSession();
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
        if (state.status == ActiveCallStatus.holding) _holdTimeUp();
      } else if (remaining != state.holdTimerSeconds) {
        state = state.copyWith(holdTimerSeconds: remaining);
      }
    });
  }

  /// The hold ran out. Connecting now could put the caller through to a phone
  /// nobody is holding, so the secretary checks in with the caller instead
  /// (keep waiting, or leave a message) and the phone asks for Kabeer's attention.
  void _holdTimeUp() {
    _directiveVersion++;
    if (state.isRealCall && state.currentCallId != null) {
      _wsService.sendMasterDirective(
        callId: state.currentCallId!,
        action: 'checkIn',
        directiveVersion: _directiveVersion,
      );
    }
    state = state.copyWith(
      status: ActiveCallStatus.secretaryScreening,
      holdTimerSeconds: 0,
      activeDirective: 'Hold time is up: your secretary is checking in with the caller',
      directiveStatus: 'sending',
      directiveVersion: _directiveVersion,
    );
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
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
  void markSpamAndEnd() => _blockAndEnd('spam', 'Marked as spam');

  /// Someone pretending to be someone else: end politely, block the browser,
  /// and keep the false claim on record.
  void markImpostorAndEnd() => _blockAndEnd('impostor', 'Marked as impostor');

  void _blockAndEnd(String reason, String label) {
    final device = state.deviceId;
    if (state.isRealCall && device != null) {
      ref.read(ownerProvider.notifier).block(device, reason: reason, name: _claimedName);
    }
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
      activeDirective: label,
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
      } else if (state.callerMessage != null || state.callerCallback != null ||
          state.callbackNumber != null || state.callbackEmail != null) {
        // The caller left a message or a way to reach them: that's the follow-up
        actionItem = followUpFor(
              name: state.callerUnknown ? null : scenario.callerName,
              reason: state.callerReason,
              message: state.callerMessage,
              callback: state.callerCallback,
              number: state.callbackNumber,
              email: state.callbackEmail,
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
        callbackNumber: state.callbackNumber,
        callbackEmail: state.callbackEmail,
        bestTime: state.bestTime,
        callerMessage: state.callerMessage,
        deviceId: state.deviceId,
        trust: state.isRealCall ? state.trust.level.name : null,
        trustNote: state.isRealCall ? state.trust.note : null,
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
            phoneNumber: state.callbackNumber,
            email: state.callbackEmail,
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
          phoneNumber: state.callbackNumber,
          email: state.callbackEmail,
        );
        ref.read(dashboardProvider.notifier).addTask(task);
      }

      // A verified caller's browser, remembered to notice a new one next time
      final linked = state.trust.contact;
      if (linked != null && state.deviceId != null) {
        ref.read(contactsProvider.notifier).recordLinkDevice(linked.id, state.deviceId!);
      }

      // Logged here, so the gateway won't offer it later as a missed call
      if (state.isRealCall) _wsService.send({'type': 'CALL_LOGGED', 'callId': callId});
    }

    // Delay reset slightly to let animations complete
    final endedCallId = state.currentCallId;
    Future.delayed(const Duration(seconds: 2), () {
      if (!ref.mounted) return;
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
