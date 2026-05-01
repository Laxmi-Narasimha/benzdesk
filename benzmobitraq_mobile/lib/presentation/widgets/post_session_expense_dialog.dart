import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/session_model.dart';
import '../../data/models/trip_model.dart';

/// Post-session expense prompt dialog.
/// Extremely simplified 1-click interface tailored for field staff.
class PostSessionExpenseDialog extends StatefulWidget {
  final SessionModel session;
  final double distanceKm;

  const PostSessionExpenseDialog({
    super.key,
    required this.session,
    required this.distanceKm,
  });

  static Future<void> showIfNeeded(BuildContext context, SessionModel session, double distanceKm) async {
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
  State<PostSessionExpenseDialog> createState() => _PostSessionExpenseDialogState();
}

class _PostSessionExpenseDialogState extends State<PostSessionExpenseDialog> {
  bool _loading = true;
  bool _submitting = false;
  String _vehicleType = 'bike';
  String? _error;
  TripModel? _activeTrip;
  String _band = 'executive';
  late double _accurateDistanceKm; // Will hold the most reliable distance
  double _customBikeRate = 0.0;
  double _customCarRate = 0.0;

  @override
  void initState() {
    super.initState();
    _accurateDistanceKm = widget.distanceKm; // Start with passed-in value
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final sb = Supabase.instance.client;
      final userId = sb.auth.currentUser?.id;
      if (userId == null) return;

      // Get employee band and custom rates
      final empData = await sb.from('employees').select('band, bike_rate_per_km, car_rate_per_km').eq('id', userId).maybeSingle();
      if (empData != null) {
        _band = empData['band'] as String? ?? 'executive';
        _customBikeRate = (empData['bike_rate_per_km'] as num?)?.toDouble() ?? 0.0;
        _customCarRate = (empData['car_rate_per_km'] as num?)?.toDouble() ?? 0.0;
      }

      // Fetch the ACCURATE distance from session_rollups (same source admin panel uses)
      try {
        final rollupData = await sb
            .from('session_rollups')
            .select('distance_km')
            .eq('session_id', widget.session.id)
            .maybeSingle();
        if (rollupData != null) {
          final rollupKm = (rollupData['distance_km'] as num?)?.toDouble() ?? 0;
          if (rollupKm > 0) {
            _accurateDistanceKm = rollupKm;
          }
        }
      } catch (_) {
        // Fallback: try shift_sessions.total_km
        try {
          final sessionData = await sb
              .from('shift_sessions')
              .select('total_km')
              .eq('id', widget.session.id)
              .maybeSingle();
          if (sessionData != null) {
            final dbKm = (sessionData['total_km'] as num?)?.toDouble() ?? 0;
            if (dbKm > 0) {
              _accurateDistanceKm = dbKm;
            }
          }
        } catch (_) {}
      }

      // Check if there's an active trip for this employee
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

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Could not load data'; });
    }
  }

  Future<void> _submitExpense() async {
    setState(() { _submitting = true; _error = null; });

    try {
      final sb = Supabase.instance.client;
      final userId = sb.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final fuelCategory = _vehicleType == 'car' ? 'fuel_car' : 'fuel_bike';
      
      final limitData = await sb
          .from('band_limits')
          .select('daily_limit')
          .eq('band', _band)
          .eq('category', fuelCategory)
          .maybeSingle();
      
      // Use custom rate if available, otherwise fall back to band limit, then default
      double customRate = _vehicleType == 'car' ? _customCarRate : _customBikeRate;
      double rate = customRate > 0 ? customRate : (limitData != null ? (limitData['daily_limit'] as num).toDouble() : (_vehicleType == 'car' ? 7.5 : 5.0));
      final amount = rate * _accurateDistanceKm;

      // Clean, professional description with locations
      final startLoc = widget.session.startAddress?.split(',').first ?? 'Start';
      final endLoc = widget.session.endAddress?.split(',').first ?? 'End';
      final vname = _vehicleType == 'car' ? 'Car' : 'Bike';
      final distanceStr = _accurateDistanceKm.toStringAsFixed(1);
      final title = '[Session ${widget.session.id.toString().substring(0, 5)}] Fuel ($distanceStr km)';
      final description = 'Fuel expense for $distanceStr km ($vname) - $startLoc to $endLoc. Session ID: ${widget.session.id}';

      // If there's an active trip, add to trip_expenses with session_id link
      if (_activeTrip != null) {
        await sb.from('trip_expenses').insert({
          'trip_id': _activeTrip!.id,
          'employee_id': userId,
          'category': fuelCategory,
          'amount': amount,
          'description': title + ' - ' + description,
          'date': DateTime.now().toIso8601String().split('T').first,
          'limit_amount': amount,
          'exceeds_limit': false,
          'session_id': widget.session.id,
        });
      } else {
        // Create a standalone expense claim
        final claim = await sb.from('expense_claims').insert({
          'employee_id': userId,
          'total_amount': amount,
          'notes': title + '] ' + description,
          'status': 'submitted',
        }).select('id').single();

        await sb.from('expense_items').insert({
          'claim_id': claim['id'],
          'category': fuelCategory,
          'amount': amount,
          'description': description,
          'expense_date': DateTime.now().toIso8601String().split('T').first,
        });
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✓ Session expense logged successfully!'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() { _submitting = false; _error = 'Failed to submit: $e'; });
    }
  }

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
                children: [
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
                  const SizedBox(height: 24),
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
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _submitting ? null : _submitExpense,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _submitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Log Expense', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Skip for now', style: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
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
            Icon(icon, color: isSelected ? Colors.blue.shade700 : Colors.grey.shade600, size: 32),
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
