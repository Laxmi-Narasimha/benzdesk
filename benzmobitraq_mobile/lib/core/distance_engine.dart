import 'dart:math';
import '../data/models/location_point_model.dart';

/// Distance Engine - Handles all distance-related calculations
/// Per industry-grade specification Section 8
class DistanceEngine {
  // Configuration constants (should match mobitraq_config in database)
  static const double maxAccuracyM = 50.0;
  static const double teleportSpeedKmh = 160.0;
  static const double jitterBaseM = 10.0;
  static const double jitterMultiplier = 2.0;
  static const double earthRadiusKm = 6371.0;

  /// Calculate Haversine distance between two points in kilometers
  static double haversineDistance({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLng / 2) * sin(dLng / 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadiusKm * c;
  }

  /// Calculate distance in meters
  static double haversineDistanceMeters({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    return haversineDistance(lat1: lat1, lng1: lng1, lat2: lat2, lng2: lng2) * 1000;
  }

  static double _toRadians(double degrees) {
    return degrees * pi / 180.0;
  }

  /// Check if a point should be accepted based on accuracy
  /// Returns false if accuracy > maxAccuracyM
  static bool isAccuracyAcceptable(double? accuracy) {
    if (accuracy == null) return true; // Unknown accuracy is allowed
    return accuracy <= maxAccuracyM;
  }

  /// Check if distance is jitter (should be treated as 0)
  /// Jitter: delta_distance_m < max(10, 2*accuracy_m)
  static bool isJitter({
    required double distanceMeters,
    required double? accuracy1,
    required double? accuracy2,
  }) {
    final accuracy = (accuracy1 ?? 0) + (accuracy2 ?? 0);
    final avgAccuracy = accuracy / 2;
    final threshold = max(jitterBaseM, jitterMultiplier * avgAccuracy);
    return distanceMeters < threshold;
  }

  /// Check if movement is a teleport (implied speed > 160 km/h)
  /// Returns true if teleportation detected
  static bool isTeleport({
    required double distanceKm,
    required Duration timeDelta,
  }) {
    if (timeDelta.inSeconds <= 0) return false;
    
    final hours = timeDelta.inSeconds / 3600.0;
    final impliedSpeedKmh = distanceKm / hours;
    
    return impliedSpeedKmh > teleportSpeedKmh;
  }

  /// Calculate filtered distance between two location points
  /// Returns 0 if:
  /// - Accuracy is not acceptable
  /// - Distance is jitter
  /// - Teleportation detected (logged separately)
  /// 
  /// Returns actual distance otherwise
  static FilteredDistanceResult calculateFilteredDistance({
    required LocationPointModel point1,
    required LocationPointModel point2,
  }) {
    // Check accuracy for both points
    if (!isAccuracyAcceptable(point1.accuracy)) {
      return FilteredDistanceResult(
        distanceKm: 0,
        accepted: false,
        reason: 'Point 1 accuracy too low: ${point1.accuracy}m',
      );
    }
    if (!isAccuracyAcceptable(point2.accuracy)) {
      return FilteredDistanceResult(
        distanceKm: 0,
        accepted: false,
        reason: 'Point 2 accuracy too low: ${point2.accuracy}m',
      );
    }

    // Calculate raw distance
    final distanceKm = haversineDistance(
      lat1: point1.latitude,
      lng1: point1.longitude,
      lat2: point2.latitude,
      lng2: point2.longitude,
    );
    final distanceMeters = distanceKm * 1000;

    // Check for jitter
    if (isJitter(
      distanceMeters: distanceMeters,
      accuracy1: point1.accuracy,
      accuracy2: point2.accuracy,
    )) {
      return FilteredDistanceResult(
        distanceKm: 0,
        accepted: true,
        reason: 'Jitter filtered: ${distanceMeters.toStringAsFixed(1)}m',
      );
    }

    // Check for teleportation
    final timeDelta = point2.recordedAt.difference(point1.recordedAt);
    if (isTeleport(distanceKm: distanceKm, timeDelta: timeDelta)) {
      return FilteredDistanceResult(
        distanceKm: 0,
        accepted: false,
        reason: 'Teleport detected: ${(distanceKm / timeDelta.inSeconds * 3600).toStringAsFixed(1)} km/h',
        isTeleport: true,
      );
    }

    return FilteredDistanceResult(
      distanceKm: distanceKm,
      accepted: true,
      reason: 'Valid distance',
    );
  }

  /// Calculate total distance from a list of points with filtering
  static double calculateTotalDistance(List<LocationPointModel> points) {
    if (points.length < 2) return 0;

    double totalKm = 0;
    for (int i = 1; i < points.length; i++) {
      final result = calculateFilteredDistance(
        point1: points[i - 1],
        point2: points[i],
      );
      if (result.accepted) {
        totalKm += result.distanceKm;
      }
    }
    return totalKm;
  }

  /// Get bearing between two points in degrees
  static double calculateBearing({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    final dLng = _toRadians(lng2 - lng1);
    final lat1Rad = _toRadians(lat1);
    final lat2Rad = _toRadians(lat2);

    final y = sin(dLng) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) -
        sin(lat1Rad) * cos(lat2Rad) * cos(dLng);

    final bearing = atan2(y, x);
    return (bearing * 180 / pi + 360) % 360;
  }
}

/// Result of filtered distance calculation
class FilteredDistanceResult {
  final double distanceKm;
  final bool accepted;
  final String reason;
  final bool isTeleport;

  const FilteredDistanceResult({
    required this.distanceKm,
    required this.accepted,
    required this.reason,
    this.isTeleport = false,
  });

  double get distanceMeters => distanceKm * 1000;

  @override
  String toString() => 'FilteredDistance($distanceKm km, accepted: $accepted, reason: $reason)';
}
