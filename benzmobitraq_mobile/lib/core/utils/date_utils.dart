import 'package:intl/intl.dart';

/// Utility class for date and time formatting
class DateTimeUtils {
  DateTimeUtils._();

  // ============================================================
  // FORMATTERS
  // ============================================================
  
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  static final DateFormat _timeFormat = DateFormat('HH:mm');
  static final DateFormat _timeWithSecondsFormat = DateFormat('HH:mm:ss');
  static final DateFormat _dateTimeFormat = DateFormat('dd MMM yyyy, HH:mm');
  static final DateFormat _shortDateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _isoFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _monthYearFormat = DateFormat('MMMM yyyy');
  static final DateFormat _dayOfWeekFormat = DateFormat('EEEE');

  // ============================================================
  // FORMAT METHODS
  // ============================================================

  /// Format date as "28 Jan 2026"
  static String formatDate(DateTime date) {
    return _dateFormat.format(date);
  }

  /// Format time as "14:30"
  static String formatTime(DateTime date) {
    return _timeFormat.format(date);
  }

  /// Format time as "14:30:45"
  static String formatTimeWithSeconds(DateTime date) {
    return _timeWithSecondsFormat.format(date);
  }

  /// Format as "28 Jan 2026, 14:30"
  static String formatDateTime(DateTime date) {
    return _dateTimeFormat.format(date);
  }

  /// Format as "28/01/2026"
  static String formatShortDate(DateTime date) {
    return _shortDateFormat.format(date);
  }

  /// Format as "2026-01-28" (ISO format)
  static String formatIsoDate(DateTime date) {
    return _isoFormat.format(date);
  }

  /// Format as "January 2026"
  static String formatMonthYear(DateTime date) {
    return _monthYearFormat.format(date);
  }

  /// Format as "Wednesday"
  static String formatDayOfWeek(DateTime date) {
    return _dayOfWeekFormat.format(date);
  }

  // ============================================================
  // RELATIVE TIME
  // ============================================================

  /// Get relative time string like "2 hours ago", "Just now", etc.
  static String getRelativeTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.isNegative) {
      return 'In the future';
    }

    if (difference.inSeconds < 60) {
      return 'Just now';
    }

    if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes ${minutes == 1 ? 'min' : 'mins'} ago';
    }

    if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    }

    if (difference.inDays < 7) {
      final days = difference.inDays;
      if (days == 1) return 'Yesterday';
      return '$days days ago';
    }

    if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    }

    if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    }

    final years = (difference.inDays / 365).floor();
    return '$years ${years == 1 ? 'year' : 'years'} ago';
  }

  /// Get short relative time like "2h", "5m", "3d"
  static String getShortRelativeTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.isNegative) {
      return 'Future';
    }

    if (difference.inSeconds < 60) {
      return 'Now';
    }

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    }

    if (difference.inHours < 24) {
      return '${difference.inHours}h';
    }

    if (difference.inDays < 7) {
      return '${difference.inDays}d';
    }

    if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()}w';
    }

    return formatShortDate(date);
  }

  // ============================================================
  // DURATION FORMATTING
  // ============================================================

  /// Format duration as "2h 30m"
  static String formatDuration(Duration duration) {
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}s';
    }

    if (duration.inMinutes < 60) {
      return '${duration.inMinutes}m';
    }

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (minutes == 0) {
      return '${hours}h';
    }

    return '${hours}h ${minutes}m';
  }

  /// Format duration as "02:30:45"
  static String formatDurationHMS(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  // ============================================================
  // DATE HELPERS
  // ============================================================

  /// Check if two dates are the same day
  static bool isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  /// Check if date is today
  static bool isToday(DateTime date) {
    return isSameDay(date, DateTime.now());
  }

  /// Check if date is yesterday
  static bool isYesterday(DateTime date) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return isSameDay(date, yesterday);
  }

  /// Get start of day (midnight)
  static DateTime startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Get end of day (23:59:59.999)
  static DateTime endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  /// Get start of week (Monday)
  static DateTime startOfWeek(DateTime date) {
    final daysFromMonday = date.weekday - 1;
    return startOfDay(date.subtract(Duration(days: daysFromMonday)));
  }

  /// Get start of month
  static DateTime startOfMonth(DateTime date) {
    return DateTime(date.year, date.month, 1);
  }

  // ============================================================
  // PARSING
  // ============================================================

  /// Parse ISO date string to DateTime
  static DateTime? parseIsoDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;
    try {
      return DateTime.parse(dateString);
    } catch (e) {
      return null;
    }
  }

  /// Parse date string with format "dd/MM/yyyy"
  static DateTime? parseShortDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;
    try {
      return _shortDateFormat.parse(dateString);
    } catch (e) {
      return null;
    }
  }
}
