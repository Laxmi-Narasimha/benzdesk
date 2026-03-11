import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../models/notification_settings.dart';

/// Local data source for storing preferences using SharedPreferences
class PreferencesLocal {
  SharedPreferences? _prefs;

  /// Initialize SharedPreferences instance
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Get SharedPreferences instance
  SharedPreferences get prefs {
    if (_prefs == null) {
      throw Exception('PreferencesLocal not initialized. Call init() first.');
    }
    return _prefs!;
  }

  // ============================================================
  // AUTHENTICATION
  // ============================================================

  /// Check if user is logged in
  bool get isLoggedIn => prefs.getBool(AppConstants.keyIsLoggedIn) ?? false;

  /// Set logged in state
  Future<bool> setLoggedIn(bool value) {
    return prefs.setBool(AppConstants.keyIsLoggedIn, value);
  }

  /// Get current user ID
  String? get userId => prefs.getString(AppConstants.keyUserId);

  /// Get user ID (method form for SessionManager)
  Future<String?> getUserId() async {
    return userId;
  }

  /// Set current user ID
  Future<bool> setUserId(String? value) {
    if (value == null) {
      return prefs.remove(AppConstants.keyUserId);
    }
    return prefs.setString(AppConstants.keyUserId, value);
  }

  /// Get current user role
  String? get userRole => prefs.getString(AppConstants.keyUserRole);

  /// Set current user role
  Future<bool> setUserRole(String? value) {
    if (value == null) {
      return prefs.remove(AppConstants.keyUserRole);
    }
    return prefs.setString(AppConstants.keyUserRole, value);
  }

  /// Check if current user is admin
  bool get isAdmin => userRole == 'admin';

  // ============================================================
  // DEVICE TOKEN (FCM)
  // ============================================================

  /// Get FCM device token
  String? get deviceToken => prefs.getString(AppConstants.keyDeviceToken);

  /// Set FCM device token
  Future<bool> setDeviceToken(String? value) {
    if (value == null) {
      return prefs.remove(AppConstants.keyDeviceToken);
    }
    return prefs.setString(AppConstants.keyDeviceToken, value);
  }

  // ============================================================
  // ACTIVE SESSION
  // ============================================================

  /// Get active session ID (if tracking is in progress)
  String? get activeSessionId => prefs.getString(AppConstants.keyActiveSessionId);

  /// Get active session ID (method form for SessionManager)
  Future<String?> getActiveSessionId() async {
    return activeSessionId;
  }

  /// Set active session ID
  Future<bool> setActiveSessionId(String? value) {
    if (value == null) {
      return prefs.remove(AppConstants.keyActiveSessionId);
    }
    return prefs.setString(AppConstants.keyActiveSessionId, value);
  }

  /// Save active session (alias for setActiveSessionId)
  Future<void> saveActiveSession(String sessionId) async {
    await setActiveSessionId(sessionId);
  }

  /// Clear active session
  Future<void> clearActiveSession() async {
    await setActiveSessionId(null);
    await clearSessionStartTime();
    await clearSessionDistance();
  }

