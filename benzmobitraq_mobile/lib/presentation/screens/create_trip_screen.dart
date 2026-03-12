import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Premium Dark Palette (shared with HomeScreen)
class _C {
  static const bg = Color(0xFFFAFAFA);
  static const surface = Color(0xFFFFFFFF);
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

/// Premium dark-themed trip creation screen
class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({super.key});

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  final _reasonController = TextEditingController();
  String _vehicleType = 'car';
  bool _loading = false;
  String? _error;

  bool _requestAdvance = false;
  final _advHotelController = TextEditingController();
  final _advTravelController = TextEditingController();
  final _advFoodController = TextEditingController();
  final _advOtherDescController = TextEditingController();
  final _advOtherAmountController = TextEditingController();
  
  final _vehicles = [
    {'value': 'car', 'label': 'Car', 'icon': Icons.directions_car},
    {'value': 'bike', 'label': 'Bike', 'icon': Icons.two_wheeler},
    {'value': 'bus', 'label': 'Bus', 'icon': Icons.directions_bus},
    {'value': 'train', 'label': 'Train', 'icon': Icons.train},
    {'value': 'flight', 'label': 'Flight', 'icon': Icons.flight},
    {'value': 'auto', 'label': 'Auto', 'icon': Icons.electric_rickshaw},
  ];

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _reasonController.dispose();
    _advHotelController.dispose();
    _advTravelController.dispose();
    _advFoodController.dispose();
    _advOtherDescController.dispose();
    _advOtherAmountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final from = _fromController.text.trim();
    final to = _toController.text.trim();

