import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:benzmobitraq_mobile/services/oem_autostart_service.dart';

/// Status of one permission row in the setup dialog.
enum _PermStatus {
  granted,
  partial, // e.g. foreground location granted but not background
  missing,
  unknown,
}

class _PermItem {
  final String key;
  final String title;
  final String why;
  _PermStatus status;
  Future<void> Function() onGrant;

  _PermItem({
    required this.key,
    required this.title,
    required this.why,
    this.status = _PermStatus.unknown,
    required this.onGrant,
  });
}

/// Unified one-popup permissions/setup screen.
///
/// Each row has a status icon (✓ green / ⚠ amber / ✗ red), a title, a
/// one-line "why we need this", and a Grant button that deep-links to
/// the exact OS settings screen. The dialog refreshes each row's
/// status every time the app resumes (user returning from settings),
/// so checkmarks light up live.
///
/// Replaces the previous "two-button OEM autostart guide" with a
/// single comprehensive checklist.
class PermissionsSetupDialog extends StatefulWidget {
  /// Force-show even if the user previously dismissed it (used by the
  /// home-screen "Permissions" tile so the rep can re-verify later).
  final bool force;

  const PermissionsSetupDialog({super.key, this.force = false});

  /// Decide whether to surface this dialog automatically on home-screen
  /// entry. Returns true if at least one critical permission is missing.
  static Future<bool> shouldAutoShow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.getBool('perms_setup_dismissed').nullToFalse()) {
        // First-ever launch always show.
        return true;
      }
      // Even on a 2nd+ launch we re-show if a critical perm reverted
      // (location turned off, battery optimisation re-enabled, etc.).
      if (await _criticalMissing()) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _criticalMissing() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return true;
      final loc = await Geolocator.checkPermission();
      if (loc == LocationPermission.denied ||
          loc == LocationPermission.deniedForever) return true;
      if (loc != LocationPermission.always) return true;
      if (Platform.isAndroid) {
        if (!(await Permission.ignoreBatteryOptimizations.isGranted)) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> show(BuildContext context, {bool force = false}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PermissionsSetupDialog(force: force),
    );
  }

  @override
  State<PermissionsSetupDialog> createState() => _PermissionsSetupDialogState();
}

