import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:awaaz_app/core/constants/relationship_constants.dart';
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
      'awaaz_contacts': '[{"id":"c9","name":"Maria Lopez","phoneNumber":"","relationship":"vipClient","company":"Brightline Studios","customNotes":null}]',
    });
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
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

  test('caller details name the caller; a known contact shows how Kabeer knows them', () async {
    expect(container.read(callProvider).callerUnknown, isTrue);
    await deliver({
      'type': 'CALLER_DETAILS', 'callId': callId,
      'name': 'Maria Lopez', 'company': 'Brightline', 'reason': 'Design review on Friday', 'urgent': true,
    });
    final state = container.read(callProvider);
    expect(state.callerUnknown, isFalse);
    expect(state.activeScenario!.callerName, 'Maria Lopez');
    expect(state.activeScenario!.relationship, RelationshipCategory.vipClient);
    expect(state.callerCompany, 'Brightline');
    expect(state.callerReason, 'Design review on Friday');
    expect(state.urgent, isTrue);
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
