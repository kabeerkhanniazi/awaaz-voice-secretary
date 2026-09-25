import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:awaaz_app/core/caller_trust.dart';
import 'package:awaaz_app/core/constants/relationship_constants.dart';
import 'package:awaaz_app/models/call_record_model.dart';
import 'package:awaaz_app/providers/owner_provider.dart';
import 'package:awaaz_app/providers/call_provider.dart';
import 'package:awaaz_app/providers/dashboard_provider.dart';
import 'package:awaaz_app/providers/storage_provider.dart';
import 'package:awaaz_app/services/websocket_service.dart';

// Voice commands arrive from the gateway as MASTER_COMMAND and must drive the
// same call actions as the banner buttons.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  final ws = WebSocketService();
  const callId = 'call_test_1';

  Future<void> deliver(Map<String, dynamic> msg) async {
    ws.debugReceive(msg);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'awaaz_call_logs': '[]',
      'awaaz_tasks': '[]',
      'awaaz_contacts': '[{"id":"c9","name":"Maria Lopez","phoneNumber":"","relationship":"vipClient","company":"Brightline Studios","customNotes":null,"linkToken":"MARIALINK01"}]',
    });
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    ws.debugSent = [];
    container.read(callProvider);
    await deliver({'type': 'INCOMING_CALL', 'callId': callId, 'callerName': 'Web Caller'});
  });

  tearDown(() {
    container.dispose();
    ws.disconnect();
  });

  test('a real incoming call starts screening; without a mic the voice panel says so', () async {
    final state = container.read(callProvider);
    expect(state.status, ActiveCallStatus.secretaryScreening);
    expect(state.currentCallId, callId);
    // The permission check goes through the (absent) recorder plugin asynchronously
    for (var i = 0; i < 50 && container.read(callProvider).voiceStatus == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(container.read(callProvider).voiceStatus, 'noMic');
  });

  test('"hold for five minutes" puts the caller on a five-minute hold', () async {
    await deliver({'type': 'MASTER_COMMAND', 'callId': callId, 'command': 'hold', 'minutes': 5});
    final state = container.read(callProvider);
    expect(state.status, ActiveCallStatus.holding);
    expect(state.holdTimerSeconds, 300);
  });

  test('a relayed message is logged as Kabeer\'s words', () async {
    await deliver({'type': 'MASTER_COMMAND', 'callId': callId, 'command': 'relay', 'message': 'I will call back tomorrow'});
    final state = container.read(callProvider);
    expect(state.activeDirective, 'I will call back tomorrow');
    expect(state.transcriptEntries.last.speaker, 'Master');
  });

  // A new call with the given gateway fields, after the one from setUp has cleared
  Future<void> freshCall(String id, Map<String, dynamic> extra) async {
    await deliver({'type': 'CALLER_HUNG_UP', 'callId': callId});
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    await deliver({'type': 'INCOMING_CALL', 'callId': id, 'callerName': 'Web Caller', ...extra});
  }

  Map<String, dynamic>? lastSent(String type) {
    final matches = ws.debugSent!.where((m) => m['type'] == type).toList();
    return matches.isEmpty ? null : matches.last;
  }

  test("a caller who only says a contact's name is a claim, not that contact", () async {
    expect(container.read(callProvider).callerUnknown, isTrue);
    await deliver({
      'type': 'CALLER_DETAILS', 'callId': callId,
      'name': 'Maria Lopez', 'company': 'Brightline', 'reason': 'Design review on Friday', 'urgent': true,
    });
    final state = container.read(callProvider);
    expect(state.callerUnknown, isFalse);
    expect(state.activeScenario!.callerName, 'Maria Lopez');
    // Never "your VIP client" on a name alone
    expect(state.activeScenario!.relationship, RelationshipCategory.unknown);
    expect(state.trust.level, TrustLevel.unverified);
    expect(state.trust.nameMatch, 'Maria Lopez');
    expect(state.callerCompany, 'Brightline');
    expect(state.callerReason, 'Design review on Friday');
    expect(state.urgent, isTrue);
    // Kabeer's secretary is told the same: a match, not a relationship
    final context = lastSent('CALLER_CONTEXT')!;
    expect(context['trust'], 'unverified');
    expect(context['nameMatch'], 'Maria Lopez');
    expect(context.containsKey('relationship'), isFalse);
  });

  test('a caller through a personal link is verified, under the name Kabeer saved', () async {
    await freshCall('call_link', {
      'device': 'dev-maria',
      'verified': {'name': 'Maria Lopez', 'via': 'link', 'token': 'MARIALINK01'},
    });
    var state = container.read(callProvider);
    expect(state.trust.level, TrustLevel.verified);
    expect(state.activeScenario!.callerName, 'Maria Lopez');
    expect(state.activeScenario!.relationship, RelationshipCategory.vipClient);
    expect(lastSent('CALLER_CONTEXT')!['relationship'], RelationshipCategory.vipClient.displayName);

    // Using Maria's link but giving another name is a warning
    await deliver({'type': 'CALLER_DETAILS', 'callId': 'call_link', 'name': 'Professor Hamid'});
    state = container.read(callProvider);
    expect(state.trust.level, TrustLevel.warning);
    expect(state.trust.note, contains('Maria Lopez'));
  });

  test('a browser that called as Ali and now claims to be a professor is flagged', () async {
    container.read(dashboardProvider.notifier).addCallLog(CallRecordModel(
      id: 'earlier', callerName: 'Ali Khan', phoneNumber: '', relationship: RelationshipCategory.unknown,
      timestamp: DateTime(2026, 9, 20), durationSeconds: 30, sentimentScore: 0, lemurSummary: '',
      transcript: const [], actionStatus: CallActionStatus.secretaryResolved, deviceId: 'dev-ali',
    ));
    await freshCall('call_prof', {'device': 'dev-ali'});
    await deliver({'type': 'CALLER_DETAILS', 'callId': 'call_prof', 'name': 'Professor Hamid', 'company': 'QAU'});
    final state = container.read(callProvider);
    expect(state.trust.level, TrustLevel.warning);
    expect(state.trust.note, 'This browser called before as Ali Khan');
    expect(lastSent('CALLER_CONTEXT')!['warnings'], contains('This browser called before as Ali Khan'));
  });

  test('marking an impostor blocks that browser and tells the gateway', () async {
    await freshCall('call_imp', {'device': 'dev-imp'});
    await deliver({'type': 'CALLER_DETAILS', 'callId': 'call_imp', 'name': 'Professor Hamid'});
    container.read(callProvider.notifier).markImpostorAndEnd();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final blocked = container.read(ownerProvider).blocked['dev-imp'];
    expect(blocked?['reason'], 'impostor');
    expect(blocked?['name'], 'Professor Hamid');
    expect(lastSent('OWNER_SETTINGS')!['blockedDevices'], contains('dev-imp'));
  });

  test('the number and email a caller confirmed reach the record and a task you can dial', () async {
    await deliver({
      'type': 'CALLER_DETAILS', 'callId': callId, 'name': 'Sam Reed', 'message': 'The lease papers are ready',
      'callbackNumber': '0300 1234567', 'callbackEmail': 'sam@example.com', 'bestTime': 'after 5 pm',
    });
    await deliver({'type': 'MASTER_COMMAND', 'callId': callId, 'command': 'end'});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final dashboard = container.read(dashboardProvider);
    final record = dashboard.callLogs.firstWhere((c) => c.id == callId);
    expect(record.callbackNumber, '0300 1234567');
    expect(record.callbackEmail, 'sam@example.com');
    expect(record.bestTime, 'after 5 pm');
    final task = dashboard.tasks.firstWhere((t) => t.callRecordId == callId);
    expect(task.actionItem, 'Call back Sam Reed (0300 1234567): The lease papers are ready');
    expect(task.phoneNumber, '0300 1234567');
    expect(task.email, 'sam@example.com');
  });

  test('a quiet call (Kabeer away) does not open his voice session', () async {
    await freshCall('call_quiet', {'quiet': 'away'});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final state = container.read(callProvider);
    expect(state.quiet, 'away');
    expect(state.voiceStatus, isNull);
  });

  test('details for another call do not rename this one', () async {
    await deliver({'type': 'CALLER_DETAILS', 'callId': 'call_other', 'name': 'Mallory'});
    expect(container.read(callProvider).callerUnknown, isTrue);
  });

  test('missed calls become call records with a call-back task, once', () async {
    final missed = {
      'type': 'MISSED_CALLS',
      'calls': [
        {
          'callId': 'call_missed_1',
          'startedAt': '2026-09-19T08:00:00.000Z',
          'endedAt': '2026-09-19T08:02:30.000Z',
          'details': {'name': 'Sam Reed', 'message': 'Please call about the lease', 'callback': '0300 1234567'},
          'tookMessage': true,
          'transcript': [
            {'speaker': 'Caller', 'text': 'Hi, this is Sam Reed.'},
          ],
        },
      ],
    };
    await deliver(missed);
    await deliver(missed); // delivered again (e.g. reconnect before the ack)

    final dashboard = container.read(dashboardProvider);
    final records = dashboard.callLogs.where((c) => c.id == 'call_missed_1').toList();
    expect(records, hasLength(1));
    expect(records.single.callerName, 'Sam Reed');
    expect(records.single.lemurSummary, 'Left a message: Please call about the lease');
    expect(records.single.durationSeconds, 150);
    final tasks = dashboard.tasks.where((t) => t.callRecordId == 'call_missed_1').toList();
    expect(tasks, hasLength(1));
    expect(tasks.single.actionItem, 'Call back Sam Reed (0300 1234567): Please call about the lease');
  });

  test('a second caller waits, keeps their details, and comes up after this call', () async {
    await deliver({'type': 'INCOMING_CALL', 'callId': 'call_second', 'callerName': 'Web Caller'});
    await deliver({'type': 'CALLER_DETAILS', 'callId': 'call_second', 'name': 'Ali Khan', 'reason': 'Invoice question'});
    await deliver({'type': 'TRANSCRIPT_UPDATE', 'callId': 'call_second', 'speaker': 'Caller', 'text': 'Hi, Ali here.'});

    // The call on screen is untouched
    expect(container.read(callProvider).currentCallId, callId);
    expect(container.read(callProvider).callerUnknown, isTrue);
    final waiting = container.read(waitingCallersProvider);
    expect(waiting.single.name, 'Ali Khan');
    expect(waiting.single.reason, 'Invoice question');

    await deliver({'type': 'CALLER_HUNG_UP', 'callId': callId});
    // The ended call clears after a short pause, then the waiting caller comes up
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    final state = container.read(callProvider);
    expect(state.currentCallId, 'call_second');
    expect(state.activeScenario!.callerName, 'Ali Khan');
    expect(state.transcriptEntries.single.text, 'Hi, Ali here.');
    expect(container.read(waitingCallersProvider), isEmpty);
  });

  test('a waiting caller who hangs up leaves the queue', () async {
    await deliver({'type': 'INCOMING_CALL', 'callId': 'call_second', 'callerName': 'Web Caller'});
    await deliver({'type': 'CALLER_HUNG_UP', 'callId': 'call_second'});
    expect(container.read(waitingCallersProvider), isEmpty);
    expect(container.read(callProvider).currentCallId, callId);
  });

  test('commands for another call are ignored', () async {
    await deliver({'type': 'MASTER_COMMAND', 'callId': 'call_other', 'command': 'hold', 'minutes': 5});
    expect(container.read(callProvider).status, ActiveCallStatus.secretaryScreening);
  });

  test('dictated tasks are saved when the call is ended by voice, restatements replace', () async {
    await deliver({'type': 'MASTER_COMMAND', 'callId': callId, 'command': 'task', 'task': 'Send John the invoice'});
    await deliver({
      'type': 'MASTER_COMMAND', 'callId': callId, 'command': 'task',
      'task': 'Send John Carter a copy of the invoice', 'replacesPrevious': true,
    });
    await deliver({
      'type': 'MASTER_COMMAND', 'callId': callId, 'command': 'task',
      'task': 'Check the Q4 contract', 'due': '2026-09-25',
    });
    await deliver({'type': 'MASTER_COMMAND', 'callId': callId, 'command': 'end'});
    expect(container.read(callProvider).status, ActiveCallStatus.callEnded);

    // _finishCall awaits the (offline) analysis request before saving
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final tasks = container.read(dashboardProvider).tasks.map((t) => t.actionItem).toList();
    expect(tasks, containsAll(['Send John Carter a copy of the invoice', 'Check the Q4 contract']));
    expect(tasks, isNot(contains('Send John the invoice')));
    final dated = container.read(dashboardProvider).tasks.firstWhere((t) => t.actionItem == 'Check the Q4 contract');
    expect(dated.dueDate, DateTime(2026, 9, 25));
    expect(container.read(dashboardProvider).callLogs.first.actionStatus.name, 'heldAndDeferred');
  });
}
