import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' hide PermissionStatus;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/relationship_constants.dart';
import '../core/contact_actions.dart';
import '../models/contact_model.dart';
import '../providers/contacts_provider.dart';
import '../providers/storage_provider.dart';
import '../widgets/common.dart';
import '../widgets/reach_out.dart';

/// People the secretary should recognise. The relationship tells her how to
/// treat them (family and friends informally, business formally).
class ContactsTab extends ConsumerStatefulWidget {
  const ContactsTab({super.key});

  @override
  ConsumerState<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends ConsumerState<ContactsTab> {
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            tooltip: 'Import from phone',
            onPressed: _importing ? null : _importFromPhone,
            icon: _importing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add contact',
        onPressed: () => _edit(context, null),
        child: const Icon(Icons.person_add_alt),
      ),
      body: contacts.isEmpty
          ? const EmptyState(
              icon: Icons.people_outline,
              title: 'No contacts',
              message: 'Add people or import them from your phone, so your secretary knows who they are.',
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: contacts.length,
              itemBuilder: (context, index) {
                final contact = contacts[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: InitialAvatar(name: contact.name),
                  title: Row(
                    children: [
                      Flexible(child: Text(contact.name, overflow: TextOverflow.ellipsis)),
                      // Has a personal link: their calls through it are verified
                      if (contact.linkToken != null) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.verified_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    [
                      contact.relationship.displayName,
                      if (contact.company?.isNotEmpty == true) contact.company!,
                      if (contact.phoneNumber.isNotEmpty) contact.phoneNumber,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: ReachOutButtons(number: contact.phoneNumber, dense: true),
                  onTap: () => _edit(context, contact),
                );
              },
            ),
    );
  }

  Future<void> _importFromPhone() async {
    setState(() => _importing = true);
    try {
      final status = await Permission.contacts.request();
      if (!status.isGranted) {
        if (mounted) showMessage(context, 'Allow contacts access to import from your phone.');
        return;
      }
      final phoneContacts = await FlutterContacts.getAll(properties: {ContactProperty.phone});
      final imported = [
        for (final c in phoneContacts)
          if ((c.displayName ?? '').trim().isNotEmpty && c.phones.isNotEmpty)
            ContactModel(
              id: const Uuid().v4(),
              name: c.displayName!.trim(),
              phoneNumber: c.phones.first.number,
              relationship: RelationshipCategory.unknown,
            ),
      ];
      final added = ref.read(contactsProvider.notifier).importContacts(imported);
      if (mounted) {
        showMessage(context, added == 0 ? 'No new contacts to import.' : 'Imported $added contacts.');
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Could not read your contacts.');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _edit(BuildContext context, ContactModel? contact) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ContactSheet(contact: contact),
    );
  }
}

class _ContactSheet extends ConsumerStatefulWidget {
  final ContactModel? contact;

  const _ContactSheet({required this.contact});

  @override
  ConsumerState<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends ConsumerState<_ContactSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.contact?.name ?? '');
  late final TextEditingController _phone = TextEditingController(text: widget.contact?.phoneNumber ?? '');
  late final TextEditingController _company = TextEditingController(text: widget.contact?.company ?? '');
  late RelationshipCategory _relationship = widget.contact?.relationship ?? RelationshipCategory.unknown;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _company.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final company = _company.text.trim().isEmpty ? null : _company.text.trim();
    final existing = widget.contact == null ? null : ref.read(contactsProvider.notifier).byId(widget.contact!.id);
    // Editing keeps the personal link and ring settings
    ref.read(contactsProvider.notifier).upsertContact(existing != null
        ? ContactModel(
            id: existing.id,
            name: name,
            phoneNumber: _phone.text.trim(),
            relationship: _relationship,
            company: company,
            customNotes: existing.customNotes,
            linkToken: existing.linkToken,
            linkDevices: existing.linkDevices,
            alwaysRing: existing.alwaysRing,
            neverRing: existing.neverRing,
          )
        : ContactModel(
            id: const Uuid().v4(),
            name: name,
            phoneNumber: _phone.text.trim(),
            relationship: _relationship,
            company: company,
          ));
    Navigator.pop(context);
  }

  void _delete() {
    ref.read(contactsProvider.notifier).deleteContact(widget.contact!.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.contact != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(editing ? 'Edit contact' : 'New contact', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: !editing,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _company,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Company (optional)'),
              ),
              const SizedBox(height: 16),
              const Text('Relationship', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in RelationshipCategory.values)
                    ChoiceChip(
                      label: Text(category.displayName),
                      selected: _relationship == category,
                      onSelected: (_) => setState(() => _relationship = category),
                    ),
                ],
              ),
              if (editing) _PersonalLinkSection(contactId: widget.contact!.id),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (editing)
                    TextButton(
                      onPressed: _delete,
                      style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                      child: const Text('Delete'),
                    ),
                  const Spacer(),
                  FilledButton(onPressed: _save, child: const Text('Save')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A contact's own call link. Calling through it is the only thing that
/// verifies who a caller is, so "always ring" and "never ring" depend on it.
class _PersonalLinkSection extends ConsumerWidget {
  final String contactId;

  const _PersonalLinkSection({required this.contactId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(contactsProvider.select((list) => list.where((c) => c.id == contactId).firstOrNull));
    if (contact == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final storage = ref.read(storageServiceProvider);
    final notifier = ref.read(contactsProvider.notifier);
    final hasLink = contact.linkToken != null;

    Future<void> send(String token) {
      final link = ContactActions.personalLink(storage.getGatewayUrl(), token);
      return ContactActions.whatsApp(
        number: contact.phoneNumber,
        text: ContactActions.inviteText(contactName: contact.name, link: link, ownerName: storage.getMasterName()),
        countryCode: storage.getCountryCode(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text('Personal link', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          hasLink
              ? "When ${contact.name.split(' ').first} calls through their link, you'll see them as verified."
              : 'Send them their own link to call you through, so your secretary knows it is really them.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: Text(hasLink ? 'Send again on WhatsApp' : 'Send on WhatsApp'),
              onPressed: () => send(notifier.ensureLinkToken(contact.id)),
            ),
            if (hasLink)
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Revoke this link?'),
                      content: const Text('The old link stops identifying them. You can send them a new one straight away.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Revoke')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    final token = notifier.revokeLink(contact.id);
                    if (context.mounted) {
                      showMessage(context, 'Old link revoked',
                          action: SnackBarAction(label: 'Send new', onPressed: () => send(token)));
                    }
                  }
                },
                child: const Text('Revoke link'),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Always ring'),
          subtitle: const Text("Even when you're busy or on do not disturb"),
          value: contact.alwaysRing,
          onChanged: hasLink ? (v) => notifier.setRinging(contact.id, alwaysRing: v) : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Never ring'),
          subtitle: const Text('Your secretary takes a message instead'),
          value: contact.neverRing,
          onChanged: hasLink ? (v) => notifier.setRinging(contact.id, neverRing: v) : null,
        ),
        if (!hasLink)
          Text(
            'These only apply to calls through their personal link, so nobody can switch them on by giving a name.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
      ],
    );
  }
}
