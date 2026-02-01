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

/// Request to start a new session (Present)
class SessionStartRequested extends SessionEvent {
  const SessionStartRequested();
}

/// Request to stop the current session (Work Done)
class SessionStopRequested extends SessionEvent {
  const SessionStopRequested();
}

/// Load session history
class SessionLoadHistory extends SessionEvent {
  final int limit;

  const SessionLoadHistory({this.limit = 30});

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
