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
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlncnVkbmlscXdtbGd2bWduZW5nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc2OTY4ODEsImV4cCI6MjA4MzI3Mjg4MX0.k0up7lc8-fnKm7x_tYxdAhM4wF5juhJuCC8WYf0H8dQ';

  // ============================================================
  // APP INFO
  // ============================================================

  /// User-facing app name. Matches the Android manifest label so the
  /// splash, OS chooser and notification headers all read identically.
  static const String appName = 'Benz Packaging: Employee';
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
  /// LOOSENED: Accept up to 50m for typical urban GPS
  static const double maxAccuracyThreshold = 50.0;

  /// Minimum distance delta for moving mode (in meters)
  /// Used as base for jitter filtering
  static const double minDistanceDelta = 15.0;

  /// Minimum speed to consider as movement (in m/s)
  /// DISABLED: Many devices report speed=0 even when moving
  /// Rely on distance+time filtering instead
  static const double minSpeedForMovement = 0.0; // Disabled

  /// Maximum realistic speed (in km/h)
  /// Per spec: "if implied speed > 160 km/h... ignore segment"
  static const double maxSpeedKmh = 160.0;

  /// Distance threshold for bike mode (in meters)
  /// Accept points when moved >= 20m for bike/slow movement tracking
  static const double bikeDistanceThreshold = 20.0;

  /// Distance threshold for car mode (in meters)
  /// Accept points when moved >= 50m for car movement tracking
  static const double carDistanceThreshold = 50.0;

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

  // ============================================================
  // GOOGLE MAPS & PLACES API
  // ============================================================

  /// Google Places API key — set via app_settings or env at runtime.
  /// Fallback value mirrors the Maps SDK key in AndroidManifest.xml so
  /// nearby-company search works out of the box when app_settings is empty.
  /// (Requires "Places API" to be enabled for this key in Google Cloud.)
  static String googlePlacesApiKey = 'AIzaSyD2EH4_Gv6tP3qS1Ue70gLfyoOZT9eIciM';

  /// OpenAI API key — set via app_settings or env at runtime
  static String openAiApiKey = '';

  /// OpenAI model id to use for company-pitch research.
  /// Override via app_settings.openai_model_id. Defaults to gpt-4o
  /// because it's reliably available, supports the responses API
  /// with web_search_preview, and produces strong structured output.
  static String openAiModelId = 'gpt-4o';

  /// Nearby manufacturing search radius in meters.
  static const int nearbySearchRadiusMeters = 5000;

  /// Maximum ranked nearby companies shown per refresh.
  static const int nearbyMaxCompanyResults = 60;

  /// Keywords for finding manufacturing companies across sectors.
  static const List<String> nearbySearchKeywords = [
    'manufacturing company',
    'factory',
    'industries',
    'industrial plant',
    'steel manufacturing',
    'metal fabrication',
    'chemical manufacturing',
    'pharmaceutical manufacturing',
    'textile mill',
    'food processing plant',
    'electronics manufacturing',
    'electrical manufacturing',
    'machinery manufacturing',
    'auto component manufacturing',
    'rubber manufacturing',
    'packaging factory',
  ];

  /// Top automotive OEMs and tier-1 suppliers to detect by name.
  /// These are major manufacturers and their plants — the primary targets.
  static const List<String> automotiveOemKeywords = [
    // Major Indian & Global OEMs
    'maruti', 'suzuki', 'honda', 'toyota', 'hyundai', 'kia',
    'tata motors', 'mahindra', 'ashok leyland', 'bajaj auto',
    'hero', 'motocorp', 'tvs', 'force motors', 'eicher',
    'bharatbenz', 've commercial', 'volvo', 'scania',
    'mercedes', 'bmw', 'audi', 'volkswagen', 'skoda',
    'ford', 'general motors', 'gm', 'renault', 'nissan',
    'mitsubishi', 'isuzu', 'jcb', 'escorts', 'swaraj',
    // Tier-1 Suppliers
    'bosch', 'denso', 'continental', 'delphi', 'valeo',
    'magneti marelli', 'motherson', 'bharat forge',
    'sundram fasteners', 'gabriel', 'munjal showa',
    'excel industries', 'jayem automotives', 'spark minds',
    'lumax', 'ficosa', 'hella', 'varroc', 'bkt', 'ceat',
    'mrf', 'apollo tyres', 'jk tyre', 'bridgestone',
    // Electric vehicle makers
    'ola electric', 'ather', 'tvs motors', 'revolt',
    'byd', 'mg motor', 'tata passenger', 'mahindra electric',
  ];

  /// Names/terms that indicate a repair shop, garage, or non-manufacturing business
  static const List<String> nonManufacturingExclusions = [
    'repair',
    'garage',
    'workshop',
    'service center',
    'service centre',
    'mechanic',
    'body shop',
    'denting',
    'painting',
    'car wash',
    'tyre shop',
    'tire shop',
    'battery shop',
    'lubricant shop',
    'spare parts',
    'accessories',
    'dealership',
    'showroom',
    'warehouse only',
    'cold storage',
    'logistics hub',
    'trading company',
    'import export',
    'distributor',
    'dealer',
    'consultant',
    'broker',
    'agent',
    'commission agent',
  ];

  // ============================================================
  // STATIONARY SPOT DETECTION (for nearby companies feature)
  // ============================================================

  /// Seconds of no significant movement before triggering stationary spot UI
  static const int stationarySpotThresholdSec = 120;

  /// Speed threshold below which we consider "not moving" (m/s)
  static const double stationarySpotSpeedMps = 1.5;

  /// Distance threshold below which we consider "not moved" (meters)
  static const double stationarySpotDistanceM = 30.0;

  /// Minimum accuracy required for stationary spot detection (meters)
  static const double stationarySpotMaxAccuracy = 50.0;

  /// Notification ID for stationary spot "nearby companies" prompt
  static const int stationarySpotNotificationId = 889;
}
