import 'dart:async';
import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:benzmobitraq_mobile/data/models/session_model.dart';
import 'package:benzmobitraq_mobile/data/models/location_point_model.dart';
import 'package:benzmobitraq_mobile/data/models/notification_settings.dart';

import 'package:benzmobitraq_mobile/data/repositories/session_repository.dart';
import 'package:benzmobitraq_mobile/data/repositories/location_repository.dart';
import 'package:benzmobitraq_mobile/data/repositories/expense_repository.dart';
import 'package:benzmobitraq_mobile/data/datasources/local/preferences_local.dart';
import 'package:benzmobitraq_mobile/core/distance_engine.dart';
import 'package:benzmobitraq_mobile/services/tracking_service.dart';
import 'package:benzmobitraq_mobile/services/permission_service.dart';
import 'package:benzmobitraq_mobile/services/geocoding_service.dart';
import 'package:benzmobitraq_mobile/services/notification_scheduler.dart';
import 'package:benzmobitraq_mobile/services/timeline_recorder.dart';
import 'package:benzmobitraq_mobile/services/notification_service.dart';

/// Session status for UI feedback
enum ManagerSessionStatus {
  idle, // No active session
  starting, // Starting session
  active, // Session running, tracking active
  stopping, // Stopping session
  error, // Error occurred
}

/// Current session state with all relevant data
///
/// Named ManagerSessionState to avoid conflict with BLoC's SessionState
class ManagerSessionState {
  final ManagerSessionStatus status;
  final SessionModel? session;
  final double currentDistanceMeters;
  final Duration duration;
  final LocationUpdate? lastLocation;
  final String? errorMessage;
  final List<String> warnings;
  final bool isPaused;

  const ManagerSessionState({
    this.status = ManagerSessionStatus.idle,
    this.session,
    this.currentDistanceMeters = 0,
    this.duration = Duration.zero,
    this.lastLocation,
    this.errorMessage,
    this.warnings = const [],
    this.isPaused = false,
  });

  double get currentDistanceKm => currentDistanceMeters / 1000;

  ManagerSessionState copyWith({
    ManagerSessionStatus? status,
    SessionModel? session,
    double? currentDistanceMeters,
    Duration? duration,
    LocationUpdate? lastLocation,
    String? errorMessage,
    List<String>? warnings,
    bool? isPaused,
  }) {
    return ManagerSessionState(
      status: status ?? this.status,
      session: session ?? this.session,
      currentDistanceMeters:
          currentDistanceMeters ?? this.currentDistanceMeters,
      duration: duration ?? this.duration,
      lastLocation: lastLocation ?? this.lastLocation,
      errorMessage: errorMessage ?? this.errorMessage,
      warnings: warnings ?? this.warnings,
      isPaused: isPaused ?? this.isPaused,
    );
  }
}

/// Session Manager - Orchestrates the entire tracking workflow
///
/// This is the main controller that ties together:
/// - Session lifecycle (Present → Work Done)
/// - Location tracking service
/// - Local queue for offline storage
/// - Sync to backend
///
/// Usage:
/// ```dart
/// final manager = SessionManager(...);
/// await manager.initialize();
///
/// // Start work
/// await manager.startSession();
///
/// // Listen to updates
/// manager.stateStream.listen((state) => updateUI(state));
///
/// // End work
/// await manager.stopSession();
/// ```
class SessionManager {
  final SessionRepository _sessionRepository;
  final LocationRepository _locationRepository;
  final ExpenseRepository? _expenseRepository;
  final PreferencesLocal _preferences;
  final PermissionService _permissionService;
  final NotificationScheduler? _notificationScheduler;
  final NotificationService? _notificationService;
  final Logger _logger = Logger();
  final Uuid _uuid = const Uuid();

  // Current state
  ManagerSessionState _state = const ManagerSessionState();
  final _stateController = StreamController<ManagerSessionState>.broadcast();

  // Timers
  Timer? _durationTimer;
  Timer? _syncTimer;
  Timer? _watchdogTimer;

  // Tracking health
  DateTime? _lastLocationUpdateAt;
  DateTime? _lastWatchdogAlertAt;
  DateTime? _lastDistanceIncreasedAt;
  double _lastWatchdogDistanceM = 0;
  // Stall threshold: if no location update arrives in this window while
  // the session is active and not paused, fire a 3x-vibration alert.
  static const Duration _stallThreshold = Duration(seconds: 90);
  static const Duration _watchdogInterval = Duration(seconds: 30);
  static const Duration _watchdogCooldown = Duration(minutes: 3);

  // Sync coordination (prevents overlapping uploads)
  bool _syncInProgress = false;
  bool _syncQueued = false;

  // Guard: prevent uploading points before session exists on server
  bool _backendSessionReady = false;

  // Timeline Recorder
  late final TimelineRecorder _timelineRecorder;

  // Configuration
  static const Duration _syncInterval = Duration(minutes: 1);

