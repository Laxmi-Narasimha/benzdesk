import 'dart:math';
import 'package:benzmobitraq_mobile/data/models/location_point_model.dart';

/// ============================================================
/// DISTANCE ENGINE - PRODUCTION GRADE
/// Zero-tolerance accuracy for employee tracking
/// ============================================================
///
/// Design principles:
/// 1. GPS noise is NOT distance - aggressive smoothing + jitter rejection
/// 2. Missing time gaps are interpolated, not counted as zero
/// 3. Teleports detected per inferred transport mode
/// 4. Chain-of-custody: every point must be verifiable
/// 5. Cross-day sessions: time gaps >12h break the chain

class DistanceEngine {
  // Earth radius in kilometers (WGS-84)
  static const double earthRadiusKm = 6371.0;

  // ============================================================
  // SPEED LIMITS BY INFERRED MODE (km/h)
  // ============================================================
  static const double maxSpeedWalkingKmh = 12.0;
  static const double maxSpeedCyclingKmh = 60.0;
  static const double maxSpeedCityKmh = 120.0;
  static const double maxSpeedHighwayKmh = 200.0;
  static const double absoluteMaxSpeedKmh = 300.0;

  // ============================================================
  // JITTER & NOISE FILTERS
  // ============================================================
  static const double jitterBaseM = 20.0;
  static const double jitterAccuracyMultiplier = 2.5;
  static const int minTimeGapSeconds = 3;
  static const int maxContinuousGapHours = 12;

  // ============================================================
  // HAVERSINE DISTANCE
  // ============================================================

