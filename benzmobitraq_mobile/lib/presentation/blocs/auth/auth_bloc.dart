import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/employee_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../services/notification_service.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// BLoC for handling authentication state
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  final NotificationService _notificationService;

  AuthBloc({
    required AuthRepository authRepository,
    required NotificationService notificationService,
  })  : _authRepository = authRepository,
        _notificationService = notificationService,
        super(AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthSignInRequested>(_onSignInRequested);
    on<AuthSignUpRequested>(_onSignUpRequested);
    on<AuthSignOutRequested>(_onSignOutRequested);
    on<AuthProfileUpdateRequested>(_onProfileUpdateRequested);
    on<AuthMagicLinkRequested>(_onMagicLinkRequested);
    on<AuthStateChanged>(_onAuthStateChanged);

    // Listen to repo updates
    _authRepository.authStateChanges.listen((data) async {
       final event = data.event;
       if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.tokenRefreshed) {
         // Use checkAuthStatus to properly save user ID to preferences
         final employee = await _authRepository.checkAuthStatus();
         add(AuthStateChanged(employee));
       } else if (event == AuthChangeEvent.signedOut) {
         // Only emit if we're not already unauthenticated (prevents duplicate events)
         if (state is! AuthUnauthenticated) {
           add(const AuthStateChanged(null));
         }
       }
    });
  }

  Future<void> _onAuthStateChanged(
    AuthStateChanged event,
    Emitter<AuthState> emit,
  ) async {
    if (event.employee != null) {
      await _registerForPushNotifications();
      emit(AuthAuthenticated(event.employee!));
    } else {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    try {
      final employee = await _authRepository.checkAuthStatus();

      if (employee != null) {
        // Register for push notifications
        await _registerForPushNotifications();
        
        emit(AuthAuthenticated(employee));
      } else {
        emit(AuthUnauthenticated());
      }
    } catch (e) {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onSignInRequested(
    AuthSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await _authRepository.signIn(
      email: event.email,
      password: event.password,
    );

    if (result.success && result.employee != null) {
      // Register for push notifications
      await _registerForPushNotifications();
      
      emit(AuthAuthenticated(result.employee!));
    } else {
      emit(AuthError(result.error ?? 'Sign in failed'));
    }
  }

  Future<void> _onSignUpRequested(
    AuthSignUpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await _authRepository.signUp(
      email: event.email,
      password: event.password,
      name: event.name,
      phone: event.phone,
    );

    if (result.success && result.employee != null) {
      // Register for push notifications
      await _registerForPushNotifications();
      
      emit(AuthAuthenticated(result.employee!));
    } else {
      emit(AuthError(result.error ?? 'Sign up failed'));
    }
  }

  Future<void> _onSignOutRequested(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    // Guard: Don't sign out if already unauthenticated or already loading sign out
    if (state is AuthUnauthenticated) return;
    if (state is AuthLoading) return;

    emit(AuthLoading());

    await _authRepository.signOut();
    // Don't emit here - let the authStateChanges listener handle it
    // This prevents duplicate AuthUnauthenticated emissions
    emit(AuthUnauthenticated());
  }

  Future<void> _onProfileUpdateRequested(
    AuthProfileUpdateRequested event,
    Emitter<AuthState> emit,
  ) async {
    final currentState = state;
    if (currentState is! AuthAuthenticated) return;

    emit(AuthLoading());

    final updatedEmployee = await _authRepository.updateProfile(
      name: event.name,
      phone: event.phone,
    );

    if (updatedEmployee != null) {
      emit(AuthAuthenticated(updatedEmployee));
    } else {
      emit(AuthError('Failed to update profile'));
      // Revert to previous state
      emit(currentState);
    }
  }

  Future<void> _onMagicLinkRequested(
    AuthMagicLinkRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await _authRepository.signInWithMagicLink(
      email: event.email,
    );

    if (result.success) {
      emit(AuthMagicLinkSent(event.email));
    } else {
      emit(AuthError(result.error ?? 'Failed to send login link'));
    }
  }

  Future<void> _registerForPushNotifications() async {
    try {
      final token = await _notificationService.getToken();
      if (token != null) {
        await _authRepository.updateDeviceToken(token);
      }
    } catch (e) {
      // Silent fail - notifications are not critical
    }
  }
}