  SessionManager({
    required SessionRepository sessionRepository,
    required LocationRepository locationRepository,
    required PreferencesLocal preferences,
    PermissionService? permissionService,
    NotificationScheduler? notificationScheduler,
    NotificationService? notificationService,
    ExpenseRepository? expenseRepository,
  })  : _sessionRepository = sessionRepository,
        _locationRepository = locationRepository,
        _expenseRepository = expenseRepository,
        _preferences = preferences,
        _permissionService = permissionService ?? PermissionService(),
        _notificationScheduler = notificationScheduler,
        _notificationService = notificationService {
    _timelineRecorder =
        TimelineRecorder(locationRepository: _locationRepository);
  }

  /// Stream of session state updates
  Stream<ManagerSessionState> get stateStream => _stateController.stream;

  /// Current session state
  ManagerSessionState get currentState => _state;

  /// Whether a session is currently active (includes paused)
  bool get isSessionActive => _state.status == ManagerSessionStatus.active;

  /// Whether a session is currently paused
  bool get isSessionPaused => _state.isPaused;

  // ============================================================
  // INITIALIZATION
  // ============================================================

  /// Initialize the session manager
  ///
  /// Must be called before using any other methods.
  /// This checks for any active session from a previous app run.
  Future<void> initialize() async {
    try {
      // Set up tracking service callbacks
      TrackingService.onLocationUpdate = _onLocationUpdate;
      TrackingService.onError = _onTrackingError;
      TrackingService.onTrackingStateChanged = _onTrackingStateChanged;
      // Listen for auto-pause and stationary spot from background service
      TrackingService.onAutoPaused = _onAutoPaused;
      TrackingService.onAutoResumed = _onAutoResumed;
      TrackingService.onStationarySpotDetected = _onStationarySpotDetected;

      // Check if there was an active session
      final activeSessionId = await _preferences.getActiveSessionId();
      if (activeSessionId != null) {
        _logger.i('Found active session: $activeSessionId');

        // Try to resume
        SessionModel? session;
        try {
          // Attempt 1: Fetch from remote (or repository logic)
          session = await _sessionRepository.getSession(activeSessionId);
        } catch (e) {
          _logger.w('Failed to fetch session from repository: $e');
        }

        // Attempt 2: Offline Fallback
        if (session == null) {
          final cachedJson = _preferences.cachedSessionJson;
          if (cachedJson != null) {
            try {
              final raw = jsonDecode(cachedJson);
              // Verify it matches the ID we expect
              if (raw['id'] == activeSessionId) {
                session = SessionModel.fromJson(raw);
                _logger.i('OFFLINE: Recovered session from local cache');
              }
            } catch (e) {
              _logger.e('Failed to parse cached session: $e');
            }
          }
        }

        if (session != null && session.isActive) {
          await _resumeSession(session);
        } else {
          // Session ended or invalid, clean up
          // Only clear if we are SURE it's gone (e.g. online check failed and no cache)
          // For now, if we can't recover it, we have to clear it to unblock the user
          _logger.w(
              'Could not recover session $activeSessionId. Clearing local state.');
          await _preferences.clearActiveSession();
          await _preferences.clearCachedSession();
        }
      }

      // Resume tracking if it was running
      await TrackingService.resumeIfNeeded();

      // CHECK FOR PENDING UPLOADS (Offline data recovery)
      // Even if we are not in an active session, we might have pending data to sync
      final pendingStop = _preferences.getPendingSessionEnd();
      final pendingLocCount = await _locationRepository.getPendingCount();

      if (pendingStop != null || pendingLocCount > 0) {
        _logger.i(
            'Found pending offline data (Stop: ${pendingStop != null}, Locs: $pendingLocCount). Starting sync timer.');
        _startSyncTimer();
      }

      _logger.i('Session manager initialized');
    } catch (e) {
      _logger.e('Error initializing session manager: $e');
    }
  }

  /// Check if tracking is ready (permissions, services, etc.)
  Future<TrackingReadiness> checkReadiness() async {
    return await _permissionService.checkTrackingReadiness();
  }

  // ============================================================
  // START SESSION
  // ============================================================

