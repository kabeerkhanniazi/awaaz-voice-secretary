import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/call_record_model.dart';
import '../models/secretary_task_model.dart';
import '../providers/dashboard_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/common.dart';
import '../widgets/reach_out.dart';
import 'call_records_tab.dart';

class CallDetailScreen extends ConsumerWidget {
  final String callId;

  const CallDetailScreen({super.key, required this.callId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final call = dashboard.callLogs.where((c) => c.id == callId).firstOrNull;
    if (call == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('This call was deleted.')));
    }
    final tasks = dashboard.tasksForCall(call.id);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final device = call.deviceId;
    final blocked = device != null && ref.watch(ownerProvider.select((o) => o.blocked.containsKey(device)));
    final hasReach = call.callbackNumber != null || call.callbackEmail != null ||
        call.bestTime != null || call.callerMessage != null;

    return Scaffold(
      appBar: AppBar(
        actions: [
          // Block the browser this call came from (web callers have no number)
          if (device != null)
            IconButton(
              tooltip: blocked ? 'Unblock this caller' : 'Block this caller',
              icon: Icon(blocked ? Icons.block : Icons.block_outlined, color: blocked ? scheme.error : null),
              onPressed: () {
                final owner = ref.read(ownerProvider.notifier);
                if (blocked) {
                  owner.unblock(device);
                  showMessage(context, 'Unblocked');
                } else {
                  owner.block(device, reason: 'spam', name: call.callerName);
                  showMessage(context, 'Blocked: calls from that browser will be refused');
                }
              },
            ),
          IconButton(
            tooltip: 'Delete call',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref, call),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
              children: [
                InitialAvatar(name: callerDisplayName(call), size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(callerDisplayName(call), style: text.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        '${dayLabel(call.timestamp)}, ${timeLabel(call.timestamp)} · ${durationLabel(call.durationSeconds)}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(call.actionStatus.label, style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          if (call.trust != null) _RecordTrust(trust: call.trust!, note: call.trustNote),

          if (hasReach) ...[
            const SectionHeader('How to reach them'),
            if (call.callbackNumber != null)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 20, right: 8),
                leading: const Icon(Icons.phone_outlined),
                title: Text(call.callbackNumber!),
                trailing: ReachOutButtons(number: call.callbackNumber),
              ),
            if (call.callbackEmail != null)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 20, right: 8),
                leading: const Icon(Icons.alternate_email),
                title: Text(call.callbackEmail!),
                trailing: ReachOutButtons(email: call.callbackEmail),
              ),
            if (call.bestTime != null)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: const Icon(Icons.schedule),
                title: Text('Best time: ${call.bestTime!}'),
              ),
            if (call.callerMessage != null)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: const Icon(Icons.notes),
                title: Text(call.callerMessage!),
              ),
          ],

          const SectionHeader('Summary'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(call.lemurSummary, style: const TextStyle(fontSize: 15, height: 1.4)),
          ),

          if (tasks.isNotEmpty) ...[
            const SectionHeader('Tasks'),
            for (final task in tasks) _TaskRow(task: task),
          ],

          const SectionHeader('Conversation'),
          if (call.transcript.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('No conversation was recorded.', style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          else
            for (final entry in call.transcript) _TranscriptRow(entry: entry),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, CallRecordModel call) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this call?'),
        content: const Text('Its summary and conversation will be removed. Tasks stay in your list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    ref.read(dashboardProvider.notifier).deleteCallLog(call.id);
    Navigator.of(context).pop();
  }
}

/// The trust verdict as it stood when the call ended.
class _RecordTrust extends StatelessWidget {
  final String trust;
  final String? note;

  const _RecordTrust({required this.trust, this.note});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (trust) {
      'verified' => ('Verified by their personal link', scheme.primary),
      'recognised' => ('Not verified · called before from this browser', scheme.onSurfaceVariant),
      'warning' => ('Warning', scheme.error),
      _ => ('Not verified: the name is what the caller said', scheme.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Text(note == null ? label : '$label · $note', style: TextStyle(fontSize: 13, color: color)),
    );
  }
}

class _TaskRow extends ConsumerWidget {
  final SecretaryTaskModel task;

  const _TaskRow({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CheckboxListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      controlAffinity: ListTileControlAffinity.leading,
      value: task.isCompleted,
      onChanged: (_) => ref.read(dashboardProvider.notifier).toggleTaskCompletion(task.id),
      title: Text(
        task.actionItem,
        style: TextStyle(decoration: task.isCompleted ? TextDecoration.lineThrough : null),
      ),
      secondary: ReachOutButtons(number: task.phoneNumber, email: task.email, dense: true),
    );
  }
}

class _TranscriptRow extends StatelessWidget {
  final TranscriptEntry entry;

  const _TranscriptRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final speaker = switch (entry.speaker) {
      'Master' => 'You',
      'Secretary' => 'Secretary',
      _ => 'Caller',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.timeOffset.isEmpty ? speaker : '$speaker · ${entry.timeOffset}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(entry.text, style: const TextStyle(fontSize: 15, height: 1.35)),
        ],
      ),
    );
  }
}
