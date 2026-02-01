import 'package:equatable/equatable.dart';

/// Event types for expense claim audit trail
enum ExpenseEventType {
  created('created'),
  submitted('submitted'),
  commentAdded('comment_added'),
  statusChanged('status_changed'),
  assigned('assigned'),
  approved('approved'),
  rejected('rejected'),
  attachmentAdded('attachment_added'),
  attachmentRemoved('attachment_removed');

  final String value;
  const ExpenseEventType(this.value);

  static ExpenseEventType fromString(String value) {
    return ExpenseEventType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ExpenseEventType.created,
    );
  }
}

/// Audit log event for expense claim
class ExpenseClaimEvent extends Equatable {
  final int id;
  final String claimId;
  final String actorId;
  final ExpenseEventType eventType;
  final Map<String, dynamic> oldData;
  final Map<String, dynamic> newData;
  final String? note;
  final DateTime createdAt;
  
  // Optional fields from joins
  final String? actorName;
  final String? actorRole;

  const ExpenseClaimEvent({
    required this.id,
    required this.claimId,
    required this.actorId,
    required this.eventType,
    this.oldData = const {},
    this.newData = const {},
    this.note,
    required this.createdAt,
    this.actorName,
    this.actorRole,
  });

  factory ExpenseClaimEvent.fromJson(Map<String, dynamic> json) {
    return ExpenseClaimEvent(
      id: json['id'] as int,
      claimId: json['claim_id'] as String,
      actorId: json['actor_id'] as String,
      eventType: ExpenseEventType.fromString(json['event_type'] as String),
      oldData: (json['old_data'] as Map<String, dynamic>?) ?? {},
      newData: (json['new_data'] as Map<String, dynamic>?) ?? {},
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      actorName: json['actor_name'] as String?,
      actorRole: json['actor_role'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'claim_id': claimId,
    'actor_id': actorId,
    'event_type': eventType.value,
    'old_data': oldData,
    'new_data': newData,
    'note': note,
    'created_at': createdAt.toIso8601String(),
  };

  /// Get a human-readable description of this event
  String getDescription() {
    switch (eventType) {
      case ExpenseEventType.created:
        return 'Claim created';
      case ExpenseEventType.submitted:
        return 'Submitted for review';
      case ExpenseEventType.commentAdded:
        return 'Added a comment';
      case ExpenseEventType.statusChanged:
        final oldStatus = oldData['status'] ?? 'unknown';
        final newStatus = newData['status'] ?? 'unknown';
        return 'Status changed from $oldStatus to $newStatus';
      case ExpenseEventType.assigned:
        return 'Assigned to admin';
      case ExpenseEventType.approved:
        return 'Claim approved';
      case ExpenseEventType.rejected:
        final reason = note ?? 'No reason provided';
        return 'Claim rejected: $reason';
      case ExpenseEventType.attachmentAdded:
        return 'Added an attachment';
      case ExpenseEventType.attachmentRemoved:
        return 'Removed an attachment';
    }
  }

  @override
  List<Object?> get props => [
    id,
    claimId,
    actorId,
    eventType,
    oldData,
    newData,
    note,
    createdAt,
    actorName,
    actorRole,
  ];
}
