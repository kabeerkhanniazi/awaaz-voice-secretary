import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../providers/call_provider.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/call_screen.dart';
import 'call_records_tab.dart';
import 'contacts_tab.dart';
import 'secretary_tasks_tab.dart';
import 'settings_tab.dart';

/// Home: Calls, Tasks, Contacts, Settings. An active call takes over the
/// screen like a phone call and can be minimised to a bar at the top.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _currentIndex = 0;
  bool _callMinimized = false;

  static const _tabs = [
    CallRecordsTab(),
    SecretaryTasksTab(),
    ContactsTab(),
    SettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final pendingCount = ref.watch(dashboardProvider.select((s) => s.pendingTaskCount));
    final call = ref.watch(callProvider);
    final callActive = call.status != ActiveCallStatus.idle;

    // A new call opens full screen, unless it's a quiet one (Kabeer is away, or
    // a "never ring" contact): then it stays a bar at the top until he opens it
    ref.listen(callProvider.select((s) => s.currentCallId), (previous, next) {
      if (next != null && next != previous) {
        setState(() => _callMinimized = ref.read(callProvider).quiet != null);
      }
    });

    return Stack(
      children: [
        Scaffold(
          body: Column(
            children: [
              if (callActive && _callMinimized) _ReturnToCallBar(call: call, onTap: _expandCall),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: callActive && _callMinimized,
                  child: IndexedStack(index: _currentIndex, children: _tabs),
                ),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) => setState(() => _currentIndex = index),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.call_outlined),
                selectedIcon: Icon(Icons.call),
                label: 'Calls',
              ),
              NavigationDestination(
                icon: Badge(
                  label: Text('$pendingCount'),
                  isLabelVisible: pendingCount > 0,
                  child: const Icon(Icons.check_circle_outline),
                ),
                selectedIcon: Badge(
                  label: Text('$pendingCount'),
                  isLabelVisible: pendingCount > 0,
                  child: const Icon(Icons.check_circle),
                ),
                label: 'Tasks',
              ),
              const NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Contacts',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !callActive || _callMinimized,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: callActive && !_callMinimized
                  ? CallScreen(key: const ValueKey('call'), onMinimize: () => setState(() => _callMinimized = true))
                  : const SizedBox.shrink(key: ValueKey('none')),
            ),
          ),
        ),
      ],
    );
  }

  void _expandCall() => setState(() => _callMinimized = false);
}

class _ReturnToCallBar extends StatelessWidget {
  final CallState call;
  final VoidCallback onTap;

  const _ReturnToCallBar({required this.call, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final live = StatusColors.of(context).live;
    final name = call.callerUnknown ? 'Unknown caller' : call.activeScenario?.callerName ?? '';
    final status = switch (call.status) {
      ActiveCallStatus.holding => 'On hold',
      ActiveCallStatus.masterPatched => call.bridgeLive ? 'On the call' : 'Connecting',
      ActiveCallStatus.callEnded => 'Ended',
      _ => 'Secretary answering',
    };
    return Material(
      color: live,
      child: InkWell(
        onTap: onTap,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.call, size: 18, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$name · $status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
                const Text('Return', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
