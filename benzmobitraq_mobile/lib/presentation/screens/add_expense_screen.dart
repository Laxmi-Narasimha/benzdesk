import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models/travel_allowance_model.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/datasources/local/preferences_local.dart';
import '../blocs/auth/auth_bloc.dart';
import '../blocs/expense/expense_bloc.dart';

/// Screen for adding a new expense claim with proper category selection
/// and daily limit tracking based on BENZ Travel Policy
class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _distanceController = TextEditingController(); // For fuel expenses
  
  // Current step: 0 = type, 1 = category, 2 = details
  int _currentStep = 0;
  
  // Selected expense type (travel or other)
  bool _isTravelExpense = true;
  
  // Selected category
  ExpenseCategoryInfo? _selectedCategory;
  
  // Date and receipt
  DateTime _selectedDate = DateTime.now();
  File? _receiptImage;
  bool _isSubmitting = false;
  
  // Employee info
  EmployeeGrade _employeeGrade = EmployeeGrade.executive;
  String? _employeeId;
  
  // Daily spent tracking
  double _alreadySpentToday = 0;
  bool _isLoadingDailyTotal = false;
  
  // Warning message
  String? _limitWarning;
  double? _dailyLimit;
  double? _remainingAllowance;

  @override
  void initState() {
    super.initState();
    _loadEmployeeInfo();
  }

  void _loadEmployeeInfo() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _employeeGrade = EmployeeGrade.fromString(authState.employee.role);
      _employeeId = authState.employee.id;
    }
  }

  Future<void> _loadDailyTotal() async {
    if (_selectedCategory == null || _employeeId == null) return;
    if (!_selectedCategory!.hasDailyLimit) return;
    
    setState(() => _isLoadingDailyTotal = true);
    
    try {
      final expenseBloc = context.read<ExpenseBloc>();
      // Get the repository from bloc or use a simplified approach
      // For now, we'll just show the limit without querying
      
      final limit = TravelAllowanceLimits.getLimitForCategory(
        grade: _employeeGrade,
        category: _selectedCategory!.displayName,
      );
      
      setState(() {
        _dailyLimit = limit;
        _alreadySpentToday = 0; // Will be fetched from actual data
        _remainingAllowance = limit;
        _isLoadingDailyTotal = false;
      });
    } catch (e) {
      setState(() => _isLoadingDailyTotal = false);
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
      alreadySpentToday: _alreadySpentToday,
    );

    setState(() => _limitWarning = warning);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _distanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ExpenseBloc, ExpenseState>(
      listener: (context, state) {
        if (state is ExpenseSubmitSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Expense submitted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else if (state is ExpenseError) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          title: const Text('Add Expense'),
          elevation: 0,
        ),
        body: Form(
          key: _formKey,
          child: Stepper(
            currentStep: _currentStep,
            onStepContinue: _onStepContinue,
            onStepCancel: _onStepCancel,
            controlsBuilder: _buildStepperControls,
            steps: [
              // Step 1: Select expense type
              Step(
                title: const Text('Expense Type'),
                subtitle: _currentStep > 0 
                    ? Text(_isTravelExpense ? 'Travel Related' : 'Other Expense')
                    : null,
                isActive: _currentStep >= 0,
                state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                content: _buildExpenseTypeStep(),
              ),
              // Step 2: Select category
              Step(
                title: const Text('Category'),
                subtitle: _currentStep > 1 && _selectedCategory != null
                    ? Text(_selectedCategory!.displayName)
                    : null,
                isActive: _currentStep >= 1,
                state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                content: _buildCategoryStep(),
              ),
              // Step 3: Enter details
              Step(
                title: const Text('Details'),
                isActive: _currentStep >= 2,
                state: StepState.indexed,
                content: _buildDetailsStep(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepperControls(BuildContext context, ControlsDetails details) {
    final isLastStep = _currentStep == 2;
    
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            TextButton(
              onPressed: details.onStepCancel,
              child: const Text('Back'),
            )
          else
            const SizedBox.shrink(),
          SizedBox(
            width: 120,
            height: 48,
            child: ElevatedButton(
              onPressed: isLastStep && _isSubmitting ? null : details.onStepContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(isLastStep ? 'Submit' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }

  void _onStepContinue() {
    if (_currentStep == 0) {
      setState(() => _currentStep = 1);
    } else if (_currentStep == 1) {
      if (_selectedCategory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a category')),
        );
        return;
      }
      _loadDailyTotal();
      setState(() => _currentStep = 2);
    } else if (_currentStep == 2) {
      _submitExpense();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
    }
  }

  Widget _buildExpenseTypeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What type of expense is this?',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTypeCard(
                title: 'Travel Related',
                subtitle: 'Conveyance, Food, Hotel, Toll, Fuel',
                icon: Icons.directions_car,
                isSelected: _isTravelExpense,
                onTap: () => setState(() => _isTravelExpense = true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTypeCard(
                title: 'Other',
                subtitle: 'Parking, Mobile, Medical, Stationary',
                icon: Icons.receipt,
                isSelected: !_isTravelExpense,
                onTap: () => setState(() => _isTravelExpense = false),
              ),
            ),
          ],
        ),
        if (_isTravelExpense) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your grade: ${_employeeGrade.displayName}\nDaily limits apply to travel expenses',
                    style: const TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
        ],
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
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
              : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 40,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryStep() {
    final categories = _isTravelExpense
        ? ExpenseCategoryInfo.travelCategories
        : ExpenseCategoryInfo.otherCategories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Grade info banner
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.badge_outlined,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Your Band: ${_employeeGrade.bandName}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),

        Text(
          'Select ${_isTravelExpense ? "travel" : "business"} expense category:',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),

        // Category cards
        ...categories.map((category) {
          final isSelected = _selectedCategory?.name == category.name;
          final limit = TravelAllowanceLimits.getLimitForCategory(
            grade: _employeeGrade,
            category: category.name,
          );

          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = category),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                    : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        category.icon,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name and description
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        if (category.description != null)
                          Text(
                            category.description!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Limit badge
                  if (limit != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Text(
                        '₹${limit.toInt()}/day',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange,
                        ),
                      ),
                    )
                  else if (category.name == 'accommodation')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '₹${TravelAllowanceLimits.getHotelNightLimit(_employeeGrade).toInt()}/night',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.purple,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Actuals',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                    ),

                  const SizedBox(width: 8),

                  // Selection indicator
                  Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.withOpacity(0.3),
                    size: 24,
                  ),
                ],
              ),
            ),
          );
        }).toList(),

        // Selected category info
        if (_selectedCategory != null && _selectedCategory!.hasDailyLimit) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    TravelAllowanceLimits.getLimitInfoText(
                      grade: _employeeGrade,
                      category: _selectedCategory!.name,
                    ),
                    style: const TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDetailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category display
        if (_selectedCategory != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Text(_selectedCategory!.icon, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedCategory!.displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (_dailyLimit != null)
                        Text(
                          'Today\'s remaining: ₹${_remainingAllowance?.toInt() ?? 0} / ₹${_dailyLimit!.toInt()}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Fuel-specific: Distance input
        if (_selectedCategory?.name == 'fuel') ...[
          _buildLabel('Distance (KM)'),
          TextFormField(
            controller: _distanceController,
            keyboardType: TextInputType.number,
            decoration: _inputDecoration('Enter distance in KM'),
            onChanged: (_) => _calculateFuelAmount(),
          ),
          const SizedBox(height: 8),
          Text(
            'Rate: ₹${TravelAllowanceLimits.getFuelRatePerKm(_employeeGrade)}/km',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Amount
        _buildLabel('Amount'),
        TextFormField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _checkAllowanceLimit(),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          decoration: _inputDecoration('0.00').copyWith(
            prefixText: '₹ ',
            prefixStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Required';
            if (double.tryParse(value) == null) return 'Invalid amount';
            if (double.parse(value) <= 0) return 'Must be > 0';
            return null;
          },
        ),

        // Warning for exceeding limit
        if (_limitWarning != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _limitWarning!,
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Date
        _buildLabel('Date'),
        InkWell(
          onTap: _selectDate,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                // Ensure textual display uses IST
                Text(DateFormat('EEEE, MMMM d, yyyy').format(DateTimeUtils.toIST(_selectedDate))),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Description
        _buildLabel('Description (Optional)'),
        TextFormField(
          controller: _descriptionController,
          maxLines: 2,
          decoration: _inputDecoration('Add a note about this expense...'),
        ),

        const SizedBox(height: 16),

        // Receipt
        _buildLabel('Receipt / Document'),
        if (_receiptImage != null)
          _buildReceiptPreview()
        else
          InkWell(
            onTap: _showImagePicker,
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.attach_file,
                    size: 32,
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add Receipt (Image, PDF, Excel)',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to select file',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Build receipt preview based on file type
  Widget _buildReceiptPreview() {
    final path = _receiptImage!.path.toLowerCase();
    final isImage = path.endsWith('.jpg') || 
                    path.endsWith('.jpeg') || 
                    path.endsWith('.png') ||
                    path.endsWith('.gif') ||
                    path.endsWith('.webp');
    final isPdf = path.endsWith('.pdf');
    final isExcel = path.endsWith('.xls') || path.endsWith('.xlsx');

    return Stack(
      children: [
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isImage 
                ? null 
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            image: isImage 
                ? DecorationImage(
                    image: FileImage(_receiptImage!),
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
                      size: 40,
                      color: isPdf ? Colors.red : Colors.green,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _receiptImage!.path.split('/').last,
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPdf ? 'PDF Document' : 'Excel File',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            icon: Icon(
              Icons.close, 
              color: isImage ? Colors.white : Colors.grey[700],
            ),
            style: IconButton.styleFrom(
              backgroundColor: isImage ? Colors.black54 : Colors.grey[200],
            ),
            onPressed: () => setState(() => _receiptImage = null),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
    );
  }

  void _calculateFuelAmount() {
    final distance = double.tryParse(_distanceController.text);
    if (distance != null && distance > 0) {
      final rate = TravelAllowanceLimits.getFuelRatePerKm(_employeeGrade);
      final amount = distance * rate;
      _amountController.text = amount.toStringAsFixed(2);
      _checkAllowanceLimit();
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
      _loadDailyTotal();
    }
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add Receipt',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Supports: JPG, PNG, PDF, Excel',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.camera_alt,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              title: const Text('Take Photo'),
              subtitle: const Text('Use camera to capture receipt'),
              onTap: () async {
                Navigator.pop(context);
                await _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.photo_library,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              title: const Text('Choose Image'),
              subtitle: const Text('Select from gallery'),
              onTap: () async {
                Navigator.pop(context);
                await _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.attach_file,
                  color: Colors.orange,
                ),
              ),
              title: const Text('Choose Document'),
              subtitle: const Text('PDF, Excel, or other files'),
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
        setState(() => _receiptImage = File(pickedFile.path));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'xls', 'xlsx', 'jpg', 'jpeg', 'png'],
      );
      
      if (result != null && result.files.single.path != null) {
        setState(() => _receiptImage = File(result.files.single.path!));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking file: $e')),
      );
    }
  }

  void _submitExpense() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }
    
    setState(() => _isSubmitting = true);
    
    context.read<ExpenseBloc>().add(ExpenseSubmitRequested(
      amount: double.parse(_amountController.text),
      category: _selectedCategory!.name, // Use name, not displayName, for database
      expenseDate: _selectedDate,
      description: _descriptionController.text.isNotEmpty 
          ? _descriptionController.text 
          : null,
      receiptPath: _receiptImage?.path,
    ));

  }
}
