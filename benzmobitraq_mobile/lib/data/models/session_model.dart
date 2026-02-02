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
  final SessionStatus status;
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
    this.status = SessionStatus.active,
    required this.createdAt,
    required this.updatedAt,
  });

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
      status: SessionStatus.fromString(json['status'] as String? ?? 'active'),
      createdAt: createdAtUtc.toLocal(),
      updatedAt: updatedAtUtc.toLocal(),
    );
  }

  /// Convert to JSON map for Supabase
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employee_id': employeeId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'start_latitude': startLatitude,
      'start_longitude': startLongitude,
      'start_address': startAddress,
      'end_latitude': endLatitude,
      'end_longitude': endLongitude,
      'end_address': endAddress,
      'total_km': totalKm,
      'status': status.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a new session for starting work
  factory SessionModel.start({
    required String id,
    required String employeeId,
    double? latitude,
    double? longitude,
    String? address,
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
    SessionStatus? status,
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
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Check if session is currently active
  bool get isActive => status == SessionStatus.active;

  /// Get session duration
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
        status,
        createdAt,
        updatedAt,
      ];
}

/// Session status enum
enum SessionStatus {
  active('active'),
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
