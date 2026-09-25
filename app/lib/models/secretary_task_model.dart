enum TaskPriority { high, medium, low }

extension TaskPriorityExtension on TaskPriority {
  String get label {
    switch (this) {
      case TaskPriority.high:
        return 'High Priority';
      case TaskPriority.medium:
        return 'Medium';
      case TaskPriority.low:
        return 'Low';
    }
  }
}

class SecretaryTaskModel {
  final String id;
  final String callRecordId;
  final String callerName;
  final String actionItem;
  final TaskPriority priority;
  final DateTime createdAt;
  final DateTime? dueDate;
  // For "call back" tasks: how to reach them, so the task can dial or write
  final String? phoneNumber;
  final String? email;
  bool isCompleted;

  SecretaryTaskModel({
    required this.id,
    required this.callRecordId,
    required this.callerName,
    required this.actionItem,
    required this.priority,
    required this.createdAt,
    this.dueDate,
    this.phoneNumber,
    this.email,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'callRecordId': callRecordId,
      'callerName': callerName,
      'actionItem': actionItem,
      'priority': priority.name,
      'createdAt': createdAt.toIso8601String(),
      'dueDate': dueDate?.toIso8601String(),
      'phoneNumber': phoneNumber,
      'email': email,
      'isCompleted': isCompleted,
    };
  }

  factory SecretaryTaskModel.fromJson(Map<String, dynamic> json) {
    return SecretaryTaskModel(
      id: json['id'] as String,
      callRecordId: json['callRecordId'] as String,
      callerName: json['callerName'] as String,
      actionItem: json['actionItem'] as String,
      priority: TaskPriority.values.firstWhere(
        (e) => e.name == json['priority'],
        orElse: () => TaskPriority.medium,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate'] as String) : null,
      phoneNumber: json['phoneNumber'] as String?,
      email: json['email'] as String?,
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecretaryTaskModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          callRecordId == other.callRecordId &&
          callerName == other.callerName &&
          actionItem == other.actionItem &&
          priority == other.priority &&
          createdAt == other.createdAt &&
          dueDate == other.dueDate &&
          isCompleted == other.isCompleted;

  @override
  int get hashCode => Object.hash(
        id,
        callRecordId,
        callerName,
        actionItem,
        priority,
        createdAt,
        dueDate,
        isCompleted,
      );
}
