import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/expense_model.dart';
import '../../../data/models/simple_expense_model.dart';
import '../../../data/repositories/expense_repository.dart';
import '../../../data/datasources/local/preferences_local.dart';

part 'expense_event.dart';
part 'expense_state.dart';

/// BLoC for handling expense state
class ExpenseBloc extends Bloc<ExpenseEvent, ExpenseState> {
  final ExpenseRepository _expenseRepository;
  final PreferencesLocal _preferences;
  final _uuid = const Uuid();

  ExpenseBloc({
    required ExpenseRepository expenseRepository,
    required PreferencesLocal preferences,
  })  : _expenseRepository = expenseRepository,
        _preferences = preferences,
        super(ExpenseInitial()) {
    on<ExpenseLoadRequested>(_onLoadRequested);
    on<ExpenseSubmitRequested>(_onSubmitRequested);
    on<ExpenseClaimCreateRequested>(_onClaimCreateRequested);
    on<ExpenseItemAddRequested>(_onItemAddRequested);
    on<ExpenseClaimSubmitRequested>(_onClaimSubmitRequested);
    on<ExpenseClaimDeleteRequested>(_onClaimDeleteRequested);
    on<ExpenseItemDeleteRequested>(_onItemDeleteRequested);
    on<ExpenseClaimDetailRequested>(_onClaimDetailRequested);
  }

  Future<void> _onLoadRequested(
    ExpenseLoadRequested event,
    Emitter<ExpenseState> emit,
  ) async {
    emit(ExpenseLoading());

    try {
      final employeeId = event.employeeId ?? _preferences.userId;
      if (employeeId == null) {
        emit(const ExpenseError('Not logged in'));
        return;
      }

      final claims = await _expenseRepository.getEmployeeClaims(
        employeeId: employeeId,
        limit: event.limit,
        offset: event.offset,
      );

      // Convert claims to simple expense models for the UI
      final expenses = <ExpenseModel>[];
      for (final claim in claims) {
        if (claim.items != null) {
          for (final item in claim.items!) {
            expenses.add(ExpenseModel(
              id: item.id,
              employeeId: claim.employeeId,
              category: item.category.displayName,
              amount: item.amount,
              description: item.description,
              expenseDate: item.expenseDate,
              status: claim.status.value,
              receiptPath: item.receiptPath,
              createdAt: item.createdAt,
              submittedAt: claim.submittedAt,
            ));
          }
        } else {
          // If no items, create expense from claim
          expenses.add(ExpenseModel(
            id: claim.id,
            employeeId: claim.employeeId,
            category: 'Other',
            amount: claim.totalAmount,
            description: claim.notes,
            expenseDate: claim.claimDate,
            status: claim.status.value,
            createdAt: claim.createdAt,
            submittedAt: claim.submittedAt,
          ));
        }
      }

      emit(ExpenseLoaded(
        expenses: expenses,
        hasMore: claims.length >= event.limit,
      ));
    } catch (e) {
      emit(ExpenseError('Failed to load expenses: $e'));
    }
  }

  Future<void> _onSubmitRequested(
    ExpenseSubmitRequested event,
    Emitter<ExpenseState> emit,
  ) async {
    emit(ExpenseLoading());

    try {
      final employeeId = _preferences.userId;
      if (employeeId == null) {
        emit(const ExpenseError('Not logged in'));
        return;
      }

      // Create claim
      final claimId = _uuid.v4();
      final claim = await _expenseRepository.createClaim(
        employeeId: employeeId,
        claimDate: event.expenseDate,
      );

      if (claim == null) {
        emit(const ExpenseError('Failed to create expense'));
        return;
      }

      // Add item
      // Prefer DB-safe category keys (e.g. "local_conveyance") and fall back to display name matching.
      var category = ExpenseCategory.fromString(event.category);
      if (category == ExpenseCategory.other && event.category.toLowerCase() != 'other') {
        category = ExpenseCategory.values.firstWhere(
          (c) => c.displayName.toLowerCase() == event.category.toLowerCase(),
          orElse: () => ExpenseCategory.other,
        );
      }

      final item = await _expenseRepository.addItem(
        claimId: claim.id,
        category: category,
        amount: event.amount,
        description: event.description,
        expenseDate: event.expenseDate,
        receiptImage: event.receiptPath != null ? File(event.receiptPath!) : null,
      );

      if (item == null) {
        emit(const ExpenseError('Failed to add expense item'));
        return;
      }

      // Submit claim
      final submittedClaim = await _expenseRepository.submitClaim(claim.id);

      final expense = ExpenseModel(
        id: item.id,
        employeeId: employeeId,
        category: category.displayName,
        amount: event.amount,
        description: event.description,
        expenseDate: event.expenseDate,
        status: submittedClaim?.status.value ?? 'submitted',
        receiptPath: item.receiptPath,
        createdAt: DateTime.now(),
        submittedAt: DateTime.now(),
      );

      emit(ExpenseSubmitSuccess(expense));
    } catch (e) {
      emit(ExpenseError('Failed to submit expense: $e'));
    }
  }

