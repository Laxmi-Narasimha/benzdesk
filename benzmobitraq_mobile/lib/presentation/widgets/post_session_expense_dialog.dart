import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:benzmobitraq_mobile/core/di/injection.dart';
import 'package:benzmobitraq_mobile/data/datasources/local/preferences_local.dart';
import 'package:benzmobitraq_mobile/data/models/session_model.dart';
import 'package:benzmobitraq_mobile/data/models/trip_model.dart';
import 'package:benzmobitraq_mobile/data/repositories/expense_repository.dart';
import 'package:benzmobitraq_mobile/services/connectivity_service.dart';
import 'package:benzmobitraq_mobile/services/session_manager.dart';

/// Post-session expense prompt dialog.
///
/// Two behaviors, switched live based on connectivity:
///  - ONLINE: writes the fuel expense directly to Supabase, same as before.
///  - OFFLINE: queues the expense locally and warns the user that the
///    optimal driving distance will be reconciled via Google Maps as
///    soon as the device gets internet back. The dialog itself listens
///    to connectivity changes — the moment internet returns it flips
///    to the normal online flow without forcing the user to re-open it.
class PostSessionExpenseDialog extends StatefulWidget {
  final SessionModel session;
  final double distanceKm;

  const PostSessionExpenseDialog({
    super.key,
    required this.session,
    required this.distanceKm,
  });

  static Future<void> showIfNeeded(
      BuildContext context, SessionModel session, double distanceKm) async {
    if (distanceKm <= 0) return; // Skip for 0 distance

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PostSessionExpenseDialog(
        session: session,
        distanceKm: distanceKm,
      ),
    );
  }

  @override
  State<PostSessionExpenseDialog> createState() =>
      _PostSessionExpenseDialogState();
}

class _PostSessionExpenseDialogState extends State<PostSessionExpenseDialog> {
  bool _loading = true;
  bool _submitting = false;
  String _vehicleType = 'bike';
  String? _error;
  String? _info; // non-error informational message (e.g. internet back)
  TripModel? _activeTrip;
  String _band = 'executive';
  late double _accurateDistanceKm; // Best-known distance at the moment
  double _customBikeRate = 0.0;
  double _customCarRate = 0.0;

