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
import 'package:benzmobitraq_mobile/core/confidence_scorer.dart';
import 'package:benzmobitraq_mobile/core/distance_engine.dart';
import 'package:benzmobitraq_mobile/services/stop_detector.dart';
import 'package:geolocator/geolocator.dart';

import 'package:benzmobitraq_mobile/services/google_maps_directions_service.dart';
import 'package:benzmobitraq_mobile/services/tracking_service.dart';
import 'package:benzmobitraq_mobile/services/permission_service.dart';
import 'package:benzmobitraq_mobile/services/tracking_alert_service.dart';
import 'package:benzmobitraq_mobile/services/geocoding_service.dart';
import 'package:benzmobitraq_mobile/services/notification_scheduler.dart';
import 'package:benzmobitraq_mobile/services/timeline_recorder.dart';
import 'package:benzmobitraq_mobile/services/notification_service.dart';
import 'package:benzmobitraq_mobile/services/connectivity_service.dart';

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
  /// When set, the wall-clock time at which the current pause is
  /// supposed to end. Drives the on-screen "Pause: 4m 23s remaining"
  /// countdown on the session card. Cleared on resume / stop / a
  /// pause without an expected duration.
  final DateTime? pauseExpectedResumeAt;

  const ManagerSessionState({
    this.status = ManagerSessionStatus.idle,
    this.session,
    this.currentDistanceMeters = 0,
    this.duration = Duration.zero,
    this.lastLocation,
    this.errorMessage,
    this.warnings = const [],
    this.isPaused = false,
    this.pauseExpectedResumeAt,
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
    DateTime? pauseExpectedResumeAt,
    bool clearPauseExpectedResumeAt = false,
  }) {
    return ManagerSessionState(
      status: status ?? this.status,
      session: session ?? this.session,
      currentDistanceMeters:
          currentDistanceMeters ?? this.currentDistanceMeters,
      duration: duration ?? this.duration,
      lastLocation: lastLocation ?? this.lastLocation,
      errorMessage: errorMessage,
      warnings: warnings ?? this.warnings,
      isPaused: isPaused ?? this.isPaused,
      pauseExpectedResumeAt: clearPauseExpectedResumeAt
          ? null
          : (pauseExpectedResumeAt ?? this.pauseExpectedResumeAt),
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

  /// Detects "stop" / "indoor_walking" segments inside a session and
  /// persists them to session_stops. Does NOT pause the session. Reset
  /// on every new session via _resetStopDetector().
  StopDetector _stopDetector = StopDetector();

  // Current state
  ManagerSessionState _state = const ManagerSessionState();
  final _stateController = StreamController<ManagerSessionState>.broadcast();

  // Timers
  Timer? _durationTimer;
  Timer? _syncTimer;
  Timer? _watchdogTimer;
  Timer? _postStartNoFixTimer;
  Timer? _envCheckTimer;
  bool _hasReceivedFirstFix = false;
  bool _lastEnvLocationServicesEnabled = true;
  bool _lastEnvPermissionGranted = true;

  /// When set in the future, the GPS-stall and distance-stall checks
  /// in `_watchdogTick` skip their alerts. Used after the BG isolate
  /// tells us location services were just restored — we want to give
  /// the freshly-resubscribed position stream 90 seconds to deliver
  /// its first fix before we cry "GPS stalled".
  DateTime? _watchdogGraceUntil;

  /// Tracks when we last nudged the user with a "are you still working?"
  /// notification because their session has been stationary for hours.
  /// We do NOT auto-end the session (product decision) — we just keep
  /// reminding them every ~60 minutes so a forgotten session doesn't
  /// run for the entire weekend.
  DateTime? _lastForgottenSessionNudgeAt;

  /// Fires the pause-expired alarm. Lives outside the duration timer so
  /// it works even if the duration timer ticks at a different cadence.
  Timer? _pauseExpiryTimer;
  int? _lastPauseExpectedMinutes;
  Timer? _pauseCountdownTicker;

  /// True when the BG isolate reported location services are OFF and
  /// has not yet reported them back ON. While this is true, the env
  /// watchdog must NOT report a new alert every 30 seconds (it would
  /// just be amplifying noise the user already saw).
  bool _bgReportsLocationOff = false;

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

  // Connectivity subscription — used to clear the offline banner
  // automatically when the device reconnects to the internet.
  StreamSubscription<bool>? _connectivitySubscription;

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

  /// Force-refresh from the on-disk values written by the background
  /// isolate. Use this on app-resume so the UI never shows a stale
  /// distance when the bg→main event channel was throttled by the OS
  /// while the app was backgrounded.
  ///
  /// Specifically fixes: "home screen says 8.4 km but the post-session
  /// dialog says 12.7 km after opening the app a few hours later."
  /// Both numbers came from different sources — one in-memory + stale,
  /// one from disk. After this call they agree.
  Future<void> rehydrateFromDisk() async {
    if (_state.session == null) return; // Nothing to rehydrate
    try {
      await _preferences.reload();
    } catch (_) {}

    double bestDistanceM = _state.currentDistanceMeters;
    try {
      final persisted = _preferences.getSessionDistanceMeters();
      if (persisted > bestDistanceM) bestDistanceM = persisted;
    } catch (_) {}
    try {
      final bg = _preferences.getBackgroundServiceDistance();
      if (bg > bestDistanceM) bestDistanceM = bg;
    } catch (_) {}

    // Recompute active duration too — relying on the in-memory timer
    // means the UI shows a frozen value if the timer was throttled.
    final start = _preferences.getSessionStartTime() ?? _state.session!.startTime;
    final rawDuration = DateTime.now().difference(start);
    int pausedSec = _state.session!.totalPausedSeconds;
    if (_state.isPaused && _state.session!.pausedAt != null) {
      pausedSec += DateTime.now()
          .difference(_state.session!.pausedAt!)
          .inSeconds
          .clamp(0, 1 << 31);
    }
    final paused = Duration(seconds: pausedSec);
    final activeDuration =
        paused > rawDuration ? Duration.zero : rawDuration - paused;

    if (bestDistanceM > _state.currentDistanceMeters ||
        activeDuration != _state.duration) {
      _logger.i(
          'REHYDRATE: distance ${_state.currentDistanceMeters.toStringAsFixed(0)}m -> ${bestDistanceM.toStringAsFixed(0)}m, '
          'duration ${_state.duration.inSeconds}s -> ${activeDuration.inSeconds}s');
      _updateState(_state.copyWith(
        currentDistanceMeters: bestDistanceM,
        duration: activeDuration,
      ));

      // Keep the persistent caches in sync so the next reader (e.g. the
      // post-session dialog) doesn't see a mismatch either.
      try {
        await _preferences.setSessionDistanceMeters(bestDistanceM);
      } catch (_) {}
    }
  }

  /// Force-flush every pending queue we have RIGHT NOW. Ordering matters:
  /// session START goes first (otherwise the server has no row to update),
  /// then session STOP (which writes the final total_km), then location
  /// points, then offline-fuel expenses (so they reconcile against
  /// authoritative total_km, not the temporary 0).
  ///
  /// Public + idempotent so the post-session dialog can call it the
  /// moment internet returns — without it, the dialog reads the
  /// stale "row exists with total_km=0" state and the UI flips to 0.
  Future<void> flushAllPendingNow() async {
    try {
      await _syncPendingSessionStart();
    } catch (e) {
      _logger.w('flushAllPendingNow: start sync failed: $e');
    }
    try {
      await _syncPendingSessionStop();
    } catch (e) {
      _logger.w('flushAllPendingNow: stop sync failed: $e');
    }
    try {
      await _syncPendingLocations();
    } catch (e) {
      _logger.w('flushAllPendingNow: locations sync failed: $e');
    }
    try {
      final n = await _locationRepository.uploadPendingTimelineEvents();
      if (n > 0) _logger.i('flushAllPendingNow: timeline events synced=$n');
    } catch (e) {
      _logger.w('flushAllPendingNow: timeline events sync failed: $e');
    }
    if (_expenseRepository != null) {
      try {
        await _expenseRepository.syncPendingExpenses();
      } catch (_) {}
      try {
        await _expenseRepository.syncPendingSessionFuels();
      } catch (_) {}
    }
  }

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
      TrackingService.onServiceStatusChanged = _onServiceStatusChanged;
      TrackingService.onStationaryAlarm = _onStationaryAlarm;
      TrackingService.onMovementAutoResumed = _onMovementAutoResumed;
      TrackingService.onWatchdogGrace = _onWatchdogGrace;
      TrackingService.onMapsGapRecovery = _onMapsGapRecovery;

      // Listen for connectivity changes. When the device goes from
      // offline → online, clear the "You are offline..." warning so the
      // user doesn't see a stale banner for the rest of the trip.
      _connectivitySubscription?.cancel();
      _connectivitySubscription = ConnectivityService.onlineChanges.listen(
        (isOnline) {
          if (isOnline && _state.status == ManagerSessionStatus.active) {
            try {
              final cleaned = List<String>.from(_state.warnings)
                ..removeWhere((s) =>
                    s.startsWith('You are offline') ||
                    s.contains('being tracked locally'));
              if (cleaned.length != _state.warnings.length) {
                _updateState(_state.copyWith(warnings: cleaned));
              }
            } catch (_) {}
          }
        },
      );

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
        } else if (session != null && !session.isActive) {
          // Server explicitly says this session is completed/cancelled.
          // Trust the server — clear local state so we don't keep
          // "resuming" a ghost session every cold start. This is the
          // other half of the offline-stop bug: even if our pending
          // stop sync never went through, anyone who finished the
          // session from the admin panel or another device will see
          // the right outcome here.
          _logger.w(
              'Server reports session $activeSessionId is ${session.status.value}. Clearing local active marker.');
          await TrackingService.stopTracking();
          await _preferences.clearActiveSession();
          await _preferences.clearCachedSession();
          await _preferences.clearPendingSessionEnd();
        } else {
          // Could not reach server AND no cached copy — we have to
          // clear it to unblock the user. (If a cached copy did exist
          // we already returned above via _resumeSession.)
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
  Future<bool> startSession({String? purpose}) async {
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

      // B. Drain any pending offline session-stop BEFORE checking the server.
      //
      // Otherwise the server still sees the previous session as `active`
      // (because the stop hasn't synced yet) and the server-check below
      // refuses to start a new one. Then getActiveSession() side-effects
      // the old session-id back into local prefs and the next app launch
      // "resumes" the old session with its old kilometers. That is the
      // exact bug field users have been hitting.
      await _syncPendingSessionStop();
      await _syncPendingSessionStart();

      // C. Check server (Strict Mode)
      // Only error out if the server truly has an active session for THIS user
      // that we cannot reconcile. Note: do NOT use the repository's
      // getActiveSession() here — it writes back to local prefs as a side
      // effect, which would re-pin the old session id. Query the data
      // source directly.
      try {
        final userIdEarly = await _sessionRepository.resolveCurrentUserId();
        if (userIdEarly != null) {
          // After draining the pending stop above, the server should no
          // longer report this user as active. If it still does, something
          // is genuinely out of sync — surface a clear error.
          final stillActive = await _sessionRepository
              .checkServerActiveSessionWithoutSideEffects(userIdEarly);
          if (stillActive != null) {
            _logger.w(
                'Server still reports active session ${stillActive.id} after sync attempt');

            // Try one targeted recovery: force-end it on the server with the
            // last-known distance from the pending stop (if any), so the user
            // can start fresh instead of being stuck behind ghost state.
            await _forceEndGhostServerSession(stillActive);

            // Re-check once more
            final reCheck = await _sessionRepository
                .checkServerActiveSessionWithoutSideEffects(userIdEarly);
            if (reCheck != null) {
              _updateState(_state.copyWith(
                status: ManagerSessionStatus.error,
                errorMessage:
                    'A previous session is still being synced. Please wait a moment and try again.',
              ));
              return false;
            }
          }
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
        purpose: purpose?.trim().isEmpty == true ? null : purpose?.trim(),
      );

      // Cache session immediately for offline recovery
      await _preferences.setCachedSessionJson(jsonEncode(session.toJson()));

      // Try to create session on server, but NEVER fail locally.
      // Offline mode is fully supported: GPS points queue to SQLite,
      // distance accumulates in SharedPreferences, and everything
      // syncs when internet returns.
      bool serverCreated = false;
      try {
        serverCreated = await _sessionRepository.startSession(
          session,
          position.latitude,
          position.longitude,
        );
      } catch (e) {
        _logger.w('Session server creation failed (offline?): $e');
      }

      if (!serverCreated) {
        // OFFLINE MODE: Queue session for later sync. Do NOT rollback.
        _logger.i('OFFLINE: Session started locally. Will sync to server when internet returns.');
        await _preferences.setPendingSessionStart(
          jsonEncode(session.toJson()),
          position.latitude,
          position.longitude,
        );
        warnings.add('You are offline. Session is being tracked locally and will sync automatically when internet returns.');
      } else {
        _logger.i('Session created on server: $sessionId');
        await _preferences.clearPendingSessionStart();
      }

      // Local tracking is always ready — server or not.
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

      // Reset stop detector and polyline-jitter cache for the fresh
      // session — prior session's state must not leak.
      _stopDetector = StopDetector();
      _lastQueuedPoint = null;

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
        // CRITICAL: Reload SharedPreferences from disk to pick up the
        // background isolate's latest writes before reading.
        try {
          await _preferences.reload();
        } catch (_) {}

        // The background service writes to 'tracking_total_distance' directly.
        // The main isolate writes to 'session_distance_meters' via _onLocationUpdate.
        // When the app is backgrounded, the main isolate may not receive updates,
        // so 'session_distance_meters' is stale. Check both keys — take the max.
        double fallbackM = _preferences.getSessionDistanceMeters();
        try {
          final bgFallback = _preferences.getBackgroundServiceDistance();
          if (bgFallback > fallbackM) {
            fallbackM = bgFallback;
            _logger.i('Recovered distance from background service prefs: ${fallbackM.toStringAsFixed(0)}m');
          }
        } catch (e) {
          _logger.w('Failed to read background service distance: $e');
        }
        verifiedDistanceKm = fallbackM / 1000;
        if (verifiedDistanceKm > 0) {
          _logger.w(
              'Falling back to persisted distance: ${verifiedDistanceKm.toStringAsFixed(2)} km');
        }
      }

      _logger.i(
          'FINAL verified distance: ${verifiedDistanceKm.toStringAsFixed(2)} km');

      // ================================================================
      // GOOGLE MAPS RECONCILIATION
      // ================================================================
      // The product owner wants the billed distance to be accurate "at
      // any cost". GPS + Kalman is correct for the actual driven route
      // (which can be longer than the optimal Maps route due to detours,
      // U-turns, traffic reroutes, etc.). But if GPS missed a chunk of
      // road (e.g. lost satellite lock in a tunnel, or location was
      // toggled off mid-trip), the GPS distance is UNDER-counted.
      //
      // Strategy: also fetch Google Maps' driving distance between the
      // start and end coordinates. If it's significantly LARGER than the
      // GPS distance, we trust Maps and lift the session distance up to
      // the Maps value — the user wasn't shorted. If GPS is larger, we
      // trust GPS (real detours, in-route stops). The decision threshold
      // (10% slack + 250m absolute) is conservative so we don't bump a
      // legitimately short trip up to a longer "optimal" route.
      double? mapsRouteKm;
      try {
        final startLat = _state.session!.startLatitude;
        final startLng = _state.session!.startLongitude;
        final endLat = position?.latitude ?? _state.lastLocation?.latitude;
        final endLng = position?.longitude ?? _state.lastLocation?.longitude;
        if (startLat != null &&
            startLng != null &&
            endLat != null &&
            endLng != null) {
          final dir = await GoogleMapsDirectionsService.getDrivingDistance(
            startLat: startLat,
            startLng: startLng,
            endLat: endLat,
            endLng: endLng,
          );
          if (dir != null && dir.distanceKm > 0) {
            mapsRouteKm = dir.distanceKm;
            _logger.i(
                'MAPS reconciliation: gps=${verifiedDistanceKm.toStringAsFixed(2)}km, '
                'maps_direct=${mapsRouteKm.toStringAsFixed(2)}km');
            // Lift only when GPS is meaningfully lower than the direct
            // route — that's the "GPS missed road" case.
            if (verifiedDistanceKm > 0 &&
                mapsRouteKm > verifiedDistanceKm * 1.10 &&
                mapsRouteKm - verifiedDistanceKm > 0.25) {
              _logger.w(
                  'MAPS reconciliation: GPS appears to have under-counted by '
                  '${(mapsRouteKm - verifiedDistanceKm).toStringAsFixed(2)}km — '
                  'using Maps value as authoritative.');
              verifiedDistanceKm = mapsRouteKm;
            }
          }
        }
      } catch (e) {
        _logger.w('Maps reconciliation failed (non-fatal): $e');
      }

      // Step 4.5: Compute confidence + reason_codes from the same point set
      // used for verifiedDistanceKm. This is the audit/quality label that
      // travels with the session for the rest of its life. We compute it
      // ONCE here, on the device, so the value persisted online and the
      // value persisted via the offline pending-stop queue are identical.
      ConfidenceResult confidenceResult;
      try {
        final pointsForScoring = await _locationRepository
            .getLocalSessionPoints(_state.session!.id);
        confidenceResult = ConfidenceScorer.score(
          points: pointsForScoring,
          estimatedKm: verifiedDistanceKm,
          rawHaversineKm: mapsRouteKm,
        );
        _logger.i(
            'Session confidence: ${confidenceResult.confidence} '
            '(score=${confidenceResult.rawScore}, '
            'reasons=${confidenceResult.reasonCodes})');
      } catch (e) {
        _logger.w('Confidence scoring failed (non-fatal): $e');
        confidenceResult = const ConfidenceResult(
          confidence: 'medium',
          reasonCodes: <String>[],
          rawScore: 50,
        );
      }

      // Close any in-progress stop candidate. Persists it iff it
      // crossed the 5-min threshold; otherwise discards.
      try {
        await _stopDetector.finalize(
          sessionId: _state.session!.id,
          employeeId: _state.session!.employeeId,
        );
      } catch (e) {
        _logger.w('StopDetector.finalize failed (non-fatal): $e');
      }

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
          confidence: confidenceResult.confidence,
          reasonCodes: confidenceResult.reasonCodes,
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
          confidence: confidenceResult.confidence,
          reasonCodes: confidenceResult.reasonCodes,
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

      _schedulePauseExpiredAlarm(null); // cancel any pending pause alarm
      _stopWatchdog();

      // Update state
      _updateState(
          const ManagerSessionState(status: ManagerSessionStatus.idle));

      _logger.i(
          'Session stopped. Distance: ${verifiedDistanceKm.toStringAsFixed(2)} km');

      // Inform the super admin that this session ended. This is the
      // "for any reason if anyone's session got stopped" hook the
      // product owner asked for. We do not distinguish user-tap vs
      // system-stop here — the super admin wants to see all of them.
      try {
        final uid = await _sessionRepository.resolveCurrentUserId();
        if (uid != null) {
          unawaited(TrackingAlertService.report(
            employeeId: uid,
            sessionId: _state.session?.id,
            code: 'session_ended',
            message:
                'Session ended after ${verifiedDistanceKm.toStringAsFixed(2)} km',
            latitude: position?.latitude ?? _state.lastLocation?.latitude,
            longitude: position?.longitude ?? _state.lastLocation?.longitude,
          ));
        }
      } catch (_) {/* best effort */}

      return endedSession;
    } catch (e) {
      _logger.e('Error stopping session: $e');
      // Also surface the unexpected failure to the super admin.
      try {
        final uid = await _sessionRepository.resolveCurrentUserId();
        if (uid != null) {
          unawaited(TrackingAlertService.report(
            employeeId: uid,
            sessionId: _state.session?.id,
            code: 'session_stopped_unexpectedly',
            message: 'Stop failed: $e',
            latitude: _state.lastLocation?.latitude,
            longitude: _state.lastLocation?.longitude,
          ));
        }
      } catch (_) {}
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
  Future<bool> pauseSession({
    bool isAutoPause = false,
    int? expectedPauseMinutes,
    String? reason,
  }) async {
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

      // The 30-min "paused too long" alarm is now scheduled by the
      // background isolate itself (it monitors `tracking_auto_pause_at`
      // and fires an OS notification via flutter_local_notifications
      // directly, which works even when the main isolate is dead).
      // We no longer use a Dart Timer here because it silently died
      // when the app was killed — the exact bug the user reported.
      // expectedPauseMinutes is ignored; pause is fixed at 30 min.
      _schedulePauseExpiredAlarm(null);

      // Pause tracking (GPS continues but distance stops)
      await TrackingService.pauseTracking();

      // Record break_start timeline event with rich metadata so the
      // admin Timeline Log shows WHY the session was paused.
      final pauseReason = reason ?? (isAutoPause ? 'auto_pause' : 'manual');
      if (_state.lastLocation != null) {
        await _timelineRecorder.recordEvent(
          eventType: 'break_start',
          latitude: _state.lastLocation!.latitude,
          longitude: _state.lastLocation!.longitude,
          timestamp: pausedAt,
          metadata: {
            'reason': pauseReason,
            'source': isAutoPause ? 'background_service' : 'user_dialog',
            'expected_minutes': expectedPauseMinutes,
          },
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
  Future<bool> resumeSession({String? reason}) async {
    // Resuming cancels any pause-expired alarm — they explicitly
    // chose to return to tracking before the alarm fired (or in
    // response to the alarm).
    _schedulePauseExpiredAlarm(null);
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

      // Record break_end timeline event with rich metadata so the
      // admin Timeline Log shows WHY the session resumed.
      final resumeReason = reason ?? 'manual';
      if (_state.lastLocation != null) {
        await _timelineRecorder.recordEvent(
          eventType: 'break_end',
          latitude: _state.lastLocation!.latitude,
          longitude: _state.lastLocation!.longitude,
          timestamp: resumedAt,
          durationSec: pauseDurationSec,
          metadata: {
            'reason': resumeReason,
            'source': resumeReason == 'auto_resume'
                ? 'background_service'
                : 'user_dialog',
          },
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

      // CRITICAL: Reload SharedPreferences to pick up any writes from the
      // background isolate that may have occurred while the main isolate was dead.
      try {
        await _preferences.reload();
      } catch (_) {}

      final persistedDistanceM = _preferences.getSessionDistanceMeters();
      // Also check the background service's direct key (may be higher)
      double bgDistM = 0;
      try {
        bgDistM = _preferences.getBackgroundServiceDistance();
      } catch (_) {}
      final bestDistanceM = persistedDistanceM > bgDistM ? persistedDistanceM : bgDistM;
      final distanceMeters =
          bestDistanceM > 0 ? bestDistanceM : session.totalKm * 1000;

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
    _hasReceivedFirstFix = true;
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
      unawaited(pauseSession(
        isAutoPause: true,
        reason: 'auto_pause',
      ));
    }
  }

  void _onAutoResumed(Map<String, dynamic> data) {
    _logger.i(
        'Auto-resume received from background service: ${data['distanceFromAnchor']}m moved');
    if (_state.session != null && _state.isPaused) {
      unawaited(resumeSession(reason: 'auto_resume'));
    }
  }

  final _stationarySpotController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get stationarySpotStream =>
      _stationarySpotController.stream;

  /// Broadcasts when the bg-isolate detects ≥10 min stationary during
  /// an active session. UI layer (home screen) subscribes and shows
  /// the full-screen alarm dialog + plays the alarm sound.
  final _stationaryAlarmController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get stationaryAlarmStream =>
      _stationaryAlarmController.stream;

  /// Broadcasts when the bg-isolate has auto-resumed tracking because
  /// the user moved ≥ 100 m at ≥ 5 km/h during a paused session.
  /// The resume has already happened by the time this fires — the
  /// UI just confirms with Stop / Continue Tracking buttons.
  final _movementAutoResumedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get movementAutoResumedStream =>
      _movementAutoResumedController.stream;

  void _onStationarySpotDetected(Map<String, dynamic> data) {
    _logger.i(
        'Stationary spot detected: lat=${data['lat']}, lng=${data['lng']}, duration=${data['durationSec']}s');
    _stationarySpotController.add(data);
  }

  /// User chose "Extend pause" in the pause-expired alarm dialog. We
  /// just reschedule the pause-expired timer for another N minutes.
  /// Public so the home screen can call it without reaching into the
  /// session bloc.
  void extendPause(int minutes) {
    if (_state.session == null || !_state.isPaused) return;
    _logger.i('Extending pause by $minutes min');
    _schedulePauseExpiredAlarm(minutes);
  }

  /// Schedule (or reschedule) the pause-expired alarm. Pass null to
  /// cancel without scheduling a new one (e.g. on resume / stop).
  ///
  /// Side effect: also starts/stops a 10-second ticker that updates a
  /// "Pause: 1m 45s remaining" foreground notification so the user
  /// has a visible countdown while paused, not just a silent timer.
  void _schedulePauseExpiredAlarm(int? minutes) {
    _pauseExpiryTimer?.cancel();
    _pauseExpiryTimer = null;
    _pauseCountdownTicker?.cancel();
    _pauseCountdownTicker = null;
    _lastPauseExpectedMinutes = minutes;
    if (minutes == null || minutes <= 0) {
      // No expected duration → clear any visible countdown.
      _updateState(_state.copyWith(clearPauseExpectedResumeAt: true));
      try {
        _notificationService?.cancelPauseCountdown();
      } catch (_) {}
      return;
    }
    final expectedAt =
        DateTime.now().add(Duration(minutes: minutes));
    _updateState(_state.copyWith(pauseExpectedResumeAt: expectedAt));

    // Schedule the actual alarm at the end of the duration.
    _pauseExpiryTimer =
        Timer(Duration(minutes: minutes), _firePauseExpiredAlarm);

    // Push the first countdown notification immediately, then refresh
    // every 10 seconds. We stop the ticker the moment we're past the
    // expected time — the alarm itself takes over from there.
    final original = Duration(minutes: minutes);
    Future<void> tick() async {
      if (_state.session == null || !_state.isPaused) {
        _pauseCountdownTicker?.cancel();
        _pauseCountdownTicker = null;
        return;
      }
      final remaining = expectedAt.difference(DateTime.now());
      try {
        await _notificationService?.showPauseCountdown(
          remaining: remaining,
          originalDuration: original,
        );
      } catch (_) {}
      if (remaining.isNegative) {
        _pauseCountdownTicker?.cancel();
        _pauseCountdownTicker = null;
      }
    }

    unawaited(tick());
    _pauseCountdownTicker =
        Timer.periodic(const Duration(seconds: 10), (_) => unawaited(tick()));

    _logger.i('Pause-expired alarm scheduled for $minutes min '
        '(expectedAt=${expectedAt.toIso8601String()})');
  }

  void _firePauseExpiredAlarm() {
    if (_state.session == null || !_state.isPaused) return;
    _logger.i('Pause-expired alarm firing');
    _stationaryAlarmController.add({
      'kind': 'pause_expired',
      'durationMin': _lastPauseExpectedMinutes ?? 30,
    });
    try {
      _notificationService?.showSessionAlarm(
        title: 'Pause time is over',
        body:
            'Your session is still paused. Resume tracking, extend the pause, or end the session.',
        data: {'kind': 'pause_expired'},
      );
    } catch (_) {}
  }

  /// The bg-isolate just noticed a long gap with significant movement
  /// (typical when location services were toggled off mid-trip).
  /// We hit Google Maps Directions to learn the true driving
  /// distance between the two anchors, then add the difference
  /// (mapsKm − haversineKm) onto the persisted session-distance.
  /// This is how an 8 km route that lost 5.2 km to "location off"
  /// gets back to ~8 km on the home screen and on the bill.
  Future<void> _onMapsGapRecovery(Map<String, dynamic> data) async {
    if (_state.session == null) return;
    try {
      final fromLat = (data['fromLat'] as num?)?.toDouble();
      final fromLng = (data['fromLng'] as num?)?.toDouble();
      final toLat = (data['toLat'] as num?)?.toDouble();
      final toLng = (data['toLng'] as num?)?.toDouble();
      final haversineM = (data['haversineM'] as num?)?.toDouble() ?? 0;
      if (fromLat == null || fromLng == null || toLat == null || toLng == null) {
        return;
      }
      final result = await GoogleMapsDirectionsService.getDrivingDistance(
        startLat: fromLat,
        startLng: fromLng,
        endLat: toLat,
        endLng: toLng,
      );
      if (result == null) {
        _logger.w(
            'MAPS-GAP-RECOVERY: Directions API returned nothing — keeping haversine value');
        return;
      }
      final mapsM = result.distanceMeters;
      // Only credit the DIFFERENCE between Maps and what we already
      // counted (the haversine got recorded by the gap-recovery fast
      // path in onPositionReceived). We credit the FULL difference
      // because the user explicitly asked for the real road distance.
      final addM = (mapsM - haversineM).toDouble();
      if (addM <= 0) {
        _logger.i(
            'MAPS-GAP-RECOVERY: Maps (${mapsM.toStringAsFixed(0)}m) <= haversine (${haversineM.toStringAsFixed(0)}m) — no credit added');
        return;
      }
      _logger.i(
          'MAPS-GAP-RECOVERY: crediting +${addM.toStringAsFixed(0)}m '
          '(maps=${mapsM.toStringAsFixed(0)}m, haversine=${haversineM.toStringAsFixed(0)}m)');

      // Write to BOTH SharedPrefs keys + the in-memory state so the
      // UI, the watchdog, and the post-session expense dialog all
      // see the corrected total immediately.
      try {
        await _preferences.reload();
        final currentSession = _preferences.getSessionDistanceMeters();
        final currentBg = _preferences.getBackgroundServiceDistance();
        final best =
            currentSession > currentBg ? currentSession : currentBg;
        final newTotal = best + addM;
        await _preferences.setSessionDistanceMeters(newTotal);
        // Also bump the bg-service key so the watchdog stays in sync.
        try {
          final sp = await SharedPreferences.getInstance();
          await sp.setDouble('tracking_total_distance', newTotal);
        } catch (_) {}
        _updateState(_state.copyWith(currentDistanceMeters: newTotal));
      } catch (e) {
        _logger.e('MAPS-GAP-RECOVERY: persistence failed: $e');
      }

      // Surface a confirmation toast / state warning so the user
      // (and the admin via tracking_alerts) can see this was
      // applied.
      final addedKm = addM / 1000.0;
      final w = List<String>.from(_state.warnings)
        ..removeWhere((s) => s.startsWith('Gap recovered'))
        ..add(
            'Gap recovered via Google Maps: +${addedKm.toStringAsFixed(2)} km');
      _updateState(_state.copyWith(warnings: w));

      final uid = await _sessionRepository.resolveCurrentUserId();
      if (uid != null) {
        unawaited(TrackingAlertService.report(
          employeeId: uid,
          sessionId: _state.session?.id,
          code: 'gap_recovered_via_maps',
          message:
              'Recovered ${addedKm.toStringAsFixed(2)} km via Google Maps after a tracking gap',
          latitude: toLat,
          longitude: toLng,
        ));
      }
    } catch (e) {
      _logger.e('MAPS-GAP-RECOVERY error: $e');
    }
  }

  /// BG isolate signalled that we just resumed (manual or auto). Give
  /// the position stream a grace period before the watchdog screams
  /// "GPS not updated for 12 min" — that was Bug 5 from the user
  /// report.
  void _onWatchdogGrace(Map<String, dynamic> data) {
    final secs = (data['durationSec'] as int?) ?? 90;
    _watchdogGraceUntil =
        DateTime.now().add(Duration(seconds: secs));
    _lastLocationUpdateAt = DateTime.now();
    _lastDistanceIncreasedAt = DateTime.now();
    _lastWatchdogAlertAt = DateTime.now();
    _logger.i('WATCHDOG: grace period $secs s applied');
  }

  void _onMovementAutoResumed(Map<String, dynamic> data) {
    _logger.i('MOVEMENT-AUTO-RESUMED: $data');
    // The bg-isolate has already called resumeActiveTracking(). Our
    // job here is two things:
    //   1) reflect the session as ACTIVE (not paused) in our state,
    //      so the home-screen UI flips back without waiting for the
    //      next location update.
    //   2) cancel the pause-expired alarm + countdown that may still
    //      be running from when the user manually paused.
    if (_state.session != null && _state.isPaused) {
      final resumedAt = DateTime.now();
      final previousPausedAt = _state.session!.pausedAt ?? resumedAt;
      final pauseDurationSec =
          resumedAt.difference(previousPausedAt).inSeconds;
      final totalPausedSeconds =
          _state.session!.totalPausedSeconds + pauseDurationSec;
      final updated = _state.session!.copyWith(
        status: SessionStatus.active,
        resumedAt: resumedAt,
        totalPausedSeconds: totalPausedSeconds,
      );
      _updateState(_state.copyWith(session: updated, isPaused: false));
      // Also record the break_end timeline event + update server status
      // so the admin Timeline Log shows the auto-resume correctly.
      unawaited(resumeSession(reason: 'auto_resume'));
    }
    _schedulePauseExpiredAlarm(null);
    try {
      _notificationService?.cancelSessionAlarm();
      _notificationService?.cancelPauseCountdown();
    } catch (_) {}
    _movementAutoResumedController.add(data);
  }

  void _onStationaryAlarm(Map<String, dynamic> data) {
    _logger.i('STATIONARY-ALARM received: $data');
    // Surface to UI for in-app dialog.
    _stationaryAlarmController.add(data);
    // Also fire the OS-level alarm notification so the user gets it
    // even when the app isn't in the foreground.
    final mins = (data['durationMin'] as int?) ?? 15;
    try {
      _notificationService?.showSessionAlarm(
        title: 'Stopped for $mins minutes',
        body:
            'Your session is still running. Tap to pause, continue tracking, or end the session.',
        data: data,
      );
    } catch (e) {
      _logger.w('Failed to show stationary alarm notification: $e');
    }
  }

  void _onTrackingError(String error) {
    _logger.e('Tracking error: $error');

    if (_state.status == ManagerSessionStatus.active) {
      _updateState(_state.copyWith(
        warnings: [..._state.warnings, error],
      ));
    }
  }

  /// Called from the BG isolate's service-status stream listener
  /// whenever Android's "location services" master toggle flips.
  ///
  /// We use this to:
  ///   1. CLEAR the "Location is OFF" warning when the user turns it
  ///      back on, instead of waiting up to 30 seconds for the env
  ///      watchdog to notice on its own polling cycle.
  ///   2. Grant the freshly-resubscribed position stream a 90-second
  ///      grace window so the watchdog doesn't fire bogus
  ///      "GPS stalled" notifications during the warm-up.
  void _onServiceStatusChanged(bool enabled) {
    _logger.i('BG reports location services enabled=$enabled');
    _bgReportsLocationOff = !enabled;

    if (enabled) {
      // 1) Clear any stale warning text.
      final w = List<String>.from(_state.warnings)
        ..removeWhere((s) =>
            s.contains('Location services') ||
            s.contains('Location permission') ||
            s.startsWith('GPS stalled') ||
            s.startsWith('GPS could not') ||
            s.startsWith('Distance not'));
      // Watchdog stamps so it doesn't immediately falsely fire.
      _lastLocationUpdateAt = DateTime.now();
      _lastDistanceIncreasedAt = DateTime.now();
      _lastWatchdogAlertAt = DateTime.now();
      _watchdogGraceUntil =
          DateTime.now().add(const Duration(seconds: 90));
      // Also re-flag the env state so the env watchdog doesn't re-fire.
      _lastEnvLocationServicesEnabled = true;
      _updateState(_state.copyWith(warnings: w));

      // Best-effort: dismiss the OS-level "Location is OFF" notification
      // and the critical 3x-vibration alert that may still be on screen.
      try {
        _notificationService?.cancelAllStaleAlerts();
      } catch (_) {}
    } else {
      // 2) Surface the OFF state immediately in the UI too.
      final w = List<String>.from(_state.warnings)
        ..removeWhere((s) => s.contains('Location services'))
        ..add('Location services are turned off');
      _updateState(_state.copyWith(warnings: w));
      _lastEnvLocationServicesEnabled = false;
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
        final started = await TrackingService.startTracking(_state.session!.id, isResume: true);
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

  /// Cache of the most-recently-queued point for this session. Used by
  /// the polyline-jitter filter below so we can reject teleport spikes
  /// at upload time instead of letting them through and rendering a
  /// zigzag route on the admin map.
  LocationPointModel? _lastQueuedPoint;

  Future<void> _queueLocation(LocationUpdate update) async {
    try {
      // POLYLINE-JITTER FILTER (Bug 1 from user report).
      //
      // We reject a point at *upload time* if:
      //   (a) accuracy is worse than 80 m (loose enough to keep noisy
      //       indoor fixes for stop detection, but tight enough to
      //       drop the worst urban-canyon spikes), OR
      //   (b) it implies a physically-impossible speed jump from the
      //       previous queued point (teleport).
      //
      // Distance accumulation is unaffected — the BG isolate already
      // computed `update.distanceDeltaM` from the *filtered* chain,
      // and rejecting a raw point from the queue doesn't subtract any
      // already-accepted distance. We're just cleaning the polyline.
      if (update.accuracy > 0 && update.accuracy > 80.0) {
        _logger.d(
            'QUEUE-FILTER: skipping point, accuracy ${update.accuracy.toStringAsFixed(1)}m');
        return;
      }
      final prev = _lastQueuedPoint;
      if (prev != null) {
        final dt = update.timestamp.difference(prev.recordedAt);
        final distMeters = Geolocator.distanceBetween(
          prev.latitude,
          prev.longitude,
          update.latitude,
          update.longitude,
        );
        // Use the same mode-aware teleport check the DistanceEngine
        // uses — keeps behaviour consistent.
        if (DistanceEngine.isTeleport(
          distanceKm: distMeters / 1000.0,
          timeDelta: dt,
          recentSpeedKmh: update.speed * 3.6,
        )) {
          _logger.d(
              'QUEUE-FILTER: skipping teleport point, ${distMeters.toStringAsFixed(0)}m in ${dt.inSeconds}s');
          return;
        }
      }

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

      _lastQueuedPoint = point;
      await _locationRepository.queueLocation(point);
      _logger.i('DIAGNOSTIC: Point queued: ${point.id}');

      // Feed StopDetector. Stops are annotations, not part of distance
      // billing — so we don't await this, and we swallow any failure
      // (offline, RLS, etc.). Distance tracking is unaffected.
      if (_state.session != null && !_state.isPaused) {
        unawaited(_stopDetector
            .onPoint(
              sessionId: _state.session!.id,
              employeeId: _state.session!.employeeId,
              point: point,
            )
            .catchError((e) {
          _logger.w('StopDetector.onPoint failed (non-fatal): $e');
          return null;
        }));
      }

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

      // Sync queued timeline events (break_start/end, session start/end,
      // stops). Without this, sessions tracked while offline have a
      // perfectly populated route on the admin map but a blank
      // Timeline Log alongside it.
      try {
        final teSent =
            await _locationRepository.uploadPendingTimelineEvents();
        if (teSent > 0) {
          _logger.i('Timeline events sync completed. Sent $teSent events.');
        }
      } catch (e) {
        _logger.w('Timeline events sync failed: $e');
      }

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

        // Sync queued offline session-fuel expenses. These are the ones
        // submitted from the post-session dialog while offline; on sync
        // we recompute the distance via Google Maps and notify the user
        // so they can review the final amount.
        try {
          final results =
              await _expenseRepository.syncPendingSessionFuels();
          for (final r in results) {
            try {
              final src = r.usedGoogleMaps ? 'Google Maps' : 'GPS estimate';
              await _notificationService?.showLocalNotification(
                title: 'Session expense synced',
                body:
                    'Reconciled ${r.distanceKm.toStringAsFixed(1)} km using $src '
                    '(₹${r.amount.toStringAsFixed(0)}). Please review and submit if any discrepancies.',
                payload: null,
              );
            } catch (e) {
              _logger.w('Failed to notify session-fuel sync: $e');
            }
          }
        } catch (e) {
          _logger.e('Error syncing offline session fuels: $e');
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

  /// Force-end a server-side session that local state believes is over.
  ///
  /// Used when a previous Stop happened offline and we can't drain the
  /// pending stop (e.g. corruption, missing pending_session_end). Without
  /// this, the server keeps the session pinned as `active` forever and
  /// every Present tap fails the server-check.
  Future<void> _forceEndGhostServerSession(SessionModel ghost) async {
    try {
      _logger.w('Force-ending ghost server session: ${ghost.id}');
      final pending = _preferences.getPendingSessionEnd();
      final double km = (pending != null &&
              (pending['sessionId'] == ghost.id))
          ? ((pending['totalKm'] as num?)?.toDouble() ?? ghost.totalKm)
          : ghost.totalKm;
      final DateTime end = (pending != null &&
              pending['endTime'] is String &&
              pending['sessionId'] == ghost.id)
          ? DateTime.parse(pending['endTime'] as String)
          : DateTime.now();
      await _sessionRepository.stopSession(
        ghost.id,
        (pending?['latitude'] as num?)?.toDouble() ?? ghost.endLatitude,
        (pending?['longitude'] as num?)?.toDouble() ?? ghost.endLongitude,
        km,
        address: pending?['address'] as String? ?? ghost.endAddress,
        endTime: end,
        totalPausedSeconds:
            (pending?['totalPausedSeconds'] as num?)?.toInt() ??
                ghost.totalPausedSeconds,
      );
      await _preferences.clearPendingSessionEnd();
      _logger.i('Ghost session force-ended');
    } catch (e) {
      _logger.e('Failed to force-end ghost session: $e');
    }
  }

  Future<void> _syncPendingSessionStart() async {
    final pending = _preferences.getPendingSessionStart();
    if (pending == null) return;

    if (await _sessionRepository.resolveCurrentUserId() == null) return;

    try {
      _logger.i('Syncing pending session start');
      final session = SessionModel.fromJson(
        jsonDecode(pending['sessionJson']) as Map<String, dynamic>,
      );

      final success = await _sessionRepository.startSession(
        session,
        (pending['latitude'] as num).toDouble(),
        (pending['longitude'] as num).toDouble(),
      );

      if (success) {
        await _preferences.clearPendingSessionStart();
        _logger.i('Pending session start synced successfully: ' + session.id);
        // CLEAR the "You are offline. Session is being tracked locally..."
        // warning the moment the server has successfully accepted the
        // session row. Without this, the banner sticks for the entire
        // remainder of the trip even though we're already syncing
        // everything live.
        try {
          final cleaned = List<String>.from(_state.warnings)
            ..removeWhere((s) =>
                s.startsWith('You are offline') ||
                s.contains('being tracked locally'));
          if (cleaned.length != _state.warnings.length) {
            _updateState(_state.copyWith(warnings: cleaned));
          }
        } catch (_) {}
      }
    } catch (e) {
      _logger.e('Failed to sync pending session start: $e');
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

      final result = await _sessionRepository.stopSession(
        pending['sessionId'],
        pending['latitude'],
        pending['longitude'],
        pending['totalKm'],
        address: pending['address'],
        endTime: DateTime.parse(pending['endTime']),
        totalPausedSeconds: (pending['totalPausedSeconds'] as num?)?.toInt(),
        confidence: pending['confidence'] as String?,
        reasonCodes: (pending['reasonCodes'] as List?)?.cast<String>(),
      );

      // CRITICAL: stopSession returns null on any internal failure (it catches
      // exceptions silently). Only clear the pending data when we have a
      // confirmed non-null result — otherwise we lose the pending stop forever
      // and total_km stays 0 in the DB.
      if (result != null) {
        await _preferences.clearPendingSessionEnd();
        _logger.i('Pending session stop synced successfully');
      } else {
        _logger.w('stopSession returned null — keeping pending stop for retry');
      }
    } catch (e) {
      _logger.e('Failed to sync pending session stop: $e');
    }
  }

  // ============================================================
  // TIMERS
  // ============================================================

  // Counter used to rate-limit expensive SharedPreferences reads inside the
  // 1-second duration timer. We only hit disk every _prefReadIntervalSec ticks.
  int _durationTimerTick = 0;
  static const int _prefReadIntervalSec = 3;

  void _startDurationTimer(DateTime startTime) {
    _durationTimer?.cancel();
    _durationTimerTick = 0;
    // Monotonic anchor: combine wall-clock startTime with a Stopwatch so
    // that NTP / timezone / manual clock changes during the session
    // can't make the displayed duration jump backwards or balloon.
    final stopwatch = Stopwatch()..start();
    final wallStartAtSwitchOn = DateTime.now();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_state.status == ManagerSessionStatus.active) {
        final now = DateTime.now();
        // Two candidates for "elapsed since startTime":
        //   wallElapsed     : DateTime.now() - startTime  (may jump if NTP changes)
        //   monotonicEquiv  : (wallStartAtSwitchOn - startTime) + stopwatch.elapsed
        // We pick whichever is *smaller and non-negative*, which is the
        // honest, time-jump-resistant elapsed value.
        final wallElapsed = now.difference(startTime);
        final monoElapsed =
            wallStartAtSwitchOn.difference(startTime) + stopwatch.elapsed;
        Duration rawDuration;
        if (wallElapsed.isNegative || monoElapsed.isNegative) {
          rawDuration = monoElapsed.isNegative ? Duration.zero : monoElapsed;
        } else {
          rawDuration =
              wallElapsed < monoElapsed ? wallElapsed : monoElapsed;
        }

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
        //
        // CRITICAL FIX: We read TWO keys:
        //   1. 'session_distance_meters' — written by main isolate's _onLocationUpdate
        //   2. 'tracking_total_distance' — written by background isolate directly
        // When the screen is off, the main isolate stops receiving events so
        // key #1 goes stale. Key #2 keeps updating. We take the max of both.
        //
        // CRITICAL FIX #2: We MUST call _preferences.reload() before reading
        // because Flutter's SharedPreferences caches all values in memory.
        // Without reload(), the main isolate's cache NEVER sees the background
        // isolate's writes — getBackgroundServiceDistance() returns the same
        // stale value forever, completely defeating the sync fix.
        //
        // Rate-limited to every 3 seconds to avoid hammering disk I/O.
        double distanceM = _state.currentDistanceMeters;
        _durationTimerTick++;
        if (_durationTimerTick % _prefReadIntervalSec == 0) {
          // Reload SharedPreferences from disk to pick up background writes
          try {
            await _preferences.reload();
          } catch (_) {}

          try {
            final persisted = _preferences.getSessionDistanceMeters();
            if (persisted > distanceM) {
              distanceM = persisted;
            }
          } catch (_) {}

          // Also read the background service's direct key.
          // This is what keeps updating when the screen is off.
          try {
            final bgDistance =
                _preferences.getBackgroundServiceDistance();
            if (bgDistance > distanceM) {
              distanceM = bgDistance;
              // Also update session_distance_meters so both keys stay in sync
              _preferences.setSessionDistanceMeters(bgDistance);
            }
          } catch (_) {}
        }

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
      await _syncPendingSessionStart(); // Sync pending Start commands FIRST
      await _syncPendingLocations(); // GPS points BEFORE stop — trigger fires on insert,
      // then endSession overwrites total_km with verified value. Reversed order causes
      // double-counting: stop sets total_km, then every GPS insert trigger adds on top.
      await _syncPendingSessionStop(); // Sync pending Stop commands LAST

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
    _hasReceivedFirstFix = false;
    _lastForgottenSessionNudgeAt = null;
    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) => _watchdogTick());

    // Post-start no-fix watchdog: 60 seconds after the session starts,
    // if zero GPS fixes have made it to the main isolate we treat that
    // as a tracking failure, try to repair, and notify the user + the
    // backend so the super admin can see something is wrong.
    _postStartNoFixTimer?.cancel();
    _postStartNoFixTimer =
        Timer(const Duration(seconds: 60), _onPostStartNoFix);

    // Environment watchdog: every 30s, check that location services are
    // still on and that the permission is still granted. Either flipping
    // off mid-session is the kind of "tracking silently stopped" bug
    // that ends up in user complaints.
    _envCheckTimer?.cancel();
    _envCheckTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _environmentTick());

    _logger.i('Tracking watchdog started (incl. post-start + env checks)');
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _postStartNoFixTimer?.cancel();
    _postStartNoFixTimer = null;
    _envCheckTimer?.cancel();
    _envCheckTimer = null;
    _lastLocationUpdateAt = null;
    _lastWatchdogAlertAt = null;
    _hasReceivedFirstFix = false;
  }

  /// Called 60 seconds after a session starts. If we still have zero
  /// GPS fixes, something is broken. Try to recover and surface it.
  Future<void> _onPostStartNoFix() async {
    if (_state.status != ManagerSessionStatus.active) return;
    if (_hasReceivedFirstFix) return; // All good

    _logger.w('POST-START WATCHDOG: 60s with no GPS fix — repairing');

    // 1. Re-check environment so we can tell the user exactly why.
    final servicesOn = await _safeIsLocationServiceEnabled();
    final permission = await _safeCheckPermission();
    final permissionGood = permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    String why = 'GPS could not get a fix within 60 seconds';
    String alertCode = 'no_gps_fix_60s';
    if (!servicesOn) {
      why = 'Location services are turned off';
      alertCode = 'location_services_disabled';
    } else if (!permissionGood) {
      why = 'Location permission is not granted';
      alertCode = 'location_permission_denied';
    }

    final w = List<String>.from(_state.warnings)
      ..removeWhere((s) =>
          s.startsWith('GPS could not') ||
          s.startsWith('Location services') ||
          s.startsWith('Location permission'))
      ..add(why);
    _updateState(_state.copyWith(warnings: w));

    try {
      await _notificationService?.showCriticalTrackingAlert(
        title: 'Tracking is not recording yet',
        body: '$why. Tap the app to fix, otherwise the trip may not be counted.',
      );
    } catch (e) {
      _logger.w('Post-start alert notification failed: $e');
    }

    // 2. Try to restart the background tracker — covers the case where
    // the position stream is dead but the OS would happily give us
    // a fix on a fresh subscription.
    if (servicesOn && permissionGood && _state.session != null) {
      try {
        await TrackingService.startTracking(_state.session!.id,
            isResume: true);
        _logger.i('POST-START WATCHDOG: attempted tracking restart');
      } catch (e) {
        _logger.e('POST-START WATCHDOG restart failed: $e');
      }
    }

    // 3. Phone-home so the super admin sees the failure.
    final userId = await _sessionRepository.resolveCurrentUserId();
    if (userId != null && _state.session != null) {
      unawaited(TrackingAlertService.report(
        employeeId: userId,
        sessionId: _state.session!.id,
        code: alertCode,
        message: why,
        latitude: _state.lastLocation?.latitude,
        longitude: _state.lastLocation?.longitude,
      ));
    }
  }

  /// Periodic environment check — fires when location services or the
  /// permission flips state mid-session.
  Future<void> _environmentTick() async {
    if (_state.status != ManagerSessionStatus.active) return;
    if (_state.isPaused) return;

    // Forgot-to-end-session nudge. If the session has been running for
    // more than 90 minutes AND distance hasn't moved in the last
    // 60 minutes AND we haven't already nudged in the last hour, fire
    // a tap-able reminder so the user can decide: end the session or
    // keep going. We never auto-end (product decision) but we also
    // never let a session sit for a full day by accident.
    _maybeNudgeForgottenSession();

    final servicesOn = await _safeIsLocationServiceEnabled();
    final permission = await _safeCheckPermission();
    final permissionGood = permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    // Detect transitions only — we don't want to spam the user every
    // 30 seconds while they remain in a bad state.
    if (servicesOn != _lastEnvLocationServicesEnabled) {
      _lastEnvLocationServicesEnabled = servicesOn;
      if (!servicesOn) {
        await _onEnvBroken('location_services_disabled',
            'Location services were turned off');
      } else {
        _logger.i('ENV WATCHDOG: location services restored');
        // Force a re-subscription via TrackingService — this covers the
        // case where the bg-isolate service-status listener missed the
        // event (rare, but cheap to defend against).
        if (_state.session != null) {
          try {
            await TrackingService.startTracking(_state.session!.id,
                isResume: true);
          } catch (_) {}
        }
        // Grant the freshly-restarted stream 90 seconds before the
        // watchdog complains again. Mirrors the bg-isolate behavior.
        _watchdogGraceUntil =
            DateTime.now().add(const Duration(seconds: 90));
        _lastLocationUpdateAt = DateTime.now();
        _lastDistanceIncreasedAt = DateTime.now();
        // Also bypass the post-start watchdog so we don't get a
        // duplicate "Tracking is not recording yet" alert on top of
        // the env-watchdog one.
        _hasReceivedFirstFix = true;
        // Clear any stale warnings text.
        final w = List<String>.from(_state.warnings)
          ..removeWhere((s) =>
              s.contains('Location services') ||
              s.startsWith('GPS stalled') ||
              s.startsWith('GPS could not'));
        _updateState(_state.copyWith(warnings: w));
      }
    }

    if (permissionGood != _lastEnvPermissionGranted) {
      _lastEnvPermissionGranted = permissionGood;
      if (!permissionGood) {
        await _onEnvBroken('location_permission_denied',
            'Location permission was revoked');
      } else {
        _logger.i('ENV WATCHDOG: permission restored');
      }
    }
  }

  Future<void> _onEnvBroken(String code, String message) async {
    _logger.w('ENV WATCHDOG: $code — $message');
    final w = List<String>.from(_state.warnings)
      ..removeWhere((s) => s.startsWith(message))
      ..add(message);
    _updateState(_state.copyWith(warnings: w));

    try {
      await _notificationService?.showCriticalTrackingAlert(
        title: 'Tracking interrupted',
        body: '$message. Trip distance may stop counting until this is fixed.',
      );
    } catch (_) {}

    final userId = await _sessionRepository.resolveCurrentUserId();
    if (userId != null && _state.session != null) {
      unawaited(TrackingAlertService.report(
        employeeId: userId,
        sessionId: _state.session!.id,
        code: code,
        message: message,
        latitude: _state.lastLocation?.latitude,
        longitude: _state.lastLocation?.longitude,
      ));
    }
  }

  void _maybeNudgeForgottenSession() {
    if (_state.session == null) return;
    final session = _state.session!;
    final now = DateTime.now();

    // 90 minutes minimum session age before we'd consider nudging.
    if (now.difference(session.startTime).inMinutes < 90) return;

    // Has distance increased in the last 60 minutes? `_lastDistanceIncreasedAt`
    // is maintained by `_onLocationUpdate`. If it's still moving, leave them
    // alone — they're actively driving.
    final lastInc = _lastDistanceIncreasedAt;
    if (lastInc != null && now.difference(lastInc).inMinutes < 60) return;

    // Throttle the nudge so we don't spam every 30 seconds.
    if (_lastForgottenSessionNudgeAt != null &&
        now.difference(_lastForgottenSessionNudgeAt!).inMinutes < 60) {
      return;
    }
    _lastForgottenSessionNudgeAt = now;

    final stationaryMinutes = lastInc != null
        ? now.difference(lastInc).inMinutes
        : now.difference(session.startTime).inMinutes;

    _logger.i(
        'FORGOTTEN-SESSION nudge: ${stationaryMinutes}min stationary, prompting user');

    try {
      _notificationService?.showCriticalTrackingAlert(
        title: 'Still working?',
        body:
            'Your session has been running for ${(now.difference(session.startTime).inMinutes / 60).toStringAsFixed(1)} hours with no movement for $stationaryMinutes minutes. '
            'Open the app and tap Work Done if you are finished.',
      );
    } catch (_) {}
  }

  Future<bool> _safeIsLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return true; // Don't false-alarm on a plugin error
    }
  }

  Future<LocationPermission> _safeCheckPermission() async {
    try {
      return await Geolocator.checkPermission();
    } catch (_) {
      return LocationPermission.whileInUse;
    }
  }

  Future<void> _watchdogTick() async {
    try {
      // Only alert during an actively-running session that is not paused.
      if (_state.status != ManagerSessionStatus.active) return;
      if (_state.isPaused) return;
      if (_lastLocationUpdateAt == null) return;

      final now = DateTime.now();

      // Suppression #1: if the BG isolate just told us location services
      // are OFF, the OFF alert is already showing. Firing a redundant
      // "GPS stalled" alert on top of it just confuses the user.
      if (_bgReportsLocationOff) return;

      // Suppression #2: grace window after a location-services restore
      // or a fresh session start. The new position stream typically
      // delivers its first fix within 30s but can take up to 60-90s
      // outdoors with a cold GPS chip.
      if (_watchdogGraceUntil != null && now.isBefore(_watchdogGraceUntil!)) {
        return;
      }

      // Cooldown: don't spam the user every 30s.
      if (_lastWatchdogAlertAt != null &&
          now.difference(_lastWatchdogAlertAt!) < _watchdogCooldown) {
        return;
      }

      // Suppression #3: the user is genuinely stationary.
      // If the most recent fix reported zero speed AND wasn't moving
      // (or the last fix is very fresh), don't bother them with
      // "GPS has not updated, move outdoors" — they're sitting still
      // on purpose. The watchdog still runs; it just stays silent.
      // This is Bug 4 from the user report ("notifications spam while
      // I'm stationary").
      final last = _state.lastLocation;
      if (last != null) {
        final speedKmh = last.speed * 3.6;
        final isReallyStationary = !last.isMoving && speedKmh < 2.0;
        if (isReallyStationary) {
          // Clear any pre-existing "distance not counting" / "GPS
          // stalled" warning banners — the user is intentionally
          // still, and an old warning telling them their GPS is
          // dying is just confusing.
          if (_state.warnings.any((w) =>
              w.startsWith('GPS stalled') ||
              w.startsWith('Distance not'))) {
            final cleaned = List<String>.from(_state.warnings)
              ..removeWhere((w) =>
                  w.startsWith('GPS stalled') ||
                  w.startsWith('Distance not'));
            _updateState(_state.copyWith(warnings: cleaned));
          }
          return;
        }
      }

      // ============================================================
      // CHECK 1: GPS SILENCE — no location updates at all
      // ============================================================
      final since = now.difference(_lastLocationUpdateAt!);
      if (since >= _stallThreshold) {
        _lastWatchdogAlertAt = now;
        final secs = since.inSeconds;
        _logger.w('WATCHDOG: No GPS update for ${secs}s - alerting user');

        // Surface a visible warning in the UI as well.
        final w = List<String>.from(_state.warnings)
          ..removeWhere((s) => s.startsWith('GPS stalled') || s.startsWith('Distance not'))
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
        return; // Don't also fire distance stall — GPS is already stalled
      }

      // ============================================================
      // CHECK 2: DISTANCE STALL — GPS IS updating but distance isn't
      // ============================================================
      // This catches the case where GPS is alive but accuracy is so
      // poor that all points are rejected by the anti-jitter filter.
      // The user sees GPS working but distance frozen.
      if (_lastDistanceIncreasedAt != null) {
        final distStall = now.difference(_lastDistanceIncreasedAt!).inSeconds;
        if (distStall >= 180) {
          _lastWatchdogAlertAt = now;
          _logger.w('WATCHDOG: Distance stalled for ${distStall}s despite GPS updates');

          final w = List<String>.from(_state.warnings)
            ..removeWhere((s) => s.startsWith('GPS stalled') || s.startsWith('Distance not'))
            ..add('Distance not counting for ${(distStall / 60).toStringAsFixed(0)} min - GPS signal may be weak');
          _updateState(_state.copyWith(warnings: w));

          try {
            await _notificationService?.showCriticalTrackingAlert(
              title: '⚠️ Distance not counting',
              body: 'GPS signal is weak (accuracy too low). '
                  'Move to an open area for better signal.',
            );
          } catch (e) {
            _logger.e('Watchdog distance-stall alert failed: $e');
          }
        }
      }
    } catch (e) {
      _logger.e('Watchdog tick error: $e');
    }
  }

  void dispose() {
    _durationTimer?.cancel();
    _syncTimer?.cancel();
    _watchdogTimer?.cancel();
    _connectivitySubscription?.cancel();
    _timelineRecorder.dispose();
    _stateController.close();
    _stationarySpotController.close();
    _stationaryAlarmController.close();
    _movementAutoResumedController.close();
  }
}
