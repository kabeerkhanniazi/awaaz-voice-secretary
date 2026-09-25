import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/secretary_task_model.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/common.dart';
import '../widgets/reach_out.dart';

class SecretaryTasksTab extends ConsumerStatefulWidget {
  const SecretaryTasksTab({super.key});

  @override
  ConsumerState<SecretaryTasksTab> createState() => _SecretaryTasksTabState();
}

class _SecretaryTasksTabState extends ConsumerState<SecretaryTasksTab> {
  bool _showCompleted = false;

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(dashboardProvider.select((s) => s.tasks));
    final open = tasks.where((t) => !t.isCompleted).toList()
      ..sort((a, b) {
        // Dated tasks first, soonest (or overdue) first; then priority; then newest
        if (a.dueDate != null || b.dueDate != null) {
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          final byDue = a.dueDate!.compareTo(b.dueDate!);
          if (byDue != 0) return byDue;
        }
        final byPriority = a.priority.index.compareTo(b.priority.index);
        return byPriority != 0 ? byPriority : b.createdAt.compareTo(a.createdAt);
      });
    final done = tasks.where((t) => t.isCompleted).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add task',
        onPressed: () => _addTask(context),
        child: const Icon(Icons.add),
      ),
      body: tasks.isEmpty
          ? const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'No tasks',
              message: 'Ask your secretary to remind you of something during a call, or add one here.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (open.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Text('All done.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                for (final task in open) _TaskTile(task: task),
                if (done.isNotEmpty) ...[
                  SectionHeader(
                    'Completed (${done.length})',
                    trailing: TextButton(
                      onPressed: () => setState(() => _showCompleted = !_showCompleted),
                      child: Text(_showCompleted ? 'Hide' : 'Show'),
                    ),
                  ),
                  if (_showCompleted) for (final task in done) _TaskTile(task: task),
                ],
              ],
            ),
    );
  }

  void _addTask(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _AddTaskSheet(),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  final SecretaryTaskModel task;

  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(dashboardProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final details = [
      if (task.callerName.isNotEmpty && task.callerName != 'Web Caller') task.callerName,
      dayLabel(task.createdAt),
    ].join(' · ');

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: scheme.error,
        child: Icon(Icons.delete_outline, color: scheme.onError),
      ),
      onDismissed: (_) {
        final index = ref.read(dashboardProvider).tasks.indexWhere((t) => t.id == task.id);
        notifier.deleteTask(task.id);
        showMessage(
          context,
          'Task deleted',
          action: SnackBarAction(label: 'Undo', onPressed: () => notifier.restoreTask(task, index)),
        );
      },
      child: CheckboxListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        controlAffinity: ListTileControlAffinity.leading,
        value: task.isCompleted,
        onChanged: (_) => notifier.toggleTaskCompletion(task.id),
        title: Text(
          task.actionItem,
          style: TextStyle(
            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            color: task.isCompleted ? scheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: Text.rich(
          TextSpan(children: [
            if (task.dueDate != null && !task.isCompleted)
              TextSpan(
                text: '${dueLabel(task.dueDate!)} · ',
                style: TextStyle(color: isOverdue(task.dueDate!) ? scheme.error : scheme.onSurface),
              ),
            if (task.priority == TaskPriority.high && !task.isCompleted)
              TextSpan(text: 'Important · ', style: TextStyle(color: scheme.error)),
            TextSpan(text: details),
          ]),
        ),
        // Call-back tasks: one tap to dial, WhatsApp or email them
        secondary: task.isCompleted ? null : ReachOutButtons(number: task.phoneNumber, email: task.email, dense: true),
      ),
    );
  }
}

class _AddTaskSheet extends ConsumerStatefulWidget {
  const _AddTaskSheet();

  @override
  ConsumerState<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends ConsumerState<_AddTaskSheet> {
  final _controller = TextEditingController();
  bool _important = false;
  DateTime? _due;

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now.add(const Duration(days: 1)),
      firstDate: DateUtils.dateOnly(now),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _due = picked);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(dashboardProvider.notifier).addTask(SecretaryTaskModel(
      id: const Uuid().v4(),
      callRecordId: 'manual',
      callerName: '',
      actionItem: text,
      priority: _important ? TaskPriority.high : TaskPriority.medium,
      createdAt: DateTime.now(),
      dueDate: _due,
    ));
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
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(hintText: 'What needs doing?'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Due date'),
                subtitle: Text(_due == null ? 'None' : dueLabel(_due!)),
                trailing: _due == null
                    ? const Icon(Icons.event_outlined)
                    : IconButton(
                        tooltip: 'Remove due date',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _due = null),
                      ),
                onTap: _pickDue,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Important'),
                value: _important,
                onChanged: (value) => setState(() => _important = value),
              ),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const Text('Add task'))),
            ],
          ),
        ),
      ),
    );
  }
}
