import 'dart:math' as math;

import 'package:benzmobitraq_mobile/data/models/location_point_model.dart';

/// Confidence + reason-codes scorer.
///
/// Produces a `high` / `medium` / `low` / `unverified_no_gps` label and the
/// set of reason codes that explain the score. Used at session end to
/// persist alongside `final_km` so admins/auditors know why a particular
/// trip is trusted (or not).
///
/// See docs/DISTANCE_TRACKING_METHODOLOGY.md §3.5 for the exact algorithm.
class ConfidenceScorer {
  static const _accuracyMedianThreshold = 30.0;
  static const _gapWarnSeconds = 120;
  static const _gapHardSeconds = 300;
  static const _spacingHardMeters = 300.0;
  static const _stationaryRatioThreshold = 0.3;
  static const _minPointsHigh = 10;
  static const _rawFilteredDiffThreshold = 0.15;

  static ConfidenceResult score({
    required List<LocationPointModel> points,
    required double estimatedKm,
    double? rawHaversineKm,
    bool anyMockDetected = false,
  }) {
    final reasons = <String>[];
    int score = 100;

    if (points.isEmpty) {
      return const ConfidenceResult(
        confidence: 'unverified_no_gps',
        reasonCodes: ['NO_GPS_POINTS'],
        rawScore: 0,
      );
    }

    if (points.length < _minPointsHigh) {
      score -= 30;
      reasons.add('SPARSE_POINTS');
    }

    final accuracies = points
        .map((p) => p.accuracy ?? double.infinity)
        .where((a) => a.isFinite)
        .toList()
      ..sort();
    if (accuracies.isNotEmpty) {
      final median = accuracies[accuracies.length ~/ 2];
      if (median > _accuracyMedianThreshold) {
        score -= 15;
        reasons.add('POOR_ACCURACY');
      }
    }

    // Sorted by time first
    final sorted = [...points]
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    var maxGapSec = 0;
    var maxSpacingM = 0.0;
    for (var i = 1; i < sorted.length; i++) {
      final dt = sorted[i].recordedAt.difference(sorted[i - 1].recordedAt).inSeconds;
      if (dt > maxGapSec) maxGapSec = dt;
      final d = _haversineMeters(
        sorted[i - 1].latitude,
        sorted[i - 1].longitude,
        sorted[i].latitude,
        sorted[i].longitude,
      );
      if (d > maxSpacingM) maxSpacingM = d;
    }

    if (maxGapSec > _gapWarnSeconds) {
      score -= 25;
      reasons.add('GPS_GAP_OVER_120S');
    }
    if (maxGapSec > _gapHardSeconds) {
      score -= 20;
    }
    if (maxSpacingM > _spacingHardMeters) {
      score -= 15;
      reasons.add('POINT_SPACING_OVER_300M');
    }

    final stationaryCount = points
        .where((p) => p.countsForDistance == false)
        .length;
    final stationaryRatio = stationaryCount / points.length;
    if (stationaryRatio > _stationaryRatioThreshold) {
      score -= 10;
      reasons.add('STATIONARY_DOMINATED');
    }

    if (anyMockDetected) {
      score -= 100;
      reasons.add('MOCK_LOCATION_DETECTED');
    }

    if (rawHaversineKm != null && estimatedKm > 0) {
      final diff = (rawHaversineKm - estimatedKm).abs() / estimatedKm;
      if (diff > _rawFilteredDiffThreshold) {
        score -= 10;
        reasons.add('RAW_FILTERED_DIFF_HIGH');
      }
    }

    final String confidence;
    if (score >= 80) {
      confidence = 'high';
    } else if (score >= 50) {
      confidence = 'medium';
    } else {
      confidence = 'low';
    }

    return ConfidenceResult(
      confidence: confidence,
      reasonCodes: List.unmodifiable(reasons),
      rawScore: score,
    );
  }

  static double _haversineMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const earthM = 6371000.0;
    final dLat = _radians(lat2 - lat1);
    final dLon = _radians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthM * c;
  }

  static double _radians(double deg) => deg * math.pi / 180.0;
}

class ConfidenceResult {
  final String confidence;
  final List<String> reasonCodes;
  final int rawScore;
  const ConfidenceResult({
    required this.confidence,
    required this.reasonCodes,
    required this.rawScore,
  });
}
