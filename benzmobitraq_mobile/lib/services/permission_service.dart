import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';

/// Permission status result with detailed information
class PermissionResult {
  final bool granted;
  final bool permanentlyDenied;
  final String message;
  final PermissionIssue? issue;

  const PermissionResult({
    required this.granted,
    this.permanentlyDenied = false,
    required this.message,
    this.issue,
  });

  static const PermissionResult success = PermissionResult(
    granted: true,
    message: 'All permissions granted',
  );
}

/// Types of permission issues
enum PermissionIssue {
  locationServicesDisabled,
  locationDenied,
  locationPermanentlyDenied,
  backgroundLocationDenied,
  batteryOptimizationEnabled,
  notificationDenied,
}

/// Service for handling all permission-related operations
/// 
/// This is a CRITICAL service for reliable background tracking.
/// Proper permission handling prevents silent failures.
class PermissionService {
  final Logger _logger = Logger();

  // ============================================================
  // LOCATION PERMISSIONS
  // ============================================================

  /// Check and request all necessary location permissions
  /// 
  /// Returns detailed result with what went wrong if not granted.
  /// This should be called BEFORE starting any tracking.
  Future<PermissionResult> requestLocationPermissions() async {
    try {
      // Step 1: Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _logger.w('Location services are disabled');
        return const PermissionResult(
          granted: false,
          message: 'Please enable location services in your device settings',
          issue: PermissionIssue.locationServicesDisabled,
        );
      }

      // Step 2: Check/request "when in use" permission first
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        _logger.i('Requesting location permission...');
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _logger.w('Location permission denied');
        return const PermissionResult(
          granted: false,
          message: 'Location permission is required to track your work sessions',
          issue: PermissionIssue.locationDenied,
        );
      }

      if (permission == LocationPermission.deniedForever) {
        _logger.e('Location permission permanently denied');
        return const PermissionResult(
          granted: false,
          permanentlyDenied: true,
          message: 'Location permission was permanently denied. Please enable it in app settings.',
          issue: PermissionIssue.locationPermanentlyDenied,
        );
      }

      // Step 3: For background tracking, we need "always" permission on Android
      if (Platform.isAndroid) {
        return await _requestBackgroundLocationAndroid();
      }

      // iOS handles background with "when in use" + background mode capability
      return PermissionResult.success;
    } catch (e) {
      _logger.e('Error checking permissions: $e');
      return PermissionResult(
        granted: false,
        message: 'Error checking permissions: $e',
      );
    }
  }

  /// Request background location permission on Android
  /// 
  /// On Android 10+, background location is a separate permission.
  /// On Android 11+, it CANNOT be requested directly from the app;
  /// user must grant it from settings.
  Future<PermissionResult> _requestBackgroundLocationAndroid() async {
    try {
      final status = await Permission.locationAlways.status;
      
      if (status.isGranted) {
        return PermissionResult.success;
      }

      // Check if we can request it (Android 10) or need to redirect (Android 11+)
      if (status.isDenied) {
        _logger.i('Requesting background location permission...');
        final result = await Permission.locationAlways.request();
        
        if (result.isGranted) {
          return PermissionResult.success;
        }
      }

      // On Android 11+, we can still work with "when in use" 
      // if we use a foreground service (which we do)
      final whenInUse = await Permission.locationWhenInUse.status;
      if (whenInUse.isGranted) {
        _logger.w('Only "when in use" permission granted. Using foreground service.');
        // This is acceptable - foreground service keeps app "in use"
        return PermissionResult.success;
      }

      return const PermissionResult(
        granted: false,
        message: 'Background location permission is recommended for reliable tracking',
        issue: PermissionIssue.backgroundLocationDenied,
      );
    } catch (e) {
      _logger.e('Error requesting background location: $e');
      // Don't fail completely - foreground service may still work
      return PermissionResult.success;
    }
  }

  // ============================================================
  // BATTERY OPTIMIZATION (Android specific)
  // ============================================================

  /// Check if battery optimization is affecting the app
  /// 
  /// This is CRITICAL on many Android devices (especially Chinese brands)
  /// that aggressively kill background apps.
  Future<bool> isBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;

    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      return status.isGranted;
    } catch (e) {
      _logger.e('Error checking battery optimization: $e');
      return false;
    }
  }

  /// Request to disable battery optimization
  /// 
  /// Shows system dialog asking user to whitelist the app.
  Future<bool> requestBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;

    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      
      if (status.isGranted) {
        _logger.i('Battery optimization disabled');
        return true;
      }

      _logger.w('Battery optimization still enabled - tracking may be unreliable');
      return false;
    } catch (e) {
      _logger.e('Error requesting battery optimization: $e');
      return false;
    }
  }

  // ============================================================
  // NOTIFICATION PERMISSIONS
  // ============================================================

  /// Check and request notification permission
  /// 
  /// Required for foreground service notification and push notifications.
  Future<bool> requestNotificationPermission() async {
    try {
      // On Android 13+, notifications need explicit permission
      if (Platform.isAndroid) {
        final status = await Permission.notification.status;
        if (!status.isGranted) {
          final result = await Permission.notification.request();
          return result.isGranted;
        }
      }
      return true;
    } catch (e) {
      _logger.e('Error requesting notification permission: $e');
      return false;
    }
  }

  // ============================================================
  // ALL-IN-ONE PERMISSION CHECK
  // ============================================================

  /// Perform all permission checks needed for tracking
  /// 
  /// Returns a comprehensive result indicating readiness to track.
  Future<TrackingReadiness> checkTrackingReadiness() async {
    final issues = <PermissionIssue>[];
    final warnings = <String>[];

    // Location permission (required)
    final locationResult = await requestLocationPermissions();
    if (!locationResult.granted) {
      return TrackingReadiness(
        canTrack: false,
        message: locationResult.message,
        issues: [locationResult.issue!],
        warnings: [],
      );
    }

    // Battery optimization (warning only)
    if (Platform.isAndroid) {
      final batteryOk = await isBatteryOptimizationDisabled();
      if (!batteryOk) {
        warnings.add(
          'Battery optimization is enabled. Tracking may stop when the app is in background. '
          'Consider disabling it in settings for reliable tracking.'
        );
        issues.add(PermissionIssue.batteryOptimizationEnabled);
      }
    }

    // Notification permission (warning only)
    final notificationOk = await requestNotificationPermission();
    if (!notificationOk) {
      warnings.add('Notification permission denied. You won\'t receive alerts.');
      issues.add(PermissionIssue.notificationDenied);
    }

    return TrackingReadiness(
      canTrack: true,
      message: 'Ready to track',
      issues: issues,
      warnings: warnings,
    );
  }

  /// Open app settings for user to manually grant permissions
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }

  /// Open location settings
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }
}

/// Result of tracking readiness check
class TrackingReadiness {
  final bool canTrack;
  final String message;
  final List<PermissionIssue> issues;
  final List<String> warnings;

  const TrackingReadiness({
    required this.canTrack,
    required this.message,
    required this.issues,
    required this.warnings,
  });

  bool get hasWarnings => warnings.isNotEmpty;
  bool get hasCriticalIssues => issues.any((i) =>
      i == PermissionIssue.locationServicesDisabled ||
      i == PermissionIssue.locationDenied ||
      i == PermissionIssue.locationPermanentlyDenied);
}
