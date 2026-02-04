import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';

import '../data/repositories/location_repository.dart';
import 'geocoding_service.dart';

/// TimelineRecorder - Clean, minimal timeline event recorder
/// 
/// Responsibilities:
/// 1. Record session START with timestamp + location
/// 2. Record session END with timestamp + location + total km
/// 3. Detect STOPS when stationary for X minutes (configurable)
class TimelineRecorder {
  final LocationRepository _locationRepository;
  final Logger _logger = Logger();

  // Configuration
  final int stopMinDurationMinutes;
  final double stopRadiusMeters;

  // State
  String? _sessionId;
  String? _employeeId;
  
  // Stop detection state
  DateTime? _stationaryStartTime;
  double? _stationaryAnchorLat;
  double? _stationaryAnchorLng;
  String? _activeStopEventId;
  bool _stopEventCreated = false;

  TimelineRecorder({
    required LocationRepository locationRepository,
    this.stopMinDurationMinutes = 5,
    this.stopRadiusMeters = 200,
  }) : _locationRepository = locationRepository;

  /// Record the START of a session
  /// 
  /// Creates a 'start' timeline event with the given location and time.
  Future<void> recordSessionStart({
    required String sessionId,
    required String employeeId,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
  }) async {
    _sessionId = sessionId;
    _employeeId = employeeId;
    _resetStopState();

    try {
      String? address;
      try {
        address = await GeocodingService.getAddressFromCoordinates(latitude, longitude);
      } catch (_) {}

      await _locationRepository.createTimelineEvent(
        employeeId: employeeId,
        sessionId: sessionId,
        eventType: 'start',
        startTime: timestamp,
        endTime: timestamp,
        durationSec: 0,
        latitude: latitude,
        longitude: longitude,
        address: address,
      );

      _logger.i('📍 Timeline: Session START recorded at ($latitude, $longitude)');
    } catch (e) {
      _logger.e('Error recording session start: $e');
    }
  }

  /// Record the END of a session
  /// 
  /// Creates an 'end' timeline event with the final location, time, and total distance.
  Future<void> recordSessionEnd({
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    required double totalDistanceKm,
  }) async {
    if (_sessionId == null || _employeeId == null) {
      _logger.w('Cannot record session end: no active session');
      return;
    }

    // Finalize any active stop event first
    await _finalizeStopEvent(timestamp);

    try {
      String? address;
      try {
        address = await GeocodingService.getAddressFromCoordinates(latitude, longitude);
      } catch (_) {}

      await _locationRepository.createTimelineEvent(
        employeeId: _employeeId!,
        sessionId: _sessionId!,
        eventType: 'end',
        startTime: timestamp,
        endTime: timestamp,
        durationSec: 0,
        latitude: latitude,
        longitude: longitude,
        address: address,
      );

      _logger.i('🏁 Timeline: Session END recorded at ($latitude, $longitude), Total: ${totalDistanceKm.toStringAsFixed(2)} km');
    } catch (e) {
      _logger.e('Error recording session end: $e');
    } finally {
      _sessionId = null;
      _employeeId = null;
      _resetStopState();
    }
  }

  /// Process a location update for stop detection
  /// 
  /// Call this on every location update. It will:
  /// - Detect when the user becomes stationary
  /// - Create a 'stop' event after [stopMinDurationMinutes]
  /// - Update the stop event while still stationary
  /// - Finalize the stop when movement resumes
  Future<void> processLocation({
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    required bool isMoving,
  }) async {
    if (_sessionId == null || _employeeId == null) return;

    if (isMoving) {
      // User is moving - finalize any active stop
      if (_stationaryStartTime != null) {
        await _finalizeStopEvent(timestamp);
        _resetStopState();
      }
      return;
    }

    // User is stationary
    if (_stationaryStartTime == null) {
      // Start tracking stationary period
      _stationaryStartTime = timestamp;
      _stationaryAnchorLat = latitude;
      _stationaryAnchorLng = longitude;
      _stopEventCreated = false;
      _activeStopEventId = null;
      _logger.d('📍 Stop candidate started at ($latitude, $longitude)');
      return;
    }

    // Check if user moved outside the stop radius
    final distanceFromAnchor = Geolocator.distanceBetween(
      _stationaryAnchorLat!,
      _stationaryAnchorLng!,
      latitude,
      longitude,
    );

    if (distanceFromAnchor > stopRadiusMeters) {
      // User moved too far - this is not a stop, reset
      await _finalizeStopEvent(timestamp);
      _resetStopState();
      // Start new stop candidate at current location
      _stationaryStartTime = timestamp;
      _stationaryAnchorLat = latitude;
      _stationaryAnchorLng = longitude;
      return;
    }

    // User is still within radius - check duration
    final stationaryDuration = timestamp.difference(_stationaryStartTime!);
    final minDuration = Duration(minutes: stopMinDurationMinutes);

    if (stationaryDuration >= minDuration) {
      // Stop threshold reached - create or update stop event
      await _upsertStopEvent(timestamp);
    }
  }

  /// Create or update the stop event
  Future<void> _upsertStopEvent(DateTime currentTime) async {
    if (_sessionId == null || _employeeId == null) return;
    if (_stationaryStartTime == null || _stationaryAnchorLat == null || _stationaryAnchorLng == null) return;

    final durationSec = currentTime.difference(_stationaryStartTime!).inSeconds;

    try {
      if (!_stopEventCreated) {
        // Create new stop event
        String? address;
        try {
          address = await GeocodingService.getAddressFromCoordinates(
            _stationaryAnchorLat!,
            _stationaryAnchorLng!,
          );
        } catch (_) {}

        _activeStopEventId = await _locationRepository.createTimelineEvent(
          employeeId: _employeeId!,
          sessionId: _sessionId!,
          eventType: 'stop',
          startTime: _stationaryStartTime!,
          endTime: currentTime,
          durationSec: durationSec,
          latitude: _stationaryAnchorLat,
          longitude: _stationaryAnchorLng,
          address: address,
        );

        _stopEventCreated = true;
        _logger.i('⏸️ Timeline: STOP event created (${durationSec ~/ 60} min)');
      } else if (_activeStopEventId != null) {
        // Update existing stop event
        await _locationRepository.updateTimelineEvent(
          id: _activeStopEventId!,
          endTime: currentTime,
          durationSec: durationSec,
          latitude: _stationaryAnchorLat,
          longitude: _stationaryAnchorLng,
        );
        _logger.d('⏸️ Timeline: STOP event updated (${durationSec ~/ 60} min)');
      }
    } catch (e) {
      _logger.e('Error upserting stop event: $e');
    }
  }

  /// Finalize an active stop event
  Future<void> _finalizeStopEvent(DateTime endTime) async {
    if (!_stopEventCreated || _activeStopEventId == null) return;
    if (_stationaryStartTime == null) return;

    final durationSec = endTime.difference(_stationaryStartTime!).inSeconds;

    try {
      await _locationRepository.updateTimelineEvent(
        id: _activeStopEventId!,
        endTime: endTime,
        durationSec: durationSec,
        latitude: _stationaryAnchorLat,
        longitude: _stationaryAnchorLng,
      );
      _logger.i('▶️ Timeline: STOP finalized (${durationSec ~/ 60} min)');
    } catch (e) {
      _logger.e('Error finalizing stop event: $e');
    }
  }

  void _resetStopState() {
    _stationaryStartTime = null;
    _stationaryAnchorLat = null;
    _stationaryAnchorLng = null;
    _activeStopEventId = null;
    _stopEventCreated = false;
  }

  void dispose() {
    _resetStopState();
    _sessionId = null;
    _employeeId = null;
  }
}
