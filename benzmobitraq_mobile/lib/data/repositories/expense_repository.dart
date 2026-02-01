import 'dart:io';

import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../datasources/remote/supabase_client.dart';
import '../models/expense_model.dart';
import '../datasources/local/expense_queue_local.dart';

/// Repository for handling expense operations
class ExpenseRepository {
  final SupabaseDataSource _dataSource;
  final SupabaseClient _supabaseClient;
  final ExpenseQueueLocal _localQueue;
  final Logger _logger = Logger();
  final Uuid _uuid = const Uuid();

  ExpenseRepository({
    required SupabaseDataSource dataSource,
    required SupabaseClient supabaseClient,
    required ExpenseQueueLocal localQueue,
  })  : _dataSource = dataSource,
        _supabaseClient = supabaseClient,
        _localQueue = localQueue;

  // ============================================================
  // EXPENSE CLAIMS
  // ============================================================

  /// Create a new expense claim
  Future<ExpenseClaimModel?> createClaim({
    required String employeeId,
    DateTime? claimDate,
    String? notes,
  }) async {
    final claim = ExpenseClaimModel.create(
      id: _uuid.v4(),
      employeeId: employeeId,
      claimDate: claimDate,
      notes: notes,
    );

    try {
      final createdComp = await _dataSource.createExpenseClaim(claim);
      // Also save to local DB as synced for viewing when offline
      await _localQueue.queueClaim(createdComp!.copyWith()); // Ensure synced is set?
      // Actually queueClaim saves as is, so we might want to mark it synced
      await _localQueue.markClaimAsSynced(claim.id); 
      return createdComp;
    } catch (e) {
      _logger.w('Offline: Queueing expense claim: $e');
      // Save locally as unsynced
      await _localQueue.queueClaim(claim);
      return claim;
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
      // 1. Get remote expenses
      final remoteClaims = await _dataSource.getEmployeeExpenses(
        employeeId: employeeId,
        limit: limit,
        offset: offset,
      );

      // 2. Get local pending expenses (only on first page/offset 0)
      List<ExpenseClaimModel> localClaims = [];
      if (offset == 0) {
        localClaims = await _localQueue.getPendingClaims();
      }

      // 3. Merge and sort
      final allClaims = [...localClaims, ...remoteClaims];
      
      // Deduplicate
      final seenIds = <String>{};
      final uniqueClaims = <ExpenseClaimModel>[];
      
      for (final claim in allClaims) {
        if (seenIds.add(claim.id)) {
          uniqueClaims.add(claim);
        }
      }
      
      uniqueClaims.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      return uniqueClaims;
    } catch (e) {
      _logger.e('Error getting employee expenses: $e');
      // Fallback to local only if remote fails
      if (offset == 0) {
         return await _localQueue.getPendingClaims();
      }
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
    // 1. Prepare item
    final item = ExpenseItemModel.create(
      id: _uuid.v4(),
      claimId: claimId,
      category: category,
      amount: amount,
      description: description,
      merchant: merchant,
      receiptPath: null, // Will be set if uploaded
      expenseDate: expenseDate,
    );
    
    // We need to store local path in the model temporarily or in the queue
    // ExpenseItemModel now has localReceiptPath in toLocalJson logic
    // But we need to pass it to queueItem if we fall back.
    // The model field 'receiptPath' is for REMOTE path. 
    // We update the item with local path before queueing if offline.

    try {
      String? receiptPath;
      if (receiptImage != null) {
        receiptPath = await _uploadReceipt(claimId, receiptImage);
        if (receiptPath == null) throw Exception('Failed to upload receipt');
      }

      final itemWithReceipt = item.copyWith(receiptPath: receiptPath);
      final createdItem = await _dataSource.addExpenseItem(itemWithReceipt);

      // Update claim total
      await _dataSource.updateExpenseClaimTotal(claimId);

      return createdItem;
    } catch (e) {
      _logger.w('Offline: Queueing expense item: $e');
      
      // Save locally with local receipt path
      // Note: We're reusing 'receiptPath' to store the local file path temporarily
      // OR better, rely on 'local_receipt_path' in the queue map.
      // Since `toLocalJson` uses `receiptPath` as `local_receipt_path` if present...
      // Wait, `toLocalJson` maps `receiptPath` to `local_receipt_path`.
      // So we set `receiptPath` to the local file path here.
      
      final offlineItem = item.copyWith(
        receiptPath: receiptImage?.path, 
      );
      
      await _localQueue.queueItem(offlineItem);
      return offlineItem;
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

  // ============================================================
  // SYNCHRONIZATION
  // ============================================================

  /// Sync all pending claims and items
  Future<int> syncPendingExpenses() async {
    int syncedCount = 0;
    
    try {
      // 1. Sync Claims
      final pendingClaims = await _localQueue.getPendingClaims();
      for (final claim in pendingClaims) {
        try {
          // Check if it already exists (idempotency check)? 
          await _dataSource.createExpenseClaim(claim);
          await _localQueue.markClaimAsSynced(claim.id);
          syncedCount++;
        } catch (e) {
           _logger.e('Error syncing claim ${claim.id}: $e');
        }
      }

      // 2. Sync Items
      final pendingItems = await _localQueue.getUnuploadedItems();
      for (final item in pendingItems) {
        try {
          String? remoteReceiptPath = item.receiptPath;
          
          // Check if we have a local receipt that needs upload
          if (item.hasReceipt && !item.receiptPath!.startsWith('receipts/')) {
             final file = File(item.receiptPath!);
             if (await file.exists()) {
               remoteReceiptPath = await _uploadReceipt(item.claimId, file);
             } else {
               _logger.w('Local receipt file not found: ${item.receiptPath}');
               remoteReceiptPath = null; 
               continue; 
             }
          }
          
          final syncItem = item.copyWith(receiptPath: remoteReceiptPath);
          await _dataSource.addExpenseItem(syncItem);
          
          await _localQueue.markItemAsUploaded(item.id, remoteReceiptPath: remoteReceiptPath);
          syncedCount++;
        } catch (e) {
          _logger.e('Error syncing item ${item.id}: $e');
          await _localQueue.incrementItemUploadAttempts(item.id);
        }
      }
      
      return syncedCount;
    } catch (e) {
      _logger.e('Error in syncPendingExpenses: $e');
      return syncedCount;
    }
  }
}