  /// Get session start time for duration calculation
  DateTime? getSessionStartTime() {
    final timestamp = prefs.getInt('session_start_time');
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Set session start time (for timer persistence)
  Future<bool> setSessionStartTime(DateTime time) {
    return prefs.setInt('session_start_time', time.millisecondsSinceEpoch);
  }

  /// Clear session start time
  Future<bool> clearSessionStartTime() {
    return prefs.remove('session_start_time');
  }

  /// Get session distance in meters (for persistence across app restart)
  double getSessionDistanceMeters() {
    return prefs.getDouble('session_distance_meters') ?? 0.0;
  }

  /// Set session distance in meters (called on each location update)
  Future<bool> setSessionDistanceMeters(double meters) {
    return prefs.setDouble('session_distance_meters', meters);
  }

  /// Clear session distance
  Future<bool> clearSessionDistance() {
    return prefs.remove('session_distance_meters');
  }

  /// Check if there's an active session
  bool get hasActiveSession => activeSessionId != null;

  /// Get cached session model JSON (for offline resume)
  String? get cachedSessionJson => prefs.getString('cached_session_json');

  /// Set cached session model JSON
  Future<bool> setCachedSessionJson(String json) {
    return prefs.setString('cached_session_json', json);
  }

  /// Clear cached session model
  Future<bool> clearCachedSession() {
    return prefs.remove('cached_session_json');
  }

  // ============================================================
  // SYNC STATUS
  // ============================================================

  /// Get last sync time
  DateTime? get lastSyncTime {
    final timestamp = prefs.getInt(AppConstants.keyLastSyncTime);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Set last sync time
  Future<bool> setLastSyncTime(DateTime value) {
    return prefs.setInt(
      AppConstants.keyLastSyncTime,
      value.millisecondsSinceEpoch,
    );
  }

  /// Save last sync time (alias for setLastSyncTime)
  Future<void> saveLastSyncTime(DateTime time) async {
    await setLastSyncTime(time);
  }

  // ============================================================
  // NOTIFICATION SETTINGS
  // ============================================================

  /// Get notification settings JSON
  String? get notificationSettingsJson => 
      prefs.getString(AppConstants.keyNotificationSettings);

  /// Set notification settings JSON
  Future<bool> setNotificationSettingsJson(String json) {
    return prefs.setString(AppConstants.keyNotificationSettings, json);
  }

  /// Get parsed notification settings (method form for SessionManager)
  /// Returns null if no settings saved, defaults will be used by caller
  Future<NotificationSettings?> getNotificationSettings() async {
    final json = notificationSettingsJson;
    if (json == null) return null;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return NotificationSettings.fromJson(map);
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // LAST KNOWN ADDRESS
  // ============================================================

  /// Get last known address
  String? get lastKnownAddress => 
      prefs.getString(AppConstants.keyLastKnownAddress);

  /// Set last known address
  Future<bool> setLastKnownAddress(String address) {
    return prefs.setString(AppConstants.keyLastKnownAddress, address);
  }

  // ============================================================
  // CLEAR DATA
  // ============================================================

  /// Clear all authentication data (on logout)
  Future<void> clearAuthData() async {
    await setLoggedIn(false);
    await setUserId(null);
    await setUserRole(null);
    await setActiveSessionId(null);
  }

  /// Clear all preferences
  Future<bool> clearAll() {
    return prefs.clear();
  }
  // ============================================================
  // OFFLINE SESSION END (PENDING SYNC)
  // ============================================================

  /// Get pending session end data (if any)
  /// Returns a Map with keys: sessionId, endTime (iso), latitude, longitude, address, totalKm
  Map<String, dynamic>? getPendingSessionEnd() {
    final jsonStr = prefs.getString('pending_session_end');
    if (jsonStr == null) return null;
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Save pending session end data
  Future<bool> setPendingSessionEnd({
    required String sessionId,
    required DateTime endTime,
    required double? latitude,
    required double? longitude,
    required String? address,
    required double totalKm,
  }) {
    final data = {
      'sessionId': sessionId,
      'endTime': endTime.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'totalKm': totalKm,
    };
    return prefs.setString('pending_session_end', jsonEncode(data));
  }

  /// Clear pending session end data
  Future<bool> clearPendingSessionEnd() {
    return prefs.remove('pending_session_end');
  }

  // ============================================================
  // CACHED EMPLOYEE PROFILE (OFFLINE AUTH)
  // ============================================================

  /// Get cached employee profile JSON
  String? get cachedEmployeeProfileJson => prefs.getString('cached_employee_profile');

  /// Save cached employee profile
  Future<bool> setCachedEmployeeProfileJson(String json) {
    return prefs.setString('cached_employee_profile', json);
  }

  /// Clear cached employee profile
  Future<bool> clearCachedEmployeeProfile() {
    return prefs.remove('cached_employee_profile');
  }
}