  static double haversineDistanceKm({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double haversineDistanceM({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) =>
      haversineDistanceKm(lat1: lat1, lng1: lng1, lat2: lat2, lng2: lng2) *
      1000.0;

  static double _toRadians(double degrees) => degrees * pi / 180.0;

  // ============================================================
  // ROLLING MEDIAN SMOOTHER
  // Reduces GPS noise by taking median of last N positions
  // ============================================================

  static List<LocationPointModel> applyRollingMedian(
    List<LocationPointModel> points, {
    int windowSize = 5,
  }) {
    if (points.length < windowSize) return points;

    final result = <LocationPointModel>[];
    for (int i = 0; i < points.length; i++) {
      final start =
          (i - windowSize ~/ 2).clamp(0, points.length - windowSize + 1);
      final end = (start + windowSize).clamp(0, points.length);
      final window = points.sublist(start, end);

      final lats = window.map((p) => p.latitude).toList()..sort();
      final lngs = window.map((p) => p.longitude).toList()..sort();

      final medianLat = lats[lats.length ~/ 2];
      final medianLng = lngs[lngs.length ~/ 2];

      result.add(LocationPointModel(
        id: points[i].id,
        sessionId: points[i].sessionId,
        employeeId: points[i].employeeId,
        latitude: medianLat,
        longitude: medianLng,
        accuracy: points[i].accuracy,
        speed: points[i].speed,
        altitude: points[i].altitude,
        heading: points[i].heading,
        isMoving: points[i].isMoving,
        address: points[i].address,
        provider: points[i].provider,
        hash: points[i].hash,
        recordedAt: points[i].recordedAt,
        createdAt: points[i].createdAt,
        serverReceivedAt: points[i].serverReceivedAt,
      ));
    }
    return result;
  }

  // ============================================================
  // SMART JITTER FILTER
  // Adaptive threshold based on the WORSE accuracy of the pair
  // ============================================================

  static bool isJitter({
    required double distanceMeters,
    required double? accuracy1,
    required double? accuracy2,
  }) {
    final maxAccuracy = max(accuracy1 ?? 50.0, accuracy2 ?? 50.0);
    final threshold = max(jitterBaseM, jitterAccuracyMultiplier * maxAccuracy);
    return distanceMeters < threshold;
  }

  // ============================================================
  // ACCURACY ACCEPTANCE
  // ============================================================

  static bool isAccuracyAcceptable(double? accuracy) {
    if (accuracy == null) return true;
    return accuracy <= 50.0;
  }

  // ============================================================
  // MODE-AWARE TELEPORT DETECTION
  // Infers transport mode from recent speed and applies limit
  // ============================================================

  static bool isTeleport({
    required double distanceKm,
    required Duration timeDelta,
    double? recentSpeedKmh,
  }) {
    if (timeDelta.inSeconds <= 0) return false;
    final hours = timeDelta.inSeconds / 3600.0;
    final impliedSpeedKmh = distanceKm / hours;

    double speedLimit;
    if (recentSpeedKmh != null) {
      if (recentSpeedKmh < 15) {
        speedLimit = maxSpeedWalkingKmh;
      } else if (recentSpeedKmh < 70) {
        speedLimit = maxSpeedCyclingKmh;
      } else if (recentSpeedKmh < 130) {
        speedLimit = maxSpeedCityKmh;
      } else {
        speedLimit = maxSpeedHighwayKmh;
      }
    } else {
      speedLimit = maxSpeedCityKmh;
    }

    return impliedSpeedKmh > speedLimit;
  }

  // ============================================================
  // FILTERED SEGMENT CALCULATION
  // ============================================================

  static FilteredSegmentResult calculateSegment({
    required LocationPointModel from,
    required LocationPointModel to,
    double? recentSpeedKmh,
  }) {
    // Mock-location rejection (Stage 2). Either endpoint flagged as mock
    // disqualifies the segment for distance. The points are still stored
    // (so the audit trail is complete and confidence scoring can see them),
    // but they contribute 0 km to the billed total.
    if (from.isMock || to.isMock) {
      return FilteredSegmentResult(
          distanceM: 0, accepted: false, reason: 'mock_location');
    }

    if (!isAccuracyAcceptable(from.accuracy)) {
      return FilteredSegmentResult(
          distanceM: 0, accepted: false, reason: 'from_accuracy_low');
    }
    if (!isAccuracyAcceptable(to.accuracy)) {
      return FilteredSegmentResult(
          distanceM: 0, accepted: false, reason: 'to_accuracy_low');
    }

    final timeDelta = to.recordedAt.difference(from.recordedAt);
    if (timeDelta.inSeconds < 0) {
      return FilteredSegmentResult(
          distanceM: 0, accepted: false, reason: 'negative_time');
    }

    // Impossible-acceleration check (Stage 2). A car cannot go from 0 to
    // highway speed in 2 seconds. If our speed delta divided by the time
    // delta implies acceleration above a physical bound, this is GPS noise
    // (typically a bad fix after reacquisition). 10 m/s² is roughly 1g —
    // genuine vehicle accel is well below this; sustained ≥10 m/s² is a
    // jet, not a car.
    if (from.speed != null && to.speed != null && timeDelta.inSeconds > 0) {
      final deltaSpeed = (to.speed! - from.speed!).abs();
      final accel = deltaSpeed / timeDelta.inSeconds;
      if (accel > 10.0) {
        return FilteredSegmentResult(
            distanceM: 0, accepted: false, reason: 'impossible_accel');
      }
    }

    // Activity-based stationary rejection. If the device's
    // ActivityRecognition API reports we're STILL with high confidence
    // at both ends of the segment, this is parked-car jitter — reject.
    if (from.activityType == 'still' &&
        to.activityType == 'still' &&
        (from.activityConfidence ?? 0) >= 75 &&
        (to.activityConfidence ?? 0) >= 75) {
      return FilteredSegmentResult(
          distanceM: 0, accepted: true, reason: 'still_activity', isNoise: true);
    }

    final distanceM = haversineDistanceM(
      lat1: from.latitude,
      lng1: from.longitude,
      lat2: to.latitude,
      lng2: to.longitude,
    );

    if (isJitter(
      distanceMeters: distanceM,
      accuracy1: from.accuracy,
      accuracy2: to.accuracy,
    )) {
      return FilteredSegmentResult(
          distanceM: 0, accepted: true, reason: 'jitter', isNoise: true);
    }

    if (isTeleport(
        distanceKm: distanceM / 1000.0,
        timeDelta: timeDelta,
        recentSpeedKmh: recentSpeedKmh)) {
      return FilteredSegmentResult(
          distanceM: 0, accepted: false, reason: 'teleport', isTeleport: true);
    }

    return FilteredSegmentResult(
        distanceM: distanceM, accepted: true, reason: 'valid');
  }

  // ============================================================
  // AUTHORITATIVE PATH DISTANCE
  // The ONE TRUE distance from a complete point chain
  // ============================================================

  static PathDistanceResult calculateAuthoritativeDistance(
    List<LocationPointModel> points, {
    bool applySmoothing = true,
  }) {
    if (points.length < 2) {
      return PathDistanceResult(
          totalKm: 0,
          segments: 0,
          noiseSegments: 0,
          teleportSegments: 0,
          gapInterpolations: 0,
          chainValid: true,
          pointCount: points.length);
    }

    final sorted = List<LocationPointModel>.from(points)
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    final unique = <LocationPointModel>[];
    String? lastHash;
    for (final p in sorted) {
      if (p.hash != null && p.hash == lastHash) continue;
      unique.add(p);
      lastHash = p.hash;
    }

    final processed =
        applySmoothing ? applyRollingMedian(unique, windowSize: 5) : unique;

    final hasAcceptedDeltas =
        unique.any((p) => p.countsForDistance && (p.distanceDeltaM ?? 0) > 0);
    if (hasAcceptedDeltas) {
      double acceptedTotalM = 0;
      int acceptedSegments = 0;
      for (final p in unique) {
        if (p.countsForDistance && (p.distanceDeltaM ?? 0) > 0) {
          acceptedTotalM += p.distanceDeltaM!;
          acceptedSegments++;
        }
      }

      return PathDistanceResult(
        totalKm: acceptedTotalM / 1000.0,
        segments: acceptedSegments,
        noiseSegments: unique.length - acceptedSegments,
        teleportSegments: 0,
        gapInterpolations: 0,
        chainValid: true,
        pointCount: unique.length,
      );
    }

    double totalKm = 0;
    int validSegments = 0;
    int noiseSegments = 0;
    int teleportSegments = 0;
    int gapInterpolations = 0;
    bool chainValid = true;
    double? recentSpeedKmh;

    for (int i = 1; i < processed.length; i++) {
      final from = processed[i - 1];
      final to = processed[i];
      final timeDelta = to.recordedAt.difference(from.recordedAt);

      if (timeDelta.inHours > maxContinuousGapHours) {
        chainValid = false;
        continue;
      }

      if (timeDelta.inSeconds > 180 &&
          timeDelta.inHours <= maxContinuousGapHours) {
        final gapDistanceM = haversineDistanceM(
          lat1: from.latitude,
          lng1: from.longitude,
          lat2: to.latitude,
          lng2: to.longitude,
        );
        final gapHours = timeDelta.inSeconds / 3600.0;
        final impliedSpeed = (gapDistanceM / 1000.0) / gapHours;

        if (impliedSpeed > absoluteMaxSpeedKmh) {
          final interpolatedKm = 5.0 * gapHours;
          totalKm += interpolatedKm;
          gapInterpolations++;
          noiseSegments++;
          continue;
        }
      }

      final result =
          calculateSegment(from: from, to: to, recentSpeedKmh: recentSpeedKmh);

      if (result.isTeleport) teleportSegments++;
      if (result.isNoise) noiseSegments++;

      if (result.accepted && !result.isNoise) {
        totalKm += result.distanceM / 1000.0;
        validSegments++;
        final segmentSpeed = result.distanceM /
            1000.0 /
            max(timeDelta.inSeconds / 3600.0, 0.001);
        recentSpeedKmh = recentSpeedKmh == null
            ? segmentSpeed
            : (recentSpeedKmh * 0.7 + segmentSpeed * 0.3);
      }
    }

    return PathDistanceResult(
      totalKm: totalKm,
      segments: validSegments,
      noiseSegments: noiseSegments,
      teleportSegments: teleportSegments,
      gapInterpolations: gapInterpolations,
      chainValid: chainValid,
      pointCount: processed.length,
    );
  }

  // ============================================================
  // CHAIN INTEGRITY VERIFICATION
  // ============================================================

  static ChainIntegrityResult verifyChainIntegrity(
      List<LocationPointModel> points) {
    if (points.isEmpty) {
      return ChainIntegrityResult(
          valid: true, coveragePercent: 100, missingRanges: []);
    }

    final sorted = List<LocationPointModel>.from(points)
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    final totalSpan =
        sorted.last.recordedAt.difference(sorted.first.recordedAt);
    if (totalSpan.inMinutes < 1) {
      return ChainIntegrityResult(
          valid: true, coveragePercent: 100, missingRanges: []);
    }

    final missingRanges = <DurationRange>[];
    Duration totalMissing = Duration.zero;

    for (int i = 1; i < sorted.length; i++) {
      final gap = sorted[i].recordedAt.difference(sorted[i - 1].recordedAt);
      if (gap.inMinutes > 5) {
        totalMissing += gap;
        missingRanges.add(DurationRange(
            start: sorted[i - 1].recordedAt, end: sorted[i].recordedAt));
      }
    }

    final coveragePercent =
        max(0, 100 - (totalMissing.inSeconds / totalSpan.inSeconds * 100))
            .round();

    return ChainIntegrityResult(
      valid: coveragePercent >= 80,
      coveragePercent: coveragePercent,
      missingRanges: missingRanges,
    );
  }

  // ============================================================
  // UTILITY METHODS
  // ============================================================

  /// Calculate a destination point given a start, bearing, and distance
  static Map<String, double> destinationPoint(
    double lat,
    double lng,
    double bearingDeg,
    double distanceM,
  ) {
    final latRad = _toRadians(lat);
    final lngRad = _toRadians(lng);
    final bearingRad = _toRadians(bearingDeg);
    final angularDist = distanceM / (earthRadiusKm * 1000.0);

    final lat2Rad = asin(
      sin(latRad) * cos(angularDist) +
          cos(latRad) * sin(angularDist) * cos(bearingRad),
    );
    final lng2Rad = lngRad +
        atan2(
          sin(bearingRad) * sin(angularDist) * cos(latRad),
          cos(angularDist) - sin(latRad) * sin(lat2Rad),
        );

    return {
      'lat': lat2Rad * 180 / pi,
      'lng': lng2Rad * 180 / pi,
    };
  }

  /// Calculate raw distance without any filtering (for comparison)
  static double calculateRawDistance(List<LocationPointModel> points) {
    if (points.length < 2) return 0;
    final sorted = List<LocationPointModel>.from(points)
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    double total = 0;
    for (int i = 1; i < sorted.length; i++) {
      total += haversineDistanceM(
        lat1: sorted[i - 1].latitude,
        lng1: sorted[i - 1].longitude,
        lat2: sorted[i].latitude,
        lng2: sorted[i].longitude,
      );
    }
    return total / 1000.0;
  }

  // ============================================================
  // LEGACY COMPATIBILITY
  // ============================================================

  static double calculateTotalDistance(List<LocationPointModel> points) {
    return calculateAuthoritativeDistance(points).totalKm;
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
    final x =
        cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLng);
    final bearing = atan2(y, x);
    return (bearing * 180 / pi + 360) % 360;
  }
}

// ============================================================
// RESULT CLASSES
// ============================================================

class FilteredSegmentResult {
  final double distanceM;
  final bool accepted;
  final String reason;
  final bool isTeleport;
  final bool isNoise;

  const FilteredSegmentResult({
    required this.distanceM,
    required this.accepted,
    required this.reason,
    this.isTeleport = false,
    this.isNoise = false,
  });

  double get distanceKm => distanceM / 1000.0;
}

class PathDistanceResult {
  final double totalKm;
  final int segments;
  final int noiseSegments;
  final int teleportSegments;
  final int gapInterpolations;
  final bool chainValid;
  final int pointCount;

  const PathDistanceResult({
    required this.totalKm,
    required this.segments,
    required this.noiseSegments,
    required this.teleportSegments,
    required this.gapInterpolations,
    required this.chainValid,
    required this.pointCount,
  });

  @override
  String toString() =>
      'PathDistance(${totalKm.toStringAsFixed(3)} km, $segments valid, '
      '$noiseSegments noise, $teleportSegments teleports, '
      '$gapInterpolations interpolated, chainValid=$chainValid)';
}

class ChainIntegrityResult {
  final bool valid;
  final int coveragePercent;
  final List<DurationRange> missingRanges;

  const ChainIntegrityResult({
    required this.valid,
    required this.coveragePercent,
    required this.missingRanges,
  });
}

class DurationRange {
  final DateTime start;
  final DateTime end;

  const DurationRange({required this.start, required this.end});

  Duration get duration => end.difference(start);
}
