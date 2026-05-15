import 'package:equatable/equatable.dart';

/// Work session model representing a Present → Work Done cycle
class SessionModel extends Equatable {
  final String id;
  final String employeeId;
  final DateTime startTime;
  final DateTime? endTime;
  final double? startLatitude;
  final double? startLongitude;
  final String? startAddress;
  final double? endLatitude;
  final double? endLongitude;
  final String? endAddress;
  final double totalKm;
  /// Locked billing distance set at session end (Stage 1 of distance
  /// rewrite). Nullable for legacy / active sessions; use `billedKm`
  /// when displaying.
  final double? finalKm;
  final SessionStatus status;
  final DateTime? pausedAt;
  final DateTime? resumedAt;
  final int totalPausedSeconds;
  /// Free-form text the user enters at session start describing why
  /// they are going out — e.g. "Visit XYZ Pvt Ltd", "Delivery run to
  /// Sector 4". Shown on the session card, in expense detail, and to
  /// admins on the timeline panel. Optional but encouraged.
  final String? purpose;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SessionModel({
    required this.id,
    required this.employeeId,
    required this.startTime,
    this.endTime,
    this.startLatitude,
    this.startLongitude,
    this.startAddress,
    this.endLatitude,
    this.endLongitude,
    this.endAddress,
    this.totalKm = 0.0,
    this.finalKm,
    this.status = SessionStatus.active,
    this.pausedAt,
    this.resumedAt,
    this.totalPausedSeconds = 0,
    this.purpose,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Billing-truthful distance. Prefer the locked `finalKm`; fall back
  /// to `totalKm` for legacy / active sessions where `finalKm` is null
  /// or zero. ALL distance displays should use this getter, not
  /// `totalKm` directly.
  double get billedKm {
    final fk = finalKm;
    if (fk != null && fk > 0) return fk;
    return totalKm;
  }

  /// Create from JSON map (Supabase response)
  factory SessionModel.fromJson(Map<String, dynamic> json) {
    // Parse times and convert to local timezone for proper duration calculation
    final startTimeUtc = DateTime.parse(json['start_time'] as String);
    final endTimeUtc = json['end_time'] != null
        ? DateTime.parse(json['end_time'] as String)
        : null;
    final createdAtUtc = DateTime.parse(json['created_at'] as String);
    final updatedAtUtc = DateTime.parse(json['updated_at'] as String);
    
    return SessionModel(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      startTime: startTimeUtc.toLocal(),
      endTime: endTimeUtc?.toLocal(),
      startLatitude: (json['start_latitude'] as num?)?.toDouble(),
      startLongitude: (json['start_longitude'] as num?)?.toDouble(),
      startAddress: json['start_address'] as String?,
      endLatitude: (json['end_latitude'] as num?)?.toDouble(),
      endLongitude: (json['end_longitude'] as num?)?.toDouble(),
      endAddress: json['end_address'] as String?,
      totalKm: (json['total_km'] as num?)?.toDouble() ?? 0.0,
      finalKm: (json['final_km'] as num?)?.toDouble(),
      status: SessionStatus.fromString(json['status'] as String? ?? 'active'),
      pausedAt: json['paused_at'] != null ? DateTime.parse(json['paused_at'] as String).toLocal() : null,
      resumedAt: json['resumed_at'] != null ? DateTime.parse(json['resumed_at'] as String).toLocal() : null,
      totalPausedSeconds: (json['total_paused_seconds'] as int?) ?? 0,
      purpose: json['purpose'] as String?,
      createdAt: createdAtUtc.toLocal(),
      updatedAt: updatedAtUtc.toLocal(),
    );
  }

  /// Convert to JSON map for Supabase INSERT.
  /// IMPORTANT: Always convert to UTC to avoid timezone interpretation issues.
  /// NOTE: paused_at / resumed_at / total_paused_seconds are intentionally
  /// omitted here — those columns require a DB migration that hasn't shipped
  /// yet.  Sending non-existent columns causes Postgres to reject the INSERT
  /// silently, which is exactly why new sessions were never appearing.
  /// Once the migration is applied (see infra/supabase/migrations/), restore
  /// those three fields and update updateSessionStatus() accordingly.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employee_id': employeeId,
      'start_time': startTime.toUtc().toIso8601String(),
      'end_time': endTime?.toUtc().toIso8601String(),
      'start_latitude': startLatitude,
      'start_longitude': startLongitude,
      'start_address': startAddress,
      'end_latitude': endLatitude,
      'end_longitude': endLongitude,
      'end_address': endAddress,
      'total_km': totalKm,
      'status': status.value,
      'purpose': purpose,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  /// Create a new session for starting work
  factory SessionModel.start({
    required String id,
    required String employeeId,
    double? latitude,
    double? longitude,
    String? address,
    String? purpose,
  }) {
    final now = DateTime.now();
    return SessionModel(
      id: id,
      employeeId: employeeId,
      startTime: now,
      startLatitude: latitude,
      startLongitude: longitude,
      startAddress: address,
      status: SessionStatus.active,
      purpose: purpose,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Create a copy with modified fields
  SessionModel copyWith({
    String? id,
    String? employeeId,
    DateTime? startTime,
    DateTime? endTime,
    double? startLatitude,
    double? startLongitude,
    String? startAddress,
    double? endLatitude,
    double? endLongitude,
    String? endAddress,
    double? totalKm,
    double? finalKm,
    SessionStatus? status,
    DateTime? pausedAt,
    DateTime? resumedAt,
    int? totalPausedSeconds,
    String? purpose,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SessionModel(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      startLatitude: startLatitude ?? this.startLatitude,
      startLongitude: startLongitude ?? this.startLongitude,
      startAddress: startAddress ?? this.startAddress,
      endLatitude: endLatitude ?? this.endLatitude,
      endLongitude: endLongitude ?? this.endLongitude,
      endAddress: endAddress ?? this.endAddress,
      totalKm: totalKm ?? this.totalKm,
      finalKm: finalKm ?? this.finalKm,
      status: status ?? this.status,
      pausedAt: pausedAt ?? this.pausedAt,
      resumedAt: resumedAt ?? this.resumedAt,
      totalPausedSeconds: totalPausedSeconds ?? this.totalPausedSeconds,
      purpose: purpose ?? this.purpose,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Check if session is currently active (includes paused)
  bool get isActive => status == SessionStatus.active || status == SessionStatus.paused;

  /// Check if session is currently paused
  bool get isPaused => status == SessionStatus.paused;

  /// Get session duration excluding pause time
  Duration get activeDuration {
    final end = endTime ?? DateTime.now();
    var rawDuration = end.difference(startTime);
    final paused = Duration(seconds: totalPausedSeconds);
    if (paused > rawDuration) return Duration.zero;
    return rawDuration - paused;
  }

  /// Get raw session duration (including pauses)
  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  @override
  List<Object?> get props => [
        id,
        employeeId,
        startTime,
        endTime,
        startLatitude,
        startLongitude,
        startAddress,
        endLatitude,
        endLongitude,
        endAddress,
        totalKm,
        finalKm,
        status,
        pausedAt,
        resumedAt,
        totalPausedSeconds,
        purpose,
        createdAt,
        updatedAt,
      ];
}

/// Session status enum
enum SessionStatus {
  active('active'),
  paused('paused'),
  completed('completed'),
  cancelled('cancelled');

  final String value;

  const SessionStatus(this.value);

  static SessionStatus fromString(String value) {
    return SessionStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SessionStatus.active,
    );
  }
}
