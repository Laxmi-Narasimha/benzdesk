import '../constants/app_constants.dart';

/// Filter and validate location points to ensure data quality
class LocationFilter {
  LocationFilter._();

  /// Validate a single location point
  /// 
  /// Returns true if the point meets quality criteria
  static bool isValidPoint({
    required double latitude,
    required double longitude,
    required double accuracy,
    double? speed,
  }) {
    // Check for null island (0,0) - common GPS error
    if (latitude == 0.0 && longitude == 0.0) {
      return false;
    }

    // Check valid coordinate ranges
    if (latitude < -90 || latitude > 90) {
      return false;
    }
    if (longitude < -180 || longitude > 180) {
      return false;
    }

    // Check accuracy threshold
    if (accuracy > AppConstants.maxAccuracyThreshold) {
      return false;
    }

    // Check for unrealistic negative accuracy (shouldn't happen, but defensive)
    if (accuracy < 0) {
      return false;
    }

    // If speed is provided, check for unrealistic values
    if (speed != null) {
      final double speedKmh = speed * 3.6; // Convert m/s to km/h
      if (speedKmh > AppConstants.maxSpeedKmh || speedKmh < 0) {
        return false;
      }
    }

    return true;
  }

  /// Check if movement between two points is significant
  /// 
  /// Returns true if the distance is large enough to not be GPS jitter
  static bool isSignificantMovement({
    required double distanceMeters,
    required double accuracy,
  }) {
    // Use the larger of minDistanceDelta or 2x accuracy
    final double threshold = _max(
      AppConstants.minDistanceDelta,
      accuracy * 2,
    );
    
    return distanceMeters >= threshold;
  }

  /// Check if speed between two points is realistic
  static bool isRealisticSpeed({
    required double distanceMeters,
    required Duration timeDiff,
  }) {
    if (timeDiff.inSeconds <= 0) {
      // If time difference is 0 or negative, can't calculate speed
      // Accept the point to avoid blocking updates
      return true;
    }

    final double speedMps = distanceMeters / timeDiff.inSeconds;
    final double speedKmh = speedMps * 3.6;

    return speedKmh <= AppConstants.maxSpeedKmh;
  }

  /// Determine if device should be considered stationary
  /// 
  /// Uses a rolling window of recent points to determine if the device
  /// has been effectively stationary
  static bool isStationary({
    required List<LocationPointData> recentPoints,
    required double radiusMeters,
    required int minPointsRequired,
  }) {
    if (recentPoints.length < minPointsRequired) {
      return false;
    }

    // Use the first point as the anchor
    final anchor = recentPoints.first;

    // Check if all points are within the radius
    for (final point in recentPoints) {
      final distance = _calculateDistance(
        anchor.latitude,
        anchor.longitude,
        point.latitude,
        point.longitude,
      );
      
      if (distance > radiusMeters) {
        return false;
      }
    }

    return true;
  }

  /// Simple distance calculation for internal use
  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    // Simple Haversine - could import from DistanceCalculator but keeping self-contained
    const double earthRadius = 6371000.0;
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

  static double _max(double a, double b) => a > b ? a : b;
  static double _toRadians(double deg) => deg * 3.14159265359 / 180;
  static double _sin(double x) => _sinTaylor(x);
  static double _cos(double x) => _sinTaylor(x + 3.14159265359 / 2);
  static double _sqrt(double x) => _sqrtNewton(x);
  static double _atan2(double y, double x) => _atan2Impl(y, x);

  // Taylor series approximation for sin
  static double _sinTaylor(double x) {
    // Normalize to [-π, π]
    const double pi = 3.14159265359;
    while (x > pi) x -= 2 * pi;
    while (x < -pi) x += 2 * pi;
    
    double result = x;
    double term = x;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }

  // Newton's method for sqrt
  static double _sqrtNewton(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  // atan2 implementation
  static double _atan2Impl(double y, double x) {
    const double pi = 3.14159265359;
    if (x > 0) {
      return _atanTaylor(y / x);
    } else if (x < 0 && y >= 0) {
      return _atanTaylor(y / x) + pi;
    } else if (x < 0 && y < 0) {
      return _atanTaylor(y / x) - pi;
    } else if (x == 0 && y > 0) {
      return pi / 2;
    } else if (x == 0 && y < 0) {
      return -pi / 2;
    }
    return 0;
  }

  // Taylor series for atan
  static double _atanTaylor(double x) {
    if (x > 1) return 3.14159265359 / 2 - _atanTaylor(1 / x);
    if (x < -1) return -3.14159265359 / 2 - _atanTaylor(1 / x);
    
    double result = x;
    double term = x;
    for (int i = 1; i <= 20; i++) {
      term *= -x * x;
      result += term / (2 * i + 1);
    }
    return result;
  }
}

/// Simple data class for location points used in filtering
class LocationPointData {
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;

  const LocationPointData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });
}
