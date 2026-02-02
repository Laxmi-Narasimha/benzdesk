import 'package:logger/logger.dart';

import '../datasources/remote/supabase_client.dart';
import '../models/notification_model.dart';

/// Repository for handling notification operations
class NotificationRepository {
  final SupabaseDataSource _dataSource;
  final Logger _logger = Logger();

  NotificationRepository({
    required SupabaseDataSource dataSource,
  }) : _dataSource = dataSource;

  /// Get notifications for current user
  Future<List<NotificationModel>> getNotifications({
    required String userId,
    required bool isAdmin,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      return await _dataSource.getNotifications(
        userId: userId,
        isAdmin: isAdmin,
        limit: limit,
        offset: offset,
      );
    } catch (e) {
      _logger.e('Error fetching notifications: $e');
      return [];
    }
  }

  /// Get unread notification count
  Future<int> getUnreadCount({
    required String userId,
    required bool isAdmin,
  }) async {
    try {
      return await _dataSource.getUnreadNotificationCount(
        userId: userId,
        isAdmin: isAdmin,
      );
    } catch (e) {
      _logger.e('Error getting unread count: $e');
      return 0;
    }
  }

  /// Mark a single notification as read
  Future<bool> markAsRead(String notificationId) async {
    try {
      await _dataSource.markNotificationAsRead(notificationId);
      return true;
    } catch (e) {
      _logger.e('Error marking notification as read: $e');
      return false;
    }
  }

  /// Mark all notifications as read
  Future<bool> markAllAsRead({
    required String userId,
    required bool isAdmin,
  }) async {
    try {
      await _dataSource.markAllNotificationsAsRead(
        userId: userId,
        isAdmin: isAdmin,
      );
      return true;
    } catch (e) {
      _logger.e('Error marking all notifications as read: $e');
      return false;
    }
  }
}
