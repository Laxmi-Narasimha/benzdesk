import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../datasources/local/preferences_local.dart';
import '../datasources/remote/supabase_client.dart';
import '../models/session_model.dart';

/// Repository for handling work session operations
class SessionRepository {
  final SupabaseDataSource _dataSource;
  final PreferencesLocal _preferences;
  final Logger _logger = Logger();
  final Uuid _uuid = const Uuid();

  SessionRepository({
    required SupabaseDataSource dataSource,
    required PreferencesLocal preferences,
  })  : _dataSource = dataSource,
        _preferences = preferences;

  /// Check if there's an active session
  bool get hasActiveSession => _preferences.hasActiveSession;

  /// Get active session ID from local storage
  String? get activeSessionId => _preferences.activeSessionId;

  /// Resolve the current authenticated user id (Supabase auth.uid).
  ///
  /// RLS policies require employee_id to match auth.uid(). If preferences are
  /// stale (or were never set), prefer the live Supabase auth uid and sync it
  /// back into preferences.
  Future<String?> resolveCurrentUserId() async {
    final authUid = _dataSource.currentUserId;
    final prefsUid = _preferences.userId;

    if (authUid != null) {
      if (prefsUid != authUid) {
        await _preferences.setUserId(authUid);
      }
      return authUid;
    }

    return prefsUid;
  }

  /// Start a new work session with a pre-created model (used by SessionManager)
  Future<bool> startSession(
    SessionModel session,
    double latitude,
    double longitude,
  ) async {
    try {
      final userId = await resolveCurrentUserId();
      if (userId == null) {
        _logger.e('User not authenticated');
        return false;
      }

      _logger.i('Starting session: ${session.id}');
      
      await _dataSource.createSession(session);
      
      // Store session ID locally
      await _preferences.setActiveSessionId(session.id);

      // Update employee state
      await _dataSource.updateEmployeeState(
        employeeId: userId,
        sessionId: session.id,
        latitude: latitude,
        longitude: longitude,
        address: session.startAddress,
        todayKm: 0,
      );

      _logger.i('Session started successfully: ${session.id}');
      return true;
    } catch (e) {
      _logger.e('Error starting session: $e');
      return false;
    }
  }