    if (from.isEmpty || to.isEmpty) {
      setState(() => _error = 'Please enter both From and To locations');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final sb = Supabase.instance.client;
      final userId = sb.auth.currentUser?.id;
      if (userId == null) { setState(() { _error = 'Not logged in'; _loading = false; }); return; }

      final existing = await sb.from('trips').select('id').eq('employee_id', userId).eq('status', 'active').limit(1).maybeSingle();
      if (existing != null) {
        setState(() { _error = 'You already have an active trip. Complete it first.'; _loading = false; });
        return;
      }

      final insertedTripResponse = await sb.from('trips').insert({
        'employee_id': userId,
        'from_location': from,
        'to_location': to,
        'reason': _reasonController.text.trim().isNotEmpty ? _reasonController.text.trim() : null,
        'vehicle_type': _vehicleType,
        'status': 'active',
        'started_at': DateTime.now().toUtc().toIso8601String(),
      }).select('id');

      if (_requestAdvance) {
        final double hotelAmt = double.tryParse(_advHotelController.text) ?? 0;
        final double travelAmt = double.tryParse(_advTravelController.text) ?? 0;
        final double foodAmt = double.tryParse(_advFoodController.text) ?? 0;
        final double otherAmt = double.tryParse(_advOtherAmountController.text) ?? 0;
        final totalAdv = hotelAmt + travelAmt + foodAmt + otherAmt;

        if (totalAdv > 0) {
          final summaryDetails = [];
          if (hotelAmt > 0) summaryDetails.add('Hotel: ₹$hotelAmt');
          if (travelAmt > 0) summaryDetails.add('Travel: ₹$travelAmt');
          if (foodAmt > 0) summaryDetails.add('Food: ₹$foodAmt');
          if (otherAmt > 0) summaryDetails.add('Other: ₹$otherAmt (${_advOtherDescController.text})');
          
          final tripTitle = 'Trip Advance: $from → $to';
          final notes = 'Advance Request details:\n${summaryDetails.join('\n')}';

          final claimRes = await sb.from('expense_claims').insert({
            'employee_id': userId,
            'claim_date': DateTime.now().toUtc().toIso8601String().split('T')[0],
            'total_amount': totalAdv,
            'status': 'submitted',
            'notes': tripTitle, // Title format often used by the system
          }).select('id').single();

          if (claimRes['id'] != null) {
            await sb.from('expense_items').insert({
              'claim_id': claimRes['id'],
              'category': 'advance_request',
              'amount': totalAdv,
              'description': notes,
              'expense_date': DateTime.now().toUtc().toIso8601String().split('T')[0],
            });
            
            // To sync the advance with trip context, we can also put trip_id but expense_items has no trip_id.
            // But we made the connection in the title.
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: const [
              Icon(Icons.check_circle, color: Colors.white, size: 18), SizedBox(width: 8),
              Expanded(child: Text('Trip started! Track live & add expenses anytime.')),
            ]),
            backgroundColor: _C.accent.withOpacity(0.9),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to create trip. ${e.toString().contains('trips') ? 'Database tables not ready.' : 'Please try again.'}';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: _C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Start New Trip', style: GoogleFonts.inter(color: _C.textPrimary, fontWeight: FontWeight.w700)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: _C.textSecondary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F9F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD4EED8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: Color(0xFF2E7D32), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Your trip starts immediately — no approval needed.',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF2E7D32), height: 1.4, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Route Card
            _buildGlassCard(
              icon: Icons.route, title: 'Route',
              child: Column(
                children: [
                  _buildDarkTextField(_fromController, 'From *', 'e.g., Hyderabad Office',
                      Icon(Icons.my_location, color: _C.accent, size: 18)),
                  const SizedBox(height: 16),
                  _buildDarkTextField(_toController, 'To *', 'e.g., Mumbai Client Site',
                      Icon(Icons.location_on, color: Colors.red.shade400, size: 18)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Vehicle Card
            _buildGlassCard(
              icon: Icons.directions_car, title: 'Vehicle',
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: _vehicles.map((v) {
                  final selected = _vehicleType == v['value'];
                  return GestureDetector(
                    onTap: () => setState(() => _vehicleType = v['value'] as String),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? _C.accent.withOpacity(0.08) : _C.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selected ? _C.accent.withOpacity(0.2) : _C.cardBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(v['icon'] as IconData, size: 16, color: selected ? _C.accent : _C.textDim),
                          const SizedBox(width: 6),
                          Text(v['label'] as String, style: GoogleFonts.inter(
                            color: selected ? _C.accent : _C.textSecondary,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 13,
                          )),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // Reason Card
            _buildGlassCard(
              icon: Icons.notes, title: 'Purpose', subtitle: '(optional)',
              child: _buildDarkTextField(_reasonController, '', 'e.g., Client meeting, site visit...', null, maxLines: 2),
            ),
            const SizedBox(height: 16),

            // Advance Cash Request Card
            Container(
              decoration: BoxDecoration(
                color: _C.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _C.cardBorder),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: _requestAdvance,
                  onExpansionChanged: (val) => setState(() => _requestAdvance = val),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.money, color: Colors.amber, size: 22),
                  ),
                  title: Text('Request Advance Cash', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: _C.textPrimary)),
                  subtitle: Text('Apply for anticipated travel expenses', style: GoogleFonts.inter(fontSize: 12, color: _C.textSecondary)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          const SizedBox(height: 16),
                          Text('Expected Expenses', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: _C.textPrimary)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildDarkTextField(_advHotelController, 'Hotel / Acc.', 'Amount', null, keyboardType: TextInputType.number),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildDarkTextField(_advTravelController, 'Travel', 'Amount', null, keyboardType: TextInputType.number),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildDarkTextField(_advFoodController, 'Food / DA', 'Amount', null, keyboardType: TextInputType.number),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildDarkTextField(_advOtherAmountController, 'Other', 'Amount', null, keyboardType: TextInputType.number),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildDarkTextField(_advOtherDescController, 'Other Description', 'E.g., Client gifts, registration...', null),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: Colors.red.shade400),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: GoogleFonts.inter(color: Colors.red.shade400, fontSize: 13))),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),

            // Submit
            SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_arrow_rounded, size: 24),
                label: Text(_loading ? 'Starting...' : 'Start Trip Now',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassCard({required IconData icon, required String title, String? subtitle, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _C.cardBorder, width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: _C.accent.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: _C.accent, size: 16),
            ),
            const SizedBox(width: 10),
            Text(title, style: GoogleFonts.inter(color: _C.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
            if (subtitle != null) ...[
              const SizedBox(width: 4),
              Text(subtitle, style: GoogleFonts.inter(color: _C.textSecondary, fontSize: 12)),
            ],
          ]),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildDarkTextField(TextEditingController controller, String label, String hint, Widget? prefixIcon, {int maxLines = 1, TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.words,
      style: GoogleFonts.inter(color: _C.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label.isNotEmpty ? label : null,
        labelStyle: GoogleFonts.inter(color: _C.textSecondary),
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: _C.textDim),
        prefixIcon: prefixIcon,
        filled: true,
        fillColor: _C.bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _C.cardBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _C.cardBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.accent, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
