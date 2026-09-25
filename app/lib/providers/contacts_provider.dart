import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contact_model.dart';
import '../core/constants/relationship_constants.dart';
import '../core/contact_actions.dart';
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
    _update(contactId, (c) => c.copyWith(relationship: newCategory));
  }

  void _update(String contactId, ContactModel Function(ContactModel) change) {
    _save(state.map((c) => c.id == contactId ? change(c) : c).toList());
  }

  ContactModel? byId(String contactId) {
    for (final c in state) {
      if (c.id == contactId) return c;
    }
    return null;
  }

  /// The contact's personal-link token, created the first time it is shared.
  String ensureLinkToken(String contactId) {
    final existing = byId(contactId)?.linkToken;
    if (existing != null) return existing;
    final token = ContactActions.newLinkToken();
    _update(contactId, (c) => c.copyWith(linkToken: token, linkDevices: const []));
    return token;
  }

  /// Stops the old link working and returns a new one to send instead.
  String revokeLink(String contactId) {
    final token = ContactActions.newLinkToken();
    _update(contactId, (c) => c.copyWith(linkToken: token, linkDevices: const []));
    return token;
  }

  /// Remembers a browser that called through this contact's link.
  void recordLinkDevice(String contactId, String deviceId) {
    final contact = byId(contactId);
    if (contact == null || deviceId.isEmpty || contact.linkDevices.contains(deviceId)) return;
    // Keep the last few; a person rarely has more browsers than that
    final devices = [...contact.linkDevices, deviceId];
    _update(contactId, (c) => c.copyWith(linkDevices: devices.length > 8 ? devices.sublist(devices.length - 8) : devices));
  }

  /// "Always ring" and "never ring" exclude each other.
  void setRinging(String contactId, {bool? alwaysRing, bool? neverRing}) {
    _update(contactId, (c) => c.copyWith(
          alwaysRing: alwaysRing ?? (neverRing == true ? false : c.alwaysRing),
          neverRing: neverRing ?? (alwaysRing == true ? false : c.neverRing),
        ));
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
