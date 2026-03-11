import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/trip_model.dart';

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

class CreateTripExpenseScreen extends StatefulWidget {
  final TripModel trip;
  const CreateTripExpenseScreen({super.key, required this.trip});

  @override
  State<CreateTripExpenseScreen> createState() => _CreateTripExpenseScreenState();
}

class _CreateTripExpenseScreenState extends State<CreateTripExpenseScreen> {
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  final _customTitleController = TextEditingController();
  String _category = 'food_da';
  bool _loading = false;
  String? _error;
  List<BandLimit> _limits = [];
  bool _limitsLoaded = false;
  File? _receiptImage;

  final _categories = [
    {'value': 'food_da', 'label': 'Food DA', 'icon': Icons.restaurant},
    {'value': 'hotel', 'label': 'Hotel', 'icon': Icons.hotel},
    {'value': 'local_travel', 'label': 'Local Travel', 'icon': Icons.directions_car},
    {'value': 'fuel_car', 'label': 'Fuel (Car)', 'icon': Icons.local_gas_station},
    {'value': 'fuel_bike', 'label': 'Fuel (Bike)', 'icon': Icons.two_wheeler},
    {'value': 'laundry', 'label': 'Laundry', 'icon': Icons.local_laundry_service},
    {'value': 'internet', 'label': 'Internet', 'icon': Icons.wifi},
    {'value': 'toll', 'label': 'Toll/Parking', 'icon': Icons.local_parking},
    {'value': 'other', 'label': 'Other', 'icon': Icons.more_horiz},
  ];

  @override
  void initState() { super.initState(); _loadLimits(); }

  Future<void> _loadLimits() async {
    try {
      final sb = Supabase.instance.client;
      final userId = sb.auth.currentUser?.id;
      if (userId == null) return;
      final empData = await sb.from('employees').select('band').eq('id', userId).maybeSingle();
      final band = empData?['band'] as String? ?? 'executive';
      final limitsData = await sb.from('band_limits').select().eq('band', band);
      if (mounted) setState(() { _limits = (limitsData as List).map((j) => BandLimit.fromJson(j)).toList(); _limitsLoaded = true; });
    } catch (e) {
      if (mounted) setState(() => _limitsLoaded = true);
    }
  }

  @override
  void dispose() { 
    _amountController.dispose(); 
    _descController.dispose(); 
    _customTitleController.dispose();
    super.dispose(); 
  }

  BandLimit? _getCurrentLimit() {
    try { return _limits.firstWhere((l) => l.category == _category); } catch (_) { return null; }
  }

  /// Calculate the effective limit for the current category.
  /// For per_km categories (fuel_car, fuel_bike), multiply rate by trip's totalKm.
  double? _getEffectiveLimit() {
    final limit = _getCurrentLimit();
    if (limit == null || limit.dailyLimit > 90000) return null;
    if (limit.unit == 'per_km') {
      final km = widget.trip.totalKm;
      if (km <= 0) return null; // No km recorded yet
      return limit.dailyLimit * km;
    }
    return limit.dailyLimit;
  }

  String _getLimitText() {
    if (!_limitsLoaded) return 'Loading limits...';
    final limit = _getCurrentLimit();
    if (limit == null) return 'No limit set (Actuals)';
    if (limit.dailyLimit > 90000) return 'No strict limit (Actuals)';
    if (limit.unit == 'per_km') {
      final km = widget.trip.totalKm;
      if (km <= 0) return '₹${limit.dailyLimit.toStringAsFixed(1)}/km (No km recorded yet)';
      final effective = limit.dailyLimit * km;
      return '₹${limit.dailyLimit.toStringAsFixed(1)}/km × ${km.toStringAsFixed(1)} km = ₹${effective.toStringAsFixed(0)}';
    }
    String unit = limit.unit == 'per_night' ? 'night' : 'day';
    return 'Your Limit: ₹${limit.dailyLimit.toStringAsFixed(0)} / $unit';
  }

