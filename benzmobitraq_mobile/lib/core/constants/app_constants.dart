/// Application-wide constants
/// 
/// IMPORTANT: Replace these with your actual Supabase credentials before deployment.
/// Consider using environment variables or a secure config for production.
class AppConstants {
  AppConstants._();

  // ============================================================
  // SUPABASE CONFIGURATION
  // ============================================================
  
  /// Your Supabase project URL
  /// Replace with your actual Supabase URL
  static const String supabaseUrl = 'https://igrudnilqwmlgvmgneng.supabase.co';
  
  /// Your Supabase anonymous key
  /// Replace with your actual Supabase anon key
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlncnVkbmlscXdtbGd2bWduZW5nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc2OTY4ODEsImV4cCI6MjA4MzI3Mjg4MX0.k0up7lc8-fnKm7x_tYxdAhM4wF5juhJuCC8WYf0H8dQ';

  // ============================================================
  // APP INFO
  // ============================================================
  
  static const String appName = 'BenzMobiTraq';
  static const String appVersion = '1.0.0';

  // ============================================================
  // LOCATION TRACKING CONFIGURATION
  // Per industry-grade specification Section 7.3
  // ============================================================
  
  /// Minimum time between location updates (in seconds)
  /// Per spec: "do not accept more than 1 point per 5 seconds"
  static const int minTimeBetweenUpdates = 5;
  
  /// Maximum time between location updates when moving (in seconds)
  static const int maxTimeBetweenUpdates = 60;
  
  /// Interval for stationary mode checks (in seconds)
  /// Per spec: "switch to stationary checks every 2 minutes"
  static const int stationaryCheckInterval = 120;
  
  /// Radius to consider as "same location" when stationary (in meters)
  /// Per spec: "displacement from anchor < 30m"
  static const int stationaryRadius = 30;
  
  /// Speed threshold for bike vs car mode (in m/s)
  /// Per spec: "if speed_mps <= 8 (bike-like)"
  static const double bikeSpeedThresholdMps = 8.0;

  // ============================================================
  // ANTI-JITTER FILTERS
  // Per industry-grade specification Section 8
  // ============================================================
  
  /// Maximum acceptable accuracy (in meters)
  /// Per spec: "Reject points where accuracy_m > 50"
  static const double maxAccuracyThreshold = 50.0;
  
  /// Minimum distance delta for moving mode (in meters)
  /// Used as base for jitter filtering
  static const double minDistanceDelta = 10.0;
  
  /// Maximum realistic speed (in km/h)
  /// Per spec: "if implied speed > 160 km/h... ignore segment"
  static const double maxSpeedKmh = 160.0;
  
  /// Distance threshold for bike mode (in meters)
  /// Per spec: "if speed_mps <= 8 (bike-like): accept new point when moved ≥ 30m"
  static const double bikeDistanceThreshold = 30.0;
  
  /// Distance threshold for car mode (in meters)
  /// Per spec: "else (car-like): accept new point when moved ≥ 60m"
  static const double carDistanceThreshold = 60.0;
  
  /// Distance filter for geolocator (in meters)
  static const int distanceFilterDefault = 10;
  static const int distanceFilterBikes = 10;
  static const int distanceFilterCars = 20;


  // ============================================================
  // BATCH UPLOAD CONFIGURATION
  // ============================================================
  
  /// Interval between batch uploads (in seconds)
  static const int batchUploadInterval = 180; // 3 minutes
  
  /// Maximum points to include in a single batch
  static const int maxPointsPerBatch = 50;
  
  /// Retry delay for failed uploads (in seconds)
  static const int uploadRetryDelay = 30;
  
  /// Maximum retry attempts for failed uploads
  static const int maxUploadRetries = 5;

  // ============================================================
  // STUCK DETECTION (defaults, actual values from server settings)
  // ============================================================
  
  /// Default radius for stuck detection (in meters)
  static const double defaultStuckRadius = 150.0;
  
  /// Default duration for stuck alert (in minutes)
  static const int defaultStuckDurationMinutes = 30;

  // ============================================================
  // UI CONSTANTS
  // ============================================================
  
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  static const double borderRadius = 12.0;
  static const double cardElevation = 2.0;

  // ============================================================
  // ANIMATION DURATIONS
  // ============================================================
  
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 350);
  static const Duration longAnimation = Duration(milliseconds: 500);

  // ============================================================
  // STORAGE KEYS
  // ============================================================
  
  static const String keyIsLoggedIn = 'is_logged_in';
  static const String keyUserId = 'user_id';
  static const String keyUserRole = 'user_role';
  static const String keyDeviceToken = 'device_token';
  static const String keyActiveSessionId = 'active_session_id';
  static const String keyLastSyncTime = 'last_sync_time';
  static const String keyNotificationSettings = 'notification_settings';
  static const String keyLastKnownAddress = 'last_known_address';

  // ============================================================
  // NOTIFICATION IDs
  // ============================================================
  
  /// Notification ID for location tracking foreground service
  static const int trackingNotificationId = 888;
}
