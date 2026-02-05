import 'package:intl/intl.dart';

/// Utility class for date and time formatting
class DateTimeUtils {
  DateTimeUtils._();

  // ============================================================
  // TIMEZONE CONFIG
  // ============================================================
  
  /// Convert any DateTime to IST (UTC+5:30)
  static DateTime toIST(DateTime date) {
    if (date.isUtc) {
      return date.add(const Duration(hours: 5, minutes: 30));
    }
    // If it's already local, we assume the device might be anywhere.
    // Ideally we should work with UTC dates from the backend.
    // If we want to force IST representation even if device is elsewhere:
    return date.toUtc().add(const Duration(hours: 5, minutes: 30));
  }

  // ============================================================
  // FORMATTERS
  // ============================================================
  
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  static final DateFormat _timeFormat = DateFormat('h:mm a'); // Changed to AM/PM as per generic preference, or stick to HH:mm if enforced. Keeping HH:mm for consistency with existing or switching? grep showed h:mm a in many places. Let's make it consistent.
  // Actually, let's keep the defined formatters but ensure they are applied to IST converted dates.
  
  // existing formatters
  static final DateFormat _fmtDate = DateFormat('dd MMM yyyy');
  static final DateFormat _fmtTime = DateFormat('HH:mm');
  static final DateFormat _fmtTimeSec = DateFormat('HH:mm:ss');
  static final DateFormat _fmtDateTime = DateFormat('dd MMM yyyy, HH:mm');
  static final DateFormat _fmtShortDate = DateFormat('dd/MM/yyyy');
  static final DateFormat _fmtIso = DateFormat('yyyy-MM-dd');
  static final DateFormat _fmtMonthYear = DateFormat('MMMM yyyy');
  static final DateFormat _fmtDayWeek = DateFormat('EEEE');

  // ============================================================
  // FORMAT METHODS
  // ============================================================

  /// Format date as "28 Jan 2026" (IST)
  static String formatDate(DateTime date) {
    return _fmtDate.format(toIST(date));
  }

  /// Format time as "14:30" (IST)
  static String formatTime(DateTime date) {
    return _fmtTime.format(toIST(date));
  }

  /// Format time as "14:30:45" (IST)
  static String formatTimeWithSeconds(DateTime date) {
    return _fmtTimeSec.format(toIST(date));
  }

  /// Format as "28 Jan 2026, 14:30" (IST)
  static String formatDateTime(DateTime date) {
    return _fmtDateTime.format(toIST(date));
  }

  /// Format as "28/01/2026" (IST)
  static String formatShortDate(DateTime date) {
    return _fmtShortDate.format(toIST(date));
  }

  /// Format as "2026-01-28" (IST)
  static String formatIsoDate(DateTime date) {
    return _fmtIso.format(toIST(date));
  }

  /// Format as "January 2026" (IST)
  static String formatMonthYear(DateTime date) {
    return _fmtMonthYear.format(toIST(date));
  }

  /// Format as "Wednesday" (IST)
  static String formatDayOfWeek(DateTime date) {
    return _fmtDayWeek.format(toIST(date));
  }

  // ============================================================
  // RELATIVE TIME
  // ============================================================

  /// Get relative time string like "2 hours ago", "Just now", etc.
  static String getRelativeTime(DateTime date) {
    final now = toIST(DateTime.now().toUtc());
    final dateIst = toIST(date); // Ensure comparison is in same zone (effectively offset doesn't matter for diff, but consistency)
    final difference = now.difference(dateIst);

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
    final now = toIST(DateTime.now().toUtc());
    final dateIst = toIST(date);
    final difference = now.difference(dateIst);

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

  /// Check if two dates are the same day (in IST)
  static bool isSameDay(DateTime date1, DateTime date2) {
    final d1 = toIST(date1);
    final d2 = toIST(date2);
    return d1.year == d2.year &&
        d1.month == d2.month &&
        d1.day == d2.day;
  }

  /// Check if date is today (in IST)
  static bool isToday(DateTime date) {
    return isSameDay(date, DateTime.now().toUtc());
  }

  /// Check if date is yesterday (in IST)
  static bool isYesterday(DateTime date) {
    final nowIst = toIST(DateTime.now().toUtc());
    final yesterdayIst = nowIst.subtract(const Duration(days: 1));
    return isSameDay(date, yesterdayIst); // isSameDay handles conversion
  }

  /// Get start of day (midnight) in IST
  static DateTime startOfDay(DateTime date) {
    final d = toIST(date);
    return DateTime(d.year, d.month, d.day);
  }

  /// Get end of day (23:59:59.999) in IST
  static DateTime endOfDay(DateTime date) {
    final d = toIST(date);
    return DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
  }

  /// Get start of week (Monday) in IST
  static DateTime startOfWeek(DateTime date) {
    final d = toIST(date);
    final daysFromMonday = d.weekday - 1;
    final monday = d.subtract(Duration(days: daysFromMonday));
    return DateTime(monday.year, monday.month, monday.day);
  }

  /// Get start of month in IST
  static DateTime startOfMonth(DateTime date) {
    final d = toIST(date);
    return DateTime(d.year, d.month, 1);
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
      return _fmtShortDate.parse(dateString);
    } catch (e) {
      return null;
    }
  }
}
