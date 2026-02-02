import 'package:logger/logger.dart';

import '../datasources/local/location_queue_local.dart';
import '../datasources/remote/supabase_client.dart';
import '../models/location_point_model.dart';
import '../../core/constants/app_constants.dart';

/// Repository for handling location point operations
class LocationRepository {
  final SupabaseDataSource _dataSource;
  final LocationQueueLocal _localQueue;
  final Logger _logger = Logger();

  LocationRepository({
    required SupabaseDataSource dataSource,
    required LocationQueueLocal localQueue,
  })  : _dataSource = dataSource,
        _localQueue = localQueue;

  // ============================================================
  // LOCAL QUEUE OPERATIONS
  // ============================================================

  /// Add a location point to the local queue
  Future<void> queueLocation(LocationPointModel point) async {
    try {
      await _localQueue.enqueue(point);
      _logger.d('Location queued: ${point.id}');
    } catch (e) {
      _logger.e('Error queueing location: $e');
    }
  }

  /// Add multiple location points to the queue
  Future<void> queueLocations(List<LocationPointModel> points) async {
    try {
      await _localQueue.enqueueAll(points);
      _logger.d('${points.length} locations queued');
    } catch (e) {
      _logger.e('Error queueing locations: $e');
    }
  }

  /// Get the count of pending (unuploaded) locations
  Future<int> getPendingCount() async {
    try {
      return await _localQueue.getUnuploadedCount();
    } catch (e) {
      _logger.e('Error getting pending count: $e');
      return 0;
    }
  }

  /// Get the last recorded location for a session
  Future<LocationPointModel?> getLastLocation(String sessionId) async {
    try {
      return await _localQueue.getLastPoint(sessionId);
    } catch (e) {
      _logger.e('Error getting last location: $e');
      return null;
    }
  }

  /// Get approximate session distance from local data
  Future<double> getLocalSessionDistance(String sessionId) async {
    try {
      return await _localQueue.getSessionDistance(sessionId);
    } catch (e) {
      _logger.e('Error getting local session distance: $e');
      return 0;
    }
  }

  // ============================================================
  // REMOTE UPLOAD OPERATIONS
  // ============================================================

  /// Upload pending locations to server
  /// 
  /// Returns the number of points successfully uploaded
  Future<int> uploadPendingLocations() async {
    try {
      final pendingPoints = await _localQueue.getUnuploaded(
        limit: AppConstants.maxPointsPerBatch,
        maxAttempts: AppConstants.maxUploadRetries,
      );

      if (pendingPoints.isEmpty) {
        _logger.d('No pending locations to upload');
        return 0;
      }

      _logger.i('Uploading ${pendingPoints.length} location points');

      try {
        await _dataSource.uploadLocationBatch(pendingPoints);

        // Mark as uploaded
        final ids = pendingPoints.map((p) => p.id).toList();
        await _localQueue.markAsUploaded(ids);

        _logger.i('Successfully uploaded ${pendingPoints.length} points');
        return pendingPoints.length;
      } catch (e) {
        // Upload failed, increment retry counter
        final ids = pendingPoints.map((p) => p.id).toList();
        await _localQueue.incrementUploadAttempts(ids);
        
        _logger.e('Failed to upload batch of ${pendingPoints.length} locations. First ID: ${pendingPoints.first.id}. Error: $e');
        return 0;
      }
    } catch (e) {
      _logger.e('Error in upload process: $e');
      return 0;
    }
  }

  /// Force upload all remaining points for a session
  /// 
  /// Used when ending a session to ensure all data is uploaded
  Future<bool> forceUploadSession(String sessionId) async {
    try {
      final sessionPoints = await _localQueue.getBySession(sessionId);
      
      if (sessionPoints.isEmpty) {
        return true;
      }

      // Filter to only unuploaded points
      // Note: This is a simplified check - in production you'd want to
      // track uploaded status per point in the local query
      
      _logger.i('Force uploading ${sessionPoints.length} points for session $sessionId');

      // Upload in batches
      for (int i = 0; i < sessionPoints.length; i += AppConstants.maxPointsPerBatch) {
        final batch = sessionPoints.skip(i).take(AppConstants.maxPointsPerBatch).toList();
        
        try {
          await _dataSource.uploadLocationBatch(batch);
          
          final ids = batch.map((p) => p.id).toList();
          await _localQueue.markAsUploaded(ids);
        } catch (e) {
          _logger.e('Error uploading batch: $e');
          // Continue with next batch
        }
      }

      return true;
    } catch (e) {
      _logger.e('Error force uploading session: $e');
      return false;
    }
  }

  // ============================================================
  // REMOTE READ OPERATIONS
  // ============================================================

  /// Get location points for a session from server
  Future<List<LocationPointModel>> getSessionLocations(String sessionId) async {
    try {
      return await _dataSource.getSessionLocations(sessionId);
    } catch (e) {
      _logger.e('Error getting session locations: $e');
      return [];
    }
  }

  /// Get location points for an employee within a date range
  /// Used by AdminTimelineScreen for timeline generation
  Future<List<LocationPointModel>> getPointsByEmployeeAndDateRange({
    required String employeeId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      return await _dataSource.getPointsByEmployeeAndDateRange(
        employeeId: employeeId,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      _logger.e('Error getting points by date range: $e');
      return [];
    }
  }

  /// Get location points for the current user within a date range
  /// Used by MyTimelineScreen for the logged-in employee's timeline
  Future<List<LocationPointModel>> getLocationPointsForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      // Get current user ID from Supabase auth
      final userId = _dataSource.currentUserId;
      if (userId == null) {
        _logger.e('No logged in user');
        return [];
      }
      
      return await _dataSource.getPointsByEmployeeAndDateRange(
        employeeId: userId,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      _logger.e('Error getting points for date range: $e');
      return [];
    }
  }


  // ============================================================
  // EMPLOYEE STATE
  // ============================================================

  /// Update employee state with current location
  Future<void> updateEmployeeState({
    required String employeeId,
    String? sessionId,
    required double latitude,
    required double longitude,
    double? accuracy,
    double? todayKm,
  }) async {
    try {
      await _dataSource.updateEmployeeState(
        employeeId: employeeId,
        sessionId: sessionId,
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        todayKm: todayKm,
      );
    } catch (e) {
      _logger.e('Error updating employee state: $e');
    }
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  /// Clean up old uploaded data
  Future<void> cleanupOldData() async {
    try {
      final deleted = await _localQueue.deleteOldUploaded();
      if (deleted > 0) {
        _logger.i('Cleaned up $deleted old location records');
      }
    } catch (e) {
      _logger.e('Error cleaning up old data: $e');
    }
  }

  /// Clear all local queue data
  Future<void> clearLocalQueue() async {
    try {
      await _localQueue.clearAll();
      _logger.i('Local queue cleared');
    } catch (e) {
      _logger.e('Error clearing local queue: $e');
    }
  }
}
