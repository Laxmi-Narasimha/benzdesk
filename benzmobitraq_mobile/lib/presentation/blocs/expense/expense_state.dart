part of 'expense_bloc.dart';

/// Base class for expense states
abstract class ExpenseState extends Equatable {
  const ExpenseState();

  @override
  List<Object?> get props => [];
}

/// Initial state before loading
class ExpenseInitial extends ExpenseState {}

/// Loading state
class ExpenseLoading extends ExpenseState {}

/// List of expense claims loaded (using ExpenseClaimModel)
class ExpenseListLoaded extends ExpenseState {
  final List<ExpenseClaimModel> claims;
  final bool hasMore;

  const ExpenseListLoaded({
    required this.claims,
    this.hasMore = false,
  });

  @override
  List<Object?> get props => [claims, hasMore];
}

/// Expenses loaded (using simple ExpenseModel for screens)
class ExpenseLoaded extends ExpenseState {
  final List<ExpenseModel> expenses;
  final bool hasMore;

  const ExpenseLoaded({
    required this.expenses,
    this.hasMore = false,
  });

  @override
  List<Object?> get props => [expenses, hasMore];
}

/// Expense claim detail loaded
class ExpenseClaimDetailLoaded extends ExpenseState {
  final ExpenseClaimModel claim;

  const ExpenseClaimDetailLoaded(this.claim);

  @override
  List<Object?> get props => [claim];
}

/// Expense claim created
class ExpenseClaimCreated extends ExpenseState {
  final ExpenseClaimModel claim;

  const ExpenseClaimCreated(this.claim);

  @override
  List<Object?> get props => [claim];
}

/// Expense item added
class ExpenseItemAdded extends ExpenseState {
  final ExpenseItemModel item;

  const ExpenseItemAdded(this.item);

  @override
  List<Object?> get props => [item];
}

/// Simple expense submitted successfully
class ExpenseSubmitSuccess extends ExpenseState {
  final ExpenseModel expense;

  const ExpenseSubmitSuccess(this.expense);

  @override
  List<Object?> get props => [expense];
}

/// Expense claim submitted
class ExpenseClaimSubmitted extends ExpenseState {
  final ExpenseClaimModel claim;

  const ExpenseClaimSubmitted(this.claim);

  @override
  List<Object?> get props => [claim];
}

/// Expense claim deleted
class ExpenseClaimDeleted extends ExpenseState {
  final String claimId;

  const ExpenseClaimDeleted(this.claimId);

  @override
  List<Object?> get props => [claimId];
}

/// Expense item deleted
class ExpenseItemDeleted extends ExpenseState {
  final String itemId;

  const ExpenseItemDeleted(this.itemId);

  @override
  List<Object?> get props => [itemId];
}

/// Error state
class ExpenseError extends ExpenseState {
  final String message;

  const ExpenseError(this.message);

  @override
  List<Object?> get props => [message];
}
