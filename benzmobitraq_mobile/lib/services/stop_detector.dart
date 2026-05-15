import 'dart:math' as math;

import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:benzmobitraq_mobile/data/models/location_point_model.dart';

/// Detects "stop" and "indoor_walking" segments inside a session.
///
/// A stop is when the user stays within [stopRadiusM] for at least
/// [minStopDuration]. We do NOT pause the session — distance tracking
/// continues. We only record an annotation so admins can see
/// "stayed at customer X from 11:05 to 11:38" in the timeline.
///
/// An indoor-walking segment is detected when:
///   - the user is reported as WALKING by Activity Recognition
///     (or ON_FOOT) with confidence >= 60
///   - AND GPS accuracy degrades sharply (> 40 m median over the
///     window) — typical sign of being inside a building
/// This is a sub-class of "stop" — the user is at a location, but
/// moving around within it. It's tagged distinctly so admins can
/// distinguish "parked outside" from "walked into the customer site".
///
/// Used from the main isolate (SessionManager._onLocationUpdate). The
/// background isolate would also be a valid host; we picked the main
/// isolate because that's where we already have the live point stream
/// + Supabase client. Stops only need ~1-min granularity, so any UI
/// throttling that affects the main isolate is acceptable.
///
/// See docs/DISTANCE_TRACKING_METHODOLOGY.md for the bigger picture.
class StopDetector {
  StopDetector({
    Duration minStopDuration = const Duration(minutes: 5),
    Duration mergeWindow = const Duration(minutes: 3),
    double stopRadiusM = 50.0,
    double indoorAccuracyThresholdM = 40.0,
  })  : _minStopDuration = minStopDuration,
        _mergeWindow = mergeWindow,
        _stopRadiusM = stopRadiusM,
        _indoorAccuracyThresholdM = indoorAccuracyThresholdM;

  final Duration _minStopDuration;
  final Duration _mergeWindow;
  final double _stopRadiusM;
  final double _indoorAccuracyThresholdM;

  final Logger _logger = Logger();
  final Uuid _uuid = const Uuid();

  /// In-progress candidate stop. Once it grows past minStopDuration we
  /// promote it to a confirmed stop and persist it.
  _Candidate? _candidate;

  /// The last confirmed stop we wrote. Used so that if the user
  /// moves 30m, stays still for 6 min, then moves back, we MERGE
  /// rather than creating two adjacent stops.
  _ConfirmedStop? _lastConfirmed;

  /// Notify the detector of a new GPS point. Returns the type of
  /// transition that happened, if any:
  ///   - null: nothing meaningful changed (still moving, or still inside
  ///     the same stop)
  ///   - 'stop_started': a new candidate is being tracked
  ///   - 'stop_confirmed': a candidate just crossed the 5-min threshold
  ///   - 'stop_ended': the user has left the stop radius
  Future<String?> onPoint({
    required String sessionId,
    required String employeeId,
    required LocationPointModel point,
  }) async {
    // No candidate yet → start one anchored at this point.
    if (_candidate == null) {
      _candidate = _Candidate(
        anchorLat: point.latitude,
        anchorLng: point.longitude,
        startedAt: point.recordedAt,
        lastSeenAt: point.recordedAt,
        pointCount: 1,
        sumAccuracy: point.accuracy ?? 0,
        accuracySamples: point.accuracy != null ? 1 : 0,
        walkingHits: _isWalking(point) ? 1 : 0,
      );
      return null;
    }

    final c = _candidate!;
    final distanceM = _haversineMeters(
      c.anchorLat,
      c.anchorLng,
      point.latitude,
      point.longitude,
    );

    if (distanceM > _stopRadiusM) {
      // Moved outside the radius → candidate ends. If it was long
      // enough, confirm it; otherwise discard.
      final duration = c.lastSeenAt.difference(c.startedAt);
      _candidate = null;

      if (duration >= _minStopDuration) {
        final confirmed = await _persistStop(
          sessionId: sessionId,
          employeeId: employeeId,
          candidate: c,
        );
        _lastConfirmed = confirmed;
        return 'stop_ended';
      }
      // Start a fresh candidate at the new location.
      _candidate = _Candidate(
        anchorLat: point.latitude,
        anchorLng: point.longitude,
        startedAt: point.recordedAt,
        lastSeenAt: point.recordedAt,
        pointCount: 1,
        sumAccuracy: point.accuracy ?? 0,
        accuracySamples: point.accuracy != null ? 1 : 0,
        walkingHits: _isWalking(point) ? 1 : 0,
      );
      return null;
    }

    // Still inside the radius — extend the candidate.
    c.lastSeenAt = point.recordedAt;
    c.pointCount++;
    if (point.accuracy != null) {
      c.sumAccuracy += point.accuracy!;
      c.accuracySamples++;
    }
    if (_isWalking(point)) c.walkingHits++;

    final duration = c.lastSeenAt.difference(c.startedAt);
    if (duration >= _minStopDuration && !c.confirmedEmitted) {
      c.confirmedEmitted = true;
      // Persist now (we'll update ended_at later when the user leaves).
      // We deliberately don't emit incremental updates for an in-progress
      // stop — the row goes into the DB at confirmation time with the
      // current ended_at, then gets a final UPDATE when the stop closes.
      final confirmed = await _persistStop(
        sessionId: sessionId,
        employeeId: employeeId,
        candidate: c,
      );
      c.persistedId = confirmed?.id;
      _lastConfirmed = confirmed;
      return 'stop_confirmed';
    }

    return null;
  }

