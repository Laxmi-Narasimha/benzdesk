import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/router/app_router.dart';
import '../../data/models/trip_model.dart';
import 'monthly_expense_summary.dart';

class ActiveTripOrMonthlySummary extends StatefulWidget {
  const ActiveTripOrMonthlySummary({super.key});

  @override
  State<ActiveTripOrMonthlySummary> createState() => _ActiveTripOrMonthlySummaryState();
}

class _ActiveTripOrMonthlySummaryState extends State<ActiveTripOrMonthlySummary> {
  TripModel? _activeTrip;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadActiveTrip();
  }

  Future<void> _loadActiveTrip() async {
    try {
      final sb = Supabase.instance.client;
      final userId = sb.auth.currentUser?.id;
      if (userId == null) return;

      final data = await sb
          .from('trips')
          .select()
          .eq('employee_id', userId)
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          if (data != null) {
            _activeTrip = TripModel.fromJson(data);
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _vehicleIcon(String vt) {
    switch (vt) {
      case 'car': return Icons.directions_car;
      case 'bike': return Icons.two_wheeler;
      case 'bus': return Icons.directions_bus;
      case 'train': return Icons.train;
      case 'flight': return Icons.flight;
      case 'auto': return Icons.electric_rickshaw;
      default: return Icons.directions_car;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_activeTrip == null) {
      // Fallback to Monthly Summary if no active trip
      return const MonthlyExpenseSummary();
    }

    final trip = _activeTrip!;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FAF5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('ONGOING TRIP', style: GoogleFonts.inter(color: Colors.green.shade800, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Started ${trip.createdAt.toLocal().toString().split(' ')[0]}',
                style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Column(
                children: [
                  Icon(Icons.my_location, color: Colors.blue.shade700, size: 16),
                  Container(height: 20, width: 1, color: Colors.grey.shade400),
                  const Icon(Icons.location_on, color: Colors.red, size: 16),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trip.fromLocation, style: GoogleFonts.inter(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 12),
                    Text(trip.toLocation, style: GoogleFonts.inter(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 16)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(_vehicleIcon(trip.vehicleType), size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(trip.vehicleType.toUpperCase(), style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                // Navigate to My Trips to manage/add expenses
                AppRouter.navigateTo(context, AppRouter.myTrips);
              },
              icon: const Icon(Icons.receipt_long, size: 18),
              label: const Text('Manage Trip & Expenses'),
            ),
          )
        ],
      ),
    );
  }
}
