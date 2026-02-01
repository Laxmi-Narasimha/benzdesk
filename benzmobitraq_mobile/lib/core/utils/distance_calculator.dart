import 'dart:math' as math;

/// Utility class for calculating distances between GPS coordinates
class DistanceCalculator {
  DistanceCalculator._();

  /// Earth's radius in meters
  static const double earthRadiusMeters = 6371000.0;

  /// Calculate distance between two GPS coordinates using the Haversine formula
  /// 
  /// Returns distance in meters
  static double haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    // Convert degrees to radians
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    final double lat1Rad = _toRadians(lat1);
    final double lat2Rad = _toRadians(lat2);

    // Haversine formula
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  /// Calculate distance with anti-jitter filtering
  /// 
  /// Returns 0 if the movement is likely GPS noise, otherwise returns the actual distance
  static double calculateFilteredDistance({
    required double prevLat,
    required double prevLon,
    required double currLat,
    required double currLon,
    required double currAccuracy,
    required DateTime prevTime,
    required DateTime currTime,
    double maxAccuracyThreshold = 50.0,
    double minDistanceDelta = 10.0,
    double maxSpeedKmh = 200.0,
  }) {
    // 1. Reject if accuracy is too poor
    if (currAccuracy > maxAccuracyThreshold) {
      return 0.0;
    }

    // 2. Calculate raw distance
    final double rawDistance = haversineDistance(prevLat, prevLon, currLat, currLon);

    // 3. Anti-jitter: ignore tiny movements (likely GPS drift)
    // Use the larger of minDistanceDelta or 2x current accuracy
    final double minDelta = math.max(minDistanceDelta, currAccuracy * 2);
    if (rawDistance < minDelta) {
      return 0.0;
    }

    // 4. Anti-teleport: reject unrealistic speed jumps
    final Duration timeDiff = currTime.difference(prevTime);
    if (timeDiff.inSeconds > 0) {
      final double speedMps = rawDistance / timeDiff.inSeconds;
      final double speedKmh = speedMps * 3.6;

      if (speedKmh > maxSpeedKmh) {
        // Teleport detected - ignore this point
        return 0.0;
      }
    }

    return rawDistance;
  }

  /// Check if a point is within a certain radius of another point
  static bool isWithinRadius(
    double centerLat,
    double centerLon,
    double pointLat,
    double pointLon,
    double radiusMeters,
  ) {
    final double distance = haversineDistance(centerLat, centerLon, pointLat, pointLon);
    return distance <= radiusMeters;
  }

  /// Calculate bearing between two points in degrees (0-360)
  static double calculateBearing(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final double lat1Rad = _toRadians(lat1);
    final double lat2Rad = _toRadians(lat2);
    final double dLon = _toRadians(lon2 - lon1);

    final double x = math.sin(dLon) * math.cos(lat2Rad);
    final double y = math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLon);

    double bearing = math.atan2(x, y);
    bearing = _toDegrees(bearing);
    bearing = (bearing + 360) % 360;

    return bearing;
  }

  /// Calculate speed in km/h between two points
  static double calculateSpeedKmh(
    double distance,
    Duration timeDiff,
  ) {
    if (timeDiff.inSeconds == 0) return 0.0;
    final double speedMps = distance / timeDiff.inSeconds;
    return speedMps * 3.6;
  }

  /// Convert meters to kilometers
  static double metersToKilometers(double meters) {
    return meters / 1000.0;
  }

  /// Convert kilometers to meters
  static double kilometersToMeters(double kilometers) {
    return kilometers * 1000.0;
  }

  /// Format distance for display
  /// 
  /// Returns formatted string like "1.5 km" or "500 m"
  static String formatDistance(double meters) {
    if (meters >= 1000) {
      final double km = meters / 1000;
      return '${km.toStringAsFixed(1)} km';
    } else {
      return '${meters.round()} m';
    }
  }

  // Convert degrees to radians
  static double _toRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  // Convert radians to degrees
  static double _toDegrees(double radians) {
    return radians * 180 / math.pi;
  }
}
