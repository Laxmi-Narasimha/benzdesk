import 'package:equatable/equatable.dart';

/// Simple expense model for quick expense submission
/// This is a simplified wrapper for single-item expense claims
class ExpenseModel extends Equatable {
  final String? id;
  final String employeeId;
  final String category;
  final double amount;
  final String? description;
  final DateTime expenseDate;
  final String status;
  final String? receiptPath;
  final DateTime? createdAt;
  final DateTime? submittedAt;

  const ExpenseModel({
    this.id,
    required this.employeeId,
    required this.category,
    required this.amount,
    this.description,
    required this.expenseDate,
    this.status = 'pending',
    this.receiptPath,
    this.createdAt,
    this.submittedAt,
  });

  /// Create from JSON
  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    return ExpenseModel(
      id: json['id'] as String?,
      employeeId: json['employee_id'] as String,
      category: json['category'] as String,
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] as String?,
      expenseDate: DateTime.parse(json['expense_date'] as String),
      status: json['status'] as String? ?? 'pending',
      receiptPath: json['receipt_path'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      submittedAt: json['submitted_at'] != null
          ? DateTime.parse(json['submitted_at'] as String)
          : null,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'employee_id': employeeId,
      'category': category,
      'amount': amount,
      'description': description,
      'expense_date': expenseDate.toIso8601String().split('T')[0],
      'status': status,
      'receipt_path': receiptPath,
    };
  }

  ExpenseModel copyWith({
    String? id,
    String? employeeId,
    String? category,
    double? amount,
    String? description,
    DateTime? expenseDate,
    String? status,
    String? receiptPath,
    DateTime? createdAt,
    DateTime? submittedAt,
  }) {
    return ExpenseModel(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      expenseDate: expenseDate ?? this.expenseDate,
      status: status ?? this.status,
      receiptPath: receiptPath ?? this.receiptPath,
      createdAt: createdAt ?? this.createdAt,
      submittedAt: submittedAt ?? this.submittedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        employeeId,
        category,
        amount,
        description,
        expenseDate,
        status,
        receiptPath,
        createdAt,
        submittedAt,
      ];
}
