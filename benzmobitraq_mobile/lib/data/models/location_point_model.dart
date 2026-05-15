import 'package:equatable/equatable.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Location point model representing a single GPS reading.
///
/// Stage 2 (migration 073) added per-point quality fields:
///   - elapsedRealtimeNanos: monotonic Android timestamp, clock-jump safe
///   - isMock: mock-location detection
///   - speedAccuracyMps / bearingAccuracyDeg: reliability of speed/bearing
///   - activityType / activityConfidence: ActivityRecognition labels
///
/// These are used at session end by ConfidenceScorer and server-side by the
/// finalization Edge Function (Roads API) to decide trust + filter noise.
class LocationPointModel extends Equatable {
  final String id;
  final String sessionId;
  final String employeeId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? speed;
  final double? altitude;
  final double? heading;
  final bool isMoving;
  final String? address;
  final String? provider; // gps/network/fused
  final String? hash; // For idempotency
  final bool countsForDistance;
  final double? distanceDeltaM;
  final DateTime recordedAt;
  final DateTime createdAt;
  final DateTime? serverReceivedAt;

  // Stage 2 quality fields (all nullable for backwards compatibility)
  final int? elapsedRealtimeNanos;
  final bool isMock;
  final double? speedAccuracyMps;
  final double? bearingAccuracyDeg;
  final String? activityType; // 'in_vehicle' | 'still' | 'walking' | ...
  final int? activityConfidence; // 0..100

  const LocationPointModel({
    required this.id,
    required this.sessionId,
    required this.employeeId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.speed,
    this.altitude,
    this.heading,
    this.isMoving = true,
    this.address,
    this.provider,
    this.hash,
    this.countsForDistance = false,
    this.distanceDeltaM,
    required this.recordedAt,
    required this.createdAt,
    this.serverReceivedAt,
    this.elapsedRealtimeNanos,
    this.isMock = false,
    this.speedAccuracyMps,
    this.bearingAccuracyDeg,
    this.activityType,
    this.activityConfidence,
  });

  /// Compute hash for idempotency.
  /// hash = sha256(employeeId + sessionId + recordedAtSeconds + latRounded5 + lngRounded5)
  static String computeHash({
    required String employeeId,
    required String sessionId,
    required DateTime recordedAt,
    required double latitude,
    required double longitude,
  }) {
    final recordedAtSeconds = recordedAt.millisecondsSinceEpoch ~/ 1000;
    final latRounded = latitude.toStringAsFixed(5);
    final lngRounded = longitude.toStringAsFixed(5);

    final raw = '$employeeId$sessionId$recordedAtSeconds$latRounded$lngRounded';
    final bytes = utf8.encode(raw);
    final digest = sha256.convert(bytes);

    return digest.toString();
  }

  /// Create from JSON map (Supabase response)
  factory LocationPointModel.fromJson(Map<String, dynamic> json) {
    return LocationPointModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      employeeId: json['employee_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      isMoving: json['is_moving'] as bool? ?? true,
      address: json['address'] as String?,
      provider: json['provider'] as String?,
      hash: json['hash'] as String?,
      countsForDistance: json['counts_for_distance'] as bool? ?? false,
      distanceDeltaM: (json['distance_delta_m'] as num?)?.toDouble(),
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      serverReceivedAt: json['server_received_at'] != null
          ? DateTime.parse(json['server_received_at'] as String)
          : null,
      elapsedRealtimeNanos: (json['elapsed_realtime_nanos'] as num?)?.toInt(),
      isMock: json['is_mock'] as bool? ?? false,
      speedAccuracyMps: (json['speed_accuracy_mps'] as num?)?.toDouble(),
      bearingAccuracyDeg: (json['bearing_accuracy_deg'] as num?)?.toDouble(),
      activityType: json['activity_type'] as String?,
      activityConfidence: (json['activity_confidence'] as num?)?.toInt(),
    );
  }

