import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/call_record_model.dart';
import '../models/secretary_task_model.dart';
import 'storage_provider.dart';

/// Call list filters.
enum CallFilter { all, talked, handled, spam }

extension CallFilterLabel on CallFilter {
  String get label {
    switch (this) {
      case CallFilter.all:
        return 'All';
      case CallFilter.talked:
        return 'You talked';
      case CallFilter.handled:
        return 'Handled';
      case CallFilter.spam:
        return 'Spam';
    }
  }
}

class DashboardState {
  final List<CallRecordModel> callLogs;
  final List<SecretaryTaskModel> tasks;
  final CallFilter activeFilter;

  DashboardState({
    this.callLogs = const [],
    this.tasks = const [],
    this.activeFilter = CallFilter.all,
  });

  DashboardState copyWith({
    List<CallRecordModel>? callLogs,
    List<SecretaryTaskModel>? tasks,
    CallFilter? activeFilter,
  }) {
    return DashboardState(
      callLogs: callLogs ?? this.callLogs,
      tasks: tasks ?? this.tasks,
      activeFilter: activeFilter ?? this.activeFilter,
    );
  }

  List<CallRecordModel> get filteredCallLogs {
    switch (activeFilter) {
      case CallFilter.talked:
        return callLogs.where((c) => c.actionStatus == CallActionStatus.patchedToMaster).toList();
      case CallFilter.handled:
        return callLogs
            .where((c) =>
                c.actionStatus == CallActionStatus.secretaryResolved ||
                c.actionStatus == CallActionStatus.heldAndDeferred)
            .toList();
      case CallFilter.spam:
        return callLogs.where((c) => c.actionStatus == CallActionStatus.declinedSpam).toList();
      case CallFilter.all:
        return callLogs;
    }
  }

  int get pendingTaskCount => tasks.where((t) => !t.isCompleted).length;

  List<SecretaryTaskModel> tasksForCall(String callId) =>
      tasks.where((t) => t.callRecordId == callId).toList();
}

class DashboardNotifier extends Notifier<DashboardState> {
  @override
  DashboardState build() {
    final storage = ref.read(storageServiceProvider);
    return DashboardState(callLogs: storage.getCallLogs(), tasks: storage.getTasks());
  }

  void setFilter(CallFilter filter) {
    state = state.copyWith(activeFilter: filter);
  }

  void addCallLog(CallRecordModel record) {
    final updatedLogs = [record, ...state.callLogs];
    state = state.copyWith(callLogs: updatedLogs);
    ref.read(storageServiceProvider).saveCallLogs(updatedLogs);
  }

  void deleteCallLog(String callId) {
    final updatedLogs = state.callLogs.where((c) => c.id != callId).toList();
    state = state.copyWith(callLogs: updatedLogs);
    ref.read(storageServiceProvider).saveCallLogs(updatedLogs);
  }

  void addTask(SecretaryTaskModel task) {
    final updatedTasks = [task, ...state.tasks];
    state = state.copyWith(tasks: updatedTasks);
    ref.read(storageServiceProvider).saveTasks(updatedTasks);
  }

  /// Puts back a task removed by mistake (undo), at its old position.
  void restoreTask(SecretaryTaskModel task, int index) {
    final updatedTasks = [...state.tasks]..insert(index.clamp(0, state.tasks.length), task);
    state = state.copyWith(tasks: updatedTasks);
    ref.read(storageServiceProvider).saveTasks(updatedTasks);
  }

  void toggleTaskCompletion(String taskId) {
    final updatedTasks = state.tasks.map((t) {
      if (t.id == taskId) {
        return SecretaryTaskModel(
          id: t.id,
          callRecordId: t.callRecordId,
          callerName: t.callerName,
          actionItem: t.actionItem,
          priority: t.priority,
          createdAt: t.createdAt,
          dueDate: t.dueDate,
          isCompleted: !t.isCompleted,
        );
      }
      return t;
    }).toList();

    state = state.copyWith(tasks: updatedTasks);
    ref.read(storageServiceProvider).saveTasks(updatedTasks);
  }

  void deleteTask(String taskId) {
    final updatedTasks = state.tasks.where((t) => t.id != taskId).toList();
    state = state.copyWith(tasks: updatedTasks);
    ref.read(storageServiceProvider).saveTasks(updatedTasks);
  }
}

final dashboardProvider = NotifierProvider<DashboardNotifier, DashboardState>(DashboardNotifier.new);
