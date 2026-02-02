import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../../models/location_point_model.dart';

/// Local SQLite database for storing location points when offline
class LocationQueueLocal {
  Database? _database;

  static const String _tableName = 'location_queue';
  static const String _dbName = 'benzmobitraq_locations.db';
  static const int _dbVersion = 1;

  /// Initialize the database
  Future<void> init() async {
    if (_database != null) return;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    _database = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Get database instance
  Database get db {
    if (_database == null) {
      throw Exception('LocationQueueLocal not initialized. Call init() first.');
    }
    return _database!;
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        employee_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL,
        speed REAL,
        altitude REAL,
        heading REAL,
        is_moving INTEGER DEFAULT 1,
        recorded_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        uploaded INTEGER DEFAULT 0,
        upload_attempts INTEGER DEFAULT 0,
        last_upload_attempt INTEGER
      )
    ''');

    // Index for faster queries
    await db.execute('''
      CREATE INDEX idx_uploaded ON $_tableName (uploaded)
    ''');

    await db.execute('''
      CREATE INDEX idx_session ON $_tableName (session_id)
    ''');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle future schema migrations here
  }

  // ============================================================
  // QUEUE OPERATIONS
  // ============================================================

  /// Add a location point to the queue
  Future<void> enqueue(LocationPointModel point) async {
    final data = point.toLocalJson();
    await db.insert(
      _tableName,
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Add multiple location points to the queue
  Future<void> enqueueAll(List<LocationPointModel> points) async {
    final batch = db.batch();
    for (final point in points) {
      batch.insert(
        _tableName,
        point.toLocalJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Get unuploaded location points
  /// 
  /// [limit] - Maximum number of points to retrieve
  /// [maxAttempts] - Only get points with fewer than this many upload attempts
  Future<List<LocationPointModel>> getUnuploaded({
    int limit = 50,
    int maxAttempts = 5,
  }) async {
    final results = await db.query(
      _tableName,
      where: 'uploaded = 0 AND upload_attempts < ?',
      whereArgs: [maxAttempts],
      orderBy: 'recorded_at ASC',
      limit: limit,
    );

    return results.map((row) => LocationPointModel.fromLocalJson(row)).toList();
  }

  /// Mark points as uploaded
  Future<void> markAsUploaded(List<String> ids) async {
    if (ids.isEmpty) return;

    final placeholders = List.filled(ids.length, '?').join(',');
    await db.update(
      _tableName,
      {'uploaded': 1},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  /// Increment upload attempts for failed uploads
  Future<void> incrementUploadAttempts(List<String> ids) async {
    if (ids.isEmpty) return;

    final placeholders = List.filled(ids.length, '?').join(',');
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.rawUpdate('''
      UPDATE $_tableName 
      SET upload_attempts = upload_attempts + 1,
          last_upload_attempt = ?
      WHERE id IN ($placeholders)
    ''', [now, ...ids]);
  }

  /// Delete uploaded points older than a certain age
  Future<int> deleteOldUploaded({Duration maxAge = const Duration(days: 7)}) async {
    final cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    
    return await db.delete(
      _tableName,
      where: 'uploaded = 1 AND recorded_at < ?',
      whereArgs: [cutoff],
    );
  }

  /// Get count of unuploaded points
  Future<int> getUnuploadedCount() async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName WHERE uploaded = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get points for a specific session
  Future<List<LocationPointModel>> getBySession(String sessionId) async {
    final results = await db.query(
      _tableName,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'recorded_at ASC',
    );

    return results.map((row) => LocationPointModel.fromLocalJson(row)).toList();
  }

  /// Delete all points for a session
  Future<int> deleteBySession(String sessionId) async {
    return await db.delete(
      _tableName,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Get the most recent point for a session
  Future<LocationPointModel?> getLastPoint(String sessionId) async {
    final results = await db.query(
      _tableName,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'recorded_at DESC',
      limit: 1,
    );

    if (results.isEmpty) return null;
    return LocationPointModel.fromLocalJson(results.first);
  }

  /// Get total distance for a session (approximate, from local points)
  Future<double> getSessionDistance(String sessionId) async {
    final points = await getBySession(sessionId);
    if (points.length < 2) return 0.0;

    double totalDistance = 0.0;
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      
      // Calculate distance using Haversine approximation
      final distanceMeters = _approximateDistance(
        prev.latitude, prev.longitude,
        curr.latitude, curr.longitude,
      );
      
      totalDistance += distanceMeters;
    }

    return totalDistance;
  }

  /// Simple distance approximation (should use real Haversine in production)
  double _approximateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // meters
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    
    final double a = _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_toRadians(lat1)) * _cos(_toRadians(lat2)) *
        _sin(dLon / 2) * _sin(dLon / 2);
    
    final double c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double deg) => deg * 3.14159265359 / 180;
  double _sin(double x) => x - (x * x * x) / 6 + (x * x * x * x * x) / 120;
  double _cos(double x) => 1 - (x * x) / 2 + (x * x * x * x) / 24;
  double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
  double _atan2(double y, double x) {
    if (x > 0) return y / x;
    if (x < 0 && y >= 0) return y / x + 3.14159;
    if (x < 0 && y < 0) return y / x - 3.14159;
    if (x == 0 && y > 0) return 3.14159 / 2;
    if (x == 0 && y < 0) return -3.14159 / 2;
    return 0;
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  /// Clear all data from the queue
  Future<void> clearAll() async {
    await db.delete(_tableName);
  }

  /// Close the database
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
