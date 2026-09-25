import '../models/call_record_model.dart';
import 'constants/relationship_constants.dart';
import '../models/contact_model.dart';

/// How much a caller's identity can be trusted.
///
/// Only a personal link Kabeer handed out verifies anyone. A name is otherwise
/// just a claim: it may match a contact, and a browser that called before
/// under a different name is a warning sign, but neither proves who it is.
enum TrustLevel { verified, recognised, unverified, warning }

class CallerTrust {
  final TrustLevel level;
  /// The contact whose personal link was used (verified calls only)
  final ContactModel? contact;
  /// A contact whose name matches what an unverified caller claims
  final String? nameMatch;
  final List<String> warnings;
  /// A verified link used from a browser it hasn't been used from before
  final bool newDevice;

  const CallerTrust({
    this.level = TrustLevel.unverified,
    this.contact,
    this.nameMatch,
    this.warnings = const [],
    this.newDevice = false,
  });

  bool get verified => contact != null;

  /// Short label for the call screen and records.
  String get label {
    switch (level) {
      case TrustLevel.verified:
        return "Verified · via ${contact!.name}'s link";
      case TrustLevel.recognised:
        return 'Not verified · called before from this browser';
      case TrustLevel.unverified:
        return 'Not verified';
      case TrustLevel.warning:
        return 'Warning';
    }
  }

  /// The one line of detail worth showing under the label, if any.
  String? get note {
    if (warnings.isNotEmpty) return warnings.first;
    if (newDevice) return 'Used from a new device';
    if (!verified && nameMatch != null) return 'Name matches your contact $nameMatch, but this caller is not verified';
    return null;
  }

  /// Sent to the gateway so Kabeer's secretary briefs him the same way.
  Map<String, dynamic> contextMessage(String callId) => {
        'type': 'CALLER_CONTEXT',
        'callId': callId,
        'trust': level.name,
        if (contact != null) 'relationship': contact!.relationship.displayName,
        if (contact?.company != null) 'company': contact!.company,
        if (contact?.customNotes != null) 'note': contact!.customNotes,
        if (!verified && nameMatch != null) 'nameMatch': nameMatch,
        'warnings': [...warnings, if (newDevice) "Used ${contact!.name}'s personal link from a new device"],
      };
}

/// Names the secretary records before she knows who it is
const _placeholderNames = {'web caller', 'unknown caller', ''};

String _norm(String name) => name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// "Maria" and "Maria Lopez" are the same person; "Ali" and "Professor Khan" are not.
bool sameName(String a, String b) {
  final x = _norm(a);
  final y = _norm(b);
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  final shorter = x.length <= y.length ? x : y;
  final longer = x.length <= y.length ? y : x;
  final wholeWord = shorter.length >= 3 && longer.split(' ').any((part) => part == shorter);
  final prefix = shorter.length >= 4 && longer.startsWith(shorter);
  return wholeWord || prefix;
}

CallerTrust assessCaller({
  required String? claimedName,
  String? linkToken,
  bool staleLink = false,
  String? deviceId,
  required List<ContactModel> contacts,
  required List<CallRecordModel> history,
}) {
  final claimed = claimedName?.trim() ?? '';
  final hasClaim = !_placeholderNames.contains(claimed.toLowerCase());

  // Verified: the call came through a personal link this phone handed out
  ContactModel? contact;
  if (linkToken != null && linkToken.isNotEmpty) {
    for (final c in contacts) {
      if (c.linkToken == linkToken) contact = c;
    }
  }
  if (contact != null) {
    final warnings = <String>[
      if (hasClaim && !sameName(claimed, contact.name))
        'Gives the name "$claimed", but called through ${contact.name}\'s personal link',
    ];
    final newDevice = deviceId != null && deviceId.isNotEmpty &&
        contact.linkDevices.isNotEmpty && !contact.linkDevices.contains(deviceId);
    return CallerTrust(
      level: warnings.isEmpty ? TrustLevel.verified : TrustLevel.warning,
      contact: contact,
      warnings: warnings,
      newDevice: newDevice,
    );
  }

  final warnings = <String>[
    if (staleLink || (linkToken != null && linkToken.isNotEmpty)) 'Called through an old or unknown personal link',
  ];

  // What this browser called itself before
  final earlierNames = <String>[];
  if (deviceId != null && deviceId.isNotEmpty) {
    for (final record in history) {
      if (record.deviceId != deviceId) continue;
      final name = record.callerName.trim();
      if (_placeholderNames.contains(name.toLowerCase())) continue;
      if (!earlierNames.any((n) => sameName(n, name))) earlierNames.add(name);
    }
  }
  final consistent = hasClaim && earlierNames.any((n) => sameName(n, claimed));
  if (hasClaim && earlierNames.isNotEmpty && !consistent) {
    warnings.add('This browser called before as ${earlierNames.take(3).join(', ')}');
  }

  String? nameMatch;
  if (hasClaim) {
    for (final c in contacts) {
      if (sameName(c.name, claimed)) {
        nameMatch = c.name;
        break;
      }
    }
  }

  return CallerTrust(
    level: warnings.isNotEmpty
        ? TrustLevel.warning
        : consistent
            ? TrustLevel.recognised
            : TrustLevel.unverified,
    nameMatch: nameMatch,
    warnings: warnings,
  );
}
