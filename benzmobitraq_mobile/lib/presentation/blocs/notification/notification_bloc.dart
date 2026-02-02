import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/notification_model.dart';
import '../../../data/repositories/notification_repository.dart';

part 'notification_event.dart';
part 'notification_state.dart';

/// BLoC for handling notification state
class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final NotificationRepository _notificationRepository;

  NotificationBloc({
    required NotificationRepository notificationRepository,
  })  : _notificationRepository = notificationRepository,
        super(NotificationInitial()) {
    on<NotificationLoadRequested>(_onLoadRequested);
    on<NotificationMarkReadRequested>(_onMarkReadRequested);
    on<NotificationMarkAllReadRequested>(_onMarkAllReadRequested);
    on<NotificationRefreshRequested>(_onRefreshRequested);
  }

  Future<void> _onLoadRequested(
    NotificationLoadRequested event,
    Emitter<NotificationState> emit,
  ) async {
    emit(NotificationLoading());

    try {
      final notifications = await _notificationRepository.getNotifications(
        userId: event.userId,
        isAdmin: event.isAdmin,
        limit: event.limit,
        offset: event.offset,
      );

      final unreadCount = await _notificationRepository.getUnreadCount(
        userId: event.userId,
        isAdmin: event.isAdmin,
      );

      emit(NotificationLoaded(
        notifications: notifications,
        unreadCount: unreadCount,
        hasMore: notifications.length >= event.limit,
      ));
    } catch (e) {
      emit(NotificationError('Failed to load notifications: $e'));
    }
  }

  Future<void> _onMarkReadRequested(
    NotificationMarkReadRequested event,
    Emitter<NotificationState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotificationLoaded) return;

    try {
      await _notificationRepository.markAsRead(event.notificationId);

      // Update local state
      final updatedNotifications = currentState.notifications.map((n) {
        if (n.id == event.notificationId) {
          return n.copyWith(isRead: true);
        }
        return n;
      }).toList();

      emit(NotificationLoaded(
        notifications: updatedNotifications,
        unreadCount: currentState.unreadCount > 0 
            ? currentState.unreadCount - 1 
            : 0,
        hasMore: currentState.hasMore,
      ));
    } catch (e) {
      // Silent fail - notification will sync on next load
    }
  }

  Future<void> _onMarkAllReadRequested(
    NotificationMarkAllReadRequested event,
    Emitter<NotificationState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotificationLoaded) return;

    try {
      await _notificationRepository.markAllAsRead(
        userId: event.userId,
        isAdmin: event.isAdmin,
      );

      // Update local state
      final updatedNotifications = currentState.notifications.map((n) {
        return n.copyWith(isRead: true);
      }).toList();

      emit(NotificationLoaded(
        notifications: updatedNotifications,
        unreadCount: 0,
        hasMore: currentState.hasMore,
      ));
    } catch (e) {
      emit(NotificationError('Failed to mark all as read: $e'));
    }
  }

  Future<void> _onRefreshRequested(
    NotificationRefreshRequested event,
    Emitter<NotificationState> emit,
  ) async {
    // Reload from beginning
    add(NotificationLoadRequested(
      userId: event.userId,
      isAdmin: event.isAdmin,
    ));
  }
}
