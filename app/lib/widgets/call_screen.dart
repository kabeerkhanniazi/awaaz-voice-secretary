import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/caller_trust.dart';
import '../core/constants/relationship_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/call_record_model.dart';
import '../providers/call_provider.dart';
import 'common.dart';

/// Full-screen view of the call in progress: who is calling and why, what the
/// secretary is doing, the conversation so far, and Kabeer's actions.
class CallScreen extends ConsumerStatefulWidget {
  final VoidCallback onMinimize;

  const CallScreen({super.key, required this.onMinimize});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Keeps the call timer current
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callProvider);
    final notifier = ref.read(callProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final scenario = call.activeScenario;
    if (scenario == null) return const SizedBox.shrink();

    final name = call.callerUnknown ? 'Unknown caller' : scenario.callerName;
    final reason = call.callerReason ?? (call.isRealCall ? null : scenario.dialogueIntent);
    final ended = call.status == ActiveCallStatus.callEnded;
    final patched = call.status == ActiveCallStatus.masterPatched;

    return Material(
      color: scheme.surfaceContainerLowest,
      child: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onMinimize,
                    icon: const Icon(Icons.keyboard_arrow_down),
                    tooltip: 'Minimise',
                  ),
                  Expanded(
                    child: Text(
                      _statusLine(call),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: _statusColor(context, call)),
                    ),
                  ),
                  if (!ended && !patched)
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_horiz),
                      onSelected: (value) {
                        if (value == 'spam') notifier.markSpamAndEnd();
                        if (value == 'impostor') notifier.markImpostorAndEnd();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'spam', child: Text('Spam: block and end')),
                        PopupMenuItem(value: 'impostor', child: Text('Impostor: block and end')),
                      ],
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),

            const _WaitingStrip(),

            // Caller
            const SizedBox(height: 16),
            InitialAvatar(name: call.callerUnknown ? null : name, size: 72),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(name, style: text.headlineSmall, textAlign: TextAlign.center),
                  if (_knownAs(call) != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _knownAs(call)!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  if (call.isRealCall) ...[
                    const SizedBox(height: 6),
                    _TrustLine(trust: call.trust),
                  ],
                  if (call.urgent) ...[
                    const SizedBox(height: 6),
                    Text('Urgent', style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    reason ?? (call.callerUnknown ? 'Your secretary is finding out who is calling.' : ''),
                    style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  if (call.isRealCall && !patched && !ended && call.activeDirective != null) ...[
                    const SizedBox(height: 12),
                    _DirectiveLine(call: call),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),
            if (call.isRealCall && !patched && !ended) _SecretaryPanel(call: call),

            // Conversation on the secretary line
            Expanded(child: _Conversation(entries: call.transcriptEntries)),

            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: ended
                  ? const SizedBox(height: 72)
                  : patched
                      ? _PatchedActions(call: call)
                      : _ScreeningActions(call: call),
            ),
          ],
        ),
      ),
    );
  }

  /// "Important client · Brightline Studios": how Kabeer knows them (from his
  /// contacts) and where they're calling from, whichever is known.
  String? _knownAs(CallState call) {
    final relationship = call.activeScenario?.relationship ?? RelationshipCategory.unknown;
    final parts = [
      if (relationship != RelationshipCategory.unknown) relationship.displayName,
      ?call.callerCompany,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String _statusLine(CallState call) {
    final elapsed = DateTime.now().difference(call.startTime ?? DateTime.now()).inSeconds;
    switch (call.status) {
      case ActiveCallStatus.holding:
        return 'On hold · ${clockLabel(call.holdTimerSeconds)} left';
      case ActiveCallStatus.masterPatched:
        return call.bridgeLive ? 'On the call · ${clockLabel(elapsed)}' : 'Connecting you...';
      case ActiveCallStatus.callEnded:
        return 'Call ended';
      default:
        // Kabeer set himself away, or a "never ring" contact: she takes a message
        if (call.quiet != null) return 'Your secretary is taking a message · ${clockLabel(elapsed)}';
        return 'Your secretary is answering · ${clockLabel(elapsed)}';
    }
  }

  Color _statusColor(BuildContext context, CallState call) {
    final scheme = Theme.of(context).colorScheme;
    final status = StatusColors.of(context);
    switch (call.status) {
      case ActiveCallStatus.holding:
        return status.warning;
      case ActiveCallStatus.masterPatched:
        return status.live;
      default:
        return scheme.onSurfaceVariant;
    }
  }
}

/// Kabeer's voice line to his secretary: status, her latest words, mute.
class _SecretaryPanel extends ConsumerWidget {
  final CallState call;

  const _SecretaryPanel({required this.call});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(callProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final live = call.voiceStatus == 'listening' || call.voiceStatus == 'speaking';

    Widget body;
    if (call.voiceStatus == null || call.voiceStatus == 'noMic') {
      body = Row(
        children: [
          Expanded(
            child: Text(
              call.voiceStatus == 'noMic'
                  ? 'Microphone access is needed to talk to your secretary.'
                  : 'Talk to your secretary about this call.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: notifier.startVoiceSession,
            icon: const Icon(Icons.mic_none, size: 18),
            label: const Text('Talk'),
          ),
        ],
      );
    } else {
      final label = switch (call.voiceStatus) {
        'connecting' => 'Connecting to your secretary...',
        'speaking' => 'Secretary',
        'listening' => call.micMuted ? 'Muted' : 'Listening',
        _ => 'Secretary unavailable',
      };
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Dot(active: live && !call.micMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              ),
              if (live)
                IconButton(
                  onPressed: notifier.toggleMute,
                  visualDensity: VisualDensity.compact,
                  tooltip: call.micMuted ? 'Unmute' : 'Mute',
                  icon: Icon(call.micMuted ? Icons.mic_off : Icons.mic_none, size: 20),
                  color: call.micMuted ? scheme.error : scheme.onSurfaceVariant,
                ),
            ],
          ),
          if (call.lastBriefing != null) ...[
            const SizedBox(height: 4),
            Text(call.lastBriefing!, style: const TextStyle(fontSize: 15, height: 1.35)),
          ],
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: body,
    );
  }
}