class _PermissionsSetupDialogState extends State<PermissionsSetupDialog>
    with WidgetsBindingObserver {
  final Logger _logger = Logger();
  bool _refreshing = false;
  late List<_PermItem> _items;
  String _brand = '';

  @override
  void initState() {
    super.initState();
    _items = _buildItems();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll(initial: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // User returning from a settings screen — re-check everything.
      _refreshAll();
    }
  }

  List<_PermItem> _buildItems() {
    return [
      _PermItem(
        key: 'location_service',
        title: 'Location services on',
        why: 'GPS itself must be turned on system-wide.',
        onGrant: () async {
          try {
            await Geolocator.openLocationSettings();
          } catch (_) {}
        },
      ),
      _PermItem(
        key: 'location_always',
        title: 'Location permission: Allow all the time',
        why:
            'Required for tracking to continue when your phone screen is off or the app is in the background.',
        onGrant: () async {
          // First try the "always" upgrade. If still denied permanently,
          // pop the app-info screen so user can manually flip.
          var status = await Permission.locationAlways.request();
          if (status.isPermanentlyDenied) {
            await openAppSettings();
          }
        },
      ),
      _PermItem(
        key: 'notifications',
        title: 'Notifications',
        why:
            'So you get the ongoing tracking notification, alerts, and arrival pings.',
        onGrant: () async {
          var status = await Permission.notification.request();
          if (status.isPermanentlyDenied) {
            await openAppSettings();
          }
        },
      ),
      _PermItem(
        key: 'activity_recognition',
        title: 'Physical activity',
        why:
            'Detects when you\'re driving vs walking — improves distance accuracy and stop detection.',
        onGrant: () async {
          var status = await Permission.activityRecognition.request();
          if (status.isPermanentlyDenied) await openAppSettings();
        },
      ),
      _PermItem(
        key: 'battery',
        title: 'Battery: Unrestricted',
        why:
            'Stops Android from killing the tracking service after a few minutes in the background.',
        onGrant: () async {
          final ok = await OemAutostartService.openBatterySaver();
          if (!ok) await openAppSettings();
        },
      ),
      _PermItem(
        key: 'autostart',
        title: 'Auto-start enabled',
        why:
            'On Xiaomi / Vivo / Oppo / Realme / Samsung, this lets the app re-launch tracking when the OS kills it.',
        onGrant: () async {
          final ok = await OemAutostartService.openAutoStart();
          if (!ok) await OemAutostartService.openAppInfo();
        },
      ),
    ];
  }

  Future<void> _refreshAll({bool initial = false}) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      _brand = await OemAutostartService.manufacturer();
      // Location services + permission
      final svcOn = await Geolocator.isLocationServiceEnabled();
      _itemByKey('location_service').status =
          svcOn ? _PermStatus.granted : _PermStatus.missing;

      final loc = await Geolocator.checkPermission();
      _PermStatus locStatus;
      if (loc == LocationPermission.always) {
        locStatus = _PermStatus.granted;
      } else if (loc == LocationPermission.whileInUse) {
        locStatus = _PermStatus.partial;
      } else {
        locStatus = _PermStatus.missing;
      }
      _itemByKey('location_always').status = locStatus;

      if (Platform.isAndroid) {
        final notif = await Permission.notification.status;
        _itemByKey('notifications').status =
            notif.isGranted ? _PermStatus.granted : _PermStatus.missing;

        final act = await Permission.activityRecognition.status;
        _itemByKey('activity_recognition').status =
            act.isGranted ? _PermStatus.granted : _PermStatus.missing;

        final batt = await Permission.ignoreBatteryOptimizations.status;
        _itemByKey('battery').status =
            batt.isGranted ? _PermStatus.granted : _PermStatus.missing;
      } else {
        _itemByKey('notifications').status = _PermStatus.granted;
        _itemByKey('activity_recognition').status = _PermStatus.granted;
        _itemByKey('battery').status = _PermStatus.granted;
      }

      // Autostart we can't check programmatically — there's no API.
      // Mark as "unknown" so the row stays informational. We rely on
      // the user tapping Grant + confirming themselves.
      _itemByKey('autostart').status =
          await _isBrandWithAutostart(_brand)
              ? _PermStatus.unknown
              : _PermStatus.granted;
    } catch (e) {
      _logger.w('refreshAll failed: $e');
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
        if (!initial) {
          HapticFeedback.lightImpact();
        }
      }
    }
  }

  Future<bool> _isBrandWithAutostart(String b) async {
    const stockBehavedBrands = {
      'google',
      'nothing',
      'motorola',
      'sony',
      'nokia',
      'hmd',
    };
    return !stockBehavedBrands.contains(b) && b.isNotEmpty;
  }

  _PermItem _itemByKey(String k) => _items.firstWhere((i) => i.key == k);

  Future<void> _onDone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('perms_setup_dismissed', true);
      await OemAutostartService.markSetupSeen();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  int get _grantedCount =>
      _items.where((i) => i.status == _PermStatus.granted).length;
  int get _totalCount => _items.length;

  @override
  Widget build(BuildContext context) {
    final allOk = _grantedCount == _totalCount &&
        !_items.any((i) => i.status == _PermStatus.unknown);
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (allOk ? Colors.green : Colors.deepOrange)
                        .withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    allOk ? Icons.verified_user : Icons.security,
                    color: allOk ? Colors.green : Colors.deepOrange,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  allOk ? 'You\'re all set' : 'Allow tracking permissions',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  allOk
                      ? 'All permissions granted. Tracking will work reliably.'
                      : 'Grant these so your sessions don\'t stop when the screen goes off.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '$_grantedCount of $_totalCount granted'
                      + (_brand.isNotEmpty ? ' · $_brand device' : ''),
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black45,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 14),

              // Items
              for (final item in _items) ...[
                _PermRow(
                  item: item,
                  onTap: () async {
                    await item.onGrant();
                    // small delay so the launched Settings screen is on top
                    // before we re-check.
                    await Future.delayed(const Duration(milliseconds: 250));
                    await _refreshAll();
                  },
                ),
                const SizedBox(height: 8),
              ],

              const SizedBox(height: 6),
              Row(
                children: [
                  TextButton(
                    onPressed: _refreshing ? null : () => _refreshAll(),
                    child: _refreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Refresh'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _onDone,
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          allOk ? Colors.green : Colors.deepOrange,
                    ),
                    child: Text(allOk ? 'Done' : 'I\'ll finish later'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  final _PermItem item;
  final VoidCallback onTap;
  const _PermRow({required this.item, required this.onTap});

  Color get _statusColor {
    switch (item.status) {
      case _PermStatus.granted:
        return Colors.green;
      case _PermStatus.partial:
        return Colors.amber.shade700;
      case _PermStatus.missing:
        return Colors.red.shade600;
      case _PermStatus.unknown:
        return Colors.blueGrey;
    }
  }

  IconData get _statusIcon {
    switch (item.status) {
      case _PermStatus.granted:
        return Icons.check_circle;
      case _PermStatus.partial:
        return Icons.error_outline;
      case _PermStatus.missing:
        return Icons.cancel;
      case _PermStatus.unknown:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final granted = item.status == _PermStatus.granted;
    return Material(
      color: granted ? Colors.green.withValues(alpha: 0.06) : Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: granted ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_statusIcon, color: _statusColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.why,
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.black54, height: 1.3),
                    ),
                  ],
                ),
              ),
              if (!granted) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Grant',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

extension _BoolFallback on bool? {
  bool nullToFalse() => this ?? false;
}
