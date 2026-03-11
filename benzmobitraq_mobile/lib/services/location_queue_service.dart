import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../data/datasources/local/location_queue_local.dart';
import '../data/repositories/location_repository.dart';
import '../data/models/location_point_model.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/distance_calculator.dart';

/// Service for managing location queue and batch uploads
class LocationQueueService {
  final LocationRepository _repository;
  final LocationQueueLocal _localQueue;
  final Connectivity _connectivity;
  final Logger _logger = Logger();
  final Uuid _uuid = const Uuid();

  // In-memory cache for current session
  final List<LocationPointModel> _sessionPoints = [];
  String? _currentSessionId;
  double _sessionDistance = 0;
  LocationPointModel? _lastValidPoint;

  LocationQueueService({
    required LocationRepository repository,
    required LocationQueueLocal localQueue,
    Connectivity? connectivity,
  })  : _repository = repository,
        _localQueue = localQueue,
        _connectivity = connectivity ?? Connectivity();

  /// Initialize the service
  Future<void> initialize() async {
    await _localQueue.init();
  }

  /// Start tracking for a new session
  void startSession(String sessionId) {
    _currentSessionId = sessionId;
    _sessionPoints.clear();
    _sessionDistance = 0;
    _lastValidPoint = null;
    _logger.i('Location queue started for session: $sessionId');
  }

  /// Stop tracking and cleanup
  Future<void> stopSession() async {
    _logger.i('Location queue stopped for session: $_currentSessionId');
    _currentSessionId = null;
    _sessionPoints.clear();
    _sessionDistance = 0;
    _lastValidPoint = null;
  }

  /// Add a new location point
  Future<bool> addLocation({
    required String employeeId,
    required double latitude,
    required double longitude,
    double? accuracy,
    double? speed,
    double? altitude,
    double? heading,
    bool isMoving = true,
  }) async {
    if (_currentSessionId == null) {
      _logger.w('Cannot add location: No active session');
      return false;
    }

    try {
      // Validate and filter point
      if (accuracy != null && accuracy > AppConstants.maxAccuracyThreshold) {
        _logger.d('Location rejected: accuracy too low ($accuracy m)');
        return false;
      }

      // Calculate distance from last point
      double distanceDelta = 0;
      if (_lastValidPoint != null) {
        distanceDelta = DistanceCalculator.calculateFilteredDistance(
          prevLat: _lastValidPoint!.latitude,
          prevLon: _lastValidPoint!.longitude,
          currLat: latitude,
          currLon: longitude,
          currAccuracy: accuracy ?? AppConstants.maxAccuracyThreshold,
          prevTime: _lastValidPoint!.recordedAt,
          currTime: DateTime.now(),
        );

        // Skip if distance is too small (jitter)
        if (distanceDelta < AppConstants.minDistanceDelta) {
          _logger.d('Location rejected: distance too small ($distanceDelta m)');
          return false;
        }
      }

      // Create location point
      final point = LocationPointModel.create(
        id: _uuid.v4(),
        sessionId: _currentSessionId!,
        employeeId: employeeId,
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        speed: speed,
        altitude: altitude,
        heading: heading,
        isMoving: isMoving,
        recordedAt: DateTime.now(),
      );

      // Add to local queue
      await _repository.queueLocation(point);
      
      // Update session tracking
      _sessionPoints.add(point);
      _sessionDistance += distanceDelta;
      _lastValidPoint = point;

      _logger.d('Location added: ${point.id}, distance: $distanceDelta m, total: $_sessionDistance m');

      // Check if we should upload
      await _checkAndUpload();

      return true;
    } catch (e) {
      _logger.e('Error adding location: $e');
      return false;
    }
  }

  /// Check if batch upload is needed
  Future<void> _checkAndUpload() async {
    final pendingCount = await _repository.getPendingCount();
    
    if (pendingCount >= AppConstants.maxPointsPerBatch) {
      await uploadPending();
    }
  }

  /// Upload pending locations to server
  Future<int> uploadPending() async {
    try {
      // Check connectivity - handle both old and new API
      final connectivityResult = await _connectivity.checkConnectivity();
      
      // New API returns List<ConnectivityResult>, old API returns single ConnectivityResult
      bool hasNoConnection = false;
      if (connectivityResult is List) {
        hasNoConnection = (connectivityResult as List).isEmpty || 
            (connectivityResult as List).contains(ConnectivityResult.none);
      } else {
        hasNoConnection = connectivityResult == ConnectivityResult.none;
      }
      
      if (hasNoConnection) {
        _logger.d('Skipping upload: No connectivity');
        return 0;
      }

      return await _repository.uploadPendingLocations();
    } catch (e) {
      _logger.e('Error uploading pending locations: $e');
      return 0;
    }
  }

  /// Force upload all remaining points for a session
  Future<void> forceUpload(String sessionId) async {
    try {
      _logger.i('Force uploading session: $sessionId');
      await _repository.forceUploadSession(sessionId);
    } catch (e) {
      _logger.e('Error force uploading: $e');
    }
  }

  /// Get current session distance in meters
  double get currentSessionDistance => _sessionDistance;

  /// Get session distance from local database
  Future<double> getSessionDistance(String sessionId) async {
    if (sessionId == _currentSessionId) {
      return _sessionDistance;
    }
    return await _repository.getLocalSessionDistance(sessionId);
  }

  /// Get pending upload count
  Future<int> getPendingCount() async {
    return await _repository.getPendingCount();
  }

  /// Get last recorded point
  LocationPointModel? get lastPoint => _lastValidPoint;

  /// Check if currently tracking
  bool get isTracking => _currentSessionId != null;
}
