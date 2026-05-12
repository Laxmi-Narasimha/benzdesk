import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:benzmobitraq_mobile/app.dart';
import 'package:benzmobitraq_mobile/core/constants/app_constants.dart';
import 'package:benzmobitraq_mobile/core/di/injection.dart';
import 'package:benzmobitraq_mobile/services/connectivity_service.dart';
import 'package:benzmobitraq_mobile/services/notification_service.dart';
import 'package:benzmobitraq_mobile/services/tracking_service.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

/// BLoC observer for debugging state changes
class AppBlocObserver extends BlocObserver {
  @override
  void onCreate(BlocBase bloc) {
    super.onCreate(bloc);
    debugPrint('🟢 Bloc Created: ${bloc.runtimeType}');
  }

  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    // Filter out SessionBloc to avoid spamming logs every second (timer updates)
    if (bloc.runtimeType.toString() != 'SessionBloc') {
      debugPrint('🔄 ${bloc.runtimeType} Change: ${change.currentState.runtimeType} → ${change.nextState.runtimeType}');
    }
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    debugPrint('❌ ${bloc.runtimeType} Error: $error');
  }

  @override
  void onClose(BlocBase bloc) {
    super.onClose(bloc);
    debugPrint('🔴 Bloc Closed: ${bloc.runtimeType}');
  }
}

/// WorkManager callback - runs even when app is killed.
/// Checks if the tracking service is alive and restarts it if needed.
@pragma('vm:entry-point')
void _workManagerCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final isRunning = await FlutterBackgroundService().isRunning();
      if (!isRunning) {
        debugPrint('WorkManager: tracking service was killed, restarting...');
        await TrackingService.initialize();
        await TrackingService.resumeIfNeeded();
      }
    } catch (e) {
      debugPrint('WorkManager watchdog error: $e');
    }
    return Future.value(true);
  });
}

/// Application entry point
void main() {
  // Catch errors at the root level
  runZonedGuarded(() {
    // 1. Initialize Bindings immediately required for runApp
    WidgetsFlutterBinding.ensureInitialized();
    
    // 2. Run a "Bootstrapper" app immediately to show UI (No Grey Screen!)
    runApp(const AppBootstrapper());
    
  }, (error, stack) {
    debugPrint('🚨 UNCAUGHT ZONE ERROR: $error');
  });
}

/// A simplified app that loads first to handle initialization
class AppBootstrapper extends StatefulWidget {
  const AppBootstrapper({super.key});

