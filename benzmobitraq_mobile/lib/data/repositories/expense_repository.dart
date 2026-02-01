import 'dart:io';

import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../datasources/remote/supabase_client.dart';
import '../models/expense_model.dart';

/// Repository for handling expense operations
class ExpenseRepository {
  final SupabaseDataSource _dataSource;
  final SupabaseClient _supabaseClient;
  final Logger _logger = Logger();
  final Uuid _uuid = const Uuid();

  ExpenseRepository({
    required SupabaseDataSource dataSource,
    required SupabaseClient supabaseClient,
  })  : _dataSource = dataSource,
        _supabaseClient = supabaseClient;

  // ============================================================
  // EXPENSE CLAIMS
  // ============================================================

  /// Create a new expense claim
  Future<ExpenseClaimModel?> createClaim({
    required String employeeId,
    DateTime? claimDate,
    String? notes,
  }) async {
    try {
      final claim = ExpenseClaimModel.create(
        id: _uuid.v4(),
        employeeId: employeeId,
        claimDate: claimDate,
        notes: notes,
      );

      return await _dataSource.createExpenseClaim(claim);
    } catch (e) {
      _logger.e('Error creating expense claim: $e');
      return null;
    }
  }

  /// Get expense claim by ID
  Future<ExpenseClaimModel?> getClaim(String claimId) async {
    try {
      return await _dataSource.getExpenseClaim(claimId);
    } catch (e) {
      _logger.e('Error getting expense claim: $e');
      return null;
    }
  }

  /// Get expense claims for employee
  Future<List<ExpenseClaimModel>> getEmployeeClaims({
    required String employeeId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      return await _dataSource.getEmployeeExpenses(
        employeeId: employeeId,
        limit: limit,
        offset: offset,
      );
    } catch (e) {
      _logger.e('Error getting employee expenses: $e');
      return [];
    }
  }

  /// Submit expense claim for approval
  Future<ExpenseClaimModel?> submitClaim(String claimId) async {
    try {
      return await _dataSource.submitExpenseClaim(claimId);
    } catch (e) {
      _logger.e('Error submitting expense claim: $e');
      return null;
    }
  }

  /// Delete expense claim (only drafts)
  Future<bool> deleteClaim(String claimId) async {
    try {
      await _dataSource.deleteExpenseClaim(claimId);
      return true;
    } catch (e) {
      _logger.e('Error deleting expense claim: $e');
      return false;
    }
  }

  // ============================================================
  // EXPENSE ITEMS
  // ============================================================

  /// Add expense item to a claim
  Future<ExpenseItemModel?> addItem({
    required String claimId,
    required ExpenseCategory category,
    required double amount,
    String? description,
    String? merchant,
    File? receiptImage,
    DateTime? expenseDate,
  }) async {
    try {
      String? receiptPath;

      // Upload receipt image if provided
      if (receiptImage != null) {
        receiptPath = await _uploadReceipt(claimId, receiptImage);
      }

      final item = ExpenseItemModel.create(
        id: _uuid.v4(),
        claimId: claimId,
        category: category,
        amount: amount,
        description: description,
        merchant: merchant,
        receiptPath: receiptPath,
        expenseDate: expenseDate,
      );

      final createdItem = await _dataSource.addExpenseItem(item);

      // Update claim total
      await _dataSource.updateExpenseClaimTotal(claimId);

      return createdItem;
    } catch (e) {
      _logger.e('Error adding expense item: $e');
      return null;
    }
  }

  /// Delete expense item
  Future<bool> deleteItem(String itemId, String claimId) async {
    try {
      await _dataSource.deleteExpenseItem(itemId);
      
      // Update claim total
      await _dataSource.updateExpenseClaimTotal(claimId);
      
      return true;
    } catch (e) {
      _logger.e('Error deleting expense item: $e');
      return false;
    }
  }

  // ============================================================
  // RECEIPTS
  // ============================================================

  /// Upload receipt image to Supabase Storage
  Future<String?> _uploadReceipt(String claimId, File imageFile) async {
    try {
      final fileName = '${_uuid.v4()}.jpg';
      final storagePath = 'receipts/$claimId/$fileName';

      await _supabaseClient.storage
          .from('expense-receipts')
          .upload(storagePath, imageFile);

      _logger.i('Receipt uploaded: $storagePath');
      return storagePath;
    } catch (e) {
      _logger.e('Error uploading receipt: $e');
      return null;
    }
  }

  /// Get signed URL for receipt image
  Future<String?> getReceiptUrl(String receiptPath) async {
    try {
      final url = await _supabaseClient.storage
          .from('expense-receipts')
          .createSignedUrl(receiptPath, 3600); // 1 hour expiry

      return url;
    } catch (e) {
      _logger.e('Error getting receipt URL: $e');
      return null;
    }
  }

  /// Delete receipt image from storage
  Future<bool> deleteReceipt(String receiptPath) async {
    try {
      await _supabaseClient.storage
          .from('expense-receipts')
          .remove([receiptPath]);

      return true;
    } catch (e) {
      _logger.e('Error deleting receipt: $e');
      return false;
    }
  }

  // ============================================================
  // STATISTICS
  // ============================================================

  /// Get total expenses for current month
  Future<double> getCurrentMonthTotal(String employeeId) async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      
      final claims = await getEmployeeClaims(
        employeeId: employeeId,
        limit: 100,
      );

      double total = 0;
      for (final claim in claims) {
        if (claim.claimDate.isAfter(startOfMonth) ||
            claim.claimDate.isAtSameMomentAs(startOfMonth)) {
          if (claim.status == ExpenseStatus.approved) {
            total += claim.totalAmount;
          }
        }
      }

