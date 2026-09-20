import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contact_model.dart';
import '../core/constants/relationship_constants.dart';
import 'storage_provider.dart';

class ContactsNotifier extends Notifier<List<ContactModel>> {
  @override
  List<ContactModel> build() => ref.read(storageServiceProvider).getContacts();

  void _save(List<ContactModel> contacts) {
    contacts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = contacts;
    ref.read(storageServiceProvider).saveContacts(contacts);
  }

  void updateRelationship(String contactId, RelationshipCategory newCategory) {
    _save(state.map((c) {
      if (c.id != contactId) return c;
      return ContactModel(
        id: c.id,
        name: c.name,
        phoneNumber: c.phoneNumber,
        relationship: newCategory,
        company: c.company,
        customNotes: c.customNotes,
      );
    }).toList());
  }

  void upsertContact(ContactModel contact) {
    _save([...state.where((c) => c.id != contact.id), contact]);
  }

  void addContact(ContactModel contact) => upsertContact(contact);

  /// Adds phonebook contacts, skipping numbers that are already saved.
  /// Returns how many were added.
  int importContacts(List<ContactModel> imported) {
    final known = state.map((c) => _digits(c.phoneNumber)).where((d) => d.isNotEmpty).toSet();
    final fresh = <ContactModel>[];
    for (final contact in imported) {
      final digits = _digits(contact.phoneNumber);
      if (digits.isEmpty || known.contains(digits)) continue;
      known.add(digits);
      fresh.add(contact);
    }
    if (fresh.isNotEmpty) _save([...state, ...fresh]);
    return fresh.length;
  }

  void deleteContact(String contactId) {
    _save(state.where((c) => c.id != contactId).toList());
  }

  /// Matches a caller's name (as the secretary heard it) or number to a contact.
  RelationshipCategory resolveRelationship(String nameOrNumber) =>
      findContact(nameOrNumber)?.relationship ?? RelationshipCategory.unknown;

  ContactModel? findContact(String nameOrNumber) {
    final query = nameOrNumber.trim().toLowerCase();
    if (query.isEmpty) return null;
    final digits = _digits(query);
    // Exact name first, then partial matches ("Maria" / "Maria Lopez")
    for (final contact in state) {
      if (contact.name.toLowerCase() == query) return contact;
    }
    for (final contact in state) {
      final name = contact.name.toLowerCase();
      if (query.length >= 4 && name.length >= 4 && (name.contains(query) || query.contains(name))) {
        return contact;
      }
      if (digits.length >= 6 && _digits(contact.phoneNumber).endsWith(digits)) return contact;
    }
    return null;
  }

  static String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');
}

final contactsProvider = NotifierProvider<ContactsNotifier, List<ContactModel>>(ContactsNotifier.new);
