import 'dart:math';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'demo_config.dart';

/// Dialling, email, WhatsApp and sharing, plus the personal call links that
/// verify a caller.
class ContactActions {
  /// "0300 1234567" -> "923001234567" (WhatsApp wants the country code and no +).
  static String internationalDigits(String number, {String countryCode = '92'}) {
    var digits = number.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('+')) return digits.substring(1);
    if (digits.startsWith('00')) return digits.substring(2);
    final code = countryCode.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) return '$code${digits.substring(1)}';
    // Already national without the leading 0 (e.g. "3001234567"), or already international
    return digits.startsWith(code) ? digits : '$code$digits';
  }

  static bool hasNumber(String? number) => (number ?? '').replaceAll(RegExp(r'\D'), '').length >= 7;

  /// Opens the phone's dialer with the number filled in; Kabeer presses call.
  static Future<bool> dial(String number) =>
      launchUrl(Uri(scheme: 'tel', path: number.replaceAll(RegExp(r'[^\d+]'), '')));

  static Future<bool> email(String address, {String? subject}) => launchUrl(Uri(
        scheme: 'mailto',
        path: address.trim(),
        query: subject == null ? null : 'subject=${Uri.encodeComponent(subject)}',
      ));

  /// Opens WhatsApp in that person's chat (or the chat picker without a
  /// number) with the text ready to send. Falls back to the share menu.
  static Future<void> whatsApp({String? number, required String text, String countryCode = '92'}) async {
    final to = hasNumber(number) ? internationalDigits(number!, countryCode: countryCode) : '';
    final uri = Uri.parse('https://wa.me/$to?text=${Uri.encodeComponent(text)}');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!opened) await share(text);
  }

  static Future<void> share(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }

  // --- Personal links ----------------------------------------------------------

  // No 0/O or 1/I, so a code survives being read aloud or retyped
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// A fresh, unguessable personal-link token (the gateway accepts 8–24 chars).
  static String newLinkToken() {
    final random = Random.secure();
    return List.generate(10, (_) => _alphabet[random.nextInt(_alphabet.length)]).join();
  }

  /// The public call page for this gateway: wss://host -> https://host
  static String callPage(String gatewayUrl) {
    if (DemoConfig.enabled) return DemoConfig.callLink;
    return gatewayUrl
        .replaceFirst(RegExp(r'^wss://'), 'https://')
        .replaceFirst(RegExp(r'^ws://'), 'http://')
        .replaceAll(RegExp(r'/+$'), '');
  }

  /// A contact's own link: calling through it tells Kabeer it's really them.
  static String personalLink(String gatewayUrl, String token) {
    final page = callPage(gatewayUrl);
    return page.contains('?') ? '$page&from=$token' : '$page/?from=$token';
  }

  static String inviteText({required String contactName, required String link, required String ownerName}) {
    final first = contactName.trim().split(RegExp(r'\s+')).first;
    return 'Hi $first, when you need to reach me, call through this link: $link\n'
        "It's your own link, so my secretary will know it's you. Please don't share it.\n— $ownerName";
  }

  static String publicShareText({required String link, required String ownerName}) =>
      'You can call me through my secretary here: $link\n— $ownerName';
}