  bool _online = ConnectivityService.isOnline;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _accurateDistanceKm = widget.distanceKm; // Start with passed-in value
    _connectivitySub = ConnectivityService.onlineChanges.listen((online) async {
      if (!mounted) return;
      final wasOnline = _online;
      setState(() {
        _online = online;
        if (!wasOnline && online) {
          // Just regained connectivity — flip to the optimistic state
          _info = 'Internet is back. You can submit now.';
          _error = null;
        }
        if (wasOnline && !online) {
          _info = null;
        }
      });
      // Once online, drain any pending session start/stop/locations
      // FIRST, then upgrade rates/distance from the server. Without
      // the explicit flush, the dialog reads `shift_sessions.total_km`
      // while the row still says 0 (the pending stop hasn't synced
      // yet), and the displayed km can drop to zero. Note we never
      // overwrite to a smaller value in _refreshDistanceFromServer,
      // but the flush also guarantees the server is correct when
      // the user submits online.
      if (online && _loading == false) {
        try {
          await getIt<SessionManager>().flushAllPendingNow();
        } catch (_) {/* best effort */}
        if (mounted) await _refreshFromServerSafely();
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      if (_online) {
        await _fetchEmployeeAndRates();
        await _refreshDistanceFromServer();
        await _detectActiveTrip();
      } else {
        // Best-effort: nothing to fetch when offline — use defaults + widget data
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null; // Don't surface a load error; just show offline state
        });
      }
    }
  }

  Future<void> _refreshFromServerSafely() async {
    try {
      await _fetchEmployeeAndRates();
      await _refreshDistanceFromServer();
      await _detectActiveTrip();
      if (mounted) setState(() {});
    } catch (_) {
      // ignore — best effort
    }
  }

  Future<void> _fetchEmployeeAndRates() async {
    final sb = Supabase.instance.client;
    final userId = sb.auth.currentUser?.id;
    if (userId == null) return;

    final empData = await sb
        .from('employees')
        .select('band, bike_rate_per_km, car_rate_per_km')
        .eq('id', userId)
        .maybeSingle();
    if (empData != null) {
      _band = empData['band'] as String? ?? 'executive';
      _customBikeRate =
          (empData['bike_rate_per_km'] as num?)?.toDouble() ?? 0.0;
      _customCarRate =
          (empData['car_rate_per_km'] as num?)?.toDouble() ?? 0.0;
    }
  }

  Future<void> _refreshDistanceFromServer() async {
    // Single source of truth: shift_sessions.final_km
    //
    // final_km is locked at session end by SessionManager.stopSession()
    // (the same value the user saw on their screen). It is never overwritten
    // by the session_rollups trigger, and it is the only value the expense
    // dialog is allowed to read for billing.
    //
    // We deliberately do NOT fall back to session_rollups.distance_km here —
    // that field is computed by a server trigger from raw haversine and is
    // always >= final_km due to GPS jitter. Reading it caused Incident A
    // (11.92 km on screen → 12.25 km in expense). See
    // docs/DISTANCE_TRACKING_METHODOLOGY.md.
    //
    // The local _accurateDistanceKm (what we passed into the dialog) is the
    // floor: if the server hasn't synced yet, we keep the local value rather
    // than show ₹0. We only adopt server final_km if it's larger.
    final sb = Supabase.instance.client;
    double? serverFinalKm;

    try {
      final sessionData = await sb
          .from('shift_sessions')
          .select('final_km, total_km, distance_source, confidence')
          .eq('id', widget.session.id)
          .maybeSingle();
      if (sessionData != null) {
        // Prefer final_km (locked by stopSession). Fall back to total_km only
        // if final_km is null AND the row pre-dates migration 072 (historic
        // sessions backfilled with final_km = total_km will not hit this path).
        final fk = (sessionData['final_km'] as num?)?.toDouble();
        final tk = (sessionData['total_km'] as num?)?.toDouble();
        serverFinalKm = (fk != null && fk > 0) ? fk : tk;
      }
    } catch (_) {
      // Network or auth issue — keep local floor, do not block the UI.
    }

    if (serverFinalKm != null && serverFinalKm > _accurateDistanceKm) {
      _accurateDistanceKm = serverFinalKm;
    }
  }

  Future<void> _detectActiveTrip() async {
    final sb = Supabase.instance.client;
    final userId = sb.auth.currentUser?.id;
    if (userId == null) return;
    final tripData = await sb
        .from('trips')
        .select()
        .eq('employee_id', userId)
        .eq('status', 'active')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (tripData != null) {
      _activeTrip = TripModel.fromJson(tripData);
      _vehicleType = _activeTrip!.vehicleType;
    }
  }

  /// Compute the rate that will be billed per km, mirroring the original
  /// online flow so the offline queue records the exact same rate.
  Future<double> _resolveRatePerKm() async {
    final fuelCategory = _vehicleType == 'car' ? 'fuel_car' : 'fuel_bike';
    double customRate =
        _vehicleType == 'car' ? _customCarRate : _customBikeRate;

    if (_online) {
      try {
        final sb = Supabase.instance.client;
        final userId = sb.auth.currentUser?.id;
        if (userId != null) {
          final overrideData = await sb
              .from('employee_expense_limits')
              .select('limit_amount, unit')
              .eq('employee_id', userId)
              .eq('category', fuelCategory)
              .eq('is_active', true)
              .maybeSingle();
          final overrideRate =
              overrideData != null && overrideData['unit'] == 'per_km'
                  ? (overrideData['limit_amount'] as num?)?.toDouble() ?? 0.0
                  : 0.0;
          if (overrideRate > 0) customRate = overrideRate;
        }

        final limitData = await sb
            .from('band_limits')
            .select('daily_limit')
            .eq('band', _band)
            .eq('category', fuelCategory)
            .maybeSingle();
        if (customRate > 0) return customRate;
        if (limitData != null) {
          return (limitData['daily_limit'] as num).toDouble();
        }
      } catch (_) {/* fall through */}
    }

    if (customRate > 0) return customRate;
    return _vehicleType == 'car' ? 7.5 : 5.0;
  }

  Future<void> _submitExpense() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final rate = await _resolveRatePerKm();

    if (!_online) {
      await _submitOffline(rate);
      return;
    }
    await _submitOnline(rate);
  }

  Future<void> _submitOnline(double rate) async {
    try {
      final sb = Supabase.instance.client;
      final userId = sb.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final fuelCategory = _vehicleType == 'car' ? 'fuel_car' : 'fuel_bike';
      final amount = rate * _accurateDistanceKm;

      final startLoc = widget.session.startAddress?.split(',').first ?? 'Start';
      final endLoc = widget.session.endAddress?.split(',').first ?? 'End';
      final vname = _vehicleType == 'car' ? 'Car' : 'Bike';
      final distanceStr = _accurateDistanceKm.toStringAsFixed(1);
      final idShort = widget.session.id.length >= 5
          ? widget.session.id.substring(0, 5)
          : widget.session.id;
      final title = '[Session $idShort] Fuel ($distanceStr km)';
      final description =
          'Fuel expense for $distanceStr km ($vname) - $startLoc to $endLoc. Session ID: ${widget.session.id}';

      if (_activeTrip != null) {
        await sb.from('trip_expenses').insert({
          'trip_id': _activeTrip!.id,
          'employee_id': userId,
          'category': fuelCategory,
          'amount': amount,
          'description': '$title - $description',
          'date': DateTime.now().toIso8601String().split('T').first,
          'limit_amount': amount,
          'exceeds_limit': false,
          'session_id': widget.session.id,
        });
      } else {
        final claim = await sb
            .from('expense_claims')
            .insert({
              'employee_id': userId,
              'total_amount': amount,
              'notes': '$title] $description',
              'status': 'submitted',
            })
            .select('id')
            .single();

        await sb.from('expense_items').insert({
          'claim_id': claim['id'],
          'category': fuelCategory,
          'amount': amount,
          'description': description,
          'expense_date': DateTime.now().toIso8601String().split('T').first,
        });
      }

      try {
        await getIt<PreferencesLocal>()
            .removeSkippedPostSessionId(widget.session.id);
      } catch (_) {}
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Session expense logged successfully'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // Network blip mid-submit → fall back to the offline queue so the
      // user is never told "it failed" when we can still recover later.
      if (!ConnectivityService.isOnline) {
        await _submitOffline(await _resolveRatePerKm());
        return;
      }
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Could not submit. Please try again.';
        });
      }
    }
  }

  Future<void> _submitOffline(double rate) async {
    try {
      final sb = Supabase.instance.client;
      final userId = sb.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final repo = getIt<ExpenseRepository>();
      await repo.queueOfflineSessionFuel(
        sessionId: widget.session.id,
        employeeId: userId,
        tripId: _activeTrip?.id,
        vehicleType: _vehicleType,
        band: _band,
        ratePerKm: rate,
        gpsDistanceKm: _accurateDistanceKm,
        startLat: widget.session.startLatitude,
        startLng: widget.session.startLongitude,
        endLat: widget.session.endLatitude,
        endLng: widget.session.endLongitude,
        startAddress: widget.session.startAddress,
        endAddress: widget.session.endAddress,
      );

      try {
        await getIt<PreferencesLocal>()
            .removeSkippedPostSessionId(widget.session.id);
      } catch (_) {}
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Saved offline. We will reconcile the distance via Google Maps when internet returns.'),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Could not save offline. Please try again.';
        });
      }
    }
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildBody(),
              ),
      ),
    );
  }

  List<Widget> _buildBody() {
    return [
      const Icon(Icons.local_gas_station, size: 48, color: Colors.blue),
      const SizedBox(height: 16),
      const Text(
        'Log Session Fuel',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(
        'Traveled ${_accurateDistanceKm.toStringAsFixed(1)} km.\nSelect your mode of travel to quickly log this expense.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
      ),
      const SizedBox(height: 16),
      _connectivityCard(),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildVehicleOption('bike', 'Bike', Icons.motorcycle),
          const SizedBox(width: 16),
          _buildVehicleOption('car', 'Car', Icons.directions_car),
        ],
      ),
      if (_error != null) ...[
        const SizedBox(height: 16),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red, fontSize: 12),
        ),
      ],
      const SizedBox(height: 24),
      ElevatedButton(
        onPressed: _submitting ? null : _submitExpense,
        style: ElevatedButton.styleFrom(
          backgroundColor: _online ? Colors.blue.shade600 : Colors.orange.shade700,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: _submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(
                _online ? 'Submit Expense' : 'Save Offline & Reconcile Later',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: _submitting
            ? null
            : () async {
                // Remember the skip so we can re-prompt on the next
                // app open — a single accidental tap should not lose
                // a legitimate fuel expense for the user.
                try {
                  await getIt<PreferencesLocal>()
                      .addSkippedPostSessionId(widget.session.id);
                } catch (_) {}
                if (mounted) Navigator.of(context).pop(false);
              },
        child: const Text('Skip for now',
            style: TextStyle(color: Colors.grey)),
      ),
    ];
  }

  Widget _connectivityCard() {
    if (_online) {
      // If we *just* came back from offline, show the celebratory hint.
      if (_info != null) {
        return _banner(
          icon: Icons.wifi_rounded,
          color: Colors.green,
          title: 'Internet is back',
          body:
              'You can now submit normally. We will record the live distance.',
        );
      }
      return const SizedBox.shrink();
    }
    return _banner(
      icon: Icons.wifi_off_rounded,
      color: Colors.orange,
      title: 'You are offline',
      body:
          'Submitting now will save this expense locally. The optimal driving distance between your start and end points will be calculated via Google Maps when internet returns and the final amount will be submitted automatically. You can also turn on internet and submit to use the live distance instead.',
    );
  }

  Widget _banner({
    required IconData icon,
    required MaterialColor color,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(
                        color: color.shade900, fontSize: 12, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleOption(String type, String label, IconData icon) {
    final isSelected = _vehicleType == type;
    return GestureDetector(
      onTap: () => setState(() => _vehicleType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.white,
          border: Border.all(
            color: isSelected ? Colors.blue.shade400 : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: isSelected ? Colors.blue.shade700 : Colors.grey.shade600,
                size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.blue.shade700 : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
