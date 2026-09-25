import 'package:intl/intl.dart';

enum AvailabilityMode { available, busy, dnd }

/// Whether Kabeer takes calls right now. Busy and do-not-disturb both let the
/// secretary take messages at once; only a verified "always ring" contact
/// still reaches him. Busy can end at a set time; DND lasts until switched off.
class Availability {
  final AvailabilityMode mode;
  final DateTime? until;
  final String? note; // "in a meeting"

  const Availability({this.mode = AvailabilityMode.available, this.until, this.note});

  bool isAwayAt(DateTime now) => mode != AvailabilityMode.available && (until == null || until!.isAfter(now));

  /// What applies now: an expired "busy until" is simply available again.
  Availability effectiveAt(DateTime now) => isAwayAt(now) ? this : const Availability();

  /// "3:00 PM", or "Mon 3:00 PM" when it isn't today.
  static String timeLabel(DateTime time, DateTime now) {
    final sameDay = time.year == now.year && time.month == now.month && time.day == now.day;
    // intl puts a narrow no-break space before AM/PM; the secretary reads this
    // label aloud, so keep it plain
    return (sameDay ? DateFormat.jm() : DateFormat('EEE h:mm a'))
        .format(time)
        .replaceAll(RegExp('[  ]'), ' ');
  }

  String describe(DateTime now) {
    final current = effectiveAt(now);
    final note = current.note?.trim();
    final suffix = note == null || note.isEmpty ? '' : ' · $note';
    switch (current.mode) {
      case AvailabilityMode.available:
        return 'Available';
      case AvailabilityMode.busy:
        return current.until == null ? 'Busy$suffix' : 'Busy until ${timeLabel(current.until!, now)}$suffix';
      case AvailabilityMode.dnd:
        return 'Do not disturb$suffix';
    }
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'until': until?.toIso8601String(),
        'note': note,
      };

  factory Availability.fromJson(Map<String, dynamic> json) => Availability(
        mode: AvailabilityMode.values.firstWhere((m) => m.name == json['mode'], orElse: () => AvailabilityMode.available),
        until: json['until'] is String ? DateTime.tryParse(json['until'] as String) : null,
        note: json['note'] as String?,
      );
}
