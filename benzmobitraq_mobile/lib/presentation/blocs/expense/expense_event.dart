part of 'expense_bloc.dart';

/// Base class for expense events
abstract class ExpenseEvent extends Equatable {
  const ExpenseEvent();

  @override
  List<Object?> get props => [];
}

/// Load expense claims for employee (uses employeeId from preferences if not provided)
class ExpenseLoadRequested extends ExpenseEvent {
  final String? employeeId;
  final int limit;
  final int offset;

  const ExpenseLoadRequested({
    this.employeeId,
    this.limit = 20,
    this.offset = 0,
  });

  @override
  List<Object?> get props => [employeeId, limit, offset];
}

/// Submit a simple expense (creates claim + item in one step)
class ExpenseSubmitRequested extends ExpenseEvent {
  final double amount;
  final String category;
  final DateTime expenseDate;
  final String? description;
  final String? receiptPath;

  const ExpenseSubmitRequested({
    required this.amount,
    required this.category,
    required this.expenseDate,
    this.description,
    this.receiptPath,
  });

  @override
  List<Object?> get props => [amount, category, expenseDate, description, receiptPath];
}

/// Create a new expense claim
class ExpenseClaimCreateRequested extends ExpenseEvent {
  final String employeeId;
  final DateTime? claimDate;
  final String? notes;

  const ExpenseClaimCreateRequested({
    required this.employeeId,
    this.claimDate,
    this.notes,
  });

  @override
  List<Object?> get props => [employeeId, claimDate, notes];
}

/// Add expense item to a claim
class ExpenseItemAddRequested extends ExpenseEvent {
  final String claimId;
  final ExpenseCategory category;
  final double amount;
  final String? description;
  final String? merchant;
  final File? receiptImage;
  final DateTime? expenseDate;

  const ExpenseItemAddRequested({
    required this.claimId,
    required this.category,
    required this.amount,
    this.description,
    this.merchant,
    this.receiptImage,
    this.expenseDate,
  });

  @override
  List<Object?> get props => [
        claimId,
        category,
        amount,
        description,
        merchant,
        receiptImage,
        expenseDate,
      ];
}

/// Submit expense claim for approval
class ExpenseClaimSubmitRequested extends ExpenseEvent {
  final String claimId;

  const ExpenseClaimSubmitRequested(this.claimId);

  @override
  List<Object?> get props => [claimId];
}

/// Delete expense claim
class ExpenseClaimDeleteRequested extends ExpenseEvent {
  final String claimId;

  const ExpenseClaimDeleteRequested(this.claimId);

  @override
  List<Object?> get props => [claimId];
}

/// Delete expense item
class ExpenseItemDeleteRequested extends ExpenseEvent {
  final String itemId;
  final String claimId;

  const ExpenseItemDeleteRequested({
    required this.itemId,
    required this.claimId,
  });

  @override
  List<Object?> get props => [itemId, claimId];
}

/// Load expense claim detail
class ExpenseClaimDetailRequested extends ExpenseEvent {
  final String claimId;

  const ExpenseClaimDetailRequested(this.claimId);

  @override
  List<Object?> get props => [claimId];
}
