part of 'auth_bloc.dart';

/// Base class for auth events
abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Check current authentication status
class AuthCheckRequested extends AuthEvent {}

/// Sign in with email and password
class AuthSignInRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthSignInRequested({
    required this.email,
    required this.password,
  });

  @override
  List<Object?> get props => [email, password];
}

/// Sign up with email, password, and profile info
class AuthSignUpRequested extends AuthEvent {
  final String email;
  final String password;
  final String name;
  final String? phone;

  const AuthSignUpRequested({
    required this.email,
    required this.password,
    required this.name,
    this.phone,
  });

  @override
  List<Object?> get props => [email, password, name, phone];
}

/// Sign out current user
class AuthSignOutRequested extends AuthEvent {}

/// Update profile information
class AuthProfileUpdateRequested extends AuthEvent {
  final String? name;
  final String? phone;

  const AuthProfileUpdateRequested({
    this.name,
    this.phone,
  });

  @override
  List<Object?> get props => [name, phone];
}

/// Auth state changed externally (e.g. from stream)
class AuthStateChanged extends AuthEvent {
  final EmployeeModel? employee;

  const AuthStateChanged(this.employee);

  @override
  List<Object?> get props => [employee];
}

/// Request Magic Link login
class AuthMagicLinkRequested extends AuthEvent {
  final String email;

  const AuthMagicLinkRequested({
    required this.email,
  });

  @override
  List<Object> get props => [email];
}

/// Magic Link sent successfully
class AuthMagicLinkSent extends AuthState {
  final String email;

  const AuthMagicLinkSent(this.email);

  @override
  List<Object> get props => [email];
}
