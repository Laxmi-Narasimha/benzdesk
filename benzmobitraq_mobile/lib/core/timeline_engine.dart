import 'dart:math';
import '../data/models/location_point_model.dart';
import 'distance_engine.dart';

/// Timeline Engine - Handles stop detection and timeline segment generation
/// Per industry-grade specification Section 9.2
class TimelineEngine {
  // Configuration constants (should match mobitraq_config in database)
  static const double stopRadiusM = 120.0;
  static const int stopMinDurationSec = 600; // 10 minutes

  /// Detect stops and moves from a chronologically sorted list of points
  /// Returns a list of TimelineEvent objects representing stops and moves
  static List<TimelineEvent> generateTimeline(List<LocationPointModel> points) {
    if (points.length < 2) return [];

    final events = <TimelineEvent>[];
    
    // Ensure points are sorted by recorded_at
    final sortedPoints = List<LocationPointModel>.from(points)
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    int i = 0;
    while (i < sortedPoints.length) {
      final clusterResult = _buildCluster(sortedPoints, i);
      
      if (clusterResult.isStop) {
        // This is a STOP event
        events.add(TimelineEvent.stop(
          startTime: clusterResult.startTime,
          endTime: clusterResult.endTime,
          centerLat: clusterResult.centerLat,
          centerLng: clusterResult.centerLng,
          pointCount: clusterResult.pointCount,
        ));
      } else if (clusterResult.pointCount > 1) {
        // This is a MOVE segment
        final distanceKm = _calculateSegmentDistance(
          sortedPoints.sublist(i, i + clusterResult.pointCount),
        );
        
        events.add(TimelineEvent.move(
          startTime: clusterResult.startTime,
          endTime: clusterResult.endTime,
          startLat: clusterResult.startLat,
          startLng: clusterResult.startLng,
          endLat: clusterResult.endLat,
          endLng: clusterResult.endLng,
          distanceKm: distanceKm,
          pointCount: clusterResult.pointCount,
        ));
      }
      
      // Move to next unprocessed point
      i += max(1, clusterResult.pointCount);
    }

    return events;
  }

  /// Build a cluster starting at the given index
  /// Returns cluster info including whether it qualifies as a stop
  static _ClusterResult _buildCluster(List<LocationPointModel> points, int startIdx) {
    if (startIdx >= points.length) {
      return _ClusterResult.empty();
    }

    final anchor = points[startIdx];
    final clusterPoints = <LocationPointModel>[anchor];
    
    double sumLat = anchor.latitude;
    double sumLng = anchor.longitude;
    
    int j = startIdx + 1;
    while (j < points.length) {
      final point = points[j];
      final distanceM = DistanceEngine.haversineDistanceMeters(
        lat1: anchor.latitude,
        lng1: anchor.longitude,
        lat2: point.latitude,
        lng2: point.longitude,
      );
      
      if (distanceM <= stopRadiusM) {
        clusterPoints.add(point);
        sumLat += point.latitude;
        sumLng += point.longitude;
        j++;
      } else {
        break;
      }
    }

    final startTime = clusterPoints.first.recordedAt;
    final endTime = clusterPoints.last.recordedAt;
    final durationSec = endTime.difference(startTime).inSeconds;
    
    final isStop = durationSec >= stopMinDurationSec && clusterPoints.length >= 2;
    
    return _ClusterResult(
      pointCount: clusterPoints.length,
      startTime: startTime,
      endTime: endTime,
      durationSec: durationSec,
      centerLat: sumLat / clusterPoints.length,
      centerLng: sumLng / clusterPoints.length,
      startLat: clusterPoints.first.latitude,
      startLng: clusterPoints.first.longitude,
      endLat: clusterPoints.last.latitude,
      endLng: clusterPoints.last.longitude,
      isStop: isStop,
    );
  }

  /// Calculate distance for a move segment
  static double _calculateSegmentDistance(List<LocationPointModel> points) {
    return DistanceEngine.calculateTotalDistance(points);
  }

  /// Downsample points for efficient polyline rendering
  /// Keep one point every [intervalSeconds] seconds or [minDistanceM] meters
  static List<LocationPointModel> downsampleForRendering(
    List<LocationPointModel> points, {
    int intervalSeconds = 15,
    double minDistanceM = 40,
  }) {
    if (points.length <= 2) return points;

    final result = <LocationPointModel>[points.first];
    
    for (int i = 1; i < points.length - 1; i++) {
      final prev = result.last;
      final current = points[i];
      
      final timeDiff = current.recordedAt.difference(prev.recordedAt).inSeconds;
      final distanceM = DistanceEngine.haversineDistanceMeters(
        lat1: prev.latitude,
        lng1: prev.longitude,
        lat2: current.latitude,
        lng2: current.longitude,
      );
      
      if (timeDiff >= intervalSeconds || distanceM >= minDistanceM) {
        result.add(current);
      }
    }
    
    // Always include the last point
    if (result.last != points.last) {
      result.add(points.last);
    }
    
    return result;
  }
}