  @override
  State<AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<AppBootstrapper> {
  bool _hasError = false;
  String _errorMessage = '';
  double _progress = 0.0;
  String _statusMessage = 'Starting...';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Step 1: Orientation (10%)
      setState(() { _statusMessage = 'Locking Orientation...'; _progress = 0.1; });
      
      // CRITICAL FIX: Fire-and-forget with timeout. Do not await infinitely.
      // Native channel might be busy with Geolocator.
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]).timeout(
        const Duration(seconds: 2), 
        onTimeout: () {
          debugPrint('⚠️ Orientation lock timed out');
          return;
        }
      ).catchError((e) {
        debugPrint('⚠️ Orientation lock failed: $e');
        return;
      });
      
      debugPrint('STEP 1: Orientation lock requested');

      // Step 2: Firebase (30%) — must be BEFORE Supabase
      // FCM background handler runs in a separate isolate that also calls
      // Firebase.initializeApp(). Having it initialized here ensures the
      // main isolate is also ready for foreground messages.
      setState(() { _statusMessage = 'Initializing Notifications...'; _progress = 0.25; });
      try {
        await Firebase.initializeApp().timeout(const Duration(seconds: 5));
        debugPrint('STEP 2: Firebase initialized');
      } catch (e) {
        debugPrint('Firebase Init Warning (non-fatal): $e');
        // Firebase is optional — FCM won't work but app will still run
      }

      // Step 3: Supabase (50%) — The critical data service
      setState(() { _statusMessage = 'Connecting to Server...'; _progress = 0.45; });
      debugPrint('STEP 3: Initializing Supabase...');
      try {
        await Supabase.initialize(
          url: AppConstants.supabaseUrl,
          anonKey: AppConstants.supabaseAnonKey,
        ).timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('Supabase Init Error: $e');
        throw 'Could not connect to server. Please check your internet connection.';
      }
      debugPrint('STEP 3: Supabase initialized');

      // Step 3a: Load app settings (API keys) from Supabase
      try {
        final settings = await Supabase.instance.client
            .from('app_settings')
            .select('key, value')
            .timeout(const Duration(seconds: 5));
        for (final row in settings as List) {
          final key = row['key'] as String;
          final value = row['value']?.toString() ?? '';
          if (key == 'google_places_api_key' && value.isNotEmpty) {
            AppConstants.googlePlacesApiKey = value;
          }
          if (key == 'openai_api_key' && value.isNotEmpty) {
            AppConstants.openAiApiKey = value;
          }
        }
        debugPrint('STEP 3a: API keys loaded from app_settings');
      } catch (e) {
        debugPrint('STEP 3a: Failed to load app_settings: $e');
      }

      // Step 3b: Connectivity monitoring — used for network-aware sync
      setState(() { _statusMessage = 'Checking Network...'; _progress = 0.48; });
      try {
        await ConnectivityService.initialize().timeout(
          const Duration(seconds: 2),
          onTimeout: () => debugPrint('Connectivity Init Timeout'),
        );
        debugPrint('STEP 3b: Connectivity monitoring initialized');
      } catch (e) {
        debugPrint('Connectivity Init Warning (non-fatal): $e');
      }

      // Step 3: Tracking Service (50%) - Optional, don't block on failure
      setState(() { _statusMessage = 'Initializing GPS...'; _progress = 0.5; });
      try {
        await TrackingService.initialize().timeout(
          const Duration(seconds: 3),
          onTimeout: () => debugPrint('Tracking Init Timeout'),
        );
      } catch (e) {
        debugPrint('Tracking Init Error: $e');
      }

      // Step 4: DI (70%)

      // Step 4: DI (70%)
      setState(() { _statusMessage = 'Loading Services...'; _progress = 0.7; });
      debugPrint('STEP 4: Configuring Dependencies...');
      await configureDependencies();
      debugPrint('STEP 4: Dependencies configured');

      // Step 4b: Initialize Notification Service (local channels MUST exist before use)
      setState(() { _statusMessage = 'Initializing Notifications...'; _progress = 0.75; });
      try {
        final notificationService = getIt<NotificationService>();
        await notificationService.initialize().timeout(const Duration(seconds: 3));
        debugPrint('STEP 4b: Notification service initialized');
      } catch (e) {
        debugPrint('Notification Init Warning (non-fatal): $e');
      }

      // Step 5: Resume Tracking (85%) - Optional
      setState(() { _statusMessage = 'Checking Status...'; _progress = 0.85; });
      try {
        await TrackingService.resumeIfNeeded();
      } catch (e) { /* ignore */ }
      debugPrint('STEP 5: Resume check complete');

      // Step 5b: Register WorkManager watchdog (restarts service if OS kills it)
      try {
        await Workmanager().initialize(_workManagerCallbackDispatcher);
        await Workmanager().registerPeriodicTask(
          'tracking-watchdog',
          'trackingWatchdog',
          frequency: const Duration(minutes: 15),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
          constraints: Constraints(networkType: NetworkType.notRequired),
        );
        debugPrint('STEP 5b: WorkManager watchdog registered (15min)');
      } catch (e) {
        debugPrint('WorkManager init warning: $e');
      }

      // Step 6: Finalize (100%)
      setState(() { _statusMessage = 'Ready!'; _progress = 1.0; });
      
      // Step 7: Bloc Observer
      Bloc.observer = AppBlocObserver();

      // Switch to Main App
      if (mounted) {
        runApp(const BenzMobiTraqApp());
      }

    } catch (e, stack) {
      debugPrint('🚨 BOOTSTRAP ERROR: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine content based on state
    Widget content;
    if (_hasError) {
      content = _buildErrorView();
    } else {
      content = _buildLoadingView();
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: content,
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(strokeWidth: 4, color: Color(0xFF1E88E5)),
          ),
          const SizedBox(height: 32),
          Text(
            _statusMessage,
            style: const TextStyle(
              fontSize: 16, 
              color: Colors.black87, 
              decoration: TextDecoration.none,
              fontFamily: 'Roboto'
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(value: _progress, backgroundColor: Colors.grey[200]),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 24),
            const Text(
              'Startup Failed',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _statusMessage = 'Retrying...';
                  _progress = 0;
                });
                _initializeApp();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
