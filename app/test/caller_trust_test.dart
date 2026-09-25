import 'package:flutter_test/flutter_test.dart';
import 'package:awaaz_app/core/caller_trust.dart';
import 'package:awaaz_app/core/constants/relationship_constants.dart';
import 'package:awaaz_app/core/contact_actions.dart';
import 'package:awaaz_app/models/availability.dart';
import 'package:awaaz_app/models/call_record_model.dart';
import 'package:awaaz_app/models/contact_model.dart';
import 'package:awaaz_app/providers/owner_provider.dart';

final maria = ContactModel(
  id: 'c1', name: 'Maria Lopez', phoneNumber: '0300 1234567',
  relationship: RelationshipCategory.vipClient, linkToken: 'MARIALINK01', linkDevices: const ['dev-laptop'],
);

CallRecordModel earlierCall(String name, String device) => CallRecordModel(
      id: 'r-$name', callerName: name, phoneNumber: '', relationship: RelationshipCategory.unknown,
      timestamp: DateTime(2026, 9, 20), durationSeconds: 30, sentimentScore: 0, lemurSummary: '',
      transcript: const [], actionStatus: CallActionStatus.secretaryResolved, deviceId: device,
    );

void main() {
  group('names', () {
    test('a first name matches the full name, a different person does not', () {
      expect(sameName('Maria', 'Maria Lopez'), isTrue);
      expect(sameName('maria lopez', 'Maria  Lopez'), isTrue);
      expect(sameName('Ali', 'Professor Hamid'), isFalse);
      expect(sameName('Al', 'Alex'), isFalse);
    });
  });

  group('who is calling', () {
    test('a personal link verifies, whatever name is given', () {
      final trust = assessCaller(claimedName: 'Maria', linkToken: 'MARIALINK01', deviceId: 'dev-laptop',
          contacts: [maria], history: const []);
      expect(trust.level, TrustLevel.verified);
      expect(trust.contact?.name, 'Maria Lopez');
      expect(trust.newDevice, isFalse);
    });

    test('the right link from a new browser is still verified, but noted', () {
      final trust = assessCaller(claimedName: 'Maria Lopez', linkToken: 'MARIALINK01', deviceId: 'dev-phone',
          contacts: [maria], history: const []);
      expect(trust.level, TrustLevel.verified);
      expect(trust.newDevice, isTrue);
      expect(trust.note, 'Used from a new device');
    });

    test("someone else's name on Maria's link is a warning", () {
      final trust = assessCaller(claimedName: 'Professor Hamid', linkToken: 'MARIALINK01',
          contacts: [maria], history: const []);
      expect(trust.level, TrustLevel.warning);
    });

    test("saying Maria's name without her link is only a match", () {
      final trust = assessCaller(claimedName: 'Maria Lopez', contacts: [maria], history: const []);
      expect(trust.level, TrustLevel.unverified);
      expect(trust.contact, isNull);
      expect(trust.nameMatch, 'Maria Lopez');
      expect(trust.contextMessage('c')['relationship'], isNull);
    });

    test('Ali calling back as a professor from the same browser is a warning', () {
      final trust = assessCaller(claimedName: 'Professor Hamid', deviceId: 'dev-x',
          contacts: [maria], history: [earlierCall('Ali Khan', 'dev-x')]);
      expect(trust.level, TrustLevel.warning);
      expect(trust.warnings, ['This browser called before as Ali Khan']);
    });

    test('the same name again from the same browser is recognised, not verified', () {
      final trust = assessCaller(claimedName: 'Ali', deviceId: 'dev-x',
          contacts: [maria], history: [earlierCall('Ali Khan', 'dev-x')]);
      expect(trust.level, TrustLevel.recognised);
      expect(trust.verified, isFalse);
    });

    test('an unknown or revoked link is flagged', () {
      final trust = assessCaller(claimedName: 'Maria', linkToken: 'OLDLINK0000', staleLink: true,
          contacts: [maria], history: const []);
      expect(trust.level, TrustLevel.warning);
      expect(trust.note, 'Called through an old or unknown personal link');
    });
  });

  group('numbers and links', () {
    test('local Pakistani numbers become WhatsApp numbers', () {
      expect(ContactActions.internationalDigits('0300 1234567'), '923001234567');
      expect(ContactActions.internationalDigits('+92 300 1234567'), '923001234567');
      expect(ContactActions.internationalDigits('0044 20 7946 0000'), '442079460000');
      expect(ContactActions.internationalDigits('3001234567'), '923001234567');
    });

    test('personal links carry the token, and tokens are unguessable', () {
      expect(ContactActions.personalLink('wss://aivs.up.railway.app', 'K7Q2PXMN9A'),
          'https://aivs.up.railway.app/?from=K7Q2PXMN9A');
      final a = ContactActions.newLinkToken();
      final b = ContactActions.newLinkToken();
      expect(a, matches(RegExp(r'^[A-HJ-NP-Z2-9]{10}$')));
      expect(a, isNot(b));
    });
  });

  test('the gateway gets availability, links and blocked browsers in one message', () {
    final now = DateTime(2026, 9, 25, 14, 0);
    final message = ownerSettingsMessage(
      OwnerState(
        availability: Availability(mode: AvailabilityMode.busy, until: DateTime(2026, 9, 25, 15, 0), note: 'in a meeting'),
        blocked: const {'dev-bad': {'reason': 'spam'}},
      ),
      [maria.copyWith(alwaysRing: true), ContactModel(id: 'c2', name: 'No link', phoneNumber: '', relationship: RelationshipCategory.unknown)],
      now,
    );
    expect(message['type'], 'OWNER_SETTINGS');
    expect(message['availability']['mode'], 'busy');
    expect(message['availability']['untilLabel'], '3:00 PM');
    expect(message['availability']['note'], 'in a meeting');
    expect(message['links'], [
      {'token': 'MARIALINK01', 'name': 'Maria Lopez', 'alwaysRing': true, 'neverRing': false},
    ]);
    expect(message['blockedDevices'], ['dev-bad']);

    // Once "busy until" has passed, it's simply available
    final later = ownerSettingsMessage(
      OwnerState(availability: Availability(mode: AvailabilityMode.busy, until: DateTime(2026, 9, 25, 15, 0))),
      const [], DateTime(2026, 9, 25, 16, 0),
    );
    expect(later['availability'], {'mode': 'available'});
  });
}