  /// Start a new work session
  ///
  /// This will:
  /// 1. Check permissions
  /// 2. Get current location for session start point
  /// 3. Create session in backend
  /// 4. Start background tracking
  /// 5. Begin sync timer
  Future<bool> startSession() async {
    if (_state.status == ManagerSessionStatus.active) {
      _logger.w('Session already active');
      return false;
    }

    _updateState(_state.copyWith(
      status: ManagerSessionStatus.starting,
      errorMessage: null,
    ));

    try {
      _backendSessionReady = false;

      // Step 0: Check for existing active session (PREVENT DUPLICATES)
      // A. Check local persistence first
      var existingSessionId = await _preferences.getActiveSessionId();
      if (existingSessionId != null) {
        _logger.w(
            'Cannot start new session: Already have active session $existingSessionId');
        _updateState(_state.copyWith(
          status: ManagerSessionStatus.error,
          errorMessage:
              'You already have an active session running. Please end it first.',
        ));
        return false;
      }

      // B. Check server (Strict Mode)
      // This safeguards against cases where local data was cleared but server has a running session
      try {
        final serverSession = await _sessionRepository.getActiveSession();
        if (serverSession != null) {
          _logger.w('Found existing session on server: ${serverSession.id}');

          // Auto-recover this session instead of erroring?
          // The user experience is better if we just "find" it.
          // However, startSession() expects to START a NEW one.
          // Let's return false with a specific message.

          _updateState(_state.copyWith(
            status: ManagerSessionStatus.error,
            errorMessage:
                'Found an active session on the server. Please restart the app to sync.',
          ));
          return false;
        }
      } catch (e) {
        _logger.w('Failed to check server for active session (offline?): $e');
        // If offline, we proceed based on local check (which passed)
      }

      // Step 1: Check permissions
      final readiness = await checkReadiness();
      if (!readiness.canTrack) {
        _updateState(_state.copyWith(
          status: ManagerSessionStatus.error,
          errorMessage: readiness.message,
        ));
        return false;
      }

      // Store warnings for UI
      List<String> warnings = readiness.warnings;

      // Step 2: Get current location
      final position = await TrackingService.getCurrentLocation();
      if (position == null) {
        _updateState(_state.copyWith(
          status: ManagerSessionStatus.error,
          errorMessage: 'Unable to get current location. Please try again.',
        ));
        return false;
      }

      // Step 2b: Get address
      String? address;
      try {
        address = await GeocodingService.getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );
      } catch (e) {
        _logger.w('Failed to get start address: $e');
      }

      // Step 3: Get current user ID
      final userId = await _sessionRepository.resolveCurrentUserId();
      if (userId == null) {
        _updateState(_state.copyWith(
          status: ManagerSessionStatus.error,
          errorMessage: 'Not logged in',
        ));
        return false;
      }

      // Step 4: Generate Session ID
      final sessionId = _uuid.v4();

      // CRITICAL: Wipe ALL stale tracking state from any prior session that
      // might still be lingering in SharedPreferences. Without this, a rapid
      // Stop -> Start can inherit the old session's totalDistance, last lat/lon,
      // pause flag, etc., producing wrong km on the new session.
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.remove('tracking_total_distance');
        await sp.remove('tracking_last_lat');
        await sp.remove('tracking_last_lon');
        await sp.remove('tracking_is_paused');
        await sp.remove('tracking_paused_distance');
        await sp.remove('tracking_auto_pause_at');
        await sp.remove('tracking_session_day');
        await sp.remove('tracking_last_speed_kmh');
        await sp.remove('tracking_point_buffer');
        await _preferences.setSessionDistanceMeters(0);
      } catch (e) {
        _logger.w('Failed to clear stale tracking prefs: $e');
      }

      // CRITICAL FIX: Start tracking FIRST to allow rollback
      // Step 5: Start tracking
      // Save session ID locally temporarily for the service
      await _preferences.saveActiveSession(sessionId);

      final trackingStarted = await TrackingService.startTracking(sessionId);
      if (!trackingStarted) {
        await _preferences.clearActiveSession(); // Rollback
        _updateState(_state.copyWith(
          status: ManagerSessionStatus.error,
          errorMessage: 'Failed to start location tracking',
        ));
        return false;
      }

      // Step 6: Create session in backend
      final session = SessionModel.start(
        id: sessionId,
        employeeId: userId,
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
      );

      // Cache session immediately for offline recovery
      await _preferences.setCachedSessionJson(jsonEncode(session.toJson()));

      final success = await _sessionRepository.startSession(
        session,
        position.latitude,
        position.longitude,
      );

      if (!success) {
        // Rollback tracking if DB fails
        await TrackingService.stopTracking();
        await _locationRepository.deleteLocalSessionPoints(sessionId);
        await _preferences.setSessionDistanceMeters(0);
        await _preferences.clearActiveSession();

        _updateState(_state.copyWith(
          status: ManagerSessionStatus.error,
          errorMessage:
              'Failed to create session. Please check your connection.',
        ));
        return false;
      }

      _backendSessionReady = true;

      // Timeline marker: start point
      await _timelineRecorder.recordSessionStart(
        sessionId: session.id,
        employeeId: session.employeeId,
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: session.startTime,
      );

      // Step 7: Start timers and clear any old persisted distance
      await _preferences.setSessionStartTime(session.startTime);
      await _preferences.setSessionDistanceMeters(0); // Clear for new session
      _startDurationTimer(session.startTime);
      _startSyncTimer();

      // Step 7b: Start notification scheduler with user settings
      try {
        final notifJson = _preferences.notificationSettingsJson;
        if (notifJson != null) {
          final settings = NotificationSettings.fromJson(jsonDecode(notifJson));
          _notificationScheduler?.startMonitoring(settings);
        }
      } catch (e) {
        _logger.w('Failed to load notification settings: $e');
      }

      // Step 8: Background notifications are handled directly by TrackingService

      // Update state
      _updateState(ManagerSessionState(
        status: ManagerSessionStatus.active,
        session: session,
        currentDistanceMeters: 0,
        duration: Duration.zero,
        warnings: warnings,
      ));

