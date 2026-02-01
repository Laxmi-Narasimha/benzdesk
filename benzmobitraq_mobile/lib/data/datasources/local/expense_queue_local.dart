import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/expense_model.dart';
import 'package:logger/logger.dart';

/// Local SQLite database for storing expense data when offline
class ExpenseQueueLocal {
  Database? _database;
  final Logger _logger = Logger();

  static const String _dbName = 'benzmobitraq_expenses.db';
  static const int _dbVersion = 1;
  
  static const String _tableClaims = 'expense_claims_queue';
  static const String _tableItems = 'expense_items_queue';

  /// Initialize the database
  Future<void> init() async {
    if (_database != null) return;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    _database = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  /// Get database instance
  Database get db {
    if (_database == null) {
      throw Exception('ExpenseQueueLocal not initialized. Call init() first.');
    }
    return _database!;
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    // Claims table
    await db.execute('''
      CREATE TABLE $_tableClaims (
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        claim_date INTEGER NOT NULL,
        total_amount REAL,
        status TEXT,
        notes TEXT,
        rejection_reason TEXT,
        submitted_at INTEGER,
        reviewed_at INTEGER,
        reviewed_by TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    // Items table
    await db.execute('''
      CREATE TABLE $_tableItems (
        id TEXT PRIMARY KEY,
        claim_id TEXT NOT NULL,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT,
        merchant TEXT,
        receipt_path TEXT,
        local_receipt_path TEXT,
        expense_date INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        uploaded INTEGER DEFAULT 0,
        upload_attempts INTEGER DEFAULT 0,
        FOREIGN KEY (claim_id) REFERENCES $_tableClaims (id) ON DELETE CASCADE
      )
    ''');
    
    // Index for faster queries
    await db.execute('CREATE INDEX idx_items_claim ON $_tableItems (claim_id)');
    await db.execute('CREATE INDEX idx_items_uploaded ON $_tableItems (uploaded)');
    await db.execute('CREATE INDEX idx_claims_synced ON $_tableClaims (is_synced)');
  }

  // ============================================================
  // CLAIM OPERATIONS
  // ============================================================

  /// Queue a claim (draft or submitted)
  Future<void> queueClaim(ExpenseClaimModel claim) async {
    await db.insert(
      _tableClaims,
      claim.toLocalJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get pending claims (not fully synced)
  Future<List<ExpenseClaimModel>> getPendingClaims() async {
    final results = await db.query(
      _tableClaims,
      where: 'is_synced = 0',
      orderBy: 'created_at ASC',
    );

    return results.map((row) => ExpenseClaimModel.fromLocalJson(row)).toList();
  }

  /// Mark claim as synced
  Future<void> markClaimAsSynced(String id) async {
    await db.update(
      _tableClaims,
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  /// Get a specific claim
  Future<ExpenseClaimModel?> getClaim(String id) async {
    final results = await db.query(
      _tableClaims,
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (results.isEmpty) return null;
    return ExpenseClaimModel.fromLocalJson(results.first);
  }

  // ============================================================
  // ITEM OPERATIONS
  // ============================================================

  /// Queue an item
  Future<void> queueItem(ExpenseItemModel item) async {
    await db.insert(
      _tableItems,
      item.toLocalJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get unuploaded items
  Future<List<ExpenseItemModel>> getUnuploadedItems({int limit = 20}) async {
    final results = await db.query(
      _tableItems,
      where: 'uploaded = 0',
      limit: limit,
      orderBy: 'created_at ASC',
    );

    return results.map((row) => ExpenseItemModel.fromLocalJson(row)).toList();
  }
  
  /// Get items for a claim
  Future<List<ExpenseItemModel>> getItemsForClaim(String claimId) async {
    final results = await db.query(
      _tableItems,
      where: 'claim_id = ?',
      whereArgs: [claimId],
      orderBy: 'created_at DESC',
    );

    return results.map((row) => ExpenseItemModel.fromLocalJson(row)).toList();
  }

  /// Mark item as uploaded
  Future<void> markItemAsUploaded(String id, {String? remoteReceiptPath}) async {
    final Map<String, dynamic> updates = {'uploaded': 1};
    if (remoteReceiptPath != null) {
      updates['receipt_path'] = remoteReceiptPath;
    }
    
    await db.update(
      _tableItems,
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Increment upload attempts
  Future<void> incrementItemUploadAttempts(String id) async {
    await db.rawUpdate('''
      UPDATE $_tableItems 
      SET upload_attempts = upload_attempts + 1
      WHERE id = ?
    ''', [id]);
  }
  
  /// Close database
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
