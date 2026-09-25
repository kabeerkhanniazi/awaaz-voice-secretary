import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/availability.dart';
import '../models/contact_model.dart';
import 'storage_provider.dart';

/// Kabeer's own call settings: whether he takes calls right now, and the
/// browsers he has blocked. Mirrored to the gateway (see [ownerSettingsMessage]).
class OwnerState {
  final Availability availability;
  /// device id -> {reason: 'spam' | 'impostor', name, at}
  final Map<String, Map<String, dynamic>> blocked;

  const OwnerState({this.availability = const Availability(), this.blocked = const {}});

  OwnerState copyWith({Availability? availability, Map<String, Map<String, dynamic>>? blocked}) =>
      OwnerState(availability: availability ?? this.availability, blocked: blocked ?? this.blocked);
}

class OwnerNotifier extends Notifier<OwnerState> {
  @override
  OwnerState build() {
    final storage = ref.read(storageServiceProvider);
    return OwnerState(availability: storage.getAvailability(), blocked: storage.getBlockedCallers());
  }

  void setAvailability(Availability availability) {
    state = state.copyWith(availability: availability);
    ref.read(storageServiceProvider).setAvailability(availability);
  }

  /// Blocks a caller's browser: the gateway refuses its calls from now on.
  void block(String deviceId, {required String reason, String? name}) {
    if (deviceId.isEmpty) return;
    final next = {
      ...state.blocked,
      deviceId: {'reason': reason, 'name': ?name, 'at': DateTime.now().toIso8601String()},
    };
    state = state.copyWith(blocked: next);
    ref.read(storageServiceProvider).setBlockedCallers(next);
  }

  void unblock(String deviceId) {
    final next = {...state.blocked}..remove(deviceId);
    state = state.copyWith(blocked: next);
    ref.read(storageServiceProvider).setBlockedCallers(next);
  }
}

final ownerProvider = NotifierProvider<OwnerNotifier, OwnerState>(OwnerNotifier.new);

/// What the gateway needs to decide, per call, whether to ring and who is
/// verified: availability, the personal links handed out, and blocked browsers.
Map<String, dynamic> ownerSettingsMessage(OwnerState owner, List<ContactModel> contacts, DateTime now) {
  final availability = owner.availability.effectiveAt(now);
  return {
    'type': 'OWNER_SETTINGS',
    'availability': {
      'mode': availability.mode.name,
      if (availability.until != null) 'until': availability.until!.toUtc().toIso8601String(),
      if (availability.until != null) 'untilLabel': Availability.timeLabel(availability.until!, now),
      if (availability.note != null) 'note': availability.note,
    },
    'links': [
      for (final c in contacts)
        if (c.linkToken != null)
          {'token': c.linkToken, 'name': c.name, 'alwaysRing': c.alwaysRing, 'neverRing': c.neverRing},
    ],
    'blockedDevices': owner.blocked.keys.toList(),
  };
}
