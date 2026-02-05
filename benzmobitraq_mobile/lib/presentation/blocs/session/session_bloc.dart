import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../data/models/session_model.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../services/session_manager.dart';
import '../../../services/permission_service.dart';

part 'session_event.dart';
part 'session_state.dart';

/// BLoC for managing work session state
/// 
/// This BLoC coordinates with the SessionManager to handle:
/// - Starting/stopping sessions via Present/Work Done workflow
/// - Real-time distance and duration updates
/// - Session history
class SessionBloc extends Bloc<SessionEvent, SessionState> {
  final SessionManager _sessionManager;
  final SessionRepository _sessionRepository;
  
  StreamSubscription<ManagerSessionState>? _managerSubscription;

  SessionBloc({
    required SessionManager sessionManager,
    required SessionRepository sessionRepository,
  })  : _sessionManager = sessionManager,
        _sessionRepository = sessionRepository,
        super(const SessionState()) {
    
    on<SessionInitialize>(_onInitialize);
    on<SessionStartRequested>(_onStartRequested);
    on<SessionStopRequested>(_onStopRequested);
    on<SessionLoadHistory>(_onLoadHistory);
    on<SessionLoadStats>(_onLoadStats);
    on<_SessionManagerUpdate>(_onManagerUpdate);
  }

  /// Initialize and listen to session manager updates
  Future<void> _onInitialize(
    SessionInitialize event,
    Emitter<SessionState> emit,
  ) async {
    emit(state.copyWith(status: SessionBlocStatus.loading));

    try {
      // Initialize session manager
      await _sessionManager.initialize();

      // Listen to session manager state changes
      _managerSubscription = _sessionManager.stateStream.listen((managerState) {
        add(_SessionManagerUpdate(managerState));
      });

      // Get current state
      final managerState = _sessionManager.currentState;
      emit(_mapManagerStateToBloc(managerState));
      
      // Load stats
      add(const SessionLoadStats());
    } catch (e) {
      emit(state.copyWith(
        status: SessionBlocStatus.error,
        errorMessage: 'Failed to initialize: $e',
      ));
    }
  }

  /// Handle start session request
  Future<void> _onStartRequested(
    SessionStartRequested event,
    Emitter<SessionState> emit,
  ) async {
    emit(state.copyWith(status: SessionBlocStatus.starting));

    try {
      // Check permissions and readiness first
      final readiness = await _sessionManager.checkReadiness();
      
      if (!readiness.canTrack) {
        emit(state.copyWith(
          status: SessionBlocStatus.permissionRequired,
          errorMessage: readiness.message,
          permissionIssues: readiness.issues,
        ));
        return;
      }

      // Start the session
      final success = await _sessionManager.startSession();

      if (!success) {
        emit(state.copyWith(
          status: SessionBlocStatus.error,
          errorMessage: _sessionManager.currentState.errorMessage ?? 'Failed to start session',
        ));
      }
      // State will be updated via _SessionManagerUpdate
    } catch (e) {
      emit(state.copyWith(
        status: SessionBlocStatus.error,
        errorMessage: 'Error starting session: $e',
      ));
    }
  }

  /// Handle stop session request
  Future<void> _onStopRequested(
    SessionStopRequested event,
    Emitter<SessionState> emit,
  ) async {
    // Prevent double-submission
    if (state.status == SessionBlocStatus.stopping) {
      return;
    }

    emit(state.copyWith(status: SessionBlocStatus.stopping));

    try {
      final completedSession = await _sessionManager.stopSession();

      if (completedSession != null) {
        emit(state.copyWith(
          status: SessionBlocStatus.idle,
          lastCompletedSession: completedSession,
          currentSession: null,
          currentDistanceKm: 0,
          duration: Duration.zero,
        ));
        
        // Refresh history to update the list locally
        add(const SessionLoadHistory());
        add(const SessionLoadStats());
      } else {
        emit(state.copyWith(
          status: SessionBlocStatus.error,
          errorMessage: 'Failed to stop session',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        status: SessionBlocStatus.error,
        errorMessage: 'Error stopping session: $e',
      ));
    }
  }

  /// Load session history
  Future<void> _onLoadHistory(
    SessionLoadHistory event,
    Emitter<SessionState> emit,
  ) async {
    try {
      final history = await _sessionRepository.getSessionHistory(
        limit: event.limit,
      );
      emit(state.copyWith(sessionHistory: history));
    } catch (e) {
      // Don't emit error state for history load failure
    }
  }

  /// Load monthly stats
  Future<void> _onLoadStats(
    SessionLoadStats event,
    Emitter<SessionState> emit,
  ) async {
    try {
      final stats = await _sessionRepository.getMonthlyStats();
      emit(state.copyWith(monthlyStats: stats));
    } catch (e) {
      // Ignore stats error
    }
  }

  /// Handle updates from SessionManager
  void _onManagerUpdate(
    _SessionManagerUpdate event,
    Emitter<SessionState> emit,
  ) {
    emit(_mapManagerStateToBloc(event.managerState));
  }

  /// Map SessionManager state to BLoC state
  SessionState _mapManagerStateToBloc(ManagerSessionState managerState) {
    SessionBlocStatus status;
    
    switch (managerState.status) {
      case ManagerSessionStatus.idle:
        status = SessionBlocStatus.idle;
        break;
      case ManagerSessionStatus.starting:
        status = SessionBlocStatus.starting;
        break;
      case ManagerSessionStatus.active:
        status = SessionBlocStatus.active;
        break;
      case ManagerSessionStatus.stopping:
        status = SessionBlocStatus.stopping;
        break;
      case ManagerSessionStatus.error:
        status = SessionBlocStatus.error;
        break;
      default:
        status = SessionBlocStatus.idle;
        break;
    }

    return state.copyWith(
      status: status,
      currentSession: managerState.session,
      currentDistanceKm: managerState.currentDistanceKm,
      duration: managerState.duration,
      lastLatitude: managerState.lastLocation?.latitude,
      lastLongitude: managerState.lastLocation?.longitude,
      warnings: managerState.warnings,
      errorMessage: managerState.errorMessage,
    );
  }

  @override
  Future<void> close() {
    _managerSubscription?.cancel();
    return super.close();
  }
}