  Future<void> _onClaimCreateRequested(
    ExpenseClaimCreateRequested event,
    Emitter<ExpenseState> emit,
  ) async {
    emit(ExpenseLoading());

    try {
      final claim = await _expenseRepository.createClaim(
        employeeId: event.employeeId,
        claimDate: event.claimDate,
        notes: event.notes,
      );

      if (claim != null) {
        emit(ExpenseClaimCreated(claim));
      } else {
        emit(const ExpenseError('Failed to create expense claim'));
      }
    } catch (e) {
      emit(ExpenseError('Failed to create expense claim: $e'));
    }
  }

  Future<void> _onItemAddRequested(
    ExpenseItemAddRequested event,
    Emitter<ExpenseState> emit,
  ) async {
    emit(ExpenseLoading());

    try {
      final item = await _expenseRepository.addItem(
        claimId: event.claimId,
        category: event.category,
        amount: event.amount,
        description: event.description,
        merchant: event.merchant,
        receiptImage: event.receiptImage,
        expenseDate: event.expenseDate,
      );

      if (item != null) {
        // Reload the claim to get updated total
        final updatedClaim = await _expenseRepository.getClaim(event.claimId);
        if (updatedClaim != null) {
          emit(ExpenseClaimDetailLoaded(updatedClaim));
        } else {
          emit(ExpenseItemAdded(item));
        }
      } else {
        emit(const ExpenseError('Failed to add expense item'));
      }
    } catch (e) {
      emit(ExpenseError('Failed to add expense item: $e'));
    }
  }

  Future<void> _onClaimSubmitRequested(
    ExpenseClaimSubmitRequested event,
    Emitter<ExpenseState> emit,
  ) async {
    emit(ExpenseLoading());

    try {
      final claim = await _expenseRepository.submitClaim(event.claimId);

      if (claim != null) {
        emit(ExpenseClaimSubmitted(claim));
      } else {
        emit(const ExpenseError('Failed to submit expense claim'));
      }
    } catch (e) {
      emit(ExpenseError('Failed to submit expense claim: $e'));
    }
  }

  Future<void> _onClaimDeleteRequested(
    ExpenseClaimDeleteRequested event,
    Emitter<ExpenseState> emit,
  ) async {
    emit(ExpenseLoading());

    try {
      final success = await _expenseRepository.deleteClaim(event.claimId);

      if (success) {
        emit(ExpenseClaimDeleted(event.claimId));
      } else {
        emit(const ExpenseError('Failed to delete expense claim'));
      }
    } catch (e) {
      emit(ExpenseError('Failed to delete expense claim: $e'));
    }
  }

  Future<void> _onItemDeleteRequested(
    ExpenseItemDeleteRequested event,
    Emitter<ExpenseState> emit,
  ) async {
    emit(ExpenseLoading());

    try {
      final success = await _expenseRepository.deleteItem(
        event.itemId,
        event.claimId,
      );

      if (success) {
        // Reload the claim to get updated total
        final updatedClaim = await _expenseRepository.getClaim(event.claimId);
        if (updatedClaim != null) {
          emit(ExpenseClaimDetailLoaded(updatedClaim));
        } else {
          emit(ExpenseItemDeleted(event.itemId));
        }
      } else {
        emit(const ExpenseError('Failed to delete expense item'));
      }
    } catch (e) {
      emit(ExpenseError('Failed to delete expense item: $e'));
    }
  }

  Future<void> _onClaimDetailRequested(
    ExpenseClaimDetailRequested event,
    Emitter<ExpenseState> emit,
  ) async {
    emit(ExpenseLoading());

    try {
      final claim = await _expenseRepository.getClaim(event.claimId);

      if (claim != null) {
        emit(ExpenseClaimDetailLoaded(claim));
      } else {
        emit(const ExpenseError('Expense claim not found'));
      }
    } catch (e) {
      emit(ExpenseError('Failed to load expense claim: $e'));
    }
  }
}
