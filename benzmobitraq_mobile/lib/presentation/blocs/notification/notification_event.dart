part of 'notification_bloc.dart';

/// Base class for notification events
abstract class NotificationEvent extends Equatable {
  const NotificationEvent();

  @override
  List<Object?> get props => [];
}

/// Load notifications
class NotificationLoadRequested extends NotificationEvent {
  final String userId;
  final bool isAdmin;
  final int limit;
  final int offset;

  const NotificationLoadRequested({
    required this.userId,
    required this.isAdmin,
    this.limit = 50,
    this.offset = 0,
  });

  @override
  List<Object?> get props => [userId, isAdmin, limit, offset];
}

/// Mark single notification as read
class NotificationMarkReadRequested extends NotificationEvent {
  final String notificationId;

  const NotificationMarkReadRequested(this.notificationId);

  @override
  List<Object?> get props => [notificationId];
}

/// Mark all notifications as read
class NotificationMarkAllReadRequested extends NotificationEvent {
  final String userId;
  final bool isAdmin;

  const NotificationMarkAllReadRequested({
    required this.userId,
    required this.isAdmin,
  });

  @override
  List<Object?> get props => [userId, isAdmin];
}

/// Refresh notifications
class NotificationRefreshRequested extends NotificationEvent {
  final String userId;
  final bool isAdmin;

  const NotificationRefreshRequested({
    required this.userId,
    required this.isAdmin,
  });

  @override
  List<Object?> get props => [userId, isAdmin];
}
