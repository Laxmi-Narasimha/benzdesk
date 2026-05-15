part of 'session_bloc.dart';

/// Session events
abstract class SessionEvent extends Equatable {
  const SessionEvent();

  @override
  List<Object?> get props => [];
}

/// Initialize the session bloc and manager
class SessionInitialize extends SessionEvent {
  const SessionInitialize();
}

/// Request to start a new session (Present).
///
/// [purpose] is the free-form text the rep entered describing the
/// session — e.g. "Visit XYZ Pvt Ltd". Optional; null/empty is fine.
///
/// When the rep picked a Places Autocomplete suggestion, [startPlaceId]
/// and friends carry the Google Place metadata so the server-side
/// enrichment can bind the session to a customer record.
class SessionStartRequested extends SessionEvent {
  final String? purpose;
  final String? startPlaceId;
  final String? startPlaceName;
  final double? startPlaceLatitude;
  final double? startPlaceLongitude;

  const SessionStartRequested({
    this.purpose,
    this.startPlaceId,
    this.startPlaceName,
    this.startPlaceLatitude,
    this.startPlaceLongitude,
  });

  @override
  List<Object?> get props => [
        purpose,
        startPlaceId,
        startPlaceName,
        startPlaceLatitude,
        startPlaceLongitude,
      ];
}

/// Request to stop the current session (Work Done)
class SessionStopRequested extends SessionEvent {
  const SessionStopRequested();
}

/// Request to pause the current session.
///
/// [expectedPauseMinutes] is what the user entered in the alarm dialog
/// when asked "how long do you expect to be paused?". The session
/// manager schedules a pause-expired alarm to ring at that wall-clock
/// time so the user is reminded if they forget to resume. Null means
/// no expectation was captured (regular manual pause).
class SessionPauseRequested extends SessionEvent {
  final int? expectedPauseMinutes;
  const SessionPauseRequested({this.expectedPauseMinutes});

  @override
  List<Object?> get props => [expectedPauseMinutes];
}

/// Request to resume the paused session
class SessionResumeRequested extends SessionEvent {
  const SessionResumeRequested();
}

/// Load session history
class SessionLoadHistory extends SessionEvent {
  final int limit;

  const SessionLoadHistory({this.limit = 200});

  @override
  List<Object?> get props => [limit];
}

/// Load monthly stats
class SessionLoadStats extends SessionEvent {
  const SessionLoadStats();
}

/// Internal event for session manager updates
class _SessionManagerUpdate extends SessionEvent {
  final ManagerSessionState managerState;

  const _SessionManagerUpdate(this.managerState);

  @override
  List<Object?> get props => [managerState];
}

/// Stationary spot detected by background service
class SessionStationarySpotDetected extends SessionEvent {
  final Map<String, dynamic> data;

  const SessionStationarySpotDetected(this.data);

  @override
  List<Object?> get props => [data];
}

/// Dismiss/clear the stationary spot notification
class SessionStationarySpotDismissed extends SessionEvent {
  const SessionStationarySpotDismissed();
}

/// Lightweight state refresh — re-reads current SessionManager state
/// without re-initializing. Used by the UI refresh timer every 3 seconds
/// to sync distance/duration without triggering duplicate subscriptions
/// or re-running server checks.
class SessionRefreshState extends SessionEvent {
  const SessionRefreshState();
}