      return total;
    } catch (e) {
      _logger.e('Error getting monthly total: $e');
      return 0;
    }
  }

  /// Get total expenses for a specific category on a specific date
  /// Used for daily limit tracking
  Future<double> getDailyTotalForCategory({
    required String employeeId,
    required String category,
    required DateTime date,
  }) async {
    try {
      // Get the start and end of the day
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

      // Query expenses for this category on this date
      final response = await _supabaseClient
          .from('expense_items')
          .select('amount, expense_claims!inner(employee_id, status)')
          .eq('expense_claims.employee_id', employeeId)
          .eq('category', category)
          .gte('expense_date', startOfDay.toIso8601String())
          .lte('expense_date', endOfDay.toIso8601String());

      double total = 0;
      for (final item in response as List) {
        // Count pending and approved expenses
        final status = item['expense_claims']?['status'] as String?;
        if (status == 'submitted' || status == 'approved' || status == 'pending') {
          total += (item['amount'] as num?)?.toDouble() ?? 0;
        }
      }

      _logger.i('Daily total for $category on ${date.toIso8601String()}: ₹$total');
      return total;
    } catch (e) {
      _logger.e('Error getting daily total for category: $e');
      return 0;
    }
  }

  /// Get all daily totals for categories with limits
  Future<Map<String, double>> getAllDailyTotals({
    required String employeeId,
    required DateTime date,
  }) async {
    final categories = ['local_conveyance', 'food', 'accommodation'];
    final Map<String, double> totals = {};

    for (final category in categories) {
      totals[category] = await getDailyTotalForCategory(
        employeeId: employeeId,
        category: category,
        date: date,
      );
    }

    return totals;
  }

  // ============================================================
  // COMMENTS (Chat functionality)
  // ============================================================

  /// Get all comments for an expense claim
  Future<List<Map<String, dynamic>>> getClaimComments(String claimId) async {
    try {
      final response = await _supabaseClient
          .from('expense_claim_comments')
          .select('''
            *,
            author:employees!author_id (
              id,
              name,
              role
            )
          ''')
          .eq('claim_id', claimId)
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.e('Error getting claim comments: $e');
      return [];
    }
  }

  /// Add a comment to an expense claim
  Future<Map<String, dynamic>?> addComment({
    required String claimId,
    required String authorId,
    required String body,
  }) async {
    try {
      final response = await _supabaseClient
          .from('expense_claim_comments')
          .insert({
            'claim_id': claimId,
            'author_id': authorId,
            'body': body,
            'is_internal': false,
          })
          .select('''
            *,
            author:employees!author_id (
              id,
              name,
              role
            )
          ''')
          .single();

      return response;
    } catch (e) {
      _logger.e('Error adding comment: $e');
      return null;
    }
  }

  // ============================================================
  // EVENTS (Audit trail)
  // ============================================================

  /// Get all events for an expense claim
  Future<List<Map<String, dynamic>>> getClaimEvents(String claimId) async {
    try {
      final response = await _supabaseClient
          .from('expense_claim_events')
          .select('''
            *,
            actor:employees!actor_id (
              id,
              name,
              role
            )
          ''')
          .eq('claim_id', claimId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.e('Error getting claim events: $e');
      return [];
    }
  }

  // ============================================================
  // ATTACHMENTS (Receipts/Bills)
  // ============================================================

  /// Get all attachments for an expense claim
  Future<List<Map<String,dynamic>>> getClaimAttachments(String claimId) async {
    try {
      final response = await _supabaseClient
          .from('expense_claim_attachments')
          .select('''
            *,
            uploader:employees!uploaded_by (
              id,
              name
            )
          ''')
          .eq('claim_id', claimId)
          .order('uploaded_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.e('Error getting claim attachments: $e');
      return [];
    }
  }

  /// Upload and register an attachment
  Future<Map<String, dynamic>?> uploadAttachment({
    required String claimId,
    required String uploadedBy,
    required File file,
    required String originalFilename,
    required String mimeType,
  }) async {
    try {
      // 1. Upload to storage
      final extension = originalFilename.split('.').last;
      final path = 'claims/$claimId/${DateTime.now().millisecondsSinceEpoch}.$extension';
      
      await _supabaseClient.storage
          .from('benzmobitraq-receipts')
          .upload(path, file);

      // 2. Register in database
      final sizeBytes = await file.length();
      
      final response = await _supabaseClient
          .from('expense_claim_attachments')
          .insert({
            'claim_id': claimId,
            'uploaded_by': uploadedBy,
            'bucket': 'benzmobitraq-receipts',
            'path': path,
            'original_filename': originalFilename,
            'mime_type': mimeType,
            'size_bytes': sizeBytes,
          })
          .select('''
            *,
            uploader:employees!uploaded_by (
              id,
              name
            )
          ''')
          .single();

      return response;
    } catch (e) {
      _logger.e('Error uploading attachment: $e');
      return null;
    }
  }

  /// Delete an attachment
  Future<bool> deleteAttachment({
    required int attachmentId,
    required String path,
  }) async {
    try {
      // 1. Delete from storage
      await _supabaseClient.storage
          .from('benzmobitraq-receipts')
          .remove([path]);

      // 2. Delete from database
      await _supabaseClient
          .from('expense_claim_attachments')
          .delete()
          .eq('id', attachmentId);

      return true;
    } catch (e) {
      _logger.e('Error deleting attachment: $e');
      return false;
    }
  }

  /// Get signed URL for attachment download
  Future<String?> getAttachmentUrl(String path) async {
    try {
      final url = _supabaseClient.storage
          .from('benzmobitraq-receipts')
          .createSignedUrl(path, 3600); // 1 hour expiry

      return url;
    } catch (e) {
      _logger.e('Error getting attachment URL: $e');
      return null;
    }
  }
}
