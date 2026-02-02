import '../data/models/location_point_model.dart';
import 'distance_engine.dart';

/// Alerts Engine - Handles stuck and no-signal detection
/// Per industry-grade specification Section 10
class AlertsEngine {
  // Configuration constants (should match mobitraq_config in database)
  static const double stuckRadiusM = 150.0;
  static const int stuckMinDurationMin = 30;
  static const int noSignalTimeoutMin = 20;
  static const int clockDriftThresholdMin = 10;

  /// Check if employee is stuck based on location history
  /// Returns StuckCheckResult with alert info if stuck
  static StuckCheckResult checkStuck({
    required LocationPointModel? anchorPoint,
    required DateTime? anchorTime,
    required LocationPointModel currentPoint,
  }) {
    if (anchorPoint == null || anchorTime == null) {
      // First point, set as anchor
      return StuckCheckResult(
        isStuck: false,
        shouldSetAnchor: true,
        newAnchorPoint: currentPoint,
        newAnchorTime: currentPoint.recordedAt,
      );
    }

    // Calculate distance from anchor
    final distanceFromAnchor = DistanceEngine.haversineDistanceMeters(
      lat1: anchorPoint.latitude,
      lng1: anchorPoint.longitude,
      lat2: currentPoint.latitude,
      lng2: currentPoint.longitude,
    );

    if (distanceFromAnchor <= stuckRadiusM) {
      // Still within stuck radius
      final durationMin = currentPoint.recordedAt.difference(anchorTime).inMinutes;
      
      if (durationMin >= stuckMinDurationMin) {
        return StuckCheckResult(
          isStuck: true,
          shouldSetAnchor: false,
          stuckDurationMin: durationMin,
          stuckLocation: anchorPoint,
        );
      } else {
        // Within radius but not long enough yet
        return StuckCheckResult(
          isStuck: false,
          shouldSetAnchor: false,
        );
      }
    } else {
      // Moved outside radius, reset anchor
      return StuckCheckResult(
        isStuck: false,
        shouldSetAnchor: true,
        newAnchorPoint: currentPoint,
        newAnchorTime: currentPoint.recordedAt,
      );
    }
  }

  /// Check if there's a no-signal condition
  static NoSignalCheckResult checkNoSignal({
    required DateTime? lastPointTime,
    required bool isSessionActive,
  }) {
    if (!isSessionActive || lastPointTime == null) {
      return NoSignalCheckResult(hasNoSignal: false);
    }

    final timeSinceLastPoint = DateTime.now().difference(lastPointTime);
    final minutesSinceLastPoint = timeSinceLastPoint.inMinutes;

    if (minutesSinceLastPoint >= noSignalTimeoutMin) {
      return NoSignalCheckResult(
        hasNoSignal: true,
        minutesSinceLastPoint: minutesSinceLastPoint,
      );
    }

    return NoSignalCheckResult(hasNoSignal: false);
  }

  /// Check for clock drift between device and server
  static ClockDriftCheckResult checkClockDrift({
    required DateTime deviceTime,
    required DateTime serverTime,
  }) {
    final drift = deviceTime.difference(serverTime);
    final driftMinutes = drift.inMinutes.abs();

    if (driftMinutes >= clockDriftThresholdMin) {
      return ClockDriftCheckResult(
        hasClockDrift: true,
        driftMinutes: drift.inMinutes,
        isDeviceAhead: drift.isNegative == false,
      );
    }

    return ClockDriftCheckResult(hasClockDrift: false);
  }
}

/// Result of stuck check
class StuckCheckResult {
  final bool isStuck;
  final bool shouldSetAnchor;
  final LocationPointModel? newAnchorPoint;
  final DateTime? newAnchorTime;
  final int? stuckDurationMin;
  final LocationPointModel? stuckLocation;

  const StuckCheckResult({
    required this.isStuck,
    required this.shouldSetAnchor,
    this.newAnchorPoint,
    this.newAnchorTime,
    this.stuckDurationMin,
    this.stuckLocation,
  });
}

/// Result of no-signal check
class NoSignalCheckResult {
  final bool hasNoSignal;
  final int? minutesSinceLastPoint;

  const NoSignalCheckResult({
    required this.hasNoSignal,
    this.minutesSinceLastPoint,
  });
}

/// Result of clock drift check
class ClockDriftCheckResult {
  final bool hasClockDrift;
  final int? driftMinutes;
  final bool? isDeviceAhead;

  const ClockDriftCheckResult({
    required this.hasClockDrift,
    this.driftMinutes,
    this.isDeviceAhead,
  });
}

/// Alert model for local and server storage
class MobiTraqAlert {
  final String? id;
  final String employeeId;
  final String? sessionId;
  final AlertType type;
  final AlertSeverity severity;
  final String message;
  final DateTime startTime;
  final DateTime? endTime;
  final double? lat;
  final double? lng;
  final bool isOpen;
  final DateTime createdAt;

  const MobiTraqAlert({
    this.id,
    required this.employeeId,
    this.sessionId,
    required this.type,
    required this.severity,
    required this.message,
    required this.startTime,
    this.endTime,
    this.lat,
    this.lng,
    this.isOpen = true,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'employee_id': employeeId,
      'session_id': sessionId,
      'alert_type': type.value,
      'severity': severity.value,
      'message': message,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'lat': lat,
      'lng': lng,
      'is_open': isOpen,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory MobiTraqAlert.fromJson(Map<String, dynamic> json) {
    return MobiTraqAlert(
      id: json['id'] as String?,
      employeeId: json['employee_id'] as String,
      sessionId: json['session_id'] as String?,
      type: AlertType.fromValue(json['alert_type'] as String),
      severity: AlertSeverity.fromValue(json['severity'] as String),
      message: json['message'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: json['end_time'] != null 
          ? DateTime.parse(json['end_time'] as String) 
          : null,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      isOpen: json['is_open'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  MobiTraqAlert copyWith({
    String? id,
    String? employeeId,
    String? sessionId,
    AlertType? type,
    AlertSeverity? severity,
    String? message,
    DateTime? startTime,
    DateTime? endTime,
    double? lat,
    double? lng,
    bool? isOpen,
    DateTime? createdAt,
  }) {
    return MobiTraqAlert(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      sessionId: sessionId ?? this.sessionId,
      type: type ?? this.type,
      severity: severity ?? this.severity,
      message: message ?? this.message,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      isOpen: isOpen ?? this.isOpen,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

enum AlertType {
  stuck('stuck'),
  noSignal('no_signal'),
  mockLocation('mock_location'),
  clockDrift('clock_drift'),
  forceStop('force_stop'),
  lowBattery('low_battery'),
  other('other');

  final String value;
  const AlertType(this.value);

  static AlertType fromValue(String value) {
    return AlertType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => AlertType.other,
    );
  }

  String get displayName {
    switch (this) {
      case AlertType.stuck:
        return 'Stuck';
      case AlertType.noSignal:
        return 'No Signal';
      case AlertType.mockLocation:
        return 'Mock Location';
      case AlertType.clockDrift:
        return 'Clock Drift';
      case AlertType.forceStop:
        return 'Force Stopped';
      case AlertType.lowBattery:
        return 'Low Battery';
      case AlertType.other:
        return 'Other';
    }
  }
}

enum AlertSeverity {
  info('info'),
  warn('warn'),
  critical('critical');

  final String value;
  const AlertSeverity(this.value);

  static AlertSeverity fromValue(String value) {
    return AlertSeverity.values.firstWhere(
      (e) => e.value == value,
      orElse: () => AlertSeverity.info,
    );
  }
}
