part of 'auth_bloc.dart';

/// Base class for auth states
abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

/// Initial state before auth check
class AuthInitial extends AuthState {}

/// Loading state during auth operations
class AuthLoading extends AuthState {}

/// User is authenticated
class AuthAuthenticated extends AuthState {
  final EmployeeModel employee;

  const AuthAuthenticated(this.employee);

  /// Check if user is admin
  bool get isAdmin => employee.isAdmin;

  @override
  List<Object?> get props => [employee];
}

/// User is not authenticated
class AuthUnauthenticated extends AuthState {}

/// Auth operation failed
class AuthError extends AuthState {
  final String message;

  const AuthError(this.message);

  @override
  List<Object?> get props => [message];
}