/// Internal class for cluster building
class _ClusterResult {
  final int pointCount;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSec;
  final double centerLat;
  final double centerLng;
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final bool isStop;

  const _ClusterResult({
    required this.pointCount,
    required this.startTime,
    required this.endTime,
    required this.durationSec,
    required this.centerLat,
    required this.centerLng,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    required this.isStop,
  });

  factory _ClusterResult.empty() => _ClusterResult(
    pointCount: 0,
    startTime: DateTime.now(),
    endTime: DateTime.now(),
    durationSec: 0,
    centerLat: 0,
    centerLng: 0,
    startLat: 0,
    startLng: 0,
    endLat: 0,
    endLng: 0,
    isStop: false,
  );
}

/// Timeline event representing either a STOP or MOVE
class TimelineEvent {
  final TimelineEventType type;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSec;
  
  // For stops
  final double? centerLat;
  final double? centerLng;
  
  // For moves
  final double? startLat;
  final double? startLng;
  final double? endLat;
  final double? endLng;
  final double? distanceKm;
  
  final int pointCount;

  const TimelineEvent._({
    required this.type,
    required this.startTime,
    required this.endTime,
    required this.durationSec,
    this.centerLat,
    this.centerLng,
    this.startLat,
    this.startLng,
    this.endLat,
    this.endLng,
    this.distanceKm,
    required this.pointCount,
  });

  factory TimelineEvent.stop({
    required DateTime startTime,
    required DateTime endTime,
    required double centerLat,
    required double centerLng,
    required int pointCount,
  }) {
    return TimelineEvent._(
      type: TimelineEventType.stop,
      startTime: startTime,
      endTime: endTime,
      durationSec: endTime.difference(startTime).inSeconds,
      centerLat: centerLat,
      centerLng: centerLng,
      pointCount: pointCount,
    );
  }

  factory TimelineEvent.move({
    required DateTime startTime,
    required DateTime endTime,
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    required double distanceKm,
    required int pointCount,
  }) {
    return TimelineEvent._(
      type: TimelineEventType.move,
      startTime: startTime,
      endTime: endTime,
      durationSec: endTime.difference(startTime).inSeconds,
      startLat: startLat,
      startLng: startLng,
      endLat: endLat,
      endLng: endLng,
      distanceKm: distanceKm,
      pointCount: pointCount,
    );
  }

  String get durationFormatted {
    final minutes = durationSec ~/ 60;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m';
  }

  String get distanceFormatted {
    if (distanceKm == null) return '-';
    if (distanceKm! < 1) {
      return '${(distanceKm! * 1000).round()}m';
    }
    return '${distanceKm!.toStringAsFixed(1)}km';
  }

  Map<String, dynamic> toJson() {
    return {
      'event_type': type.name,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'duration_sec': durationSec,
      'center_lat': centerLat,
      'center_lng': centerLng,
      'start_lat': startLat,
      'start_lng': startLng,
      'end_lat': endLat,
      'end_lng': endLng,
      'distance_km': distanceKm,
      'point_count': pointCount,
    };
  }

  factory TimelineEvent.fromJson(Map<String, dynamic> json) {
    final type = json['event_type'] == 'stop' 
        ? TimelineEventType.stop 
        : TimelineEventType.move;
    
    return TimelineEvent._(
      type: type,
      startTime: DateTime.parse(json['start_time']),
      endTime: DateTime.parse(json['end_time']),
      durationSec: json['duration_sec'] as int,
      centerLat: (json['center_lat'] as num?)?.toDouble(),
      centerLng: (json['center_lng'] as num?)?.toDouble(),
      startLat: (json['start_lat'] as num?)?.toDouble(),
      startLng: (json['start_lng'] as num?)?.toDouble(),
      endLat: (json['end_lat'] as num?)?.toDouble(),
      endLng: (json['end_lng'] as num?)?.toDouble(),
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      pointCount: json['point_count'] as int? ?? 0,
    );
  }
}

enum TimelineEventType {
  stop,
  move,
}
