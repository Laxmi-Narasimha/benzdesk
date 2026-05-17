import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:benzmobitraq_mobile/services/tracking_service.dart';

/// In-app diagnostics screen — the user can open this from Settings to
/// see, in real time, what the tracking pipeline is actually doing.
/// Designed so we (support) can ask "open Settings → Diagnostics and
/// read the values to me" without needing logcat or a debug APK.
///
/// Shows:
///   - Live GPS fix (lat/lng/accuracy/speed/heading) updating every
///     second from the raw Geolocator stream (NOT the per-fix-filter
///     output) so the user sees what the chip itself reports.
///   - Last LocationUpdate emitted by the BG isolate (post-filter,
///     after the cluster gate). Differences between this and the raw
///     fix tell us the filter is rejecting points (which is what we
///     want when stationary).
///   - BG service state (running, current session id, total distance,
///     paused flag).
///   - Last error from the BG isolate.
///   - Permission grant status for the 5 permissions tracking depends on.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  StreamSubscription<Position>? _posSub;
  Position? _lastRaw;
  DateTime? _lastRawAt;
  LocationUpdate? _lastFiltered;
  DateTime? _lastFilteredAt;
  String? _lastError;
  DateTime? _lastErrorAt;
  bool _serviceRunning = false;
  String? _sessionId;
  bool _isPaused = false;
  double _totalDistanceM = 0;

  Timer? _stateTicker;
  PackageInfo? _pkg;
  Map<String, bool> _perms = {};

  // We piggyback on TrackingService's existing static callbacks. Save
  // and restore prior handlers so we don't break the live UI in
  // home_screen while diagnostics is open.
  Function(LocationUpdate)? _priorLocationCb;
  Function(String)? _priorErrorCb;
  Function(bool)? _priorTrackingCb;

  @override
  void initState() {
    super.initState();
    _attachCallbacks();
    _startRawStream();
    _startStateTicker();
    _loadPkg();
    _loadPerms();
  }

  void _attachCallbacks() {
    _priorLocationCb = TrackingService.onLocationUpdate;
    _priorErrorCb = TrackingService.onError;
    _priorTrackingCb = TrackingService.onTrackingStateChanged;

    TrackingService.onLocationUpdate = (u) {
      _priorLocationCb?.call(u);
      if (!mounted) return;
      setState(() {
        _lastFiltered = u;
        _lastFilteredAt = DateTime.now();
        _totalDistanceM = u.totalDistance;
      });
    };
    TrackingService.onError = (msg) {
      _priorErrorCb?.call(msg);
      if (!mounted) return;
      setState(() {
        _lastError = msg;
        _lastErrorAt = DateTime.now();
      });
    };
    TrackingService.onTrackingStateChanged = (isTracking) {
      _priorTrackingCb?.call(isTracking);
      if (!mounted) return;
      setState(() => _serviceRunning = isTracking);
    };
  }

  void _startRawStream() {
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0, // 0 = every fix, ~1 Hz
      ),
    ).listen(
      (p) {
        if (!mounted) return;
        setState(() {
          _lastRaw = p;
          _lastRawAt = DateTime.now();
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _lastError = 'GPS stream error: $e';
          _lastErrorAt = DateTime.now();
        });
      },
      cancelOnError: false,
    );
  }

  void _startStateTicker() {
    _stateTicker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      try {
        final running = await TrackingService.isTracking();
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final sid = prefs.getString('tracking_session_id');
        final paused = prefs.getBool('tracking_is_paused') ?? false;
        final dist = prefs.getDouble('tracking_total_distance') ?? 0;
        if (!mounted) return;
        setState(() {
          _serviceRunning = running;
          _sessionId = sid;
          _isPaused = paused;
          if (_lastFiltered == null) _totalDistanceM = dist;
        });
      } catch (_) {}
    });
  }

  Future<void> _loadPkg() async {
    try {
      final p = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _pkg = p);
    } catch (_) {}
  }

  Future<void> _loadPerms() async {
    final results = <String, bool>{};
    for (final entry in const [
      ('Location (while in use)', Permission.locationWhenInUse),
      ('Location (always)', Permission.locationAlways),
      ('Notifications', Permission.notification),
      ('Activity recognition', Permission.activityRecognition),
      ('Ignore battery optimizations', Permission.ignoreBatteryOptimizations),
    ]) {
      try {
        final s = await entry.$2.status;
        results[entry.$1] = s.isGranted;
      } catch (_) {
        results[entry.$1] = false;
      }
    }
    if (!mounted) return;
    setState(() => _perms = results);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateTicker?.cancel();
    // Restore prior callbacks so home_screen keeps receiving updates.
    TrackingService.onLocationUpdate = _priorLocationCb;
    TrackingService.onError = _priorErrorCb;
    TrackingService.onTrackingStateChanged = _priorTrackingCb;
    super.dispose();
  }

  String _fmtAgo(DateTime? t) {
    if (t == null) return '—';
    final ms = DateTime.now().difference(t).inMilliseconds;
    if (ms < 1000) return '${ms}ms ago';
    final s = ms / 1000;
    if (s < 60) return '${s.toStringAsFixed(1)}s ago';
    return '${(s / 60).toStringAsFixed(1)}m ago';
  }

  String _fmt(double? v, {int d = 6, String unit = ''}) {
    if (v == null || v.isNaN || v.isInfinite) return '—';
    return '${v.toStringAsFixed(d)}$unit';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Diagnostics',
          style: GoogleFonts.inter(
            color: const Color(0xFF1A1A2E),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy report',
            icon: const Icon(Icons.copy_all, color: Color(0xFF1A1A2E)),
            onPressed: _copyReport,
          ),
          IconButton(
            tooltip: 'Refresh permissions',
            icon: const Icon(Icons.refresh, color: Color(0xFF1A1A2E)),
            onPressed: _loadPerms,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section('App', [
              _kv('Package', _pkg?.packageName ?? '—'),
              _kv('Version',
                  '${_pkg?.version ?? '—'} (${_pkg?.buildNumber ?? '—'})'),
            ]),
            const SizedBox(height: 12),
            _section('Background service', [
              _kv('Running', _serviceRunning ? 'YES' : 'no'),
              _kv('Session id', _sessionId ?? '—'),
              _kv('Paused', _isPaused ? 'YES' : 'no'),
              _kv('Total distance',
                  '${(_totalDistanceM / 1000).toStringAsFixed(3)} km'),
            ]),
            const SizedBox(height: 12),
            _section('Raw GPS fix (updates every second)', [
              _kv('Latitude', _fmt(_lastRaw?.latitude, d: 6)),
              _kv('Longitude', _fmt(_lastRaw?.longitude, d: 6)),
              _kv('Accuracy', _fmt(_lastRaw?.accuracy, d: 1, unit: ' m')),
              _kv('Speed (chip)',
                  _fmt((_lastRaw?.speed ?? 0) * 3.6, d: 2, unit: ' km/h')),
              _kv('Heading', _fmt(_lastRaw?.heading, d: 1, unit: '°')),
              _kv('Altitude', _fmt(_lastRaw?.altitude, d: 1, unit: ' m')),
              _kv('Last update', _fmtAgo(_lastRawAt)),
            ]),
            const SizedBox(height: 12),
            _section('Filtered fix (after cluster gate, what we record)', [
              _kv('Latitude', _fmt(_lastFiltered?.latitude, d: 6)),
              _kv('Longitude', _fmt(_lastFiltered?.longitude, d: 6)),
              _kv('Accuracy',
                  _fmt(_lastFiltered?.accuracy, d: 1, unit: ' m')),
              _kv('Speed',
                  _fmt((_lastFiltered?.speed ?? 0) * 3.6, d: 2, unit: ' km/h')),
              _kv('Counts for distance',
                  (_lastFiltered?.countsForDistance ?? false) ? 'yes' : 'no'),
              _kv('Δ from previous',
                  _fmt(_lastFiltered?.distanceDeltaM, d: 1, unit: ' m')),
              _kv('Last update', _fmtAgo(_lastFilteredAt)),
            ]),
            const SizedBox(height: 12),
            _section('Permissions', [
              for (final e in _perms.entries)
                _kv(e.key, e.value ? '✓ granted' : '✗ NOT granted',
                    bad: !e.value),
            ]),
            const SizedBox(height: 12),
            _section('Last error', [
              _kv('Message', _lastError ?? '— (none)', bad: _lastError != null),
              _kv('When', _fmtAgo(_lastErrorAt)),
            ]),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Send a screenshot of this screen if tracking is misbehaving.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyReport() async {
    final buf = StringBuffer()
      ..writeln('BenzMobiTraq diagnostics')
      ..writeln('Generated: ${DateTime.now().toIso8601String()}')
      ..writeln('Version: ${_pkg?.version}+${_pkg?.buildNumber}')
      ..writeln('Service running: $_serviceRunning')
      ..writeln('Session: $_sessionId  paused=$_isPaused')
      ..writeln(
          'Total distance: ${(_totalDistanceM / 1000).toStringAsFixed(3)} km')
      ..writeln('Raw fix: lat=${_lastRaw?.latitude} lng=${_lastRaw?.longitude} '
          'acc=${_lastRaw?.accuracy} speed=${_lastRaw?.speed} '
          'at=${_fmtAgo(_lastRawAt)}')
      ..writeln('Filtered: lat=${_lastFiltered?.latitude} '
          'lng=${_lastFiltered?.longitude} '
          'counts=${_lastFiltered?.countsForDistance} '
          'delta=${_lastFiltered?.distanceDeltaM} at=${_fmtAgo(_lastFilteredAt)}')
      ..writeln('Permissions: $_perms')
      ..writeln('Last error: $_lastError (${_fmtAgo(_lastErrorAt)})');
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostics report copied to clipboard')),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF64748B),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {bool bad = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              k,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: GoogleFonts.robotoMono(
                fontSize: 13,
                color: bad ? const Color(0xFFDC2626) : const Color(0xFF1A1A2E),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