  bool _isExceeding() {
    final effective = _getEffectiveLimit();
    if (effective == null) return false;
    final amt = double.tryParse(_amountController.text) ?? 0;
    return amt > effective;
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (pickedFile != null && mounted) {
        setState(() => _receiptImage = File(pickedFile.path));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }

  Future<void> _submit() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) { setState(() => _error = 'Enter amount'); return; }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) { setState(() => _error = 'Invalid amount'); return; }
    
    if (_category == 'other' && _customTitleController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a title for the other expense.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      final sb = Supabase.instance.client;
      final userId = sb.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final effectiveLimit = _getEffectiveLimit();
      final double? limitAmount = effectiveLimit;
      final bool exceeds = limitAmount != null && amount > limitAmount;

      String? receiptPath;
      if (_receiptImage != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = 'receipts/${userId}_${timestamp}.jpg';
        await sb.storage.from('benzmobitraq-receipts').upload(path, _receiptImage!);
        receiptPath = path;
      }

      String finalDesc = _descController.text.trim();
      if (_category == 'other' && _customTitleController.text.trim().isNotEmpty) {
        final title = _customTitleController.text.trim();
        finalDesc = finalDesc.isNotEmpty ? '[$title] $finalDesc' : '[$title]';
      }

      await sb.from('trip_expenses').insert({
        'trip_id': widget.trip.id, 'employee_id': userId, 'category': _category,
        'amount': amount, 'description': finalDesc.isNotEmpty ? finalDesc : null,
        'date': DateTime.now().toIso8601String().split('T').first,
        'limit_amount': limitAmount, 'exceeds_limit': exceeds,
        'receipt_path': receiptPath,
      });

      // Upload attachment natively to trip_expenses if present
      if (receiptPath != null && _receiptImage != null) {
        // Handled via standard attachment bucket, the admin panel accesses this via the receipt_path directly.
        print('Receipt uploaded for trip expense: $receiptPath');
      }      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(exceeds ? '⚠ Expense logged (over limit)' : '✓ Expense logged!'),
          backgroundColor: exceeds ? Colors.orange.shade800 : const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Failed to submit. Try again.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOver = _isExceeding();

    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: _C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Add Expense', style: GoogleFonts.inter(color: _C.textPrimary, fontWeight: FontWeight.w700)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: _C.textSecondary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Trip Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2EBF5)),
              ),
              child: Row(children: [
                const Icon(Icons.route, color: Color(0xFF3B82F6), size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text('${widget.trip.fromLocation} → ${widget.trip.toLocation}',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF1D4ED8), fontSize: 13))),
              ]),
            ),
            const SizedBox(height: 24),

            // Category
            Text('Category', style: GoogleFonts.inter(color: _C.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _categories.map((c) {
                final selected = _category == c['value'];
                return GestureDetector(
                  onTap: () => setState(() => _category = c['value'] as String),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? _C.accent.withOpacity(0.08) : _C.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? _C.accent.withOpacity(0.3) : _C.cardBorder),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(c['icon'] as IconData, size: 14, color: selected ? _C.accent : _C.textDim),
                      const SizedBox(width: 6),
                      Text(c['label'] as String, style: GoogleFonts.inter(
                        color: selected ? _C.accent : _C.textSecondary, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 13)),
                    ]),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            
            // Custom Title for 'other'
            if (_category == 'other') ...[
              TextField(
                controller: _customTitleController,
                textCapitalization: TextCapitalization.words,
                style: GoogleFonts.inter(color: _C.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: 'Custom Title *',
                  labelStyle: GoogleFonts.inter(color: _C.textSecondary),
                  hintText: 'e.g., Office Supplies',
                  hintStyle: GoogleFonts.inter(color: _C.textDim),
                  filled: true, fillColor: _C.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.cardBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.cardBorder)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.accent)),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Amount
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.inter(color: _C.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: 'Amount (₹) *',
                labelStyle: GoogleFonts.inter(color: _C.textSecondary),
                prefixIcon: const Icon(Icons.currency_rupee, color: _C.accent, size: 18),
                filled: true, fillColor: _C.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.cardBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.cardBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.accent)),
                errorText: isOver ? 'Exceeds policy limit!' : null,
                errorStyle: TextStyle(color: Colors.orange.shade800),
              ),
            ),

            // Limit info
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 20),
              child: Row(children: [
                Icon(Icons.info_outline, size: 14, color: isOver ? Colors.orange.shade800 : _C.textDim),
                const SizedBox(width: 6),
                Expanded(child: Text(_getLimitText(), style: GoogleFonts.inter(
                  fontSize: 12, fontWeight: isOver ? FontWeight.w600 : FontWeight.w500,
                  color: isOver ? Colors.orange.shade800 : _C.textSecondary))),
              ]),
            ),

            // Attachment
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _C.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _C.cardBorder, style: BorderStyle.solid),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: _C.cardBorder)),
                      child: Icon(_receiptImage != null ? Icons.image : Icons.add_a_photo, color: _C.textSecondary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_receiptImage != null ? 'Receipt Attached' : 'Attach Receipt', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: _C.textPrimary, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(_receiptImage != null ? 'Tap to replace image' : 'Optional image of bill/receipt', style: GoogleFonts.inter(color: _C.textDim, fontSize: 11)),
                        ],
                      ),
                    ),
                    if (_receiptImage != null)
                      const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Description
            TextField(
              controller: _descController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.inter(color: _C.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Description (Optional)',
                labelStyle: GoogleFonts.inter(color: _C.textSecondary),
                hintText: 'e.g., Client dinner at XYZ',
                hintStyle: GoogleFonts.inter(color: _C.textDim),
                filled: true, fillColor: _C.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.cardBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.cardBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.accent)),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFCA5A5))),
                child: Row(children: [
                  const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: GoogleFonts.inter(color: const Color(0xFFDC2626), fontSize: 13))),
                ]),
              ),
            ],

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isOver ? Colors.orange.shade700 : _C.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check_circle_outline),
                label: Text(_loading ? 'Submitting...' : (isOver ? 'Submit Over Limit' : 'Submit Expense'),
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
