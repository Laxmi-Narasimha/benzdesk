import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/router/app_router.dart';
import '../../services/geocoding_service.dart';
import '../../services/permission_service.dart';
import '../../services/tracking_service.dart';
import '../blocs/auth/auth_bloc.dart';
import '../blocs/session/session_bloc.dart';
import '../widgets/stats_card.dart';
import '../widgets/app_bottom_nav_bar.dart';
import 'settings_screen.dart';

/// Main home screen with session tracking
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PermissionService _permissionService = PermissionService();
  bool _batteryDialogShown = false;
  String? _currentAddress;
  bool _isLoadingAddress = false;

  @override
  void initState() {
    super.initState();
    // Load session history
    context.read<SessionBloc>().add(const SessionLoadHistory());
    // Check battery optimization on first load
    _checkBatteryOptimization();
    // Fetch initial location
    _fetchCurrentLocation();
  }

  Future<void> _fetchCurrentLocation() async {
    if (!mounted) return;
    setState(() => _isLoadingAddress = true);
    
    try {
      final position = await TrackingService.getCurrentLocation();
      if (position != null && mounted) {
        final address = await GeocodingService.getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );
        setState(() => _currentAddress = address);
      }
    } catch (e) {
      debugPrint('Error fetching location: $e');
    } finally {
      if (mounted) setState(() => _isLoadingAddress = false);
    }
  }
  // The block starts at 22 (class definition start)
  
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
            color: Colors.orange.withOpacity(0.1),
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

  void _onPresentTapped() {
    context.read<SessionBloc>().add(const SessionStartRequested());
  }

  void _onWorkDoneTapped() {
    context.read<SessionBloc>().add(const SessionStopRequested());
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
              '${_capitalize(employee?.name.split(' ').first ?? 'User')}',
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
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
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
                  AppRouter.navigateTo(context, AppRouter.sessionHistory);
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
                  leading: Icon(Icons.history),
                  title: Text('Session History'),
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
                  
                  // Stats Cards
                  _buildStatsSection(context, sessionState),
                  const SizedBox(height: 20),
                  
                  // Quick Actions
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
                .withOpacity(0.3),
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
                            color: Colors.greenAccent.withOpacity(0.5),
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
              if (sessionState.isActive) ...[
                const Icon(
                  Icons.gps_fixed,
                  color: Colors.white70,
                  size: 18,
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          
          // Distance display
          if (sessionState.isActive) ...[
            Text(
              'Distance Traveled',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
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
                    color: Colors.white.withOpacity(0.6),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap Present to start tracking',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          const SizedBox(height: 20),
          
          // Action button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: sessionState.isLoading
                  ? null
                  : sessionState.isActive
                      ? _onWorkDoneTapped
                      : _onPresentTapped,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: sessionState.isActive
                    ? const Color(0xFF059669)
                    : Theme.of(context).colorScheme.primary,
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
                          sessionState.isActive
                              ? const Color(0xFF059669)
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          sessionState.isActive
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outline,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          sessionState.isActive ? 'Work Done' : 'Present',
                          style: const TextStyle(
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

  Widget _buildStatsSection(BuildContext context, SessionState sessionState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's Progress",
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatsCard(
                title: 'Distance',
                value: '${sessionState.currentDistanceKm.toStringAsFixed(1)} km',
                icon: Icons.route_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatsCard(
                title: 'Duration',
                value: sessionState.durationFormatted,
                icon: Icons.timer_outlined,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ],
        ),
      ],
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
        // First row - Live Location and Settings
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
        // Second row - Expenses and History
        Row(
          children: [
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
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.history,
                label: 'View History',
                onTap: () {
                  AppRouter.navigateTo(context, AppRouter.sessionHistory);
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
                  color: const Color(0xFFC9A227).withOpacity(0.1),
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
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
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
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.keyboard_arrow_down,
          size: 16,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
        ),
      ],
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Capitalize first letter of a string
  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }
}