/// What Kabeer last asked the secretary to tell the caller, and whether she has.
/// Who the caller really is: verified by a personal link, or only a claim.
class _TrustLine extends StatelessWidget {
  final CallerTrust trust;

  const _TrustLine({required this.trust});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = StatusColors.of(context);
    final (icon, color) = switch (trust.level) {
      TrustLevel.verified => (Icons.verified_outlined, status.live),
      TrustLevel.warning => (Icons.warning_amber_rounded, scheme.error),
      _ => (Icons.help_outline, scheme.onSurfaceVariant),
    };
    final note = trust.note;
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(child: Text(trust.label, style: TextStyle(fontSize: 13, color: color))),
          ],
        ),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(
            note,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: trust.level == TrustLevel.warning ? scheme.error : scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _DirectiveLine extends StatelessWidget {
  final CallState call;

  const _DirectiveLine({required this.call});

  static String _failureText(String? reason) {
    switch (reason) {
      case 'call_not_connected':
      case 'unknown_call':
      case 'caller_socket_closed':
        return 'The caller is no longer connected';
      case 'interrupted_by_caller':
        return 'The caller interrupted. Try again';
      case 'timeout_no_agent_speech':
      case 'no_agent_transcript':
        return "Your secretary couldn't say it. Try again";
      default:
        return "Couldn't reach the caller";
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = call.directiveStatus == 'failed';
    final status = switch (call.directiveStatus) {
      'injected' => 'Your secretary is telling them',
      'spoken' => 'Told the caller',
      'failed' => _failureText(call.directiveError),
      _ => 'Sending',
    };
    return Column(
      children: [
        Text(
          call.activeDirective!,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 2),
        Text(
          status,
          style: TextStyle(fontSize: 12, color: failed ? scheme.error : scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Callers who rang during this call. The secretary is keeping them company;
/// they come up when this call ends.
class _WaitingStrip extends ConsumerWidget {
  const _WaitingStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = ref.watch(waitingCallersProvider);
    if (waiting.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final first = waiting.first;
    final label = waiting.length == 1
        ? 'Also calling: ${first.name}${first.reason != null ? ' · ${first.reason}' : ''}'
        : '${waiting.length} more callers waiting: ${waiting.map((c) => c.name).join(', ')}';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.call_outlined, size: 16, color: StatusColors.of(context).warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text('Next', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;

  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? StatusColors.of(context).live : Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

/// What was said on the secretary line (and Kabeer's own instructions).
class _Conversation extends StatelessWidget {
  final List<TranscriptEntry> entries;

  const _Conversation({required this.entries});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (entries.isEmpty) return const SizedBox.shrink();
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[entries.length - 1 - index];
        final speaker = switch (entry.speaker) {
          'Master' => 'You',
          'Secretary' => 'Secretary',
          _ => 'Caller',
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(speaker, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(entry.text, style: const TextStyle(fontSize: 15, height: 1.35)),
            ],
          ),
        );
      },
    );
  }
}

class _ScreeningActions extends ConsumerWidget {
  final CallState call;

  const _ScreeningActions({required this.call});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(callProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CallAction(
          icon: Icons.call,
          label: 'Connect',
          background: StatusColors.of(context).live,
          foreground: scheme.onPrimary,
          onTap: notifier.acceptAndPatch,
        ),
        _CallAction(icon: Icons.pause, label: 'Hold', onTap: () => _pickHold(context, notifier)),
        _CallAction(
          icon: Icons.chat_bubble_outline,
          label: 'Message',
          onTap: () => _composeMessage(context, notifier, call),
        ),
        _CallAction(
          icon: Icons.call_end,
          label: 'End',
          background: scheme.error,
          foreground: scheme.onError,
          onTap: notifier.endCall,
        ),
      ],
    );
  }

  void _pickHold(BuildContext context, CallNotifier notifier) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Ask the caller to hold for', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            for (final minutes in const [1, 2, 5, 10])
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(minutes == 1 ? '1 minute' : '$minutes minutes'),
                onTap: () {
                  Navigator.pop(context);
                  notifier.holdCall(minutes * 60);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _composeMessage(BuildContext context, CallNotifier notifier, CallState call) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MessageSheet(onSend: notifier.sendCustomDirective),
    );
  }
}

class _MessageSheet extends StatefulWidget {
  final void Function(String) onSend;

  const _MessageSheet({required this.onSend});

  @override
  State<_MessageSheet> createState() => _MessageSheetState();
}

class _MessageSheetState extends State<_MessageSheet> {
  final _controller = TextEditingController();

  static const _quickReplies = [
    "I'll call back in 15 minutes.",
    'Please send the details by email.',
    'Can this wait until tomorrow morning?',
    'Ask what this is regarding.',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send(String message) {
    final text = message.trim();
    if (text.isEmpty) return;
    Navigator.pop(context);
    widget.onSend(text);
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
              const Text('Tell the caller', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'Your secretary passes it on in her own words.',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reply in _quickReplies)
                    ActionChip(label: Text(reply), onPressed: () => _send(reply)),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: false,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                decoration: const InputDecoration(hintText: 'Or type a message'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: () => _send(_controller.text), child: const Text('Send')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatchedActions extends ConsumerWidget {
  final CallState call;

  const _PatchedActions({required this.call});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(callProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (call.bridgeLive)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Use earphones to avoid echo.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CallAction(
              icon: call.micMuted ? Icons.mic_off : Icons.mic_none,
              label: call.micMuted ? 'Unmute' : 'Mute',
              onTap: notifier.toggleMute,
            ),
            _CallAction(
              icon: Icons.call_end,
              label: 'Hang up',
              background: scheme.error,
              foreground: scheme.onError,
              onTap: notifier.hangUp,
            ),
          ],
        ),
      ],
    );
  }
}

class _CallAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? background;
  final Color? foreground;

  const _CallAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: background ?? scheme.surfaceContainer,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 60,
              height: 60,
              child: Icon(icon, color: foreground ?? scheme.onSurface),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
