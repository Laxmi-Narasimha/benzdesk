import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';

import '../../models/employee_model.dart';
import '../../models/session_model.dart';
import '../../models/location_point_model.dart';
import '../../models/notification_model.dart';
import '../../models/expense_model.dart';

/// Remote data source for Supabase operations
class SupabaseDataSource {
  final SupabaseClient _client;
  final Logger _logger = Logger();

  SupabaseDataSource(this._client);

  /// Get the current logged in user's ID
  String? get currentUserId => _client.auth.currentUser?.id;

  // ============================================================
  // EMPLOYEES
  // ============================================================

  /// Get employee by ID
  Future<EmployeeModel?> getEmployee(String id) async {
    final response = await _client
        .from('employees')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return EmployeeModel.fromJson(response);
  }

  /// Create or update employee profile
  Future<EmployeeModel> upsertEmployee(EmployeeModel employee) async {
    final response = await _client
        .from('employees')
        .upsert(employee.toJson())
        .select()
        .single();

    return EmployeeModel.fromJson(response);
  }

  /// Update device token for push notifications
  Future<void> updateDeviceToken(String employeeId, String token) async {
    await _client
        .from('employees')
        .update({
          'device_token': token,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', employeeId);
  }

  /// Get all employees (admin only)
  Future<List<EmployeeModel>> getAllEmployees() async {
    final response = await _client
        .from('employees')
        .select()
        .eq('is_active', true)
        .order('name');

    return (response as List)
        .map((e) => EmployeeModel.fromJson(e))
        .toList();
  }

  // ============================================================
  // SESSIONS
  // ============================================================

  /// Create a new work session
  Future<SessionModel> createSession(SessionModel session) async {
    final response = await _client
        .from('shift_sessions')
        .insert(session.toJson())
        .select()
        .single();

    return SessionModel.fromJson(response);
  }

  /// Get session by ID
  Future<SessionModel?> getSession(String id) async {
    final response = await _client
        .from('shift_sessions')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return SessionModel.fromJson(response);
  }

  /// Get active session for employee
  Future<SessionModel?> getActiveSession(String employeeId) async {
    final response = await _client
        .from('shift_sessions')
        .select()
        .eq('employee_id', employeeId)
        .eq('status', 'active')
        .maybeSingle();

    if (response == null) return null;
    return SessionModel.fromJson(response);
  }

  /// End a work session
  Future<SessionModel> endSession({
    required String sessionId,
    required double totalKm,
    double? endLatitude,
    double? endLongitude,
    String? endAddress,
  }) async {
    final response = await _client
        .from('shift_sessions')
        .update({
          'end_time': DateTime.now().toIso8601String(),
          'end_latitude': endLatitude,
          'end_longitude': endLongitude,
          'end_address': endAddress,
          'total_km': totalKm,
          'status': 'completed',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId)
        .select()
        .single();

    return SessionModel.fromJson(response);
  }

  /// Update session km
  Future<void> updateSessionKm(String sessionId, double totalKm) async {
    await _client
        .from('shift_sessions')
        .update({
          'total_km': totalKm,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId);
  }

  /// Get sessions for employee (with pagination)
  Future<List<SessionModel>> getEmployeeSessions({
    required String employeeId,
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _client
        .from('shift_sessions')
        .select()
        .eq('employee_id', employeeId)
        .order('start_time', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List)
        .map((e) => SessionModel.fromJson(e))
        .toList();
  }

  /// Get today's sessions for employee
  Future<List<SessionModel>> getTodaySessions(String employeeId) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final response = await _client
        .from('shift_sessions')
        .select()
        .eq('employee_id', employeeId)
        .gte('start_time', startOfDay.toIso8601String())
        .lt('start_time', endOfDay.toIso8601String())
        .order('start_time', ascending: false);

    return (response as List)
        .map((e) => SessionModel.fromJson(e))
        .toList();
  }

  /// Get sessions for current month (stats)
  Future<List<SessionModel>> getMonthlySessions(String employeeId) async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 1);

    final response = await _client
        .from('shift_sessions')
        .select()
        .eq('employee_id', employeeId)
        .gte('start_time', startOfMonth.toIso8601String())
        .lt('start_time', endOfMonth.toIso8601String());

    return (response as List)
        .map((e) => SessionModel.fromJson(e))
        .toList();
  }

  // ============================================================
  // LOCATION POINTS
  // ============================================================

  /// Upload a batch of location points
  Future<void> uploadLocationBatch(List<LocationPointModel> points) async {
    if (points.isEmpty) return;

    try {
      final data = points.map((p) => p.toJson()).toList();
      
      // Enhanced diagnostic logging
      _logger.i('SYNC: Uploading ${points.length} location points...');
      _logger.d('SYNC: Session: ${points.first.sessionId}');
      _logger.d('SYNC: Employee: ${points.first.employeeId}');
      _logger.d('SYNC: Auth UID: $currentUserId');
      _logger.d('SYNC: Hash: ${data.first['hash']}');
      
      // Verify employee_id matches auth.uid (RLS requirement)
      if (points.first.employeeId != currentUserId) {
        _logger.e('SYNC WARNING: employee_id (${points.first.employeeId}) != auth.uid ($currentUserId)');
      }
      
      try {
        // Try upsert first (idempotent)
        await _client.from('location_points').upsert(data, onConflict: 'hash');
        _logger.i('SYNC: Successfully uploaded ${points.length} points via upsert');
      } catch (upsertError) {
        _logger.w('SYNC: Upsert failed, trying insert: $upsertError');
        
        // Fallback to insert (handles case where hash column issue)
        try {
          await _client.from('location_points').insert(data);
          _logger.i('SYNC: Successfully uploaded ${points.length} points via insert');
        } catch (insertError) {
          // If insert fails due to schema drift (missing columns), retry with a sanitized payload.
          final msg = insertError.toString().toLowerCase();
          if (msg.contains('column') &&
              (msg.contains('hash') || msg.contains('provider') || msg.contains('address'))) {
            _logger.w('SYNC: Insert failed due to missing columns. Retrying with sanitized payload...');

            final sanitized = data.map((row) {
              final copy = Map<String, dynamic>.from(row);
              copy.remove('hash');
              copy.remove('provider');
              copy.remove('address');
              return copy;
            }).toList();

            try {
              await _client.from('location_points').insert(sanitized);
              _logger.i('SYNC: Successfully uploaded ${points.length} points via sanitized insert');
              return;
            } catch (sanitizedError) {
              _logger.e('SYNC CRITICAL: Sanitized insert also failed: $sanitizedError');
              rethrow;
            }
          }

          // If insert also fails, it's likely an RLS issue
          _logger.e('SYNC CRITICAL: Insert also failed: $insertError');
          _logger.e('SYNC: This is likely an RLS policy issue. Check employee_id matches auth.uid.');
          rethrow;
        }
      }
    } catch (e) {
      _logger.e('SYNC FAILED: $e');
      _logger.e('SYNC: Points employee_id: ${points.first.employeeId}, auth.uid: $currentUserId');
      rethrow;
    }
  }

  /// Get location points for a session
  Future<List<LocationPointModel>> getSessionLocations(String sessionId) async {
    final response = await _client
        .from('location_points')
        .select()
        .eq('session_id', sessionId)
        .order('recorded_at');

    return (response as List)
        .map((e) => LocationPointModel.fromJson(e))
        .toList();
  }

  /// Get location points for an employee within a date range
  /// Used by AdminTimelineScreen
  Future<List<LocationPointModel>> getPointsByEmployeeAndDateRange({
    required String employeeId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await _client
        .from('location_points')
        .select()
        .eq('employee_id', employeeId)
        .gte('recorded_at', startDate.toIso8601String())
        .lt('recorded_at', endDate.toIso8601String())
        .order('recorded_at');

    return (response as List)
        .map((e) => LocationPointModel.fromJson(e))
        .toList();
  }

  /// Get all employees (admin view with active status)
  Future<List<Map<String, dynamic>>> getActiveEmployeesList() async {
    final response = await _client
        .from('employees')
        .select('id, name, email, role')
        .eq('is_active', true)
        .order('name');

    return (response as List).cast<Map<String, dynamic>>();
  }

  // ============================================================
  // EMPLOYEE STATE
  // ============================================================


  /// Update employee state (for stuck detection)
  Future<void> updateEmployeeState({
    required String employeeId,
    String? sessionId,
    double? latitude,
    double? longitude,
    double? accuracy,
    String? address,
    double? todayKm,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    await _client.from('employee_states').upsert({
      'employee_id': employeeId,
      'current_session_id': sessionId,
      'last_latitude': latitude,
      'last_longitude': longitude,
      'last_accuracy': accuracy,
      'last_address': address,
      'last_update': now.toIso8601String(),
      'today_km': todayKm,
      'today_date': today.toIso8601String().split('T')[0],
      'updated_at': now.toIso8601String(),
    });
  }

  /// Clear employee state (when session ends)
  Future<void> clearEmployeeState(String employeeId) async {
    await _client.from('employee_states').upsert({
      'employee_id': employeeId,
      'current_session_id': null,
      'is_stuck': false,
      'stuck_alert_sent': false,
      'anchor_latitude': null,
      'anchor_longitude': null,
      'anchor_time': null,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // ============================================================
  // NOTIFICATIONS
  // ============================================================

  /// Get notifications for user
  Future<List<NotificationModel>> getNotifications({
    required String userId,
    required bool isAdmin,
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _client.from('mobile_notifications').select();

    if (isAdmin) {
      // Admins see admin-role notifications or ones addressed to them
      query = query.or('recipient_id.eq.$userId,recipient_role.eq.admin');
    } else {
      // Regular employees only see their own notifications
      query = query.eq('recipient_id', userId);
    }

    final response = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List)
        .map((e) => NotificationModel.fromJson(e))
        .toList();
  }

  /// Get unread notification count
  Future<int> getUnreadNotificationCount({
    required String userId,
    required bool isAdmin,
  }) async {
    var query = _client.from('mobile_notifications').select('id');

    if (isAdmin) {
      query = query.or('recipient_id.eq.$userId,recipient_role.eq.admin');
    } else {
      query = query.eq('recipient_id', userId);
    }

    final response = await query.eq('is_read', false);
    return (response as List).length;
  }

  /// Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    await _client
        .from('mobile_notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  /// Mark all notifications as read
  Future<void> markAllNotificationsAsRead({
    required String userId,
    required bool isAdmin,
  }) async {
    if (isAdmin) {
      await _client
          .from('mobile_notifications')
          .update({'is_read': true})
          .or('recipient_id.eq.$userId,recipient_role.eq.admin');
    } else {
      await _client
          .from('mobile_notifications')
          .update({'is_read': true})
          .eq('recipient_id', userId);
    }
  }

  // ============================================================
  // EXPENSES
  // ============================================================

  /// Create expense claim
  Future<ExpenseClaimModel> createExpenseClaim(ExpenseClaimModel claim) async {
    try {
      _logger.d('Creating expense claim...');
      _logger.d('Claim employee_id: ${claim.employeeId}');
      _logger.d('Current auth.uid: $currentUserId');
      
      final response = await _client
          .from('expense_claims')
          .insert(claim.toJson())
          .select()
          .single();

      _logger.i('Expense claim created successfully: ${response['id']}');
      return ExpenseClaimModel.fromJson(response);
    } catch (e) {
      _logger.e('CRITICAL: Failed to create expense claim: $e');
      _logger.e('Claim employee_id: ${claim.employeeId}');
      _logger.e('Current auth.uid: $currentUserId');
      rethrow;
    }
  }

  /// Get expense claim by ID
  Future<ExpenseClaimModel?> getExpenseClaim(String id) async {
    final response = await _client
        .from('expense_claims')
        .select('*, expense_items(*)')
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return ExpenseClaimModel.fromJson(response);
  }

  /// Get expense claims for employee
  Future<List<Map<String, dynamic>>> getEmployeeExpenses({
    required String employeeId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _client
          .from('expense_claims')
          .select('*, employees(name, phone), expense_items(*)')
          .eq('employee_id', employeeId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.e('Error fetching employee expenses: $e');
      rethrow;
    }
  }

  /// Create a timeline event (e.g. stop)
  Future<void> createTimelineEvent({
    required String employeeId,
    required String sessionId,
    required String eventType, // 'stop', 'move'
    required DateTime startTime,
    required DateTime endTime,
    int? durationSec,
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    try {
      final startUtc = startTime.toUtc();
      final endUtc = endTime.toUtc();
      final data = {
        'employee_id': employeeId,
        'session_id': sessionId,
        'day': startUtc.toIso8601String().split('T')[0],
        'event_type': eventType,
        'start_time': startUtc.toIso8601String(),
        'end_time': endUtc.toIso8601String(),
        'duration_sec': durationSec ?? endUtc.difference(startUtc).inSeconds,
        'center_lat': latitude,
        'center_lng': longitude,
        'address': address,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      await _client.from('timeline_events').insert(data);
      _logger.i('Created timeline event: $eventType');
    } catch (e) {
      _logger.e('Error creating timeline event: $e');
      // Don't rethrow to avoid disrupting tracking flow
    }
  }

  /// Create an alert
  Future<void> createAlert({
    required String employeeId,
    String? sessionId,
    required String alertType,
    required String message,
    required String severity,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final data = {
        'employee_id': employeeId,
        'session_id': sessionId,
        'alert_type': alertType,
        'message': message,
        'severity': severity,
        'start_time': DateTime.now().toUtc().toIso8601String(),
        'lat': latitude,
        'lng': longitude,
        'is_open': true,
      };

      await _client.from('mobitraq_alerts').insert(data);
      _logger.i('Created alert: $alertType');
    } catch (e) {
      _logger.e('Error creating alert: $e');
    }
  }
  /// Add expense item
  Future<ExpenseItemModel> addExpenseItem(ExpenseItemModel item) async {
    final response = await _client
        .from('expense_items')
        .insert(item.toJson())
        .select()
        .single();

    return ExpenseItemModel.fromJson(response);
  }

  /// Update expense claim total
  Future<void> updateExpenseClaimTotal(String claimId) async {
    // Calculate total from items
    final itemsResponse = await _client
        .from('expense_items')
        .select('amount')
        .eq('claim_id', claimId);

    double total = 0;
    for (final item in itemsResponse as List) {
      total += (item['amount'] as num).toDouble();
    }

    await _client
        .from('expense_claims')
        .update({
          'total_amount': total,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', claimId);
  }

  /// Submit expense claim
  Future<ExpenseClaimModel> submitExpenseClaim(String claimId) async {
    final response = await _client
        .from('expense_claims')
        .update({
          'status': 'submitted',
          'submitted_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', claimId)
        .select()
        .single();

    return ExpenseClaimModel.fromJson(response);
  }

  /// Delete expense item
  Future<void> deleteExpenseItem(String itemId) async {
    await _client.from('expense_items').delete().eq('id', itemId);
  }

  /// Delete expense claim
  Future<void> deleteExpenseClaim(String claimId) async {
    // Items will be deleted via CASCADE
    await _client.from('expense_claims').delete().eq('id', claimId);
  }

  // ============================================================
  // APP SETTINGS
  // ============================================================

  /// Get app setting by key
  Future<dynamic> getSetting(String key) async {
    final response = await _client
        .from('mobile_app_settings')
        .select('value')
        .eq('key', key)
        .maybeSingle();

    return response?['value'];
  }

  /// Get all app settings
  Future<Map<String, dynamic>> getAllSettings() async {
    final response = await _client.from('mobile_app_settings').select();

    final settings = <String, dynamic>{};
    for (final row in response as List) {
      settings[row['key']] = row['value'];
    }
    return settings;
  }
}
