import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:logger/logger.dart';

import '../core/constants/app_constants.dart';

/// Service for detecting device motion state (moving vs stationary)
class MotionDetectorService {
  final Logger _logger = Logger();

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  
  // Motion detection state
  bool _isMoving = false;
  DateTime? _lastMovementTime;
  DateTime? _stationaryStartTime;
  
  // Circular buffer for motion samples
  final List<double> _magnitudeBuffer = [];
  static const int _bufferSize = 50;
  
  // Thresholds
  static const double _movementThreshold = 0.5; // m/s² above baseline
  static const double _baselineGravity = 9.81;
  
  // Callbacks
  Function(bool isMoving)? onMotionStateChanged;
  Function(Duration stationaryDuration)? onStationaryCheck;

  Timer? _stationaryCheckTimer;

  /// Start monitoring motion
  void startMonitoring() {
    _accelerometerSubscription?.cancel();
    
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 200),
    ).listen(
      _onAccelerometerEvent,
      onError: (error) {
        _logger.e('Accelerometer error: $error');
      },
    );

    // Start stationary check timer
    _stationaryCheckTimer = Timer.periodic(
      Duration(seconds: AppConstants.stationaryCheckInterval),
      (_) => _checkStationaryState(),
    );

    _logger.i('Motion monitoring started');
  }

  /// Stop monitoring motion
  void stopMonitoring() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    
    _stationaryCheckTimer?.cancel();
    _stationaryCheckTimer = null;
    
    _magnitudeBuffer.clear();
    _isMoving = false;
    _lastMovementTime = null;
    _stationaryStartTime = null;

    _logger.i('Motion monitoring stopped');
  }

  /// Handle accelerometer event
  void _onAccelerometerEvent(AccelerometerEvent event) {
    // Calculate magnitude of acceleration
    final magnitude = _calculateMagnitude(event.x, event.y, event.z);
    
    // Add to buffer
    _magnitudeBuffer.add(magnitude);
    if (_magnitudeBuffer.length > _bufferSize) {
      _magnitudeBuffer.removeAt(0);
    }

    // Check for motion
    final deviation = (magnitude - _baselineGravity).abs();
    
    if (deviation > _movementThreshold) {
      _onMotionDetected();
    }
  }

  /// Calculate acceleration magnitude
  double _calculateMagnitude(double x, double y, double z) {
    return _sqrt(x * x + y * y + z * z);
  }

  /// Called when motion is detected
  void _onMotionDetected() {
    _lastMovementTime = DateTime.now();
    
    if (!_isMoving) {
      _isMoving = true;
      _stationaryStartTime = null;
      onMotionStateChanged?.call(true);
      _logger.d('Motion state: MOVING');
    }
  }

  /// Check stationary state
  void _checkStationaryState() {
    if (_lastMovementTime == null) {
      _onBecameStationary();
      return;
    }

    final timeSinceMovement = DateTime.now().difference(_lastMovementTime!);
    
    if (timeSinceMovement.inSeconds >= AppConstants.stationaryCheckInterval) {
      _onBecameStationary();
    }
  }

  /// Called when device becomes stationary
  void _onBecameStationary() {
    if (_isMoving) {
      _isMoving = false;
      _stationaryStartTime = DateTime.now();
      onMotionStateChanged?.call(false);
      _logger.d('Motion state: STATIONARY');
    }

    // Notify about stationary duration
    if (_stationaryStartTime != null) {
      final duration = DateTime.now().difference(_stationaryStartTime!);
      onStationaryCheck?.call(duration);
    }
  }

  /// Get current motion state
  bool get isMoving => _isMoving;

  /// Get stationary duration (if stationary)
  Duration? get stationaryDuration {
    if (_isMoving || _stationaryStartTime == null) {
      return null;
    }
    return DateTime.now().difference(_stationaryStartTime!);
  }

  /// Get average magnitude from buffer
  double get averageMagnitude {
    if (_magnitudeBuffer.isEmpty) return _baselineGravity;
    return _magnitudeBuffer.reduce((a, b) => a + b) / _magnitudeBuffer.length;
  }

  /// Get variance in magnitude (indicates activity level)
  double get magnitudeVariance {
    if (_magnitudeBuffer.length < 2) return 0;
    
    final avg = averageMagnitude;
    double sumSquares = 0;
    for (final value in _magnitudeBuffer) {
      sumSquares += (value - avg) * (value - avg);
    }
    return sumSquares / _magnitudeBuffer.length;
  }

  // Simple square root implementation
  double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
}
