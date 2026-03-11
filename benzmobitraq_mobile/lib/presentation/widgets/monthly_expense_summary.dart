import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

/// Monthly expense summary card for the Home Screen.
/// Shows total expenses this month, number of claims, and a mini breakdown.
class MonthlyExpenseSummary extends StatefulWidget {
  const MonthlyExpenseSummary({super.key});

  @override
  State<MonthlyExpenseSummary> createState() => _MonthlyExpenseSummaryState();
}

class _MonthlyExpenseSummaryState extends State<MonthlyExpenseSummary> {
  double _totalAmount = 0;
  int _claimCount = 0;
  int _approvedCount = 0;
  int _pendingCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMonthlySummary();
  }

  Future<void> _loadMonthlySummary() async {
    try {
      final sb = Supabase.instance.client;
      final userId = sb.auth.currentUser?.id;
      if (userId == null) return;

      final now = DateTime.now();
      final firstOfMonth = DateTime(now.year, now.month, 1);
      final monthStart = firstOfMonth.toIso8601String().split('T').first;

      // Query expense_claims for this month
      final data = await sb
          .from('expense_claims')
          .select('id, total_amount, status')
          .eq('employee_id', userId)
          .gte('created_at', '${monthStart}T00:00:00');

      if (data is List) {
        double total = 0;
        int approved = 0;
        int pending = 0;
        for (final item in data) {
          total += (item['total_amount'] as num?)?.toDouble() ?? 0;
          final status = (item['status'] as String?)?.toLowerCase() ?? '';
          if (status == 'approved') approved++;
          if (status == 'submitted' || status == 'pending') pending++;
        }
        if (mounted) {
          setState(() {
            _totalAmount = total;
            _claimCount = data.length;
            _approvedCount = approved;
            _pendingCount = pending;
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthName = DateFormat('MMMM yyyy').format(DateTime.now());

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade700, Colors.blue.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade200.withOpacity(0.5),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _loading
          ? const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator(color: Colors.white)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      monthName,
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_claimCount claims',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '₹${NumberFormat('#,##,###').format(_totalAmount.toInt())}',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total expenses this month',
                  style: GoogleFonts.inter(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatusChip(
                      label: '$_approvedCount Approved',
                      color: Colors.green.shade300,
                    ),
                    const SizedBox(width: 8),
                    _StatusChip(
                      label: '$_pendingCount Pending',
                      color: Colors.amber.shade300,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
