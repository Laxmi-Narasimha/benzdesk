part of 'session_bloc.dart';

/// Session bloc status
enum SessionBlocStatus {
  initial,
  loading,
  idle,              // No active session
  starting,          // Starting session
  active,            // Session running
  stopping,          // Stopping session
  permissionRequired, // Need permissions
  error,
}

/// Session state for the UI
class SessionState extends Equatable {
  final SessionBlocStatus status;
  final SessionModel? currentSession;
  final double currentDistanceKm;
  final Duration duration;
  final double? lastLatitude;
  final double? lastLongitude;
  final SessionModel? lastCompletedSession;
  final List<SessionModel> sessionHistory;
  final List<String> warnings;
  final List<PermissionIssue> permissionIssues;
  final String? errorMessage;
  final Map<String, dynamic> monthlyStats;

  const SessionState({
    this.status = SessionBlocStatus.initial,
    this.currentSession,
    this.currentDistanceKm = 0,
    this.duration = Duration.zero,
    this.lastLatitude,
    this.lastLongitude,
    this.lastCompletedSession,
    this.sessionHistory = const [],
    this.warnings = const [],
    this.permissionIssues = const [],
    this.errorMessage,
    this.monthlyStats = const {'distance': 0.0, 'duration': Duration.zero, 'count': 0},
  });

  /// Whether a session is currently active
  bool get isActive => status == SessionBlocStatus.active;

  /// Whether the bloc is in a loading state
  bool get isLoading => 
      status == SessionBlocStatus.loading ||
      status == SessionBlocStatus.starting ||
      status == SessionBlocStatus.stopping;

  /// Get formatted distance string
  String get distanceFormatted => currentDistanceKm.toStringAsFixed(2);

  /// Get formatted duration string
  String get durationFormatted {
    // Use absolute value to prevent negative display
    final absDuration = duration.isNegative ? Duration.zero : duration;
    final hours = absDuration.inHours;
    final minutes = absDuration.inMinutes.remainder(60);
    final seconds = absDuration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  SessionState copyWith({
    SessionBlocStatus? status,
    SessionModel? currentSession,
    double? currentDistanceKm,
    Duration? duration,
    double? lastLatitude,
    double? lastLongitude,
    SessionModel? lastCompletedSession,
    List<SessionModel>? sessionHistory,
    List<String>? warnings,
    List<PermissionIssue>? permissionIssues,
    String? errorMessage,
    Map<String, dynamic>? monthlyStats,
  }) {
    return SessionState(
      status: status ?? this.status,
      currentSession: currentSession ?? this.currentSession,
      currentDistanceKm: currentDistanceKm ?? this.currentDistanceKm,
      duration: duration ?? this.duration,
      lastLatitude: lastLatitude ?? this.lastLatitude,
      lastLongitude: lastLongitude ?? this.lastLongitude,
      lastCompletedSession: lastCompletedSession ?? this.lastCompletedSession,
      sessionHistory: sessionHistory ?? this.sessionHistory,
      warnings: warnings ?? this.warnings,
      permissionIssues: permissionIssues ?? this.permissionIssues,
      errorMessage: errorMessage,
      monthlyStats: monthlyStats ?? this.monthlyStats,
    );
  }

  @override
  List<Object?> get props => [
        status,
        currentSession,
        currentDistanceKm,
        duration,
        lastLatitude,
        lastLongitude,
        lastCompletedSession,
        sessionHistory,
        warnings,
        permissionIssues,
        errorMessage,
        monthlyStats,
      ];
}
