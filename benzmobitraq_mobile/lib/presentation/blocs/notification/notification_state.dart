part of 'notification_bloc.dart';

/// Base class for notification states
abstract class NotificationState extends Equatable {
  const NotificationState();

  @override
  List<Object?> get props => [];
}

/// Initial state before loading
class NotificationInitial extends NotificationState {}

/// Loading state
class NotificationLoading extends NotificationState {}

/// Notifications loaded
class NotificationLoaded extends NotificationState {
  final List<NotificationModel> notifications;
  final int unreadCount;
  final bool hasMore;

  const NotificationLoaded({
    required this.notifications,
    required this.unreadCount,
    this.hasMore = false,
  });

  @override
  List<Object?> get props => [notifications, unreadCount, hasMore];
}

/// Error state
class NotificationError extends NotificationState {
  final String message;

  const NotificationError(this.message);

  @override
  List<Object?> get props => [message];
}
