import '../core/constants/relationship_constants.dart';

class ContactModel {
  final String id;
  final String name;
  final String phoneNumber;
  final RelationshipCategory relationship;
  final String? company;
  final String? customNotes;
  // The personal link Kabeer shared with this person (…/?from=TOKEN). Calling
  // through it is what verifies them; null until he shares one.
  final String? linkToken;
  // Browsers that have called through that link, to notice a new one
  final List<String> linkDevices;
  // Only for calls verified by the personal link: ring even when Kabeer is
  // away, or never ring (the secretary takes a message)
  final bool alwaysRing;
  final bool neverRing;

  ContactModel({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.relationship,
    this.company,
    this.customNotes,
    this.linkToken,
    this.linkDevices = const [],
    this.alwaysRing = false,
    this.neverRing = false,
  });

  ContactModel copyWith({
    String? name,
    String? phoneNumber,
    RelationshipCategory? relationship,
    String? company,
    String? customNotes,
    String? linkToken,
    bool clearLink = false,
    List<String>? linkDevices,
    bool? alwaysRing,
    bool? neverRing,
  }) {
    return ContactModel(
      id: id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      relationship: relationship ?? this.relationship,
      company: company ?? this.company,
      customNotes: customNotes ?? this.customNotes,
      linkToken: clearLink ? null : (linkToken ?? this.linkToken),
      linkDevices: clearLink ? const [] : (linkDevices ?? this.linkDevices),
      alwaysRing: alwaysRing ?? this.alwaysRing,
      neverRing: neverRing ?? this.neverRing,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'relationship': relationship.name,
      'company': company,
      'customNotes': customNotes,
      'linkToken': linkToken,
      'linkDevices': linkDevices,
      'alwaysRing': alwaysRing,
      'neverRing': neverRing,
    };
  }

  factory ContactModel.fromJson(Map<String, dynamic> json) {
    return ContactModel(
      id: json['id'] as String,
      name: json['name'] as String,
      phoneNumber: json['phoneNumber'] as String,
      relationship: RelationshipCategory.values.firstWhere(
        (e) => e.name == json['relationship'],
        orElse: () => RelationshipCategory.unknown,
      ),
      company: json['company'] as String?,
      customNotes: json['customNotes'] as String?,
      linkToken: json['linkToken'] as String?,
      linkDevices: (json['linkDevices'] as List?)?.whereType<String>().toList() ?? const [],
      alwaysRing: json['alwaysRing'] == true,
      neverRing: json['neverRing'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContactModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          phoneNumber == other.phoneNumber &&
          relationship == other.relationship &&
          company == other.company &&
          customNotes == other.customNotes &&
          linkToken == other.linkToken &&
          linkDevices.join(',') == other.linkDevices.join(',') &&
          alwaysRing == other.alwaysRing &&
          neverRing == other.neverRing;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        phoneNumber,
        relationship,
        company,
        customNotes,
        linkToken,
        linkDevices.join(','),
        alwaysRing,
        neverRing,
      );
}
