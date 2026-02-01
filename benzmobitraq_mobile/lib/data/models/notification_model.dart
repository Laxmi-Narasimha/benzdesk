import 'package:equatable/equatable.dart';

/// Notification model for in-app and push notifications
class NotificationModel extends Equatable {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final String? recipientId;
  final String? recipientRole;
  final bool isRead;
  final bool isPushed;
  final DateTime? pushSentAt;
  final String? relatedEmployeeId;
  final String? relatedSessionId;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    this.recipientId,
    this.recipientRole,
    this.isRead = false,
    this.isPushed = false,
    this.pushSentAt,
    this.relatedEmployeeId,
    this.relatedSessionId,
    required this.createdAt,
  });

  /// Create from JSON map (Supabase response)
  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String,
      type: NotificationType.fromString(json['type'] as String),
      title: json['title'] as String,
      body: json['body'] as String,
      data: (json['data'] as Map<String, dynamic>?) ?? {},
      recipientId: json['recipient_id'] as String?,
      recipientRole: json['recipient_role'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      isPushed: json['is_pushed'] as bool? ?? false,
      pushSentAt: json['push_sent_at'] != null
          ? DateTime.parse(json['push_sent_at'] as String)
          : null,
      relatedEmployeeId: json['related_employee_id'] as String?,
      relatedSessionId: json['related_session_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.value,
      'title': title,
      'body': body,
      'data': data,
      'recipient_id': recipientId,
      'recipient_role': recipientRole,
      'is_read': isRead,
      'is_pushed': isPushed,
      'push_sent_at': pushSentAt?.toIso8601String(),
      'related_employee_id': relatedEmployeeId,
      'related_session_id': relatedSessionId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Create a copy with modified fields
  NotificationModel copyWith({
    String? id,
    NotificationType? type,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    String? recipientId,
    String? recipientRole,
    bool? isRead,
    bool? isPushed,
    DateTime? pushSentAt,
    String? relatedEmployeeId,
    String? relatedSessionId,
    DateTime? createdAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      recipientId: recipientId ?? this.recipientId,
      recipientRole: recipientRole ?? this.recipientRole,
      isRead: isRead ?? this.isRead,
      isPushed: isPushed ?? this.isPushed,
      pushSentAt: pushSentAt ?? this.pushSentAt,
      relatedEmployeeId: relatedEmployeeId ?? this.relatedEmployeeId,
      relatedSessionId: relatedSessionId ?? this.relatedSessionId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Check if this is a stuck alert
  bool get isStuckAlert => type == NotificationType.stuckAlert;

  @override
  List<Object?> get props => [
        id,
        type,
        title,
        body,
        data,
        recipientId,
        recipientRole,
        isRead,
        isPushed,
        pushSentAt,
        relatedEmployeeId,
        relatedSessionId,
        createdAt,
      ];
}

/// Notification type enum
enum NotificationType {
  stuckAlert('stuck_alert'),
  expenseSubmitted('expense_submitted'),
  expenseApproved('expense_approved'),
  expenseRejected('expense_rejected'),
  sessionStarted('session_started'),
  sessionEnded('session_ended');

  final String value;

  const NotificationType(this.value);

  static NotificationType fromString(String value) {
    return NotificationType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => NotificationType.stuckAlert,
    );
  }

  String get displayName {
    switch (this) {
      case NotificationType.stuckAlert:
        return 'Stuck Alert';
      case NotificationType.expenseSubmitted:
        return 'Expense Submitted';
      case NotificationType.expenseApproved:
        return 'Expense Approved';
      case NotificationType.expenseRejected:
        return 'Expense Rejected';
      case NotificationType.sessionStarted:
        return 'Session Started';
      case NotificationType.sessionEnded:
        return 'Session Ended';
    }
  }
}
