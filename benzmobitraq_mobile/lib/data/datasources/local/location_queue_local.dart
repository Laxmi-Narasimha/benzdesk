import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import 'package:benzmobitraq_mobile/data/models/location_point_model.dart';

/// Local SQLite database for storing location points when offline
class LocationQueueLocal {
  Database? _database;

  static const String _tableName = 'location_queue';
  static const String _timelineTableName = 'timeline_events_queue';
  static const String _dbName = 'benzmobitraq_locations.db';
  // v5: added timeline_events_queue for offline-recordable
  //     start/end/break_start/break_end/stop events
  // v6: metadata JSON column for timeline events
  // v7: per-point quality fields for Stage 2 of distance rewrite:
  //     elapsed_realtime_nanos, is_mock, speed_accuracy_mps,
  //     bearing_accuracy_deg, activity_type, activity_confidence
  static const int _dbVersion = 7;

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
        address TEXT,
        provider TEXT,
        hash TEXT,
        counts_for_distance INTEGER DEFAULT 0,
        distance_delta_m REAL,
        recorded_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        uploaded INTEGER DEFAULT 0,
        upload_attempts INTEGER DEFAULT 0,
        last_upload_attempt INTEGER,
        elapsed_realtime_nanos INTEGER,
        is_mock INTEGER DEFAULT 0,
        speed_accuracy_mps REAL,
        bearing_accuracy_deg REAL,
        activity_type TEXT,
        activity_confidence INTEGER
      )
    ''');

    // Index for faster queries
    await db.execute('''
      CREATE INDEX idx_uploaded ON $_tableName (uploaded)
    ''');

    await db.execute('''
      CREATE INDEX idx_session ON $_tableName (session_id)
    ''');

    // v5 schema (also created on fresh installs)
    await _createTimelineEventsTable(db);
  }

  Future<void> _createTimelineEventsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_timelineTableName (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        employee_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        duration_sec INTEGER,
        latitude REAL,
        longitude REAL,
        address TEXT,
        metadata TEXT,
        created_at INTEGER NOT NULL,
        uploaded INTEGER DEFAULT 0,
        upload_attempts INTEGER DEFAULT 0
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_te_uploaded ON $_timelineTableName (uploaded)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_te_session ON $_timelineTableName (session_id)');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v2: add address column (required by LocationPointModel.toLocalJson)
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN address TEXT;');
      } catch (_) {/* ignore if already exists */}
    }

    // v3: add provider + hash columns (idempotency + provenance)
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN provider TEXT;');
      } catch (_) {/* ignore if already exists */}
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN hash TEXT;');
      } catch (_) {/* ignore if already exists */}
    }

    // v4: mark which raw points are accepted for distance rollups
    if (oldVersion < 4) {
      try {
        await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN counts_for_distance INTEGER DEFAULT 0;');
      } catch (_) {/* ignore if already exists */}
      try {
        await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN distance_delta_m REAL;');
      } catch (_) {/* ignore if already exists */}
    }

    // v5: queue for timeline_events so an offline-only session still
    // populates the admin's Timeline Log when sync happens.
    if (oldVersion < 5) {
      await _createTimelineEventsTable(db);
    }

    // v6: add metadata JSON column to existing timeline_events_queue.
    if (oldVersion < 6) {
      try {
        await db.execute(
            'ALTER TABLE $_timelineTableName ADD COLUMN metadata TEXT;');
      } catch (_) {/* ignore if already exists */}
    }

    // v7: per-point quality fields (Stage 2 of distance rewrite).
    // All nullable; existing rows get NULLs which the scorer treats as
    // "unknown" rather than rejecting the point.
    if (oldVersion < 7) {
      final newCols = <String, String>{
        'elapsed_realtime_nanos': 'INTEGER',
        'is_mock': 'INTEGER DEFAULT 0',
        'speed_accuracy_mps': 'REAL',
        'bearing_accuracy_deg': 'REAL',
        'activity_type': 'TEXT',
        'activity_confidence': 'INTEGER',
      };
      for (final entry in newCols.entries) {
        try {
          await db.execute(
              'ALTER TABLE $_tableName ADD COLUMN ${entry.key} ${entry.value};');
        } catch (_) {/* ignore if already exists */}
      }
    }
  }

  // ============================================================
  // TIMELINE EVENTS QUEUE
  // ============================================================
  //
  // We mirror EVERY successful + unsuccessful insert into
  // public.timeline_events here. On reconnect the sync worker walks
  // this table, replays unsynced rows in chronological order, and
  // marks them uploaded. Without this table, sessions tracked while
  // offline have completely empty admin Timeline Logs even after
  // the location-points sync finishes.

  Future<void> enqueueTimelineEvent({
    required String id,
    required String employeeId,
    required String sessionId,
    required String eventType,
    required DateTime startTime,
    DateTime? endTime,
    int? durationSec,
    double? latitude,
    double? longitude,
    String? address,
    Map<String, dynamic>? metadata,
  }) async {
    await db.insert(
      _timelineTableName,
      {
        'id': id,
        'session_id': sessionId,
        'employee_id': employeeId,
        'event_type': eventType,
        'start_time': startTime.millisecondsSinceEpoch,
        'end_time': endTime?.millisecondsSinceEpoch,
        'duration_sec': durationSec,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'metadata': metadata == null ? null : jsonEncode(metadata),
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'uploaded': 0,
        'upload_attempts': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getUnuploadedTimelineEvents(
      {int limit = 100}) async {
    return await db.query(
      _timelineTableName,
      where: 'uploaded = 0 AND upload_attempts < 8',
      orderBy: 'start_time ASC',
      limit: limit,
    );
  }

  Future<void> markTimelineEventUploaded(String id) async {
    await db.update(
      _timelineTableName,
      {'uploaded': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> incrementTimelineEventAttempts(String id) async {
    await db.rawUpdate(
      'UPDATE $_timelineTableName SET upload_attempts = upload_attempts + 1 WHERE id = ?',
      [id],
    );
  }

  Future<int> getUnuploadedTimelineEventCount() async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_timelineTableName WHERE uploaded = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ============================================================
  // QUEUE OPERATIONS
  // ============================================================

  /// Hard cap on the number of UNUPLOADED rows we are willing to keep
  /// in the local queue. Once exceeded we drop the oldest rows. Without
  /// this, a user who is offline for a week generates ~50k points and
  /// every subsequent insert + read gets progressively slower until the
  /// app feels broken. 20k is roughly 5 full days of dense tracking.
  static const int _maxUnuploadedRows = 20000;
  // How often to actually run the trim (insert-hot path).
  static const int _trimEveryNInserts = 200;
  int _insertsSinceTrim = 0;

  /// Add a location point to the queue
  Future<void> enqueue(LocationPointModel point) async {
    final data = point.toLocalJson();
    await db.insert(
      _tableName,
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    _insertsSinceTrim++;
    if (_insertsSinceTrim >= _trimEveryNInserts) {
      _insertsSinceTrim = 0;
      // Fire-and-forget so we never block the GPS write path.
      // ignore: unawaited_futures
      _trimUnuploadedIfTooLarge();
    }
  }

  Future<void> _trimUnuploadedIfTooLarge() async {
    try {
      final count = await getUnuploadedCount();
      if (count <= _maxUnuploadedRows) return;

      final excess = count - _maxUnuploadedRows;
      // Drop the *oldest* unuploaded points (the recent ones are far
      // more relevant for an in-progress session).
      await db.rawDelete('''
        DELETE FROM $_tableName
        WHERE id IN (
          SELECT id FROM $_tableName
          WHERE uploaded = 0
          ORDER BY recorded_at ASC
          LIMIT ?
        )
      ''', [excess]);
    } catch (_) {
      // never crash a tracking write because of a trim
    }
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
  Future<int> deleteOldUploaded(
      {Duration maxAge = const Duration(days: 7)}) async {
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

    final acceptedDistance = points
        .where((p) => p.countsForDistance && (p.distanceDeltaM ?? 0) > 0)
        .fold<double>(0.0, (sum, p) => sum + p.distanceDeltaM!);
    if (acceptedDistance > 0) return acceptedDistance;

    double totalDistance = 0.0;
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];

      // Calculate distance using Haversine approximation
      final distanceMeters = _approximateDistance(
        prev.latitude,
        prev.longitude,
        curr.latitude,
        curr.longitude,
      );

      totalDistance += distanceMeters;
    }

    return totalDistance;
  }

  /// Simple distance approximation (should use real Haversine in production)
  double _approximateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // meters
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);

    final double a = _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_toRadians(lat1)) *
            _cos(_toRadians(lat2)) *
            _sin(dLon / 2) *
            _sin(dLon / 2);

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
