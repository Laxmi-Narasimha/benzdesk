import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/di/injection.dart';
import 'services/tracking_service.dart';

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

      // Step 5: Resume Tracking (85%) - Optional
      setState(() { _statusMessage = 'Checking Status...'; _progress = 0.85; });
      try {
        await TrackingService.resumeIfNeeded();
      } catch (e) { /* ignore */ }
      debugPrint('STEP 5: Resume check complete');
      
      // Note: Firebase/Notifications will be initialized lazily when needed
      // This keeps startup fast and prevents crashes if Firebase isn't configured

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
