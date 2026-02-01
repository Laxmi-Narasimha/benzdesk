import 'package:equatable/equatable.dart';

/// Expense claim model representing a collection of expense items
class ExpenseClaimModel extends Equatable {
  final String id;
  final String employeeId;
  final DateTime claimDate;
  final double totalAmount;
  final ExpenseStatus status;
  final String? notes;
  final String? rejectionReason;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Related data (populated when fetching with joins)
  final List<ExpenseItemModel>? items;
  final String? employeeName;

  const ExpenseClaimModel({
    required this.id,
    required this.employeeId,
    required this.claimDate,
    this.totalAmount = 0.0,
    this.status = ExpenseStatus.draft,
    this.notes,
    this.rejectionReason,
    this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
    required this.createdAt,
    required this.updatedAt,
    this.items,
    this.employeeName,
  });

  /// Create from JSON map (Supabase response)
  factory ExpenseClaimModel.fromJson(Map<String, dynamic> json) {
    List<ExpenseItemModel>? items;
    if (json['expense_items'] != null) {
      items = (json['expense_items'] as List<dynamic>)
          .map((e) => ExpenseItemModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return ExpenseClaimModel(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      claimDate: DateTime.parse(json['claim_date'] as String),
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      status: ExpenseStatus.fromString(json['status'] as String? ?? 'draft'),
      notes: json['notes'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      submittedAt: json['submitted_at'] != null
          ? DateTime.parse(json['submitted_at'] as String)
          : null,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      reviewedBy: json['reviewed_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      items: items,
      employeeName: json['employees']?['name'] as String?,
    );
  }

  /// Convert to JSON map for Supabase
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employee_id': employeeId,
      'claim_date': claimDate.toIso8601String().split('T')[0],
      'total_amount': totalAmount,
      'status': status.value,
      'notes': notes,
      'rejection_reason': rejectionReason,
      'submitted_at': submittedAt?.toIso8601String(),
      'reviewed_at': reviewedAt?.toIso8601String(),
      'reviewed_by': reviewedBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a new expense claim
  factory ExpenseClaimModel.create({
    required String id,
    required String employeeId,
    DateTime? claimDate,
    String? notes,
  }) {
    final now = DateTime.now();
    return ExpenseClaimModel(
      id: id,
      employeeId: employeeId,
      claimDate: claimDate ?? now,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Create a copy with modified fields
  ExpenseClaimModel copyWith({
    String? id,
    String? employeeId,
    DateTime? claimDate,
    double? totalAmount,
    ExpenseStatus? status,
    String? notes,
    String? rejectionReason,
    DateTime? submittedAt,
    DateTime? reviewedAt,
    String? reviewedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ExpenseItemModel>? items,
    String? employeeName,
  }) {
    return ExpenseClaimModel(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      claimDate: claimDate ?? this.claimDate,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      submittedAt: submittedAt ?? this.submittedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      items: items ?? this.items,
      employeeName: employeeName ?? this.employeeName,
    );
  }

  /// Check if claim can be edited
  bool get canEdit => status == ExpenseStatus.draft;

  /// Check if claim can be submitted
  bool get canSubmit => status == ExpenseStatus.draft && totalAmount > 0;

  @override
  List<Object?> get props => [
        id,
        employeeId,
        claimDate,
        totalAmount,
        status,
        notes,
        rejectionReason,
        submittedAt,
        reviewedAt,
        reviewedBy,
        createdAt,
        updatedAt,
        items,
        employeeName,
      ];
}

/// Expense item model representing a single expense entry
class ExpenseItemModel extends Equatable {
  final String id;
  final String claimId;
  final ExpenseCategory category;
  final double amount;
  final String? description;
  final String? merchant;
  final String? receiptPath;
  final DateTime expenseDate;
  final DateTime createdAt;

  const ExpenseItemModel({
    required this.id,
    required this.claimId,
    required this.category,
    required this.amount,
    this.description,
    this.merchant,
    this.receiptPath,
    required this.expenseDate,
    required this.createdAt,
  });

  /// Create from JSON map (Supabase response)
  factory ExpenseItemModel.fromJson(Map<String, dynamic> json) {
    return ExpenseItemModel(
      id: json['id'] as String,
      claimId: json['claim_id'] as String,
      category: ExpenseCategory.fromString(json['category'] as String),
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] as String?,
      merchant: json['merchant'] as String?,
      receiptPath: json['receipt_path'] as String?,
      expenseDate: DateTime.parse(json['expense_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Convert to JSON map for Supabase
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'claim_id': claimId,
      'category': category.value,
      'amount': amount,
      'description': description,
      'merchant': merchant,
      'receipt_path': receiptPath,
      'expense_date': expenseDate.toIso8601String().split('T')[0],
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Create a new expense item
  factory ExpenseItemModel.create({
    required String id,
    required String claimId,
    required ExpenseCategory category,
    required double amount,
    String? description,
    String? merchant,
    String? receiptPath,
    DateTime? expenseDate,
  }) {
    final now = DateTime.now();
    return ExpenseItemModel(
      id: id,
      claimId: claimId,
      category: category,
      amount: amount,
      description: description,
      merchant: merchant,
      receiptPath: receiptPath,
      expenseDate: expenseDate ?? now,
      createdAt: now,
    );
  }

  /// Create a copy with modified fields
  ExpenseItemModel copyWith({
    String? id,
    String? claimId,
    ExpenseCategory? category,
    double? amount,
    String? description,
    String? merchant,
    String? receiptPath,
    DateTime? expenseDate,
    DateTime? createdAt,
  }) {
    return ExpenseItemModel(
      id: id ?? this.id,
      claimId: claimId ?? this.claimId,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      merchant: merchant ?? this.merchant,
      receiptPath: receiptPath ?? this.receiptPath,
      expenseDate: expenseDate ?? this.expenseDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Check if item has a receipt
  bool get hasReceipt => receiptPath != null && receiptPath!.isNotEmpty;

  @override
  List<Object?> get props => [
        id,
        claimId,
        category,
        amount,
        description,
        merchant,
        receiptPath,
        expenseDate,
        createdAt,
      ];
}

/// Expense status enum
enum ExpenseStatus {
  draft('draft'),
  submitted('submitted'),
  approved('approved'),
  rejected('rejected');

  final String value;

  const ExpenseStatus(this.value);

  static ExpenseStatus fromString(String value) {
    return ExpenseStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ExpenseStatus.draft,
    );
  }

  String get displayName {
    switch (this) {
      case ExpenseStatus.draft:
        return 'Draft';
      case ExpenseStatus.submitted:
        return 'Submitted';
      case ExpenseStatus.approved:
        return 'Approved';
      case ExpenseStatus.rejected:
        return 'Rejected';
    }
  }
}

/// Expense category enum (aligned with BenzDesk)
enum ExpenseCategory {
  travelAllowance('travel_allowance'),
  transportExpense('transport_expense'),
  localConveyance('local_conveyance'),
  fuel('fuel'),
  toll('toll'),
  food('food'),
  accommodation('accommodation'),
  pettyCash('petty_cash'),
  advanceRequest('advance_request'),
  mobileInternet('mobile_internet'),
  stationary('stationary'),
  medical('medical'),
  other('other');

  final String value;

  const ExpenseCategory(this.value);

  static ExpenseCategory fromString(String value) {
    return ExpenseCategory.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ExpenseCategory.other,
    );
  }

  String get displayName {
    switch (this) {
      case ExpenseCategory.travelAllowance:
        return 'Travel Allowance (TA/DA)';
      case ExpenseCategory.transportExpense:
        return 'Transport Expense';
      case ExpenseCategory.localConveyance:
        return 'Local Conveyance';
      case ExpenseCategory.fuel:
        return 'Fuel';
      case ExpenseCategory.toll:
        return 'Toll';
      case ExpenseCategory.food:
        return 'Food & Meals';
      case ExpenseCategory.accommodation:
        return 'Accommodation';
      case ExpenseCategory.pettyCash:
        return 'Petty Cash';
      case ExpenseCategory.advanceRequest:
        return 'Advance Expense';
      case ExpenseCategory.mobileInternet:
        return 'Mobile/Internet';
      case ExpenseCategory.stationary:
        return 'Stationary';
      case ExpenseCategory.medical:
        return 'Medical';
      case ExpenseCategory.other:
        return 'Other';
    }
  }

  String get icon {
    switch (this) {
      case ExpenseCategory.travelAllowance:
        return '🚗';
      case ExpenseCategory.transportExpense:
        return '🚐';
      case ExpenseCategory.localConveyance:
        return '🚌';
      case ExpenseCategory.fuel:
        return '⛽';
      case ExpenseCategory.toll:
        return '🛣️';
      case ExpenseCategory.food:
        return '🍽️';
      case ExpenseCategory.accommodation:
        return '🏨';
      case ExpenseCategory.pettyCash:
        return '💵';
      case ExpenseCategory.advanceRequest:
        return '💳';
      case ExpenseCategory.mobileInternet:
        return '📱';
      case ExpenseCategory.stationary:
        return '✏️';
      case ExpenseCategory.medical:
        return '🏥';
      case ExpenseCategory.other:
        return '📋';
    }
  }
}

