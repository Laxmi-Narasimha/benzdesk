import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:benzmobitraq_mobile/core/di/injection.dart';
import 'package:benzmobitraq_mobile/data/datasources/local/preferences_local.dart';
import 'package:benzmobitraq_mobile/data/models/location_point_model.dart';
import 'package:benzmobitraq_mobile/data/repositories/location_repository.dart';
import 'package:benzmobitraq_mobile/presentation/blocs/session/session_bloc.dart';
import 'package:benzmobitraq_mobile/presentation/widgets/draggable_session_pill.dart';
import 'package:benzmobitraq_mobile/presentation/widgets/post_session_expense_dialog.dart';
import 'package:benzmobitraq_mobile/services/google_maps_directions_service.dart';
import 'package:benzmobitraq_mobile/services/session_manager.dart';

/// Live, in-app map view shown while a session is active.
///
/// Use cases this serves:
///   - Driver opens it on a car mount and uses the breadcrumb trail
///     as a "where have I been" view (NOT turn-by-turn navigation —
///     reps still use Google Maps for that; this is supplementary).
///   - Bike rider tucks the phone away; the session keeps tracking via
///     the background service whether this screen is open or not.
///   - Either: the rep gets a one-tap arrival notification when they
///     enter the destination geofence, plus a floating session pill
///     they can drag to any corner of the screen.
///
/// **Important**: closing this screen does NOT end the session.
/// Tracking is owned by the background isolate and continues until
/// the rep explicitly taps Work Done (here or from the home screen).
class LiveSessionMapScreen extends StatefulWidget {
  const LiveSessionMapScreen({super.key});

  @override
  State<LiveSessionMapScreen> createState() => _LiveSessionMapScreenState();
}

class _LiveSessionMapScreenState extends State<LiveSessionMapScreen> {
  final Completer<GoogleMapController> _mapCtrlCompleter =
      Completer<GoogleMapController>();

  late final SessionManager _sessionManager;
  late final PreferencesLocal _preferences;
  late final LocationRepository _locationRepo;

  StreamSubscription<ManagerSessionState>? _stateSub;
  ManagerSessionState? _state;

  // Camera-follow toggle. Auto-follows the user; pauses when the user
  // pans the map; resumes when the user taps the "Recenter" FAB.
  bool _followUser = true;

  // Pill UI state (loaded from prefs).
  PillCorner _pillCorner = PillCorner.bottomRight;
  bool _pillCollapsed = false;

  // Destination cached at session start.
  Map<String, dynamic>? _destination;
  LatLng? _destinationLatLng;
  String? _destinationName;

  // Arrival state: did we already cross the 100m geofence?
  bool _arrived = false;
  bool _arrivalBannerVisible = false;
  Timer? _arrivalBannerTimer;

  // Polyline of breadcrumbs. We render two layers: the full local
  // history (loaded once from SQLite at open) and the live tail
  // (appended as new fixes arrive).
  final List<LatLng> _breadcrumbs = [];
  bool _historyLoaded = false;

  /// Decoded polyline of the optimal driving route from start → destination,
  /// fetched once via Google Directions API at session start. Drawn as a
  /// muted gray line under the live blue breadcrumb trail so the rep can
  /// see at-a-glance how their actual path compares to the planned one.
  /// Null when there's no destination or when the API call failed.
  final List<LatLng> _plannedRoute = [];
  bool _plannedRouteLoading = false;
  double? _plannedRouteKm;
  int? _plannedRouteEtaSec;

  // Initial camera position — populated lazily from the first fix.
  CameraPosition? _initialCamera;

  static const double _arrivalRadiusM = 100.0;