      _logger.i('Session started: $sessionId');
      _startWatchdog();
      return true;
    } catch (e) {
      _logger.e('Error starting session: $e');
      // Emergency rollback
      await TrackingService.stopTracking();
      // Best-effort cleanup of any queued points for the generated session
      final maybeSessionId = await _preferences.getActiveSessionId();
      if (maybeSessionId != null) {
        await _locationRepository.deleteLocalSessionPoints(maybeSessionId);
      }
      await _preferences.clearActiveSession();

      _updateState(_state.copyWith(
        status: ManagerSessionStatus.error,
        errorMessage: 'Error starting session: $e',
      ));
      return false;
    }
  }

  // ============================================================
  // STOP SESSION
  // ============================================================

  /// Stop the current work session
  ///
  /// This will:
  /// 1. Stop background tracking
  /// 2. Get final location
  /// 3. Sync remaining location points
  /// 4. Update session in backend with end time and total km
  Future<SessionModel?> stopSession() async {
    if (_state.status != ManagerSessionStatus.active) {
      _logger.w('No active session to stop');
      return null;
    }

    _updateState(_state.copyWith(status: ManagerSessionStatus.stopping));
    try {
      // Step 1: Stop tracking service (async — do NOT trust returned distance value
      // as it may race with the background isolate's final SharedPrefs write)
      await TrackingService.stopTracking();

      // Step 2: Stop timers
      _durationTimer?.cancel();

      // Step 3: Get final location
      final position = await TrackingService.getCurrentLocation();

      String? address;
      if (position != null) {
        try {
          address = await GeocodingService.getAddressFromCoordinates(
            position.latitude,
            position.longitude,
          );
        } catch (e) {
          _logger.w('Failed to get end address: $e');
        }
      }

      // Step 4: Sync any remaining points to server
      await _syncPendingLocations();

      final endTime = DateTime.now();
      var finalTotalPausedSeconds = _state.session?.totalPausedSeconds ?? 0;
      if (_state.isPaused && _state.session?.pausedAt != null) {
        final inProgressPauseSeconds =
            endTime.difference(_state.session!.pausedAt!).inSeconds;
        if (inProgressPauseSeconds > 0) {
          finalTotalPausedSeconds += inProgressPauseSeconds;
        }
      }

      // ================================================================
      // STEP 4b: AUTHORITATIVE DISTANCE CALCULATION
      //
      // Source of truth = local SQLite queue (always written synchronously
      // during tracking, no race conditions, works offline).
      //
      // Why NOT use TrackingService.stopTracking() return value:
      //   stopTracking() reads SharedPreferences right after telling the
      //   background isolate to stop. The isolate is async and has NOT yet
      //   written its final totalDistance — so you often get 0 or stale data.
      //
      // Why NOT use raw condition "serverKm < clientKm * 2":
      //   When clientKm = 0 (because of the race above), the condition becomes
      //   "serverKm < 0" which is ALWAYS false — so server distance was
      //   never used. That's why DB stored 296 km instead of ~419 km.
      // ================================================================
      final sessionId = _state.session!.id;
      double verifiedDistanceKm = 0;

      // ================================================================
      // AUTHORITATIVE DISTANCE CALCULATION
      // Combine ALL points (local + server), deduplicate by hash,
      // apply rolling median smoothing, and calculate with
      // mode-aware teleport detection + gap interpolation.
      // ================================================================
      final allPoints = <LocationPointModel>[];

      // Load server first, then local SQLite. Local points contain the newest
      // accepted-distance flags even if the server schema is not migrated yet.
      try {
        final serverPoints =
            await _locationRepository.getSessionLocations(sessionId);
        if (serverPoints.isNotEmpty) {
          allPoints.addAll(serverPoints);
          _logger.i('Server points: ${serverPoints.length}');
        }
      } catch (e) {
        _logger.w('Server distance check failed: $e');
      }

      try {
        final localPoints =
            await _locationRepository.getLocalSessionPoints(sessionId);
        if (localPoints.isNotEmpty) {
          allPoints.addAll(localPoints);
          _logger.i('Local SQLite points: ${localPoints.length}');
        }
      } catch (e) {
        _logger.w('Local distance calc failed: $e');
      }

      if (allPoints.length >= 2) {
        // Deduplicate by hash, sort by time, calculate authoritative distance
        final uniquePoints = <String, LocationPointModel>{};
        for (final p in allPoints) {
          if (p.hash != null) uniquePoints[p.hash!] = p;
        }
        final combined = uniquePoints.values.toList();
        combined.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

        final authResult = DistanceEngine.calculateAuthoritativeDistance(
            combined,
            applySmoothing: true);
        verifiedDistanceKm = authResult.totalKm;

        final integrity = DistanceEngine.verifyChainIntegrity(combined);
        _logger.i(
            'Authoritative distance: ${verifiedDistanceKm.toStringAsFixed(3)} km | '
            '${authResult.pointCount} pts, ${authResult.segments} valid segments, '
            '${authResult.noiseSegments} noise, ${authResult.teleportSegments} teleports, '
            '${authResult.gapInterpolations} interpolated gaps | '
            'Chain valid: ${authResult.chainValid}, Coverage: ${integrity.coveragePercent}%');
      }

      // Ultimate fallback: persisted SharedPrefs distance
      if (verifiedDistanceKm == 0) {
        verifiedDistanceKm = _preferences.getSessionDistanceMeters() / 1000;
        _logger.w(
            'Falling back to persisted distance: ${verifiedDistanceKm.toStringAsFixed(2)} km');
      }

      _logger.i(
          'FINAL verified distance: ${verifiedDistanceKm.toStringAsFixed(2)} km');
      // Step 5: End session in backend
      SessionModel? endedSession;
      try {
        endedSession = await _sessionRepository.stopSession(
          _state.session!.id,
          position?.latitude,
          position?.longitude,
          verifiedDistanceKm,
          address: address,
          endTime: endTime,
          totalPausedSeconds: finalTotalPausedSeconds,
        );
      } catch (e) {
        _logger.w('Failed to stop session online: $e');
      }

      // Step 5b: Offline Fallback
      if (endedSession == null) {
        _logger.i('OFFLINE: Queueing session stop locally');
        await _preferences.setPendingSessionEnd(
          sessionId: _state.session!.id,
          endTime: endTime,
          latitude: position?.latitude ?? _state.lastLocation?.latitude,
          longitude: position?.longitude ?? _state.lastLocation?.longitude,
          address: address,
          totalKm: verifiedDistanceKm,
          totalPausedSeconds: finalTotalPausedSeconds,
        );

        // Ensure sync timer is running to retry this later
        _startSyncTimer();

        // Create artificial ended session for UI
        endedSession = _state.session!.copyWith(
          endTime: endTime,
          totalKm: verifiedDistanceKm,
          status: SessionStatus.completed,
          totalPausedSeconds: finalTotalPausedSeconds,
        );
      }

      // Timeline marker: end point
      final endMarkerTime = endTime;
      final endLat = position?.latitude ?? _state.lastLocation?.latitude;
      final endLng = position?.longitude ?? _state.lastLocation?.longitude;
      if (endLat != null && endLng != null) {
        await _timelineRecorder.recordSessionEnd(
          latitude: endLat,
          longitude: endLng,
          timestamp: endMarkerTime,
          totalDistanceKm: verifiedDistanceKm,
        );
      }

      // Calculate final duration from start time to ensure accuracy
      // Step 6: Clear local session
      await _preferences.clearActiveSession();
      await _preferences.clearCachedSession(); // Clear offline cache
      _backendSessionReady = false;

      // Step 7: Background notification summary is handled by background service or skipped

      _stopWatchdog();

      // Update state
      _updateState(
          const ManagerSessionState(status: ManagerSessionStatus.idle));

      _logger.i(
          'Session stopped. Distance: ${verifiedDistanceKm.toStringAsFixed(2)} km');
      return endedSession;
    } catch (e) {
      _logger.e('Error stopping session: $e');
      _updateState(_state.copyWith(
        status: ManagerSessionStatus.error,
        errorMessage: 'Error stopping session: $e',
      ));
      return null;
    }
  }

  // ============================================================
  // RESUME SESSION (after app restart)
  // ============================================================

  // ============================================================
  // PAUSE / RESUME
  // ============================================================

  /// Pause the current session (manual or auto)
  Future<bool> pauseSession({bool isAutoPause = false}) async {
    if (_state.session == null || _state.isPaused) {
      _logger.w('Cannot pause: no session or already paused');
      return false;
    }

    try {
      final pausedAt = DateTime.now();
      final updatedSession = _state.session!.copyWith(
        status: SessionStatus.paused,
        pausedAt: pausedAt,
      );

      // Pause tracking (GPS continues but distance stops)
      await TrackingService.pauseTracking();

      // Record break_start timeline event
      if (_state.lastLocation != null) {
        await _timelineRecorder.recordEvent(
          eventType: 'break_start',
          latitude: _state.lastLocation!.latitude,
          longitude: _state.lastLocation!.longitude,
          timestamp: pausedAt,
        );
      }

      // Update backend session status
      try {
        await _sessionRepository.updateSessionStatus(
          updatedSession.id,
          SessionStatus.paused,
          pausedAt: pausedAt,
        );
      } catch (e) {
        _logger.w('Failed to update session status on server: $e');
      }

      _updateState(_state.copyWith(
        session: updatedSession,
        isPaused: true,
      ));

      _logger.i(
          'Session paused at ${pausedAt.toIso8601String()} (${isAutoPause ? "auto" : "manual"})');
      return true;
    } catch (e) {
      _logger.e('Error pausing session: $e');
      return false;
    }
  }

  /// Resume a paused session
  Future<bool> resumeSession() async {
    if (_state.session == null || !_state.isPaused) {
      _logger.w('Cannot resume: no session or not paused');
      return false;
    }

    try {
      final resumedAt = DateTime.now();
      final previousPausedAt = _state.session!.pausedAt ?? resumedAt;
      final pauseDurationSec = resumedAt.difference(previousPausedAt).inSeconds;
      final totalPausedSeconds =
          _state.session!.totalPausedSeconds + pauseDurationSec;

      final updatedSession = _state.session!.copyWith(
        status: SessionStatus.active,
        resumedAt: resumedAt,
        totalPausedSeconds: totalPausedSeconds,
      );

      // Resume tracking
      await TrackingService.resumeTracking();

      // Record break_end timeline event
      if (_state.lastLocation != null) {
        await _timelineRecorder.recordEvent(
          eventType: 'break_end',
          latitude: _state.lastLocation!.latitude,
          longitude: _state.lastLocation!.longitude,
          timestamp: resumedAt,
          durationSec: pauseDurationSec,
        );
      }

      // Update backend session status
      try {
        await _sessionRepository.updateSessionStatus(
          updatedSession.id,
          SessionStatus.active,
          resumedAt: resumedAt,
          totalPausedSeconds: totalPausedSeconds,
        );
      } catch (e) {
        _logger.w('Failed to update session status on server: $e');
      }

      _updateState(_state.copyWith(
        session: updatedSession,
        isPaused: false,
      ));

      _logger.i(
          'Session resumed at ${resumedAt.toIso8601String()}, total paused: ${Duration(seconds: totalPausedSeconds).inMinutes} min');
      return true;
    } catch (e) {
      _logger.e('Error resuming session: $e');
      return false;
    }
  }

  // ============================================================
  // RESUME SESSION (after app restart)
  // ============================================================

  Future<void> _resumeSession(SessionModel session) async {
    try {
      // Get persisted start time (more accurate for timer)
      final persistedStart = _preferences.getSessionStartTime();
      final startTime = persistedStart ?? session.startTime;

      // Get persisted distance (more accurate than database value)
      // Fall back to database value only if nothing persisted
      final persistedDistanceM = _preferences.getSessionDistanceMeters();
      final distanceMeters =
          persistedDistanceM > 0 ? persistedDistanceM : session.totalKm * 1000;

      // Check if session was paused before app restart
      final isPausedNow = session.isPaused;

      _updateState(ManagerSessionState(
        status: ManagerSessionStatus.active,
        session: session,
        currentDistanceMeters: distanceMeters,
        duration: session.activeDuration,
        isPaused: isPausedNow,
      ));

      _startDurationTimer(startTime);
      _startSyncTimer();
      _startWatchdog();

      // Attempt to restart tracking
      await TrackingService.resumeIfNeeded();

      // Session exists on server (we fetched it), so uploads are safe
      _backendSessionReady = true;

      _logger.i(
          'Session resumed: ${session.id}, distance: ${distanceMeters / 1000} km, paused: $isPausedNow');
    } catch (e) {
      _logger.e('Error resuming session: $e');
    }
  }

  // ============================================================
  // LOCATION UPDATES
  // ============================================================

  void _onLocationUpdate(LocationUpdate update) {
    // CRITICAL FIX: Do NOT drop updates during the 'stopping' transition.
    // The background isolate may deliver a final fix while the main isolate
    // is mid-stopSession() - if we drop it, the distance from that last
    // segment is permanently lost. Only ignore if there is truly no session.
    final st = _state.status;
    if (st != ManagerSessionStatus.active && st != ManagerSessionStatus.stopping) {
      return;
    }
    if (_state.session == null) return;
    // Ignore points belonging to a different (older) session id.
    if (update.sessionId != null && update.sessionId != _state.session!.id) {
      _logger.w('Ignoring location update for old session ${update.sessionId}');
      return;
    }

    // Watchdog: mark when we last received GPS data.
    _lastLocationUpdateAt = DateTime.now();
    // Watchdog: mark when distance actually increased.
    if (update.totalDistance > _lastWatchdogDistanceM) {
      _lastDistanceIncreasedAt = DateTime.now();
      _lastWatchdogDistanceM = update.totalDistance;
    }

    // ALWAYS queue location for sync (even when paused) for chain-of-custody
    _queueLocation(update);

    // Persist distance for app restart recovery
    _preferences.setSessionDistanceMeters(update.totalDistance);

    // Only process stops and update distance UI when not paused
    if (!_state.isPaused) {
      // Stop Detection via TimelineRecorder
      unawaited(_timelineRecorder.processLocation(
        latitude: update.latitude,
        longitude: update.longitude,
        timestamp: update.timestamp,
        isMoving: update.isMoving,
      ));

      // Update distance state
      _updateState(_state.copyWith(
        currentDistanceMeters: update.totalDistance,
        lastLocation: update,
      ));
    } else {
      // Still update last location so UI shows current position
      _updateState(_state.copyWith(
        lastLocation: update,
      ));
    }
  }

  void _onAutoPaused(Map<String, dynamic> data) {
    _logger.i('Auto-pause received from background service');
    if (_state.session != null && !_state.isPaused) {
      unawaited(pauseSession(isAutoPause: true));
    }
  }

  void _onAutoResumed(Map<String, dynamic> data) {
    _logger.i(
        'Auto-resume received from background service: ${data['distanceFromAnchor']}m moved');
    if (_state.session != null && _state.isPaused) {
      unawaited(resumeSession());
    }
  }

  final _stationarySpotController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get stationarySpotStream =>
      _stationarySpotController.stream;

  void _onStationarySpotDetected(Map<String, dynamic> data) {
    _logger.i(
        'Stationary spot detected: lat=${data['lat']}, lng=${data['lng']}, duration=${data['durationSec']}s');
    _stationarySpotController.add(data);
  }

  void _onTrackingError(String error) {
    _logger.e('Tracking error: $error');

    if (_state.status == ManagerSessionStatus.active) {
      _updateState(_state.copyWith(
        warnings: [..._state.warnings, error],
      ));
    }
  }

  void _onTrackingStateChanged(bool isTracking) {
    _logger.i('Tracking state changed: $isTracking');

    if (!isTracking &&
        _state.status == ManagerSessionStatus.active &&
        !_state.isPaused) {
      // Tracking stopped unexpectedly - try to restart
      _logger.w('Tracking stopped unexpectedly, attempting restart...');
      _attemptTrackingRestart();
    }
  }

  Future<void> _attemptTrackingRestart() async {
    if (_state.session == null) return;

    try {
      await Future.delayed(const Duration(seconds: 2));

      if (_state.status == ManagerSessionStatus.active) {
        final started = await TrackingService.startTracking(_state.session!.id);
        if (started) {
          _logger.i('Tracking restarted successfully');
        } else {
          _logger.e('Failed to restart tracking');
        }
      }
    } catch (e) {
      _logger.e('Error restarting tracking: $e');
    }
  }

  // ============================================================
  // LOCATION QUEUE & SYNC
  // ============================================================

  Future<void> _queueLocation(LocationUpdate update) async {
    try {
      final point = LocationPointModel.create(
        id: _uuid.v4(),
        sessionId: update.sessionId ?? _state.session?.id ?? '',
        employeeId: _state.session?.employeeId ?? '',
        latitude: update.latitude,
        longitude: update.longitude,
        accuracy: update.accuracy,
        speed: update.speed,
        altitude: update.altitude,
        heading: update.heading,
        isMoving: update.isMoving,
        countsForDistance: update.countsForDistance,
        distanceDeltaM: update.distanceDeltaM,
        recordedAt: update.timestamp,
      );

      await _locationRepository.queueLocation(point);
      _logger.i('DIAGNOSTIC: Point queued: ${point.id}');

      // CRITICAL FIX: Sync more aggressively - every 5 points instead of waiting for timer
      final pendingCount = await _locationRepository.getPendingCount();
      _logger.d('Queued location point. Pending: $pendingCount');

      if (_backendSessionReady && pendingCount >= 3) {
        _logger.i('Triggering immediate sync (3+ points pending)');
        unawaited(_syncPendingLocations());
      }
    } catch (e) {
      _logger.e('Error queueing location: $e');
    }
  }

  Future<void> _syncPendingLocations() async {
    if (_syncInProgress) {
      _syncQueued = true;
      return;
    }

    _syncInProgress = true;
    try {
      // Sync location points
      final uploadedCount = await _locationRepository.uploadPendingLocations();
      _logger.i('Location sync completed. Uploaded $uploadedCount points.');

      // Sync pending expenses
      if (_expenseRepository != null) {
        try {
          final expenseSyncCount =
              await _expenseRepository.syncPendingExpenses();
          if (expenseSyncCount > 0) {
            _logger
                .i('Expense sync completed. Synced $expenseSyncCount items.');
          }
        } catch (e) {
          _logger.e('Error syncing expenses: $e');
        }
      }

      await _preferences.saveLastSyncTime(DateTime.now());
      _logger.i('Full sync completed');
    } catch (e) {
      _logger.e('Error syncing locations: $e');
    } finally {
      _syncInProgress = false;
      if (_syncQueued) {
        _syncQueued = false;
        // Run one more pass to catch any points queued during the previous sync
        unawaited(_syncPendingLocations());
      }
    }
  }

  Future<void> _syncPendingSessionStop() async {
    final pending = _preferences.getPendingSessionEnd();
    if (pending == null) return;

    // Only sync if we have "internet" (aka backend access)
    // We can infer this if `_backendSessionReady` OR if we can fetch user id
    if (await _sessionRepository.resolveCurrentUserId() == null) return;

    try {
      _logger.i('Syncing pending session stop for ${pending['sessionId']}');

      await _sessionRepository.stopSession(
        pending['sessionId'],
        pending['latitude'],
        pending['longitude'],
        pending['totalKm'],
        address: pending['address'],
        endTime: DateTime.parse(pending['endTime']),
        totalPausedSeconds: (pending['totalPausedSeconds'] as num?)?.toInt(),
      );

      await _preferences.clearPendingSessionEnd();
      _logger.i('Pending session stop synced successfully');
    } catch (e) {
      _logger.e('Failed to sync pending session stop: $e');
    }
  }

  // ============================================================
  // TIMERS
  // ============================================================

  void _startDurationTimer(DateTime startTime) {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state.status == ManagerSessionStatus.active) {
        final now = DateTime.now();
        final rawDuration = now.difference(startTime);

        // Base paused seconds from completed pauses
        int totalPausedSec = _state.session?.totalPausedSeconds ?? 0;

        // If currently paused, add the in-progress pause duration so the
        // displayed duration FREEZES during pause (doesn't keep counting).
        if (_state.isPaused && _state.session?.pausedAt != null) {
          final currentPauseSec =
              now.difference(_state.session!.pausedAt!).inSeconds;
          if (currentPauseSec > 0) {
            totalPausedSec += currentPauseSec;
          }
        }

        final paused = Duration(seconds: totalPausedSec);
        final activeDuration =
            paused > rawDuration ? Duration.zero : rawDuration - paused;

        // SAFETY NET: re-read latest distance from persistent prefs.
        // This ensures the UI continues updating even if a locationUpdate
        // event from the background isolate is delayed or dropped
        // (which can happen on long trips when the OS throttles main
        // isolate while the app is backgrounded).
        double distanceM = _state.currentDistanceMeters;
        try {
          final persisted = _preferences.getSessionDistanceMeters();
          if (persisted > distanceM) {
            distanceM = persisted;
          }
        } catch (_) {}

        _updateState(_state.copyWith(
          duration: activeDuration,
          currentDistanceMeters: distanceM,
        ));
      }
    });
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) async {
      await _syncPendingSessionStop(); // Sync pending Stop commands
      await _syncPendingLocations(); // Sync location points

      // Self-cancellation: If no active session AND no pending data, stop the timer
      if (_state.status != ManagerSessionStatus.active) {
        final pendingStop = _preferences.getPendingSessionEnd();
        final pendingLocCount = await _locationRepository.getPendingCount();

        if (pendingStop == null && pendingLocCount == 0) {
          _logger.i('Sync timer auto-cancelled (No session, no pending data)');
          _syncTimer?.cancel();
          _syncTimer = null;
        }
      }
    });
  }

  // ============================================================
  // STATE MANAGEMENT
  // ============================================================

  void _updateState(ManagerSessionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  // ============================================================
  // TRACKING HEALTH WATCHDOG
  // ============================================================

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _lastLocationUpdateAt = DateTime.now();
    _lastDistanceIncreasedAt = DateTime.now();
    _lastWatchdogDistanceM = 0;
    _lastWatchdogAlertAt = null;
    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) => _watchdogTick());
    _logger.i('Tracking watchdog started');
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _lastLocationUpdateAt = null;
    _lastWatchdogAlertAt = null;
  }

  Future<void> _watchdogTick() async {
    try {
      // Only alert during an actively-running session that is not paused.
      if (_state.status != ManagerSessionStatus.active) return;
      if (_state.isPaused) return;
      if (_lastLocationUpdateAt == null) return;

      final since = DateTime.now().difference(_lastLocationUpdateAt!);
      if (since < _stallThreshold) return;

      // Cooldown: don't spam the user every 30s.
      final now = DateTime.now();
      if (_lastWatchdogAlertAt != null &&
          now.difference(_lastWatchdogAlertAt!) < _watchdogCooldown) {
        return;
      }
      _lastWatchdogAlertAt = now;

      final secs = since.inSeconds;
      _logger.w('WATCHDOG: No GPS update for ${secs}s - alerting user');

      // EXTRA CHECK: GPS is updating but distance hasn't moved for 3+ min
      // (user is moving but threshold is too high / GPS is stuck)
      if (_lastDistanceIncreasedAt != null) {
        final distStall = DateTime.now().difference(_lastDistanceIncreasedAt!).inSeconds;
        if (distStall >= 180) {
          _logger.w('WATCHDOG: Distance stalled for ${distStall}s despite GPS updates');
        }
      }

      // Surface a visible warning in the UI as well.
      final w = List<String>.from(_state.warnings)
        ..removeWhere((s) => s.startsWith('GPS stalled'))
        ..add('GPS stalled ${secs}s ago - distance may not be updating');
      _updateState(_state.copyWith(warnings: w));

      // Fire the 3x vibration alert via notification service.
      try {
        await _notificationService?.showCriticalTrackingAlert(
          title: 'Tracking issue detected',
          body: 'GPS has not updated for ${(secs / 60).toStringAsFixed(0)} min. '
              'Open the app, check location permissions, and move outdoors if possible.',
        );
      } catch (e) {
        _logger.e('Watchdog alert failed: $e');
      }

      // Attempt automatic recovery: try restarting tracking once.
      try {
        if (_state.session != null) {
          await TrackingService.startTracking(_state.session!.id,
              isResume: true);
          _logger.i('Watchdog: attempted tracking restart');
        }
      } catch (e) {
        _logger.e('Watchdog restart failed: $e');
      }
    } catch (e) {
      _logger.e('Watchdog tick error: $e');
    }
  }

  void dispose() {
    _durationTimer?.cancel();
    _syncTimer?.cancel();
    _watchdogTimer?.cancel();
    _timelineRecorder.dispose();
    _stateController.close();
  }
}