  /// Convert to JSON map for Supabase
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'employee_id': employeeId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'speed': speed,
      'altitude': altitude,
      'heading': heading,
      'is_moving': isMoving,
      'address': address,
      'provider': provider,
      'counts_for_distance': countsForDistance,
      'distance_delta_m': distanceDeltaM,
      'hash': hash ??
          computeHash(
            employeeId: employeeId,
            sessionId: sessionId,
            recordedAt: recordedAt,
            latitude: latitude,
            longitude: longitude,
          ),
      'recorded_at': recordedAt.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      // Stage 2 fields (only sent if non-null/non-default — Supabase ignores
      // unknown columns gracefully but sending null keeps the schema honest).
      'elapsed_realtime_nanos': elapsedRealtimeNanos,
      'is_mock': isMock,
      'speed_accuracy_mps': speedAccuracyMps,
      'bearing_accuracy_deg': bearingAccuracyDeg,
      'activity_type': activityType,
      'activity_confidence': activityConfidence,
    };
  }

  /// Convert to JSON for local SQLite storage (offline queue).
  Map<String, dynamic> toLocalJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'employee_id': employeeId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'speed': speed,
      'altitude': altitude,
      'heading': heading,
      'is_moving': isMoving ? 1 : 0,
      'address': address,
      'provider': provider,
      'counts_for_distance': countsForDistance ? 1 : 0,
      'distance_delta_m': distanceDeltaM,
      'hash': hash ??
          computeHash(
            employeeId: employeeId,
            sessionId: sessionId,
            recordedAt: recordedAt,
            latitude: latitude,
            longitude: longitude,
          ),
      'recorded_at': recordedAt.millisecondsSinceEpoch,
      'created_at': createdAt.millisecondsSinceEpoch,
      'uploaded': 0,
      // Stage 2 fields (SQLite v7 columns; see LocationQueueLocal._onUpgrade)
      'elapsed_realtime_nanos': elapsedRealtimeNanos,
      'is_mock': isMock ? 1 : 0,
      'speed_accuracy_mps': speedAccuracyMps,
      'bearing_accuracy_deg': bearingAccuracyDeg,
      'activity_type': activityType,
      'activity_confidence': activityConfidence,
    };
  }

  /// Create from local SQLite storage
  factory LocationPointModel.fromLocalJson(Map<String, dynamic> json) {
    final rawCountsForDistance = json['counts_for_distance'];
    final rawIsMock = json['is_mock'];
    return LocationPointModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      employeeId: json['employee_id'] as String,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      accuracy: json['accuracy'] as double?,
      speed: json['speed'] as double?,
      altitude: json['altitude'] as double?,
      heading: json['heading'] as double?,
      isMoving: (json['is_moving'] as int) == 1,
      address: json['address'] as String?,
      provider: json['provider'] as String?,
      hash: json['hash'] as String?,
      countsForDistance:
          rawCountsForDistance == true || rawCountsForDistance == 1,
      distanceDeltaM: (json['distance_delta_m'] as num?)?.toDouble(),
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
          json['recorded_at'] as int,
          isUtc: true),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int,
          isUtc: true),
      elapsedRealtimeNanos: (json['elapsed_realtime_nanos'] as num?)?.toInt(),
      isMock: rawIsMock == true || rawIsMock == 1,
      speedAccuracyMps: (json['speed_accuracy_mps'] as num?)?.toDouble(),
      bearingAccuracyDeg: (json['bearing_accuracy_deg'] as num?)?.toDouble(),
      activityType: json['activity_type'] as String?,
      activityConfidence: (json['activity_confidence'] as num?)?.toInt(),
    );
  }

  /// Create a new location point with auto-computed hash
  factory LocationPointModel.create({
    required String id,
    required String sessionId,
    required String employeeId,
    required double latitude,
    required double longitude,
    double? accuracy,
    double? speed,
    double? altitude,
    double? heading,
    bool isMoving = true,
    String? address,
    String? provider,
    bool countsForDistance = false,
    double? distanceDeltaM,
    DateTime? recordedAt,
    int? elapsedRealtimeNanos,
    bool isMock = false,
    double? speedAccuracyMps,
    double? bearingAccuracyDeg,
    String? activityType,
    int? activityConfidence,
  }) {
    final now = (recordedAt ?? DateTime.now()).toUtc();
    final pointHash = computeHash(
      employeeId: employeeId,
      sessionId: sessionId,
      recordedAt: now,
      latitude: latitude,
      longitude: longitude,
    );

    return LocationPointModel(
      id: id,
      sessionId: sessionId,
      employeeId: employeeId,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      speed: speed,
      altitude: altitude,
      heading: heading,
      isMoving: isMoving,
      address: address,
      provider: provider,
      hash: pointHash,
      countsForDistance: countsForDistance,
      distanceDeltaM: distanceDeltaM,
      recordedAt: now,
      createdAt: now,
      elapsedRealtimeNanos: elapsedRealtimeNanos,
      isMock: isMock,
      speedAccuracyMps: speedAccuracyMps,
      bearingAccuracyDeg: bearingAccuracyDeg,
      activityType: activityType,
      activityConfidence: activityConfidence,
    );
  }

  /// Create a copy with modified fields
  LocationPointModel copyWith({
    String? id,
    String? sessionId,
    String? employeeId,
    double? latitude,
    double? longitude,
    double? accuracy,
    double? speed,
    double? altitude,
    double? heading,
    bool? isMoving,
    String? address,
    String? provider,
    String? hash,
    bool? countsForDistance,
    double? distanceDeltaM,
    DateTime? recordedAt,
    DateTime? createdAt,
    DateTime? serverReceivedAt,
    int? elapsedRealtimeNanos,
    bool? isMock,
    double? speedAccuracyMps,
    double? bearingAccuracyDeg,
    String? activityType,
    int? activityConfidence,
  }) {
    return LocationPointModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      employeeId: employeeId ?? this.employeeId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      speed: speed ?? this.speed,
      altitude: altitude ?? this.altitude,
      heading: heading ?? this.heading,
      isMoving: isMoving ?? this.isMoving,
      address: address ?? this.address,
      provider: provider ?? this.provider,
      hash: hash ?? this.hash,
      countsForDistance: countsForDistance ?? this.countsForDistance,
      distanceDeltaM: distanceDeltaM ?? this.distanceDeltaM,
      recordedAt: recordedAt ?? this.recordedAt,
      createdAt: createdAt ?? this.createdAt,
      serverReceivedAt: serverReceivedAt ?? this.serverReceivedAt,
      elapsedRealtimeNanos: elapsedRealtimeNanos ?? this.elapsedRealtimeNanos,
      isMock: isMock ?? this.isMock,
      speedAccuracyMps: speedAccuracyMps ?? this.speedAccuracyMps,
      bearingAccuracyDeg: bearingAccuracyDeg ?? this.bearingAccuracyDeg,
      activityType: activityType ?? this.activityType,
      activityConfidence: activityConfidence ?? this.activityConfidence,
    );
  }

  /// Get speed in km/h (if speed is available in m/s)
  double? get speedKmh => speed != null ? speed! * 3.6 : null;

  /// Get speed in m/s
  double? get speedMps => speed;

  @override
  List<Object?> get props => [
        id,
        sessionId,
        employeeId,
        latitude,
        longitude,
        accuracy,
        speed,
        altitude,
        heading,
        isMoving,
        address,
        provider,
        hash,
        countsForDistance,
        distanceDeltaM,
        recordedAt,
        createdAt,
        serverReceivedAt,
        elapsedRealtimeNanos,
        isMock,
        speedAccuracyMps,
        bearingAccuracyDeg,
        activityType,
        activityConfidence,
      ];
}
