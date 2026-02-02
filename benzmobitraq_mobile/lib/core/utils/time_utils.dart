/// Time utilities for Indian Standard Time (IST) and duration formatting
/// 
/// IST is UTC+5:30. This utility ensures consistent time handling
/// throughout the BenzMobiTraq app.
class TimeUtils {
  /// IST offset from UTC
  static const Duration istOffset = Duration(hours: 5, minutes: 30);

  /// Get current time in IST
  static DateTime nowIST() {
    return DateTime.now().toUtc().add(istOffset);
  }

  /// Convert any DateTime to IST
  static DateTime toIST(DateTime time) {
    return time.toUtc().add(istOffset);
  }

  /// Format time as HH:MM (24-hour) in IST
  static String formatTimeIST(DateTime time) {
    final ist = toIST(time);
    return '${ist.hour.toString().padLeft(2, '0')}:${ist.minute.toString().padLeft(2, '0')}';
  }

  /// Format time as HH:MM:SS (24-hour) in IST
  static String formatTimeFullIST(DateTime time) {
    final ist = toIST(time);
    return '${ist.hour.toString().padLeft(2, '0')}:'
           '${ist.minute.toString().padLeft(2, '0')}:'
           '${ist.second.toString().padLeft(2, '0')}';
  }

  /// Format date as DD/MM/YYYY in IST
  static String formatDateIST(DateTime time) {
    final ist = toIST(time);
    return '${ist.day.toString().padLeft(2, '0')}/'
           '${ist.month.toString().padLeft(2, '0')}/'
           '${ist.year}';
  }

  /// Format date and time in IST (DD/MM/YYYY HH:MM)
  static String formatDateTimeIST(DateTime time) {
    return '${formatDateIST(time)} ${formatTimeIST(time)}';
  }

  /// Format duration as H:MM:SS
  static String formatDuration(Duration duration) {
    // Handle negative durations by using absolute value
    final d = duration.isNegative ? Duration.zero : duration;
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format duration as "Xh Ym" or "Xm" for shorter durations
  static String formatDurationShort(Duration duration) {
    final d = duration.isNegative ? Duration.zero : duration;
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${d.inMinutes}m';
  }

  /// Format duration for notification (compact)
  static String formatDurationCompact(Duration duration) {
    final d = duration.isNegative ? Duration.zero : duration;
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Get greeting based on current IST time
  static String getGreeting() {
    final hour = nowIST().hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 17) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }
}
