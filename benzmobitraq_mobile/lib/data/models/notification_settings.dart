import 'package:equatable/equatable.dart';

/// User notification settings for tracking alerts
class NotificationSettings extends Equatable {
  /// Distance threshold in kilometers (1-10 km)
  final double distanceKm;
  
  /// Time threshold in minutes (10-60 min)
  final int timeMinutes;
  
  /// Whether distance-based notifications are enabled
  final bool distanceEnabled;
  
  /// Whether time-based notifications are enabled
  final bool timeEnabled;

  const NotificationSettings({
    this.distanceKm = 1.0,
    this.timeMinutes = 30,
    this.distanceEnabled = true,
    this.timeEnabled = true,
  });

  // Validation constants
  static const double minDistanceKm = 1.0;
  static const double maxDistanceKm = 10.0;
  static const int minTimeMinutes = 10;
  static const int maxTimeMinutes = 60;

  /// Create default settings
  factory NotificationSettings.defaults() {
    return const NotificationSettings(
      distanceKm: 1.0,
      timeMinutes: 30,
      distanceEnabled: true,
      timeEnabled: true,
    );
  }

  /// Validate and clamp values to allowed ranges
  NotificationSettings validate() {
    return NotificationSettings(
      distanceKm: distanceKm.clamp(minDistanceKm, maxDistanceKm),
      timeMinutes: timeMinutes.clamp(minTimeMinutes, maxTimeMinutes),
      distanceEnabled: distanceEnabled,
      timeEnabled: timeEnabled,
    );
  }

  /// Create from JSON
  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 1.0,
      timeMinutes: (json['time_minutes'] as int?) ?? 30,
      distanceEnabled: json['distance_enabled'] as bool? ?? true,
      timeEnabled: json['time_enabled'] as bool? ?? true,
    ).validate();
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'distance_km': distanceKm,
      'time_minutes': timeMinutes,
      'distance_enabled': distanceEnabled,
      'time_enabled': timeEnabled,
    };
  }

  /// Copy with modified fields
  NotificationSettings copyWith({
    double? distanceKm,
    int? timeMinutes,
    bool? distanceEnabled,
    bool? timeEnabled,
  }) {
    return NotificationSettings(
      distanceKm: distanceKm ?? this.distanceKm,
      timeMinutes: timeMinutes ?? this.timeMinutes,
      distanceEnabled: distanceEnabled ?? this.distanceEnabled,
      timeEnabled: timeEnabled ?? this.timeEnabled,
    ).validate();
  }

  /// Get distance in meters for calculations
  double get distanceMeters => distanceKm * 1000;

  /// Get time as Duration
  Duration get timeDuration => Duration(minutes: timeMinutes);

  @override
  List<Object?> get props => [distanceKm, timeMinutes, distanceEnabled, timeEnabled];
}
