import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/router/app_router.dart';
import '../../data/models/trip_model.dart';
import '../blocs/session/session_bloc.dart';

class _C {
  static const bg = Color(0xFFFAFAFA);
  static const card = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFE5E5E5);
  static const accent = Color(0xFF111111);
  static const accentDim = Color(0xFF333333);
  static const textPrimary = Color(0xFF111111);
  static const textSecondary = Color(0xFF666666);
  static const textDim = Color(0xFF999999);
  static const glassBg = Color(0x00FFFFFF);
  static const glassBorder = Color(0x00FFFFFF);
}

class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  List<TripModel> _trips = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    setState(() { _loading = true; _error = null; });
    try {
      final sb = Supabase.instance.client;
      final userId = sb.auth.currentUser?.id;
      if (userId == null) { setState(() { _error = 'Not logged in'; _loading = false; }); return; }

      final data = await sb.from('trips').select().eq('employee_id', userId).order('created_at', ascending: false);
      if (mounted) {
        setState(() { _trips = (data as List).map((json) => TripModel.fromJson(json)).toList(); _loading = false; });
      }
    } catch (e) {
      if (mounted) { setState(() { _error = 'Could not load trips.'; _loading = false; }); }
    }
  }

  void _createNewTrip() async {
    final result = await Navigator.pushNamed(context, AppRouter.createTrip);
    if (result == true) _loadTrips();
  }

  void _addExpense(TripModel trip) async {
    final result = await Navigator.pushNamed(context, AppRouter.createTripExpense, arguments: trip);
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Expense logged!'), backgroundColor: _C.accent.withOpacity(0.9), behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _completeTrip(TripModel trip) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _C.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Complete Trip?', style: GoogleFonts.inter(color: _C.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('End trip "${trip.fromLocation} → ${trip.toLocation}"?', style: GoogleFonts.inter(color: _C.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: GoogleFonts.inter(color: _C.textDim))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('Complete', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await Supabase.instance.client.from('trips').update({'status': 'completed', 'ended_at': DateTime.now().toUtc().toIso8601String()}).eq('id', trip.id);
        _loadTrips();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Trip completed!'), backgroundColor: _C.accent.withOpacity(0.9), behavior: SnackBarBehavior.floating));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTrip = _trips.where((t) => t.status == 'active').firstOrNull;
    final pastTrips = _trips.where((t) => t.status != 'active').toList();

    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: _C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('My Trips', style: GoogleFonts.inter(color: _C.textPrimary, fontWeight: FontWeight.w700)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: _C.textSecondary),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadTrips, color: _C.textDim),
        ],
      ),
      bottomNavigationBar: activeTrip == null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton.icon(
                  onPressed: _createNewTrip,
                  icon: const Icon(Icons.add_location_alt),
                  label: Text('Start New Trip', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.accent,
                    foregroundColor: _C.bg,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    minimumSize: const Size(double.infinity, 56),
                  ),
                ),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _C.accent))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.orange.shade400),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.inter(color: _C.textSecondary)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(onPressed: _loadTrips, icon: const Icon(Icons.refresh), label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(backgroundColor: _C.accent, foregroundColor: _C.bg)),
                  ],
                )))
              : _trips.isEmpty
                  ? Center(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.commute, size: 64, color: _C.textDim),
                        const SizedBox(height: 16),
                        Text('No trips yet', style: GoogleFonts.inter(fontSize: 18, color: _C.textSecondary)),
                        const SizedBox(height: 8),
                        Text('Start a trip to track your journey \n"It will get easier as you use it"', textAlign: TextAlign.center, style: GoogleFonts.inter(color: _C.textDim)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _createNewTrip,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text('Start Your First Trip', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(backgroundColor: _C.accent, foregroundColor: _C.bg, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                        ),
                      ],
                    ))
                  : RefreshIndicator(
                      color: _C.accent, backgroundColor: _C.card,
                      onRefresh: _loadTrips,
                      child: ListView(
                        padding: const EdgeInsets.all(16).copyWith(bottom: 90),
                        children: [
                          if (activeTrip != null) ...[_buildActiveTripCard(activeTrip), const SizedBox(height: 24)],
                          if (pastTrips.isNotEmpty) ...[
                            Text('Past Trips', style: GoogleFonts.inter(color: _C.textSecondary, fontWeight: FontWeight.w600, fontSize: 15)),
                            const SizedBox(height: 12),
                            ...pastTrips.map((trip) => _buildPastTripCard(trip)),
                          ],
                          if (activeTrip != null) ...[
                            const SizedBox(height: 24),
                            Center(child: Text('Complete active trip to start a new one', style: GoogleFonts.inter(color: _C.textDim, fontSize: 12))),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Widget _buildActiveTripCard(TripModel trip) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0FAF5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.accent.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(color: _C.accent.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: _C.accent.withOpacity(0.3))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: _C.accent, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('ACTIVE', style: GoogleFonts.inter(color: _C.accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    ]),
                  ),
                  const Spacer(),
                  Text(trip.createdAt.toLocal().toString().split(' ')[0], style: GoogleFonts.inter(color: _C.textDim, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 20),

              // Route
              Row(
                children: [
                  Column(children: [
                    Icon(Icons.my_location, color: _C.accent.withOpacity(0.7), size: 16),
                    Container(height: 20, width: 1, color: _C.accent.withOpacity(0.3)),
                    const Icon(Icons.location_on, color: _C.accent, size: 16),
                  ]),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(trip.fromLocation, style: GoogleFonts.inter(color: _C.textPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 16),
                    Text(trip.toLocation, style: GoogleFonts.inter(color: _C.textPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
                  ])),
                ],
              ),

              if (trip.reason != null && trip.reason!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(trip.reason!, style: GoogleFonts.inter(color: _C.textDim, fontStyle: FontStyle.italic, fontSize: 13)),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Icon(_vehicleIcon(trip.vehicleType), size: 14, color: _C.textDim),
                const SizedBox(width: 4),
                Text(trip.vehicleType.toUpperCase(), style: GoogleFonts.inter(color: _C.textDim, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              ]),

              const SizedBox(height: 20),
              Container(height: 1, color: _C.accent.withOpacity(0.15)),
              const SizedBox(height: 16),

              // Action Buttons
              Row(children: [
                Expanded(child: _buildTripBtn(Icons.receipt_long, 'Add Expense', _C.accent, _C.bg, () => _addExpense(trip))),
                const SizedBox(width: 8),
                Expanded(child: _buildTripBtn(Icons.my_location, 'Live Track', _C.glassBg, _C.textPrimary, () {
                  context.read<SessionBloc>().add(SessionStartRequested());
                  Navigator.pop(context);
                }, borderColor: _C.glassBorder)),
                const SizedBox(width: 8),
                Expanded(child: _buildTripBtn(Icons.check_circle_outline, 'Complete', Colors.orange.shade700, Colors.white, () => _completeTrip(trip))),
              ]),
            ],
          ),
        );
  }

  Widget _buildTripBtn(IconData icon, String label, Color bg, Color fg, VoidCallback onTap, {Color? borderColor}) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: borderColor != null ? Border.all(color: borderColor) : Border.all(color: Colors.transparent)),
          child: Column(children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(height: 4),
            Text(label, style: GoogleFonts.inter(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  Widget _buildPastTripCard(TripModel trip) {
    Color statusColor;
    IconData statusIcon;
    String statusText;
    switch (trip.status) {
      case 'completed': statusColor = _C.textDim; statusIcon = Icons.check_circle; statusText = 'Completed'; break;
      case 'cancelled': statusColor = Colors.red.shade400; statusIcon = Icons.cancel; statusText = 'Cancelled'; break;
      default: statusColor = _C.textDim; statusIcon = Icons.info; statusText = trip.status;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.cardBorder, width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${trip.fromLocation} → ${trip.toLocation}', style: GoogleFonts.inter(color: _C.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          Row(children: [
            Icon(_vehicleIcon(trip.vehicleType), size: 14, color: _C.textDim),
            const SizedBox(width: 4),
            Text(trip.vehicleType, style: GoogleFonts.inter(color: _C.textSecondary, fontSize: 12)),
            const SizedBox(width: 12),
            Icon(Icons.calendar_today, size: 14, color: _C.textDim),
            const SizedBox(width: 4),
            Text(trip.createdAt.toLocal().toString().split(' ')[0], style: GoogleFonts.inter(color: _C.textSecondary, fontSize: 12)),
          ]),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: statusColor.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(statusIcon, size: 12, color: statusColor),
            const SizedBox(width: 4),
            Text(statusText, style: GoogleFonts.inter(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }

  IconData _vehicleIcon(String type) {
    switch (type) {
      case 'car': return Icons.directions_car;
      case 'bike': return Icons.two_wheeler;
      case 'bus': return Icons.directions_bus;
      case 'train': return Icons.train;
      case 'flight': return Icons.flight;
      case 'auto': return Icons.electric_rickshaw;
      default: return Icons.directions_car;
    }
  }
}
