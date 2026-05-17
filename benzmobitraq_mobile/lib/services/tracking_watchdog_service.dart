import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

/// Dart bridge to the native Android watchdog (WorkManager 15-min +
/// AlarmManager exact 5-min) that resurrects the BackgroundService when
/// the OS kills it.
///
/// Call [schedule] when a session starts and [cancel] when it ends.
/// Both are idempotent and safe to call multiple times.
///
/// On iOS this is a no-op — iOS's background lifetime model is
/// fundamentally different and a different solution (significant-
/// location-change events) would apply.
class TrackingWatchdogService {
  static const _channel = MethodChannel('benzmobitraq/watchdog');
  static final _logger = Logger();

  static Future<void> schedule() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('schedule');
      _logger.i('Native watchdog scheduled');
    } catch (e) {
      _logger.w('Native watchdog schedule failed: $e');
    }
  }

  static Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('cancel');
      _logger.i('Native watchdog cancelled');
    } catch (e) {
      _logger.w('Native watchdog cancel failed: $e');
    }
  }
}
