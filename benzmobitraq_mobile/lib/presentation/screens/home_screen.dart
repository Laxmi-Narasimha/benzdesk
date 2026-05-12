import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:benzmobitraq_mobile/core/router/app_router.dart';
import 'package:benzmobitraq_mobile/core/utils/achievement_engine.dart';
import 'package:benzmobitraq_mobile/core/constants/theme_constants.dart';
import 'package:benzmobitraq_mobile/services/geocoding_service.dart';
import 'package:benzmobitraq_mobile/services/permission_service.dart';

import 'package:benzmobitraq_mobile/presentation/blocs/auth/auth_bloc.dart';
import 'package:benzmobitraq_mobile/presentation/blocs/session/session_bloc.dart';
import 'package:benzmobitraq_mobile/presentation/widgets/app_bottom_nav_bar.dart';
import 'package:benzmobitraq_mobile/presentation/widgets/post_session_expense_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:benzmobitraq_mobile/presentation/screens/settings_screen.dart';

/// Main home screen with session tracking
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final PermissionService _permissionService = PermissionService();
  bool _batteryDialogShown = false;
  String? _currentAddress;
  String? _lastStationarySpotKey; // deduplicate snackbar re-shows
  // Anti-spam guard for the Present/Work Done button. Prevents races where
  // a user taps Start->Stop->Start rapidly and the async operations interleave.
  DateTime? _lastTransitionAt;
  bool _transitionInProgress = false;
  static const Duration _transitionCooldown = Duration(seconds: 2);
  Timer? _uiRefreshTimer;

  @override
  void initState() {
    super.initState();
    // Register lifecycle observer to detect app resume
    WidgetsBinding.instance.addObserver(this);
    // Load session history
    context.read<SessionBloc>().add(const SessionLoadHistory());
    // Request permissions immediately on app entry (before user taps anything)
    _requestEssentialPermissions();
    // Check battery optimization on first load
    _checkBatteryOptimization();
    // Fetch initial location
    _fetchCurrentLocation();
    // SAFETY NET: force UI refresh every 3 seconds when active so the
    // distance/duration never goes stale even if stream events are dropped.
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        final state = context.read<SessionBloc>().state;
        if (state.isActive) {
          context.read<SessionBloc>().add(const SessionInitialize());
        }
      }
    });
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Re-sync with SessionManager when app resumes from background
      // This ensures UI matches the background tracking state shown in notification
      context.read<SessionBloc>().add(const SessionInitialize());
      // Also refresh location
      _fetchCurrentLocation();
    }
  }

  /// Request location and notification permissions immediately on app entry
  Future<void> _requestEssentialPermissions() async {
    try {
      // Request location permissions first
      final locationResult = await _permissionService.requestLocationPermissions();
      if (!locationResult.granted) {
        debugPrint('Location permission not granted: ${locationResult.issue}');
      }
      
      // Request notification permission (returns bool directly)
      final notificationGranted = await _permissionService.requestNotificationPermission();
      if (!notificationGranted) {
        debugPrint('Notification permission not granted');
      }
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
    }
  }

  Future<void> _fetchCurrentLocation() async {
    if (!mounted) return;
    try {
      // First try to get last known position (fast)
      Position? position = await Geolocator.getLastKnownPosition();
      
      // If no last known, try current position
      if (position == null) {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always || 
            permission == LocationPermission.whileInUse) {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium, // Less aggressive
          ).timeout(const Duration(seconds: 10), onTimeout: () => throw 'Timeout');
        }
      }
      
      if (position != null && mounted) {
        final address = await GeocodingService.getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (mounted) {
          setState(() => _currentAddress = address);
        }
      } else if (mounted) {
        setState(() => _currentAddress = 'Location unavailable');
      }
    } catch (e) {
      debugPrint('Error fetching location: $e');
      if (mounted) {
        setState(() => _currentAddress = 'Location unavailable');
      }
    }
  }
  
  Future<void> _checkBatteryOptimization() async {
    final isDisabled = await _permissionService.isBatteryOptimizationDisabled();
    if (!isDisabled && mounted && !_batteryDialogShown) {
      _batteryDialogShown = true;
      _showBatteryOptimizationDialog();
    }
  }

  void _showBatteryOptimizationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.battery_alert_rounded,
            color: Colors.orange,
            size: 40,
          ),
        ),
        title: const Text('Disable Battery Optimization'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'For reliable location tracking, please disable battery optimization for this app.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
            Text(
              'Without this, tracking may stop when the app is in background.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _permissionService.requestBatteryOptimizationDisabled();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  bool _canTransitionNow() {
    if (_transitionInProgress) return false;
    if (_lastTransitionAt != null &&
        DateTime.now().difference(_lastTransitionAt!) < _transitionCooldown) {
      return false;
    }
    return true;
  }

  void _onPresentTapped() {
    if (!_canTransitionNow()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait a moment before starting again'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _transitionInProgress = true;
    _lastTransitionAt = DateTime.now();
    context.read<SessionBloc>().add(const SessionStartRequested());
    // Release the guard after the cooldown so subsequent taps are accepted.
    Future.delayed(_transitionCooldown, () {
      if (mounted) _transitionInProgress = false;
    });
  }

  void _onPauseTapped() {
    context.read<SessionBloc>().add(const SessionPauseRequested());
  }

  void _onResumeTapped() {
    context.read<SessionBloc>().add(const SessionResumeRequested());
  }

  Future<void> _onWorkDoneTapped() async {
    if (!_canTransitionNow()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stopping in progress...'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final sessionState = context.read<SessionBloc>().state;
    final distanceKm = sessionState.currentDistanceKm;
    final durSec = sessionState.duration.inSeconds;
    final currentSession = sessionState.currentSession;

    // Guard against accidental Work Done tap on a session that just started
    // and hasn't traveled any real distance yet. Without this, the user can
    // tap Present -> Work Done in rapid succession and create a useless 0 km
    // session that LOOKS like a tracking bug.
    if (durSec < 30 || distanceKm < 0.1) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 40),
          title: const Text('End session so soon?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your session has only run for ' +
                    (durSec < 60
                        ? '${durSec}s'
                        : '${(durSec / 60).toStringAsFixed(0)} min') +
                    ' and ${distanceKm.toStringAsFixed(2)} km.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'GPS needs ~30 seconds and some movement to lock in accurate distance. Ending now will record this as a near-zero trip.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep Tracking'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('End Anyway'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    _transitionInProgress = true;
    _lastTransitionAt = DateTime.now();
    if (!mounted) return;
    context.read<SessionBloc>().add(const SessionStopRequested());
    Future.delayed(_transitionCooldown, () {
      if (mounted) _transitionInProgress = false;
    });

    // After session stops, prompt for fuel expense if distance > 0
    if (distanceKm > 0.1 && currentSession != null) {
      // Small delay to let session complete
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          PostSessionExpenseDialog.showIfNeeded(context, currentSession, distanceKm);
        }
      });
    }
  }

  void _handlePermissionRequired(List<PermissionIssue> issues) {
    // Show permission dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Location permission is required to track your work sessions.'),
            const SizedBox(height: 16),
            if (issues.contains(PermissionIssue.locationServicesDisabled))
              const Text('• Please enable location services'),
            if (issues.contains(PermissionIssue.locationPermanentlyDenied))
              const Text('• Please enable location in app settings'),
            if (issues.contains(PermissionIssue.batteryOptimizationEnabled))
              const Text('• Consider disabling battery optimization for reliable tracking'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              PermissionService().openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final employee = authState is AuthAuthenticated ? authState.employee : null;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Greeting + Name
            Text(
              _capitalize(employee?.name.split(' ').first ?? 'User'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 4),
            // Row 2: Location (Swiggy Style)
            BlocBuilder<SessionBloc, SessionState>(
              builder: (context, state) {
                // Determine address to show:
                // 1. From active session (live updates)
                // 2. From initial fetch
                // 3. Loading/Fallback
                
                String displayAddress = _currentAddress ?? 'Fetching location...';
                
                // If we have live coordinates, we could verify or update _currentAddress
                // But for simplicity/performance in this view, we'll rely on the header being "Current Location"
                // If state has lat/lng, we could trigger a reverse geocode if different from _currentAddress
                // For now, let's use the FutureBuilder pattern ONLY if we don't have _currentAddress yet OR if session is active
                
                if (state.isActive && state.lastLatitude != null && state.lastLongitude != null) {
                   return FutureBuilder<String>(
                    future: GeocodingService.getAddressFromCoordinates(
                      state.lastLatitude!,
                      state.lastLongitude!,
                    ),
                    builder: (context, snapshot) {
                      final location = snapshot.data ?? 'Updating...';
                      return _buildLocationRow(context, location);
                    },
                  );
                }
                
                return _buildLocationRow(context, displayAddress);
              },
            ),
          ],
        ),
        actions: [
          // Notifications
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.notifications_outlined),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
            onPressed: () {
              AppRouter.navigateTo(context, AppRouter.notifications);
            },
          ),
          // Profile menu
          PopupMenuButton<String>(
            icon: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              child: Text(
                employee?.name.substring(0, 1).toUpperCase() ?? 'U',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onSelected: (value) async {
              switch (value) {
                case 'profile':
                  AppRouter.navigateTo(context, AppRouter.profile);
                  break;
                case 'history':
                  AppRouter.navigateTo(context, AppRouter.myTimeline);
                  break;
                case 'product_guide':
                  AppRouter.navigateTo(context, AppRouter.productGuide);
                  break;
                case 'logout':
                  context.read<AuthBloc>().add(AuthSignOutRequested());
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Profile'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'history',
                child: ListTile(
                  leading: Icon(Icons.timeline),
                  title: Text('My Timeline'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'product_guide',
                child: ListTile(
                  leading: Icon(Icons.menu_book),
                  title: Text('Product Guide'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text('Sign Out', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: BlocConsumer<SessionBloc, SessionState>(
        listener: (context, state) {
          // Handle permission required
          if (state.status == SessionBlocStatus.permissionRequired) {
            _handlePermissionRequired(state.permissionIssues);
          }
          
          // Handle errors
          if (state.status == SessionBlocStatus.error && state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: Theme.of(context).colorScheme.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }

          // Show warnings - check if battery optimization warning and show dialog instead
          if (state.warnings.isNotEmpty && state.status == SessionBlocStatus.active) {
            for (final warning in state.warnings) {
              if (warning.toLowerCase().contains('battery optimization') && !_batteryDialogShown) {
                _batteryDialogShown = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _showBatteryOptimizationDialog();
                });
              } else if (!warning.toLowerCase().contains('battery optimization')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(warning),
                    backgroundColor: Colors.orange,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            }
          }

          // Stationary spot detected — show persistent banner with dismiss
          if (state.stationarySpotData != null) {
            final lat = (state.stationarySpotData!['lat'] as num?)?.toDouble() ?? 0;
            final lng = (state.stationarySpotData!['lng'] as num?)?.toDouble() ?? 0;
            final dur = state.stationarySpotData!['durationSec'] as int? ?? 0;
            final spotKey = '${lat.toStringAsFixed(6)}_${lng.toStringAsFixed(6)}_$dur';

            // Only show if this is a new/different stationary spot
            if (_lastStationarySpotKey != spotKey) {
              _lastStationarySpotKey = spotKey;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'Stopped for ${(dur / 60).ceil()} min. '
                      'Potential clients for BENZ found nearby!',
                    ),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 12),
                    action: SnackBarAction(
                      label: 'VIEW MAP',
                      textColor: Colors.white,
                      onPressed: () {
                        messenger.hideCurrentSnackBar();
                        context.read<SessionBloc>().add(const SessionStationarySpotDismissed());
                        AppRouter.navigateTo(
                          context,
                          AppRouter.tripMap,
                          arguments: TripMapArguments(
                            latitude: lat,
                            longitude: lng,
                            showNearby: true,
                          ),
                        );
                      },
                    ),
                  ),
                );
              });
            }
          } else {
            // Reset tracking when spot is cleared
            _lastStationarySpotKey = null;
          }
        },
        builder: (context, sessionState) {
          return RefreshIndicator(
            onRefresh: () async {
              context.read<SessionBloc>().add(const SessionLoadHistory());
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Session Card
                  _buildSessionCard(sessionState),
                  const SizedBox(height: 20),

                  // Next Achievement Widget
                  _buildNextAchievementCard(sessionState),
                  const SizedBox(height: 20),

                  // Quick Actions Grid
                  _buildQuickActions(context),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 0),
    );
  }

  Widget _buildSessionCard(SessionState sessionState) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: sessionState.isActive
              ? [
                  const Color(0xFF10B981), // Green
                  const Color(0xFF059669),
                ]
              : [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.secondary,
                ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (sessionState.isActive
                    ? const Color(0xFF10B981)
                    : Theme.of(context).colorScheme.primary)
                .withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status indicator
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: sessionState.isActive ? Colors.greenAccent : Colors.white54,
                  shape: BoxShape.circle,
                  boxShadow: sessionState.isActive
                      ? [
                          BoxShadow(
                            color: Colors.greenAccent.withValues(alpha: 0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                sessionState.isActive ? 'Session Active' : 'Not Tracking',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              if (sessionState.isActive) _buildGpsAccuracyChip(sessionState),
            ],
          ),
          const SizedBox(height: 20),
          
          // Distance display
          if (sessionState.isActive) ...[
            Text(
              'Distance Traveled',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  sessionState.distanceFormatted,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8, left: 4),
                  child: Text(
                    'km',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Duration
            Row(
              children: [
                const Icon(Icons.timer_outlined, color: Colors.white70, size: 16),
                const SizedBox(width: 4),
                Text(
                  sessionState.durationFormatted,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ] else ...[
            // Inactive state display
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.location_off_outlined,
                    size: 48,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap Present to start tracking',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          const SizedBox(height: 20),

          // Action buttons
          if (sessionState.isActive)
            Row(
              children: [
                // Pause/Resume button
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: sessionState.isPaused ? _onResumeTapped : _onPauseTapped,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: sessionState.isPaused
                            ? const Color(0xFF111827) // near-black for high visibility
                            : const Color(0xFF1F2937).withValues(alpha: 0.08),
                        foregroundColor: sessionState.isPaused
                            ? Colors.white
                            : const Color(0xFF111827),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            sessionState.isPaused ? Icons.play_arrow : Icons.pause,
                            size: 20,
                            color: sessionState.isPaused ? Colors.white : const Color(0xFF111827),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            sessionState.isPaused ? 'Resume Session' : 'Pause',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: sessionState.isPaused ? Colors.white : const Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Work Done button
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _onWorkDoneTapped,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF059669),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.stop_circle_outlined, size: 20),
                          SizedBox(width: 6),
                          Text(
                            'Work Done',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: sessionState.isLoading ? null : _onPresentTapped,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: sessionState.isLoading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_circle_outline, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Present',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }

  /// Live GPS accuracy chip shown while a session is active.
  /// Color-coded so the user can immediately tell if GPS is reliable:
  ///   green  <= 15m   (excellent)
  ///   amber  <= 35m   (ok)
  ///   red    >  35m   (poor - distance may be inaccurate)
  Widget _buildGpsAccuracyChip(SessionState sessionState) {
    final acc = sessionState.gpsAccuracyMeters;
    Color bg;
    Color fg;
    IconData icon;
    String label;
    if (acc == null) {
      bg = Colors.white.withValues(alpha: 0.15);
      fg = Colors.white;
      icon = Icons.gps_not_fixed;
      label = 'Acquiring GPS...';
    } else if (acc <= 15) {
      bg = Colors.greenAccent.withValues(alpha: 0.25);
      fg = Colors.white;
      icon = Icons.gps_fixed;
      label = 'GPS ${acc.toStringAsFixed(0)}m';
    } else if (acc <= 35) {
      bg = Colors.amberAccent.withValues(alpha: 0.25);
      fg = Colors.white;
      icon = Icons.gps_fixed;
      label = 'GPS ${acc.toStringAsFixed(0)}m';
    } else {
      bg = Colors.redAccent.withValues(alpha: 0.30);
      fg = Colors.white;
      icon = Icons.gps_off;
      label = 'Weak GPS ${acc.toStringAsFixed(0)}m';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        // First row - Live Location and How to Use
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.my_location_rounded,
                label: 'Live Location',
                onTap: _showLiveLocation,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.help_outline_rounded,
                label: 'How to Use',
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: const Row(
                        children: [
                          Icon(Icons.help_outline_rounded, color: Color(0xFF1976D2)),
                          SizedBox(width: 8),
                          Text('How to Use'),
                        ],
                      ),
                      content: const Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('1. Tap "Present" to start your day', style: TextStyle(fontSize: 14)),
                          SizedBox(height: 8),
                          Text('2. The app tracks your location & distance', style: TextStyle(fontSize: 14)),
                          SizedBox(height: 8),
                          Text('3. Use "Add Expense" to log expenses', style: TextStyle(fontSize: 14)),
                          SizedBox(height: 8),
                          Text('4. Check "My Timeline" for daily summary', style: TextStyle(fontSize: 14)),
                          SizedBox(height: 8),
                          Text('5. Use "Pause/Resume" for breaks (auto-pause after 15 min still)', style: TextStyle(fontSize: 14)),
                          SizedBox(height: 8),
                          Text('6. Tap "Work Done" when you finish', style: TextStyle(fontSize: 14)),
                          SizedBox(height: 12),
                          Text('💡 Keep location ON & battery optimization OFF for accurate tracking.',
                              style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Got it!'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Second row - BenzDesk Web and Add Expense
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.open_in_browser,
                label: 'BenzDesk Web',
                onTap: () async {
                  final url = Uri.parse('https://benzdesk.pages.dev');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.receipt_long_outlined,
                label: 'Add Expense',
                onTap: () {
                  AppRouter.navigateTo(context, AppRouter.addExpense);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Third row - Timeline and Settings
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.timeline_rounded,
                label: 'My Timeline',
                onTap: () {
                  AppRouter.navigateTo(context, AppRouter.myTimeline);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Fourth row - Debug Tests
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.science_outlined,
                label: 'Distance Tests',
                onTap: () {
                  AppRouter.navigateTo(context, AppRouter.debugDistanceTest);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.open_in_browser,
                label: 'BenzDesk Web',
                onTap: () async {
                  final url = Uri.parse('https://benzdesk.pages.dev');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Show live location dialog with current coordinates and address
  void _showLiveLocation() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'Getting your location...',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    try {
      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));

      // Get address from coordinates
      final address = await GeocodingService.getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Show location dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFC9A227).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Color(0xFFC9A227),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Your Location',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Address
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        address,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: const Color(0xFF334155),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Coordinates
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Coordinates',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF94A3B8),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Latitude',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                              Text(
                                position.latitude.toStringAsFixed(6),
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1A1A2E),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 30,
                          width: 1,
                          color: const Color(0xFFE2E8F0),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Longitude',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                ),
                                Text(
                                  position.longitude.toStringAsFixed(6),
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1A1A2E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Accuracy
              Row(
                children: [
                  const Icon(
                    Icons.gps_fixed,
                    size: 14,
                    color: Color(0xFF22C55E),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Accuracy: ${position.accuracy.toStringAsFixed(1)}m',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Close',
                style: GoogleFonts.inter(
                  color: const Color(0xFF1A1A2E),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not get location: $e'),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNextAchievementCard(SessionState sessionState) {
    final nextData = AchievementEngine.getNextAchievementData(
      sessionState.sessionHistory,
      sessionState.monthlyStats,
    );

    if (nextData == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerTheme.color ?? Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.emoji_events, color: const Color(0xFFB8860B).withValues(alpha: 0.6)),
            const SizedBox(width: 12),
            Text(
              'All achievements unlocked!',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final def = nextData.def;
    final progress = nextData.progress;
    final progressPercent = (progress * 100).toInt();

    return GestureDetector(
      onTap: () => AppRouter.navigateTo(context, AppRouter.achievements),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF0066CC).withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0066CC).withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0066CC).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.emoji_events, color: Color(0xFF0066CC), size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  'Next Achievement',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0066CC),
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0066CC).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$progressPercent%',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0066CC),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              def.title,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              def.subtitle,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.textSecondaryLight,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: const Color(0xFFF3F4F6),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0066CC)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRow(BuildContext context, String location) {
    return Row(
      children: [
        Icon(
          Icons.location_on,
          size: 14,
          color: Colors.orange[700],
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            location,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.keyboard_arrow_down,
          size: 16,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ],
    );
  }

  /// Capitalize first letter of a string
  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }
}
