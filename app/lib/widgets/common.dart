import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Circle with a person's initial, or a person icon when there's no name.
class InitialAvatar extends StatelessWidget {
  final String? name;
  final double size;

  const InitialAvatar({super.key, required this.name, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = name?.trim() ?? '';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: scheme.surfaceContainer, shape: BoxShape.circle),
      child: trimmed.isEmpty
          ? Icon(Icons.person_outline, size: size * 0.5, color: scheme.onSurfaceVariant)
          : Text(
              trimmed.characters.first.toUpperCase(),
              style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
    );
  }
}

/// Small muted heading above a group of rows.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const EmptyState({super.key, required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Today", "Yesterday", weekday for the last week, otherwise a date.
String dayLabel(DateTime time, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(time);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return DateFormat('EEEE').format(time);
  if (day.year == today.year) return DateFormat('d MMMM').format(time);
  return DateFormat('d MMMM y').format(time);
}

String timeLabel(DateTime time) => DateFormat('h:mm a').format(time);

/// "Due today", "Due tomorrow", "Due Friday", "Due 3 Oct", or "Overdue since 2 Oct".
String dueLabel(DateTime due, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(due);
  final diff = day.difference(today).inDays;
  if (diff < 0) return 'Overdue since ${DateFormat('d MMM').format(due)}';
  if (diff == 0) return 'Due today';
  if (diff == 1) return 'Due tomorrow';
  if (diff < 7) return 'Due ${DateFormat('EEEE').format(due)}';
  return 'Due ${DateFormat('d MMM').format(due)}';
}

bool isOverdue(DateTime due, {DateTime? now}) =>
    DateUtils.dateOnly(due).isBefore(DateUtils.dateOnly(now ?? DateTime.now()));

/// "12 sec", "3 min", "1 h 5 min".
String durationLabel(int seconds) {
  if (seconds < 60) return '$seconds sec';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min';
  final rest = minutes % 60;
  return rest == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h $rest min';
}

/// "m:ss" for timers.
String clockLabel(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

void showMessage(BuildContext context, String text, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: action));
}
