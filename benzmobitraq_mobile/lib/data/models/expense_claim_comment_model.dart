import 'package:equatable/equatable.dart';

/// Comment/message on an expense claim (for chat functionality)
class ExpenseClaimComment extends Equatable {
  final int id;
  final String claimId;
  final String authorId;
  final String body;
  final bool isInternal; // Admin-only notes
  final DateTime createdAt;
  
  // Optional fields populated from joins
  final String? authorName;
  final String? authorRole;

  const ExpenseClaimComment({
    required this.id,
    required this.claimId,
    required this.authorId,
    required this.body,
    this.isInternal = false,
    required this.createdAt,
    this.authorName,
    this.authorRole,
  });

  factory ExpenseClaimComment.fromJson(Map<String, dynamic> json) {
    return ExpenseClaimComment(
      id: json['id'] as int,
      claimId: json['claim_id'] as String,
      authorId: json['author_id'] as String,
      body: json['body'] as String,
      isInternal: json['is_internal'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      authorName: json['author_name'] as String?,
      authorRole: json['author_role'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'claim_id': claimId,
    'author_id': authorId,
    'body': body,
    'is_internal': isInternal,
    'created_at': createdAt.toIso8601String(),
  };
  
  /// Create a new comment (without ID for insertion)
  Map<String, dynamic> toInsertJson() => {
    'claim_id': claimId,
    'author_id': authorId,
    'body': body,
    'is_internal': isInternal,
  };

  @override
  List<Object?> get props => [
    id,
    claimId,
    authorId,
    body,
    isInternal,
    createdAt,
    authorName,
    authorRole,
  ];
}
