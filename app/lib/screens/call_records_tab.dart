import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/call_record_model.dart';
import '../core/theme/app_theme.dart';
import '../providers/dashboard_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/common.dart';
import '../widgets/demo_line_card.dart';
import 'call_detail_screen.dart';
import 'settings_tab.dart' show showAvailabilitySheet;

class CallRecordsTab extends ConsumerStatefulWidget {
  const CallRecordsTab({super.key});

  @override
  ConsumerState<CallRecordsTab> createState() => _CallRecordsTabState();
}

class _CallRecordsTabState extends ConsumerState<CallRecordsTab> {
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardProvider);
    final notifier = ref.read(dashboardProvider.notifier);

    var calls = dashboard.filteredCallLogs;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      calls = calls
          .where((c) =>
              c.callerName.toLowerCase().contains(q) ||
              c.lemurSummary.toLowerCase().contains(q) ||
              c.transcript.any((t) => t.text.toLowerCase().contains(q)))
          .toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: const InputDecoration(
                  hintText: 'Search calls',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              )
            : const Text('Calls'),
        actions: [
          // One tap to go busy or do-not-disturb; the secretary takes messages
          Consumer(builder: (context, ref, _) {
            final away = ref.watch(ownerProvider.select((o) => o.availability)).isAwayAt(DateTime.now());
            return IconButton(
              tooltip: away ? "You're away" : 'Available',
              icon: Icon(
                away ? Icons.do_not_disturb_on_outlined : Icons.check_circle_outline,
                color: away ? StatusColors.of(context).warning : null,
              ),
              onPressed: () => showAvailabilitySheet(context, ref),
            );
          }),
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _searchController.clear();
                _query = '';
              }
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          const DemoLineCard(),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final filter in CallFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(filter.label),
                      selected: dashboard.activeFilter == filter,
                      onSelected: (_) => notifier.setFilter(filter),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: calls.isEmpty
                ? EmptyState(
                    icon: Icons.call_outlined,
                    title: dashboard.callLogs.isEmpty ? 'No calls yet' : 'Nothing here',
                    message: dashboard.callLogs.isEmpty
                        ? 'Calls your secretary answers will appear here.'
                        : 'No calls match this filter.',
                  )
                : _CallList(calls: calls),
          ),
        ],
      ),
    );
  }
}

class _CallList extends StatelessWidget {
  final List<CallRecordModel> calls;

  const _CallList({required this.calls});

  @override
  Widget build(BuildContext context) {
    // Flatten into day headers and rows
    final items = <Object>[];
    String? currentDay;
    for (final call in calls) {
      final day = dayLabel(call.timestamp);
      if (day != currentDay) {
        items.add(day);
        currentDay = day;
      }
      items.add(call);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is String) return SectionHeader(item);
        return _CallRow(call: item as CallRecordModel);
      },
    );
  }
}

class _CallRow extends StatelessWidget {
  final CallRecordModel call;

  const _CallRow({required this.call});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spam = call.actionStatus == CallActionStatus.declinedSpam;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: InitialAvatar(name: callerDisplayName(call)),
      title: Text(
        callerDisplayName(call),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w500, color: spam ? scheme.onSurfaceVariant : null),
      ),
      subtitle: Text(
        call.lemurSummary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(timeLabel(call.timestamp), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(call.actionStatus.label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CallDetailScreen(callId: call.id)),
      ),
    );
  }
}

/// Caller names from web calls that never gave a name are shown as unknown.
String callerDisplayName(CallRecordModel call) {
  final name = call.callerName.trim();
  return (name.isEmpty || name == 'Web Caller') ? 'Unknown caller' : name;
}