  /// Force-close any in-progress candidate. Call this on session end.
  Future<void> finalize({
    required String sessionId,
    required String employeeId,
  }) async {
    final c = _candidate;
    if (c == null) return;
    final duration = c.lastSeenAt.difference(c.startedAt);
    _candidate = null;
    if (duration >= _minStopDuration) {
      await _persistStop(
        sessionId: sessionId,
        employeeId: employeeId,
        candidate: c,
      );
    }
  }

  Future<_ConfirmedStop?> _persistStop({
    required String sessionId,
    required String employeeId,
    required _Candidate candidate,
  }) async {
    final duration = candidate.lastSeenAt.difference(candidate.startedAt);
    final medianAccuracy = candidate.accuracySamples > 0
        ? candidate.sumAccuracy / candidate.accuracySamples
        : null;
    final walkingRatio = candidate.pointCount > 0
        ? candidate.walkingHits / candidate.pointCount
        : 0.0;

    // Indoor-walking heuristic: most points reported WALKING + accuracy
    // worse than normal → the user is moving around inside a building.
    final isIndoor = walkingRatio >= 0.4 &&
        (medianAccuracy ?? 0) > _indoorAccuracyThresholdM;
    final kind = isIndoor ? 'indoor_walking' : 'stop';

    // MERGE: if the last confirmed stop ended within _mergeWindow of
    // this candidate's start AND its center is within 2× radius, we
    // extend the existing row instead of inserting a new one. This
    // prevents the "moved 20m to a different parking spot" case from
    // creating two adjacent stop rows.
    final last = _lastConfirmed;
    if (last != null && last.kind == kind) {
      final timeGap = candidate.startedAt.difference(last.endedAt);
      final spatialGap = _haversineMeters(
        last.centerLat,
        last.centerLng,
        candidate.anchorLat,
        candidate.anchorLng,
      );
      if (timeGap <= _mergeWindow &&
          timeGap >= Duration.zero &&
          spatialGap <= _stopRadiusM * 2) {
        try {
          await Supabase.instance.client.from('session_stops').update({
            'ended_at': candidate.lastSeenAt.toUtc().toIso8601String(),
            'duration_sec': candidate.lastSeenAt
                .difference(last.startedAt)
                .inSeconds,
            'point_count': last.pointCount + candidate.pointCount,
          }).eq('id', last.id);
          _logger.i('STOP-MERGED ${last.id} now ends at ${candidate.lastSeenAt}');
          return last.copyWith(
            endedAt: candidate.lastSeenAt,
            pointCount: last.pointCount + candidate.pointCount,
          );
        } catch (e) {
          _logger.w('STOP-MERGE failed (fallthrough to insert): $e');
        }
      }
    }

    final id = _uuid.v4();
    final row = {
      'id': id,
      'session_id': sessionId,
      'employee_id': employeeId,
      'kind': kind,
      'started_at': candidate.startedAt.toUtc().toIso8601String(),
      'ended_at': candidate.lastSeenAt.toUtc().toIso8601String(),
      'duration_sec': duration.inSeconds,
      'center_lat': candidate.anchorLat,
      'center_lng': candidate.anchorLng,
      'radius_m': _stopRadiusM,
      'point_count': candidate.pointCount,
    };

    try {
      await Supabase.instance.client.from('session_stops').insert(row);
      _logger.i(
          'STOP-PERSIST $kind ${duration.inMinutes}min @${candidate.anchorLat.toStringAsFixed(5)},${candidate.anchorLng.toStringAsFixed(5)}');
      return _ConfirmedStop(
        id: id,
        kind: kind,
        startedAt: candidate.startedAt,
        endedAt: candidate.lastSeenAt,
        centerLat: candidate.anchorLat,
        centerLng: candidate.anchorLng,
        pointCount: candidate.pointCount,
      );
    } catch (e) {
      // Offline or RLS issue. We tolerate failure here — stops are a
      // nice-to-have annotation, not a billing field. They'll be missed
      // for this session if the network is permanently down, which is
      // acceptable.
      _logger.w('STOP-PERSIST failed (skipping): $e');
      return null;
    }
  }

  bool _isWalking(LocationPointModel p) {
    final t = p.activityType;
    return t == 'walking' || t == 'on_foot' || t == 'running';
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

class _Candidate {
  _Candidate({
    required this.anchorLat,
    required this.anchorLng,
    required this.startedAt,
    required this.lastSeenAt,
    required this.pointCount,
    required this.sumAccuracy,
    required this.accuracySamples,
    required this.walkingHits,
  });

  final double anchorLat;
  final double anchorLng;
  final DateTime startedAt;
  DateTime lastSeenAt;
  int pointCount;
  double sumAccuracy;
  int accuracySamples;
  int walkingHits;
  bool confirmedEmitted = false;
  String? persistedId;
}

class _ConfirmedStop {
  const _ConfirmedStop({
    required this.id,
    required this.kind,
    required this.startedAt,
    required this.endedAt,
    required this.centerLat,
    required this.centerLng,
    required this.pointCount,
  });

  final String id;
  final String kind;
  final DateTime startedAt;
  final DateTime endedAt;
  final double centerLat;
  final double centerLng;
  final int pointCount;

  _ConfirmedStop copyWith({
    String? id,
    String? kind,
    DateTime? startedAt,
    DateTime? endedAt,
    double? centerLat,
    double? centerLng,
    int? pointCount,
  }) {
    return _ConfirmedStop(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      centerLat: centerLat ?? this.centerLat,
      centerLng: centerLng ?? this.centerLng,
      pointCount: pointCount ?? this.pointCount,
    );
  }
}
