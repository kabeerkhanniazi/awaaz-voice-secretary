import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/theme/app_theme.dart';
import '../models/scenario_profile.dart';
import '../providers/call_provider.dart';
import '../providers/storage_provider.dart';
import '../services/background_service.dart';
import '../services/websocket_service.dart';
import '../widgets/common.dart';

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> with WidgetsBindingObserver {
  BackgroundServiceStatus _service = const BackgroundServiceStatus();
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshServiceStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Android settings (notifications, full-screen alerts)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshServiceStatus();
  }

  Future<void> _refreshServiceStatus() async {
    final status = await BackgroundService.status();
    if (mounted) setState(() => _service = status);
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(storageServiceProvider);
    final scheme = Theme.of(context).colorScheme;
    final gatewayUrl = storage.getGatewayUrl();
    final hasSecret = storage.getGatewaySecret().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SectionHeader('Connection'),
          const _ConnectionStatus(),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: const Text('Gateway'),
            subtitle: Text(gatewayUrl),
            onTap: () => _editText(
              title: 'Gateway address',
              initial: gatewayUrl,
              hint: 'aivs.up.railway.app',
              onSave: (value) {
                final url = WebSocketService.sanitizeUrl(value);
                storage.setGatewayUrl(url);
                WebSocketService().setServerUrl(url);
                BackgroundService.configure(url: url, secret: storage.getGatewaySecret());
              },
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: const Text('Gateway secret'),
            subtitle: Text(hasSecret ? 'Set' : 'Not set', style: TextStyle(color: hasSecret ? null : scheme.error)),
            onTap: () => _editText(
              title: 'Gateway secret',
              initial: '',
              hint: 'Same value as GATEWAY_AUTH_SECRET on the server',
              obscure: true,
              onSave: (value) {
                storage.setGatewaySecret(value);
                WebSocketService().setAuthSecret(value);
                BackgroundService.configure(
                  url: WebSocketService.sanitizeUrl(storage.getGatewayUrl()),
                  secret: value,
                );
              },
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: const Text('Test connection'),
            trailing: _testing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onTap: _testing ? null : _testConnection,
          ),

          const SectionHeader('Calls'),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: const Text('Ring when the app is closed'),
            subtitle: const Text('Keeps a quiet connection in the background so calls can ring like a phone call.'),
            value: _service.standby,
            onChanged: _setStandby,
          ),
          if (_service.standby && !_service.notificationsAllowed)
            _FixTile(
              text: 'Notifications are off, so calls can\'t ring.',
              action: 'Allow',
              onTap: openAppSettings,
            ),
          if (_service.standby && _service.notificationsAllowed && !_service.fullScreenAllowed)
            _FixTile(
              text: 'Full-screen call alerts are off. Calls will only show as a notification.',
              action: 'Allow',
              onTap: BackgroundService.openFullScreenSettings,
            ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: const Text('Secretary joins automatically'),
            subtitle: const Text(
              'She briefs you as soon as a call comes in. Turn off to start her yourself and use fewer call minutes.',
            ),
            value: storage.getAutoVoice(),
            onChanged: (value) async {
              await storage.setAutoVoice(value);
              setState(() {});
            },
          ),

          const SectionHeader('Your call page'),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text(_callPageUrl(gatewayUrl)),
            subtitle: const Text('Anyone can call you from this page. Tap to copy.'),
            trailing: const Icon(Icons.copy, size: 18),
            onTap: () {
              Clipboard.setData(ClipboardData(text: _callPageUrl(gatewayUrl)));
              showMessage(context, 'Link copied');
            },
          ),

          const SectionHeader('Developer'),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: const Text('Simulate a call'),
            subtitle: const Text('Try the call screen with a made-up caller. Nothing is sent to anyone.'),
            onTap: _simulate,
          ),
        ],
      ),
    );
  }

  static String _callPageUrl(String gatewayUrl) => gatewayUrl
      .replaceFirst(RegExp(r'^wss://'), 'https://')
      .replaceFirst(RegExp(r'^ws://'), 'http://');

  Future<void> _setStandby(bool enabled) async {
    if (enabled) {
      final storage = ref.read(storageServiceProvider);
      if (storage.getGatewaySecret().isEmpty) {
        showMessage(context, 'Set the gateway secret first.');
        return;
      }
      // Android 13+ needs permission before a call can ring
      await Permission.notification.request();
      await BackgroundService.configure(
        url: WebSocketService.sanitizeUrl(storage.getGatewayUrl()),
        secret: storage.getGatewaySecret(),
      );
    }
    await BackgroundService.setStandby(enabled);
    await _refreshServiceStatus();
  }

  Future<void> _testConnection() async {
    setState(() => _testing = true);
    final storage = ref.read(storageServiceProvider);
    final result = await WebSocketService().testConnection(
      storage.getGatewayUrl(),
      secret: storage.getGatewaySecret(),
    );
    if (!mounted) return;
    setState(() => _testing = false);
    showMessage(context, result['success'] == true ? 'Connected' : '${result['message']}');
  }

  void _editText({
    required String title,
    required String initial,
    required String hint,
    required void Function(String) onSave,
    bool obscure = false,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TextSheet(title: title, initial: initial, hint: hint, obscure: obscure, onSave: (value) {
        onSave(value);
        setState(() {});
      }),
    );
  }

  void _simulate() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final scenario in ScenarioProfile.presets)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(scenario.callerName),
                subtitle: Text(scenario.dialogueIntent, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ref.read(callProvider.notifier).simulateCall(scenario);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus();

  @override
  Widget build(BuildContext context) {
    final ws = WebSocketService();
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<GatewayStatus>(
      valueListenable: ws.status,
      builder: (context, status, _) {
        final (label, color) = switch (status) {
          GatewayStatus.connected => ('Connected', StatusColors.of(context).live),
          GatewayStatus.connecting => ('Connecting...', StatusColors.of(context).warning),
          GatewayStatus.authFailed => ('Rejected: ${ws.lastError ?? 'wrong secret'}', scheme.error),
          GatewayStatus.disconnected => ('Not connected, retrying', scheme.onSurfaceVariant),
        };
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: TextStyle(color: color))),
            ],
          ),
        );
      },
    );
  }
}

/// A problem with a one-tap fix, shown under the setting it affects.
class _FixTile extends StatelessWidget {
  final String text;
  final String action;
  final VoidCallback onTap;

  const _FixTile({required this.text, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.error)),
          ),
          TextButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }
}

class _TextSheet extends StatefulWidget {
  final String title;
  final String initial;
  final String hint;
  final bool obscure;
  final void Function(String) onSave;

  const _TextSheet({
    required this.title,
    required this.initial,
    required this.hint,
    required this.obscure,
    required this.onSave,
  });

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    widget.onSave(value);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                obscureText: widget.obscure,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(hintText: widget.hint),
              ),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const Text('Save'))),
            ],
          ),
        ),
      ),
    );
  }
}
