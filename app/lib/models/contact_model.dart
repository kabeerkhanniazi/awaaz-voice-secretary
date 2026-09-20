import '../core/constants/relationship_constants.dart';

class ContactModel {
  final String id;
  final String name;
  final String phoneNumber;
  final RelationshipCategory relationship;
  final String? company;
  final String? customNotes;

  ContactModel({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.relationship,
    this.company,
    this.customNotes,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'relationship': relationship.name,
      'company': company,
      'customNotes': customNotes,
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
          customNotes == other.customNotes;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        phoneNumber,
        relationship,
        company,
        customNotes,
      );
}
