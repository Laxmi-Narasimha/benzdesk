import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models/travel_allowance_model.dart';

import '../blocs/auth/auth_bloc.dart';
import '../blocs/expense/expense_bloc.dart';

// ============================================================================
// Design Constants
// ============================================================================
class _S {
  static const bg = Color(0xFFF8F9FA);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E7EB);
  static const borderFocus = Color(0xFF3B82F6);
  static const accent = Color(0xFF1E293B);
  static const accentBlue = Color(0xFF3B82F6);
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const textDim = Color(0xFF9CA3AF);
  static const successGreen = Color(0xFF10B981);
  static const warningOrange = Color(0xFFF59E0B);
  static const errorRed = Color(0xFFEF4444);
  static const infoBlueBg = Color(0xFFEFF6FF);
  static const infoBlueBorder = Color(0xFFBFDBFE);
  static const infoBlueText = Color(0xFF1D4ED8);
}

/// Screen for adding a new expense claim with proper category selection
/// and daily limit tracking based on BENZ Travel Policy
class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _distanceController = TextEditingController();
  final _fromController = TextEditingController();
  final _toController = TextEditingController();

  String _vehicleMode = 'Car';
  final List<String> _vehicleModes = [
    'Car',
    'Bike',
    'Auto',
    'Bus',
    'Train',
    'Flight',
    'Cab (Ola/Uber)',
    'Shared Cab',
  ];

  // Selected expense type
  bool _isTravelExpense = true;

  // Selected category
  ExpenseCategoryInfo? _selectedCategory;

  // Date and receipt
  DateTime _selectedDate = DateTime.now();
  File? _receiptFile;
  bool _isSubmitting = false;

  // Employee info
  EmployeeModel? _employee;
  EmployeeGrade _employeeGrade = EmployeeGrade.executive;
  String? _employeeId;

  // Limits
  String? _limitWarning;
  double? _dailyLimit;

  @override
  void initState() {
    super.initState();
    _loadEmployeeInfo();
    _amountController.addListener(_checkAllowanceLimit);
  }

  void _loadEmployeeInfo() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _employee = authState.employee;
      _employeeGrade = EmployeeGrade.fromString(authState.employee.role);
      _employeeId = authState.employee.id;
    }
  }

  void _checkAllowanceLimit() {
    if (_selectedCategory == null) {
      setState(() => _limitWarning = null);
      return;
    }

    final amountText = _amountController.text;
    if (amountText.isEmpty) {
      setState(() => _limitWarning = null);
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null) {
      setState(() => _limitWarning = null);
      return;
    }

    final warning = TravelAllowanceLimits.getWarningWithDailySpent(
      grade: _employeeGrade,
      category: _selectedCategory!.displayName,
      amount: amount,
      alreadySpentToday: 0,
      employee: _employee,
    );

    setState(() => _limitWarning = warning);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _distanceController.dispose();
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return BlocListener<ExpenseBloc, ExpenseState>(
      listener: (context, state) {
        if (state is ExpenseSubmitSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Text('Expense submitted successfully!'),
                ],
              ),
              backgroundColor: _S.successGreen,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          Navigator.pop(context);
        } else if (state is ExpenseError) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: _S.errorRed,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: _S.bg,
        appBar: AppBar(
          backgroundColor: _S.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Add Expense',
            style: GoogleFonts.inter(
              color: _S.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
          elevation: 0,
          iconTheme: const IconThemeData(color: _S.textSecondary),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: _S.border),
          ),
        ),
        body: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ===== SECTION 1: EMPLOYEE BAND INFO =====
                _buildBandInfoBanner(),
                const SizedBox(height: 24),

                // ===== SECTION 2: EXPENSE TYPE =====
                _buildSectionTitle('1. EXPENSE TYPE', Icons.category_outlined),
                const SizedBox(height: 12),
                _buildExpenseTypeToggle(),
                const SizedBox(height: 24),

                // ===== SECTION 3: CATEGORY =====
                _buildSectionTitle('2. CATEGORY', Icons.label_outline),
                const SizedBox(height: 12),
                _buildCategorySelector(),
                const SizedBox(height: 24),

                // ===== SECTION 4: POLICY LIMIT INFO =====
                if (_selectedCategory != null) ...[
                  _buildPolicyLimitCard(),
                  const SizedBox(height: 24),
                ],

                // ===== SECTION 5: TRAVEL DETAILS (if travel) =====
                if (_isTravelExpense && _selectedCategory != null) ...[
                  _buildSectionTitle('3. TRAVEL DETAILS', Icons.route_outlined),
                  const SizedBox(height: 12),
                  _buildTravelDetailsFields(),
                  const SizedBox(height: 24),
                ],

                // ===== SECTION: TITLE (if non-travel) =====
                if (!_isTravelExpense && _selectedCategory != null) ...[
                  _buildSectionTitle('3. REQUEST TITLE', Icons.title),
                  const SizedBox(height: 12),
                  _buildInputField(
                    controller: _titleController,
                    label: 'Title *',
                    hint: 'Short description of your request...',
                    icon: Icons.short_text,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Title is required for this type of request';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                ],

                // ===== SECTION 6: AMOUNT & DATE =====
                if (_selectedCategory != null) ...[
                  _buildSectionTitle(
                    _isTravelExpense ? '4. AMOUNT & DATE' : '4. AMOUNT & DATE',
                    Icons.currency_rupee,
                  ),
                  const SizedBox(height: 12),

                  // Fuel distance field
                  if (_selectedCategory?.name == 'fuel_car' ||
                      _selectedCategory?.name == 'fuel_bike') ...[
                    _buildInputField(
                      controller: _distanceController,
                      label: 'Distance (KM) *',
                      hint: 'Enter total distance travelled',
                      icon: Icons.straighten,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                      onChanged: (_) => _calculateFuelAmount(),
                      helperText:
                          'Rate: ₹${_selectedCategory?.name == 'fuel_car' ? (((_employee?.carRatePerKm ?? 0) > 0) ? _employee!.carRatePerKm : TravelAllowanceLimits.getFuelRatePerKm(_employeeGrade)) : (((_employee?.bikeRatePerKm ?? 0) > 0) ? _employee!.bikeRatePerKm : TravelAllowanceLimits.getBikeRatePerKm(_employeeGrade))}/km',
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Amount
                  _buildAmountField(),
                  const SizedBox(height: 16),

                  // Limit warning
                  if (_limitWarning != null) _buildLimitWarning(),

                  // Date 
                  _buildDatePicker(),
                  const SizedBox(height: 24),

                  // ===== SECTION 7: DESCRIPTION =====
                  _buildSectionTitle(
                    _isTravelExpense ? '5. NOTES & RECEIPT' : '5. NOTES & RECEIPT',
                    Icons.note_alt_outlined,
                  ),
                  const SizedBox(height: 12),

                  _buildInputField(
                    controller: _descriptionController,
                    label: 'Description (Optional)',
                    hint: 'e.g. Client meeting at XYZ office, dinner with vendor...',
                    icon: Icons.edit_note,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),

                  // ===== SECTION 8: RECEIPT UPLOAD =====
                  _buildReceiptUpload(),
                  const SizedBox(height: 32),

                  // ===== SUBMIT BUTTON =====
                  _buildSubmitButton(),
                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // UI BUILDING BLOCKS
  // ============================================================================

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _S.accentBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.inter(
            color: _S.accentBlue,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildBandInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _S.infoBlueBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _S.infoBlueBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _S.accentBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.badge_outlined, color: _S.accentBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Band: ${_employeeGrade.bandName}',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: _S.infoBlueText,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Limits and allowed modes are based on your employee band',
                  style: GoogleFonts.inter(
                    color: _S.infoBlueText.withOpacity(0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseTypeToggle() {
    return Row(
      children: [
        Expanded(
          child: _buildTypeCard(
            title: 'Travel Related',
            subtitle: 'Food, Hotel, Local Travel, Fuel, Toll',
            icon: Icons.directions_car_filled_outlined,
            isSelected: _isTravelExpense,
            onTap: () => setState(() {
              _isTravelExpense = true;
              _selectedCategory = null;
              _limitWarning = null;
            }),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildTypeCard(
            title: 'Other / HR',
            subtitle: 'Reimbursement, Advance, Salary Query',
            icon: Icons.receipt_long_outlined,
            isSelected: !_isTravelExpense,
            onTap: () => setState(() {
              _isTravelExpense = false;
              _selectedCategory = null;
              _limitWarning = null;
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? _S.accentBlue.withOpacity(0.06) : _S.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? _S.accentBlue : _S.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? _S.accentBlue : _S.textDim,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: isSelected ? _S.accentBlue : _S.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: isSelected ? _S.accentBlue.withOpacity(0.7) : _S.textDim,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    final categories = _isTravelExpense
        ? ExpenseCategoryInfo.travelCategories
        : ExpenseCategoryInfo.otherCategories;

    return Column(
      children: categories.map((category) {
        final isSelected = _selectedCategory?.name == category.name;
        final limit = TravelAllowanceLimits.getLimitForCategory(
          grade: _employeeGrade,
          category: category.name,
          employee: _employee,
        );

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedCategory = category;
              _limitWarning = null;
            });
            _updateDailyLimit();
            _checkAllowanceLimit();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected ? _S.accentBlue.withOpacity(0.06) : _S.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? _S.accentBlue : _S.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Emoji icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _S.accentBlue.withOpacity(0.1)
                        : _S.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(category.icon, style: const TextStyle(fontSize: 20)),
                  ),
                ),
                const SizedBox(width: 12),

                // Name + description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.displayName,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isSelected ? _S.accentBlue : _S.textPrimary,
                        ),
                      ),
                      if (category.description != null)
                        Text(
                          category.description!,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: _S.textDim,
                          ),
                        ),
                    ],
                  ),
                ),

                // Limit badge
                _buildLimitBadge(category, limit),

                const SizedBox(width: 8),

                // Check indicator
                Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected ? _S.accentBlue : _S.border,
                  size: 22,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLimitBadge(ExpenseCategoryInfo category, double? limit) {
    if (category.name == 'fuel_car') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.withOpacity(0.2)),
        ),
        child: Text(
          '₹7.5/km',
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.blue),
        ),
      );
    }
    if (category.name == 'fuel_bike') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.withOpacity(0.2)),
        ),
        child: Text(
          '₹5/km',
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.blue),
        ),
      );
    }
    if (category.name == 'hotel') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.purple.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.purple.withOpacity(0.2)),
        ),
        child: Text(
          '₹${TravelAllowanceLimits.getHotelNightLimit(_employeeGrade).toInt()}/night',
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.purple),
        ),
      );
    }
    if (limit != null && limit > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _S.warningOrange.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _S.warningOrange.withOpacity(0.2)),
        ),
        child: Text(
          '₹${limit.toInt()}/day',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: _S.warningOrange,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _S.successGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _S.successGreen.withOpacity(0.2)),
      ),
      child: Text(
        'Actuals',
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _S.successGreen,
        ),
      ),
    );
  }

  Widget _buildPolicyLimitCard() {
    final cat = _selectedCategory!;
    final isTravel = cat.isTravelRelated;
    final limit = TravelAllowanceLimits.getLimitForCategory(
      grade: _employeeGrade,
      category: cat.name,
    );

    String infoText = TravelAllowanceLimits.getLimitInfoText(
      grade: _employeeGrade,
      category: cat.name,
      employee: _employee,
    );

    // Add extra policy notes
    String? extraNote;
    if (cat.name == 'food_da') {
      extraNote = TravelAllowanceLimits.getFoodAllowanceNote(_employeeGrade);
      if (extraNote.isEmpty) extraNote = null;
    } else if (cat.name == 'hotel') {
      extraNote = 'Category: ${TravelAllowanceLimits.getHotelCategory(_employeeGrade)}\nAll bookings via Corporate Make My Trip (CMMT)';
    } else if (cat.name == 'local_travel') {
      final modes = TravelAllowanceLimits.getAllowedTransportModes(_employeeGrade);
      extraNote = 'Allowed modes: ${modes.join(', ')}';
    } else if (cat.name == 'laundry') {
      extraNote = 'Only if stay exceeds 3 nights';
    } else if (cat.name == 'toll') {
      extraNote = 'Submit actual receipts for reimbursement';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7).withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.policy_outlined, size: 16, color: Color(0xFFB45309)),
              const SizedBox(width: 6),
              Text(
                'TRAVEL POLICY',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFB45309),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            infoText,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF92400E),
            ),
          ),
          if (extraNote != null) ...[
            const SizedBox(height: 6),
            Text(
              extraNote,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF92400E).withOpacity(0.8),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTravelDetailsFields() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _S.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _S.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // From
          _buildInputField(
            controller: _fromController,
            label: 'From Location *',
            hint: 'e.g. Office, Home, Delhi...',
            icon: Icons.my_location,
            validator: (value) =>
                value == null || value.isEmpty ? 'From location is required' : null,
          ),
          const SizedBox(height: 16),

          // Arrow indicator
          Center(
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _S.accentBlue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_downward, color: _S.accentBlue, size: 16),
            ),
          ),
          const SizedBox(height: 16),

          // To
          _buildInputField(
            controller: _toController,
            label: 'To Location *',
            hint: 'e.g. Client Site, Kanpur, Airport...',
            icon: Icons.location_on_outlined,
            validator: (value) =>
                value == null || value.isEmpty ? 'To location is required' : null,
          ),
          const SizedBox(height: 16),

          // Mode of Travel
          Text(
            'Mode of Travel *',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: _S.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: _S.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _S.border),
            ),
            child: DropdownButtonFormField<String>(
              value: _vehicleMode,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.commute, color: _S.textDim, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: InputBorder.none,
              ),
              items: _vehicleModes
                  .map((mode) => DropdownMenuItem(
                        value: mode,
                        child: Text(
                          mode,
                          style: GoogleFonts.inter(
                            color: _S.textPrimary,
                            fontSize: 14,
                          ),
                        ),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _vehicleMode = val);
              },
              dropdownColor: _S.surface,
              style: GoogleFonts.inter(color: _S.textPrimary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    String? helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: _S.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: maxLines > 1
              ? TextCapitalization.sentences
              : TextCapitalization.words,
          onChanged: onChanged,
          style: GoogleFonts.inter(
            color: _S.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: _S.textDim, fontSize: 14),
            prefixIcon: Icon(icon, color: _S.textDim, size: 20),
            filled: true,
            fillColor: _S.bg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _S.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _S.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _S.borderFocus, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _S.errorRed),
            ),
            helperText: helperText,
            helperStyle: GoogleFonts.inter(color: _S.textDim, fontSize: 11),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildAmountField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Amount (₹)${_isTravelExpense ? ' *' : ' (Optional)'}',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: _S.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          style: GoogleFonts.inter(
            color: _S.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
          decoration: InputDecoration(
            hintText: '0.00',
            hintStyle: GoogleFonts.inter(color: _S.textDim, fontSize: 22, fontWeight: FontWeight.w400),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Text(
                '₹',
                style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: _S.accentBlue),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 40),
            filled: true,
            fillColor: _S.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _S.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _S.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _S.borderFocus, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _S.errorRed),
            ),
          ),
          validator: (value) {
            if (_isTravelExpense) {
              if (value == null || value.isEmpty) return 'Amount is required';
              if (double.tryParse(value) == null) return 'Enter a valid amount';
              if (double.parse(value) <= 0) return 'Amount must be greater than 0';
            } else {
              if (value != null && value.isNotEmpty && double.tryParse(value) == null) {
                return 'Enter a valid amount';
              }
            }
            return null;
          },
        ),
        // Show remaining limit info
        if (_dailyLimit != null && _dailyLimit! > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: _S.textDim),
                const SizedBox(width: 6),
                Text(
                  'Daily limit: ₹${_dailyLimit!.toInt()}',
                  style: GoogleFonts.inter(fontSize: 12, color: _S.textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLimitWarning() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _S.errorRed.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _S.errorRed.withOpacity(0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: _S.errorRed, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _limitWarning!,
                style: GoogleFonts.inter(fontSize: 12, color: _S.errorRed, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Date',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: _S.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _selectDate,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: _S.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _S.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: _S.accentBlue, size: 20),
                const SizedBox(width: 12),
                Text(
                  DateFormat('EEEE, dd MMMM yyyy').format(DateTimeUtils.toIST(_selectedDate)),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: _S.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptUpload() {
    if (_receiptFile != null) {
      return _buildReceiptPreview();
    }

    return InkWell(
      onTap: _showFilePicker,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _S.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _S.border, style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _S.accentBlue.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_upload_outlined, color: _S.accentBlue, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              'Upload Receipt / Document',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: _S.textPrimary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Supports: JPG, PNG, PDF, Excel',
              style: GoogleFonts.inter(color: _S.textDim, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap to take photo, choose from gallery, or select file',
              style: GoogleFonts.inter(color: _S.textDim, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptPreview() {
    final path = _receiptFile!.path.toLowerCase();
    final isImage = path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.gif') ||
        path.endsWith('.webp');
    final isPdf = path.endsWith('.pdf');

    return Stack(
      children: [
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isImage ? null : _S.bg,
            border: Border.all(color: _S.border),
            image: isImage
                ? DecorationImage(
                    image: FileImage(_receiptFile!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: isImage
              ? null
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isPdf ? Icons.picture_as_pdf : Icons.table_chart,
                      size: 36,
                      color: isPdf ? Colors.red : Colors.green,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _receiptFile!.path.split('/').last,
                      style: GoogleFonts.inter(fontSize: 12, color: _S.textSecondary),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: () => setState(() => _receiptFile = null),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    final isExceedingLimit = _limitWarning != null;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _isSubmitting ? null : _submitExpense,
        style: ElevatedButton.styleFrom(
          backgroundColor: isExceedingLimit ? _S.warningOrange : _S.accentBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        icon: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.check_circle_outline),
        label: Text(
          _isSubmitting
              ? 'Submitting...'
              : (isExceedingLimit ? 'Submit (Over Limit)' : 'Submit Expense'),
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // ============================================================================
  // LOGIC
  // ============================================================================

  void _updateDailyLimit() {
    if (_selectedCategory == null) {
      setState(() => _dailyLimit = null);
      return;
    }

    final limit = TravelAllowanceLimits.getLimitForCategory(
      grade: _employeeGrade,
      category: _selectedCategory!.name,
      employee: _employee,
    );

    setState(() => _dailyLimit = limit);
  }

  void _calculateFuelAmount() {
    final distance = double.tryParse(_distanceController.text);
    if (distance != null && distance > 0) {
      double rate;
      if (_selectedCategory?.name == 'fuel_car') {
         rate = ((_employee?.carRatePerKm ?? 0) > 0) ? _employee!.carRatePerKm! : TravelAllowanceLimits.getFuelRatePerKm(_employeeGrade);
      } else {
         rate = ((_employee?.bikeRatePerKm ?? 0) > 0) ? _employee!.bikeRatePerKm! : TravelAllowanceLimits.getBikeRatePerKm(_employeeGrade);
      }
      final amount = distance * rate;
      _amountController.text = amount.toStringAsFixed(2);
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  void _showFilePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _S.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Add Receipt / Document',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _S.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Supports: JPG, PNG, PDF, Excel',
              style: GoogleFonts.inter(color: _S.textDim, fontSize: 12),
            ),
            const SizedBox(height: 20),
            _buildPickerOption(
              icon: Icons.camera_alt,
              color: _S.accentBlue,
              title: 'Take Photo',
              subtitle: 'Use camera to capture receipt',
              onTap: () async {
                Navigator.pop(context);
                await _pickImage(ImageSource.camera);
              },
            ),
            _buildPickerOption(
              icon: Icons.photo_library,
              color: _S.successGreen,
              title: 'Choose Image',
              subtitle: 'Select from gallery',
              onTap: () async {
                Navigator.pop(context);
                await _pickImage(ImageSource.gallery);
              },
            ),
            _buildPickerOption(
              icon: Icons.attach_file,
              color: _S.warningOrange,
              title: 'Choose Document',
              subtitle: 'PDF, Excel, or other files',
              onTap: () async {
                Navigator.pop(context);
                await _pickDocument();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: _S.textDim)),
      onTap: onTap,
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() => _receiptFile = File(pickedFile.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'xls', 'xlsx', 'jpg', 'jpeg', 'png'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() => _receiptFile = File(result.files.single.path!));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
      }
    }
  }

  void _submitExpense() async {
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a category'),
          backgroundColor: _S.errorRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    // Duplicate detection: check for same category + date
    try {
      final sb = Supabase.instance.client;
      final userId = sb.auth.currentUser?.id;
      if (userId != null && _amountController.text.isNotEmpty) {
        final dateStr = _selectedDate.toIso8601String().split('T').first;
        final existing = await sb
            .from('expense_claims')
            .select('id, total_amount, notes')
            .eq('employee_id', userId)
            .gte('created_at', '${dateStr}T00:00:00')
            .lte('created_at', '${dateStr}T23:59:59')
            .limit(5);

        if (existing is List && existing.isNotEmpty && mounted) {
          final amount = double.parse(_amountController.text);
          final duplicateFound = existing.any((e) {
            final existingAmt = (e['total_amount'] as num?)?.toDouble() ?? 0;
            return (existingAmt - amount).abs() < 1.0;
          });

          if (duplicateFound) {
            final proceed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    const Text('Possible Duplicate'),
                  ],
                ),
                content: Text(
                  'An expense with a similar amount (₹${amount.toStringAsFixed(0)}) was already submitted today.\n\nDo you still want to submit?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Submit Anyway'),
                  ),
                ],
              ),
            );

            if (proceed != true) {
              setState(() => _isSubmitting = false);
              return;
            }
          }
        }
      }
    } catch (_) {
      // If duplicate check fails, proceed with submission anyway
    }

    if (!mounted) return;

    String finalDesc = _descriptionController.text.trim();
    if (_isTravelExpense) {
      final tripContext =
          '[${_fromController.text.trim()} → ${_toController.text.trim()} via $_vehicleMode]';
      finalDesc =
          finalDesc.isNotEmpty ? '$tripContext $finalDesc' : tripContext;
    }

    context.read<ExpenseBloc>().add(ExpenseSubmitRequested(
      amount: _amountController.text.isNotEmpty ? double.parse(_amountController.text) : 0,
      category: _selectedCategory!.name,
      expenseDate: _selectedDate,
      description: finalDesc,
      title: _titleController.text.trim().isNotEmpty ? _titleController.text.trim() : null,
      receiptPath: _receiptFile?.path,
    ));
  }
}