  @override
  void initState() {
    super.initState();
    _sessionManager = getIt<SessionManager>();
    _preferences = getIt<PreferencesLocal>();
    _locationRepo = getIt<LocationRepository>();

    _state = _sessionManager.currentState;
    _pillCorner = PillCorner.fromString(_preferences.getSessionPillCorner());
    _pillCollapsed = _preferences.getSessionPillCollapsed();
    _destination = _preferences.getActiveDestination();
    if (_destination != null) {
      final lat = (_destination!['lat'] as num?)?.toDouble();
      final lng = (_destination!['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        _destinationLatLng = LatLng(lat, lng);
      }
      _destinationName = _destination!['name'] as String?;
    }

    _initFromInitialState();
    _stateSub = _sessionManager.stateStream.listen(_onStateChanged);

    _loadHistoryPoints();
    // Fire-and-forget — the planned-route polyline is a nice-to-have
    // overlay; the map still works without it. Fetched once at open.
    unawaited(_fetchPlannedRoute());
  }

  Future<void> _fetchPlannedRoute() async {
    final session = _state?.session;
    if (session == null || _destinationLatLng == null) return;
    final startLat = session.startLatitude;
    final startLng = session.startLongitude;
    if (startLat == null || startLng == null) return;
    if (_plannedRouteLoading || _plannedRoute.isNotEmpty) return;
    setState(() => _plannedRouteLoading = true);
    try {
      final r = await GoogleMapsDirectionsService.getDrivingDistance(
        startLat: startLat,
        startLng: startLng,
        endLat: _destinationLatLng!.latitude,
        endLng: _destinationLatLng!.longitude,
      );
      if (!mounted) return;
      if (r != null && r.polyline != null && r.polyline!.isNotEmpty) {
        final decoded = _decodePolyline(r.polyline!);
        setState(() {
          _plannedRoute
            ..clear()
            ..addAll(decoded);
          _plannedRouteKm = r.distanceKm;
          _plannedRouteEtaSec = r.durationSeconds;
        });
      }
    } catch (_) {
      // Silent: planned route is non-essential
    } finally {
      if (mounted) setState(() => _plannedRouteLoading = false);
    }
  }

  /// Decodes a Google-encoded polyline (precision 5) into LatLng points.
  /// Same algorithm as encodePolyline in the Edge Function's geo.ts,
  /// just in reverse. Inlined here so we don't take a dependency on
  /// the (heavier) flutter_polyline_points package.
  List<LatLng> _decodePolyline(String encoded) {
    final list = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;
      list.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return list;
  }

  Future<void> _openInGoogleMaps() async {
    if (_destinationLatLng == null) return;
    final lat = _destinationLatLng!.latitude;
    final lng = _destinationLatLng!.longitude;
    // The `google.navigation:` URI starts Google Maps DIRECTLY in
    // navigation mode (skips the directions screen, jumps to voice
    // turn-by-turn from current location). Falls back to a generic
    // geo: URI on devices without Google Maps installed.
    final navUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final geoUri = Uri.parse(
      'geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(_destinationName ?? "Destination")})',
    );
    try {
      if (await canLaunchUrl(navUri)) {
        await launchUrl(navUri, mode: LaunchMode.externalApplication);
        return;
      }
      await launchUrl(geoUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Last-ditch — open in browser
      final webUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
      );
      try {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _arrivalBannerTimer?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  void _initFromInitialState() {
    final loc = _state?.lastLocation;
    if (loc != null) {
      _initialCamera = CameraPosition(
        target: LatLng(loc.latitude, loc.longitude),
        zoom: 16.5,
      );
    } else if (_destinationLatLng != null) {
      _initialCamera = CameraPosition(
        target: _destinationLatLng!,
        zoom: 15.5,
      );
    } else {
      // India centroid fallback so the map isn't blank while we wait.
      _initialCamera = const CameraPosition(
        target: LatLng(20.5937, 78.9629),
        zoom: 5,
      );
    }
  }

  Future<void> _loadHistoryPoints() async {
    final sid = _state?.session?.id;
    if (sid == null) {
      setState(() => _historyLoaded = true);
      return;
    }
    try {
      final points = await _locationRepo.getLocalSessionPoints(sid);
      if (!mounted) return;
      // Drop teleport spikes and mocks from the polyline (same
      // filter the upload path uses) so the map line doesn't zigzag.
      final clean = <LatLng>[];
      LocationPointModel? prev;
      for (final p in points) {
        if (p.isMock) continue;
        if (p.accuracy != null && p.accuracy! > 80) continue;
        if (prev != null) {
          final dt = p.recordedAt.difference(prev.recordedAt).inSeconds;
          if (dt > 0) {
            final d = Geolocator.distanceBetween(
                prev.latitude, prev.longitude, p.latitude, p.longitude);
            final implied = (d / dt) * 3.6;
            if (implied > 200) {
              prev = p;
              continue;
            }
          }
        }
        clean.add(LatLng(p.latitude, p.longitude));
        prev = p;
      }
      setState(() {
        _breadcrumbs
          ..clear()
          ..addAll(clean);
        _historyLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _historyLoaded = true);
    }
  }

  void _onStateChanged(ManagerSessionState s) {
    if (!mounted) return;
    final prevLoc = _state?.lastLocation;
    setState(() => _state = s);

    final loc = s.lastLocation;
    if (loc == null) return;

    // Append to live polyline if this is a new fix.
    final newPoint = LatLng(loc.latitude, loc.longitude);
    if (_breadcrumbs.isEmpty ||
        prevLoc == null ||
        prevLoc.latitude != loc.latitude ||
        prevLoc.longitude != loc.longitude) {
      _breadcrumbs.add(newPoint);
    }

    // Camera follow.
    if (_followUser) {
      _mapCtrlCompleter.future.then((c) {
        c.animateCamera(CameraUpdate.newLatLng(newPoint));
      });
    }

    // Arrival check.
    if (!_arrived && _destinationLatLng != null) {
      final d = Geolocator.distanceBetween(
        loc.latitude,
        loc.longitude,
        _destinationLatLng!.latitude,
        _destinationLatLng!.longitude,
      );
      if (d <= _arrivalRadiusM) {
        _triggerArrival();
      }
    }
  }

  Future<void> _triggerArrival() async {
    setState(() {
      _arrived = true;
      _arrivalBannerVisible = true;
    });
    // Mild haptic so the user notices even if the phone is on a mount.
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 120));
    HapticFeedback.mediumImpact();
    // Auto-hide the banner after 10s; user can also dismiss.
    _arrivalBannerTimer?.cancel();
    _arrivalBannerTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _arrivalBannerVisible = false);
    });
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _onPauseResume() {
    final isPaused = _state?.isPaused ?? false;
    final bloc = context.read<SessionBloc>();
    if (isPaused) {
      bloc.add(const SessionResumeRequested());
    } else {
      bloc.add(const SessionPauseRequested());
    }
  }

  Future<void> _onWorkDone() async {
    // Confirm with a small bottom sheet — Work Done is destructive
    // (ends the session, can't undo without admin support).
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ConfirmEndSessionSheet(),
    );
    if (ok != true || !mounted) return;
    final sessionToEnd = _state?.session;
    final distanceKm = (_state?.currentDistanceMeters ?? 0) / 1000.0;
    context.read<SessionBloc>().add(const SessionStopRequested());
    // Pop back to the home screen; the post-session expense dialog
    // is triggered by SessionBloc on the home screen, but if the rep
    // started from here we surface it directly too.
    Navigator.of(context).pop();
    if (sessionToEnd != null && distanceKm > 0.1) {
      // Best-effort surfacing of the expense dialog on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          PostSessionExpenseDialog.showIfNeeded(
            context,
            sessionToEnd,
            distanceKm,
          );
        }
      });
    }
  }

  Future<void> _recenter() async {
    final loc = _state?.lastLocation;
    if (loc == null) return;
    setState(() => _followUser = true);
    final c = await _mapCtrlCompleter.future;
    await c.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(loc.latitude, loc.longitude), 17),
    );
  }

  void _onUserMapGesture() {
    // The user is interacting with the map — pause auto-follow.
    if (_followUser) setState(() => _followUser = false);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final loc = _state?.lastLocation;
    final isPaused = _state?.isPaused ?? false;
    final distanceKm = (_state?.currentDistanceMeters ?? 0) / 1000.0;
    final duration = _state?.duration ?? Duration.zero;
    final speedKmh =
        loc != null && loc.speed.isFinite ? loc.speed * 3.6 : null;

    // Distance to destination — only meaningful when we have BOTH the
    // user's location and a destination.
    double? distanceToDestKm;
    if (loc != null && _destinationLatLng != null) {
      distanceToDestKm = Geolocator.distanceBetween(
            loc.latitude,
            loc.longitude,
            _destinationLatLng!.latitude,
            _destinationLatLng!.longitude,
          ) /
          1000.0;
    }

    final markers = <Marker>{};
    if (loc != null) {
      markers.add(Marker(
        markerId: const MarkerId('me'),
        position: LatLng(loc.latitude, loc.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'You'),
        rotation: (loc.heading != null && loc.heading!.isFinite)
            ? loc.heading!
            : 0,
        flat: true,
        anchor: const Offset(0.5, 0.5),
      ));
    }
    if (_destinationLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: _destinationLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          _arrived ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRose,
        ),
        infoWindow: InfoWindow(
          title: _destinationName ?? 'Destination',
          snippet: _arrived ? 'Arrived' : 'Destination',
        ),
      ));
    }
    if (_state?.session != null) {
      final start = _state!.session!;
      if (start.startLatitude != null && start.startLongitude != null) {
        markers.add(Marker(
          markerId: const MarkerId('start'),
          position: LatLng(start.startLatitude!, start.startLongitude!),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueViolet),
          infoWindow: const InfoWindow(title: 'Start'),
        ));
      }
    }

    final polylines = <Polyline>{};
    // Planned route — rendered UNDER the live trail. Muted gray so the
    // rep's actual blue path stands out on top. If the rep deviates,
    // they can see at a glance.
    if (_plannedRoute.length >= 2) {
      polylines.add(Polyline(
        polylineId: const PolylineId('planned'),
        points: _plannedRoute,
        color: Colors.grey.shade500,
        width: 6,
        geodesic: false,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: 0,
      ));
    }
    // Live breadcrumb trail — bright blue, drawn ON TOP of planned route.
    if (_breadcrumbs.length >= 2) {
      polylines.add(Polyline(
        polylineId: const PolylineId('trail'),
        points: _breadcrumbs,
        color: Theme.of(context).colorScheme.primary,
        width: 6,
        geodesic: true,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: 1,
      ));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ─────────── MAP ────────────────────────────────────────────────
          if (_initialCamera != null)
            GoogleMap(
              initialCameraPosition: _initialCamera!,
              myLocationEnabled: false, // we draw our own pin
              myLocationButtonEnabled: false,
              compassEnabled: true,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              tiltGesturesEnabled: true,
              markers: markers,
              polylines: polylines,
              onMapCreated: (c) {
                if (!_mapCtrlCompleter.isCompleted) {
                  _mapCtrlCompleter.complete(c);
                }
              },
              onCameraMoveStarted: _onUserMapGesture,
            )
          else
            const Center(child: CircularProgressIndicator()),

          // ─────────── TOP BAR (back + destination chip) ──────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            right: 8,
            child: Row(
              children: [
                _RoundIcon(
                  icon: Icons.arrow_back,
                  onTap: () => Navigator.of(context).maybePop(),
                  tooltip: 'Back to home',
                ),
                const SizedBox(width: 8),
                if (_destinationName != null)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _arrived
                                ? Icons.check_circle
                                : Icons.flag_outlined,
                            size: 16,
                            color: _arrived
                                ? Colors.green
                                : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _destinationName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Open in Google Maps — auto-starts turn-by-turn nav.
                // Only shows when there's an actual destination to drive
                // to. The rep can use this for navigation while our
                // tracking continues in the BG.
                if (_destinationLatLng != null) ...[
                  const SizedBox(width: 8),
                  _RoundIcon(
                    icon: Icons.navigation,
                    onTap: _openInGoogleMaps,
                    tooltip: 'Navigate in Google Maps',
                    color: const Color(0xFF1A73E8),
                  ),
                ],
              ],
            ),
          ),

          // ─────────── PLANNED-ROUTE INFO PILL ──────────────────────────────
          // When we know the optimal route distance + ETA, show it as a
          // small chip below the top bar. Free real-estate; orients the
          // rep on what they're about to drive.
          if (_plannedRouteKm != null && _plannedRouteEtaSec != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.route, size: 14, color: Colors.grey.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Route ${_plannedRouteKm!.toStringAsFixed(1)} km · '
                      '${(_plannedRouteEtaSec! / 60).round()} min',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ─────────── RECENTER FAB ───────────────────────────────────────
          if (loc != null)
            Positioned(
              right: 14,
              top: MediaQuery.of(context).padding.top + 64,
              child: _RoundIcon(
                icon: _followUser ? Icons.gps_fixed : Icons.gps_not_fixed,
                onTap: _recenter,
                tooltip: _followUser ? 'Following you' : 'Recenter',
                color: _followUser
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade700,
              ),
            ),

          // ─────────── ARRIVAL BANNER ─────────────────────────────────────
          if (_arrivalBannerVisible)
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              left: 16,
              right: 16,
              child: _ArrivalBanner(
                destinationName: _destinationName ?? 'destination',
                onDismiss: () =>
                    setState(() => _arrivalBannerVisible = false),
              ),
            ),

          // ─────────── DRAGGABLE PILL ─────────────────────────────────────
          DraggableSessionPill(
            distanceKm: distanceKm,
            duration: duration,
            speedKmh: speedKmh,
            isPaused: isPaused,
            destinationName: _destinationName,
            distanceToDestinationKm: distanceToDestKm,
            arrived: _arrived,
            onPauseResume: _onPauseResume,
            onWorkDone: _onWorkDone,
            initialCorner: _pillCorner,
            initialCollapsed: _pillCollapsed,
            onCornerChanged: (c) {
              _pillCorner = c;
              _preferences.setSessionPillCorner(c.value);
            },
            onCollapsedChanged: (c) {
              _pillCollapsed = c;
              _preferences.setSessionPillCollapsed(c);
            },
          ),

          // ─────────── HISTORY LOADER OVERLAY ─────────────────────────────
          if (!_historyLoaded)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// SMALL HELPER WIDGETS
// =============================================================================

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color? color;
  const _RoundIcon({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 22, color: color ?? Colors.grey.shade800),
          ),
        ),
      ),
    );
  }
}

class _ArrivalBanner extends StatelessWidget {
  final String destinationName;
  final VoidCallback onDismiss;
  const _ArrivalBanner({
    required this.destinationName,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (_, v, child) {
        return Transform.translate(
          offset: Offset(0, -20 * (1 - v)),
          child: Opacity(opacity: v.clamp(0, 1), child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green.shade600, Colors.green.shade700],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'You\'ve arrived',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$destinationName · Session still tracking',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, color: Colors.white, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmEndSessionSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'End this session?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'You can also Pause if you\'re just taking a break.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Cancel'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('End session'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

