import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/contact_actions.dart';
import '../providers/storage_provider.dart';
import 'common.dart';

/// Call, WhatsApp and email buttons for a number and/or email address.
/// Dialling opens the phone's dialer with the number filled in; nothing is
/// dialled until Kabeer presses call there.
class ReachOutButtons extends ConsumerWidget {
  final String? number;
  final String? email;
  /// Pre-filled WhatsApp text, if any
  final String? whatsAppText;
  final bool dense;

  const ReachOutButtons({super.key, this.number, this.email, this.whatsAppText, this.dense = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasNumber = ContactActions.hasNumber(number);
    final hasEmail = (email ?? '').contains('@');
    if (!hasNumber && !hasEmail) return const SizedBox.shrink();
    final size = dense ? 20.0 : 22.0;

    Future<void> run(Future<Object?> Function() action, String failure) async {
      try {
        final result = await action();
        if (result == false && context.mounted) showMessage(context, failure);
      } catch (_) {
        if (context.mounted) showMessage(context, failure);
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasNumber)
          IconButton(
            tooltip: 'Call',
            icon: Icon(Icons.call_outlined, size: size),
            onPressed: () => run(() => ContactActions.dial(number!), 'No app on this phone can place calls.'),
          ),
        if (hasNumber)
          IconButton(
            tooltip: 'WhatsApp',
            icon: Icon(Icons.chat_outlined, size: size),
            onPressed: () => run(
              () async {
                await ContactActions.whatsApp(
                  number: number,
                  text: whatsAppText ?? '',
                  countryCode: ref.read(storageServiceProvider).getCountryCode(),
                );
                return true;
              },
              "Couldn't open WhatsApp.",
            ),
          ),
        if (hasEmail)
          IconButton(
            tooltip: 'Email',
            icon: Icon(Icons.mail_outline, size: size),
            onPressed: () => run(() => ContactActions.email(email!), 'No email app on this phone.'),
          ),
      ],
    );
  }
}