  /// Start a new work session (Present button) - legacy method
  Future<SessionResult> startSessionLegacy({
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    try {
      final userId = await resolveCurrentUserId();
      if (userId == null) {
        return SessionResult.failure('User not authenticated');
      }

      // Check if there's already an active session
      final existingSession = await _dataSource.getActiveSession(userId);
      if (existingSession != null) {
        _logger.w('Active session already exists: ${existingSession.id}');
        await _preferences.setActiveSessionId(existingSession.id);
        return SessionResult.success(existingSession);
      }

      // Create new session
      final sessionId = _uuid.v4();
      final session = SessionModel.start(
        id: sessionId,
        employeeId: userId,
        latitude: latitude,
        longitude: longitude,
        address: address,
      );

      _logger.i('Starting new session: $sessionId');
      
      final createdSession = await _dataSource.createSession(session);
      
      // Store session ID locally
      await _preferences.setActiveSessionId(createdSession.id);

      // Update employee state
      await _dataSource.updateEmployeeState(
        employeeId: userId,
        sessionId: createdSession.id,
        latitude: latitude,
        longitude: longitude,
        address: address,
        todayKm: 0,
      );

      _logger.i('Session started successfully: ${createdSession.id}');
      return SessionResult.success(createdSession);
    } catch (e) {
      _logger.e('Error starting session: $e');
      return SessionResult.failure('Failed to start session: $e');
    }
  }

  /// Stop the current work session (used by SessionManager)
  Future<SessionModel?> stopSession(
    String sessionId,
    double? latitude,
    double? longitude,
    double totalKm, {
    String? address,
  }) async {
    try {
      final userId = await resolveCurrentUserId();
      if (userId == null) {
        _logger.e('User not authenticated');
        return null;
      }

      _logger.i('Stopping session: $sessionId with $totalKm km');

      final updatedSession = await _dataSource.endSession(
        sessionId: sessionId,
        totalKm: 0, // CRITICAL FIX: Send 0 or ignore. Let Backpack Trigger calculate true distance.
        endLatitude: latitude,
        endLongitude: longitude,
        endAddress: address,
      );

      // Clear local session
      await _preferences.setActiveSessionId(null);

      // Clear employee state
      await _dataSource.clearEmployeeState(userId);

      _logger.i('Session stopped successfully: ${updatedSession.id}');
      return updatedSession;
    } catch (e) {
      _logger.e('Error stopping session: $e');
      return null;
    }
  }

  /// Stop the current work session (Work Done button) - legacy method
  Future<SessionResult> stopSessionLegacy({
    required double totalKm,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final sessionId = _preferences.activeSessionId;
      if (sessionId == null) {
        return SessionResult.failure('No active session found');
      }

      final result = await stopSession(sessionId, latitude, longitude, totalKm);
      if (result != null) {
        return SessionResult.success(result);
      } else {
        return SessionResult.failure('Failed to stop session');
      }
    } catch (e) {
      _logger.e('Error stopping session: $e');
      return SessionResult.failure('Failed to stop session: $e');
    }
  }

  /// Get the current active session
  Future<SessionModel?> getActiveSession() async {
    try {
      final userId = await resolveCurrentUserId();
      if (userId == null) return null;

      // First check local storage
      final localSessionId = _preferences.activeSessionId;
      
      // Verify with server
      final serverSession = await _dataSource.getActiveSession(userId);

      if (serverSession == null && localSessionId != null) {
        // Local session exists but not on server, clear it
        await _preferences.setActiveSessionId(null);
        return null;
      }

      if (serverSession != null && localSessionId != serverSession.id) {
        // Sync local with server
        await _preferences.setActiveSessionId(serverSession.id);
      }

      return serverSession;
    } catch (e) {
      _logger.e('Error getting active session: $e');
      return null;
    }
  }

  /// Get session by ID
  Future<SessionModel?> getSession(String sessionId) async {
    try {
      return await _dataSource.getSession(sessionId);
    } catch (e) {
      _logger.e('Error getting session $sessionId: $e');
      return null;
    }
  }

  /// Update session km
  Future<void> updateSessionKm(String sessionId, double totalKm) async {
    try {
      await _dataSource.updateSessionKm(sessionId, totalKm);
      _logger.d('Updated session $sessionId with $totalKm km');
    } catch (e) {
      _logger.e('Error updating session km: $e');
    }
  }

  /// Get today's sessions for current user
  Future<List<SessionModel>> getTodaySessions() async {
    try {
      final userId = await resolveCurrentUserId();
      if (userId == null) return [];

      return await _dataSource.getTodaySessions(userId);
    } catch (e) {
      _logger.e('Error getting today sessions: $e');
      return [];
    }
  }

  /// Get session history for current user
  Future<List<SessionModel>> getSessionHistory({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final userId = await resolveCurrentUserId();
      if (userId == null) return [];

      return await _dataSource.getEmployeeSessions(
        employeeId: userId,
        limit: limit,
        offset: offset,
      );
    } catch (e) {
      _logger.e('Error getting session history: $e');
      return [];
    }
  }

  /// Get total km for today
  Future<double> getTodayTotalKm() async {
    try {
      final sessions = await getTodaySessions();
      
      double total = 0;
      for (final session in sessions) {
        total += session.totalKm;
      }
      
      return total;
    } catch (e) {
      _logger.e('Error getting today total km: $e');
      return 0;
    }
  }

  /// Get monthly statistics
  Future<Map<String, dynamic>> getMonthlyStats() async {
    try {
      final userId = await resolveCurrentUserId();
      if (userId == null) return {'distance': 0.0, 'duration': Duration.zero, 'count': 0};

      final sessions = await _dataSource.getMonthlySessions(userId);
      
      double totalDistance = 0;
      Duration totalDuration = Duration.zero;
      
      for (final session in sessions) {
        totalDistance += session.totalKm;
        
        final end = session.endTime ?? DateTime.now();
        final duration = end.difference(session.startTime);
        if (!duration.isNegative) {
          totalDuration += duration;
        }
      }
      
      return {
        'distance': totalDistance,
        'duration': totalDuration,
        'count': sessions.length,
      };
    } catch (e) {
      _logger.e('Error getting monthly stats: $e');
      return {'distance': 0.0, 'duration': Duration.zero, 'count': 0};
    }
  }

  /// Sync active session state with server
  Future<void> syncSessionState() async {
    try {
      final userId = await resolveCurrentUserId();
      if (userId == null) return;

      final serverSession = await _dataSource.getActiveSession(userId);
      
      if (serverSession != null) {
        await _preferences.setActiveSessionId(serverSession.id);
      } else {
        await _preferences.setActiveSessionId(null);
      }
    } catch (e) {
      _logger.e('Error syncing session state: $e');
    }
  }

  /// Get all active employees (for admin screens)
  Future<List<Map<String, dynamic>>> getActiveEmployees() async {
    try {
      return await _dataSource.getActiveEmployeesList();
    } catch (e) {
      _logger.e('Error getting active employees: $e');
      return [];
    }
  }
}


/// Result class for session operations
class SessionResult {
  final bool success;
  final SessionModel? session;
  final String? error;

  const SessionResult._({
    required this.success,
    this.session,
    this.error,
  });

  factory SessionResult.success(SessionModel session) {
    return SessionResult._(success: true, session: session);
  }

  factory SessionResult.failure(String error) {
    return SessionResult._(success: false, error: error);
  }
}
