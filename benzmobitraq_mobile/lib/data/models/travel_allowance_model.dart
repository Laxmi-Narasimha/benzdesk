// Travel allowance limits based on employee grade
// Based on BENZ Packaging Travel Policy (Updated Feb 2026)

/// Employee grade/band for travel allowance
enum EmployeeGrade {
  executive,
  seniorExecutive,
  assistant,
  assistantManager,
  manager,
  seniorManager,
  agm,
  gm,
  plantHead,
  vp,
  director;

  /// Parse grade from string (e.g., from employee role or designation)
  static EmployeeGrade fromString(String? designation) {
    if (designation == null) return EmployeeGrade.executive;
    
    final lowered = designation.toLowerCase();
    
    if (lowered.contains('director')) return EmployeeGrade.director;
    if (lowered.contains('vp') || lowered.contains('vice president')) return EmployeeGrade.vp;
    if (lowered.contains('plant head')) return EmployeeGrade.plantHead;
    if (lowered.contains('cxo')) return EmployeeGrade.vp;
    if (lowered.contains('general manager') || lowered.contains('gm')) return EmployeeGrade.gm;
    if (lowered.contains('agm') || lowered.contains('assistant general manager')) return EmployeeGrade.agm;
    if (lowered.contains('senior manager') || lowered.contains('sr. manager')) return EmployeeGrade.seniorManager;
    if (lowered.contains('manager') && !lowered.contains('assistant')) return EmployeeGrade.manager;
    if (lowered.contains('assistant manager') || lowered.contains('asst. manager')) return EmployeeGrade.assistantManager;
    if (lowered.contains('assistant') || lowered.contains('asst')) return EmployeeGrade.assistant;
    if (lowered.contains('senior executive') || lowered.contains('sr. executive')) return EmployeeGrade.seniorExecutive;
    if (lowered.contains('operator')) return EmployeeGrade.executive;
    
    return EmployeeGrade.executive;
  }
  
  /// Get display name for grade
  String get displayName {
    switch (this) {
      case EmployeeGrade.executive: return 'Executive';
      case EmployeeGrade.seniorExecutive: return 'Senior Executive';
      case EmployeeGrade.assistant: return 'Assistant';
      case EmployeeGrade.assistantManager: return 'Assistant Manager';
      case EmployeeGrade.manager: return 'Manager';
      case EmployeeGrade.seniorManager: return 'Senior Manager';
      case EmployeeGrade.agm: return 'AGM';
      case EmployeeGrade.gm: return 'GM';
      case EmployeeGrade.plantHead: return 'Plant Head';
      case EmployeeGrade.vp: return 'VP';
      case EmployeeGrade.director: return 'Director';
    }
  }

  /// Get band name for display (grouped)
  String get bandName {
    switch (this) {
      case EmployeeGrade.executive:
      case EmployeeGrade.seniorExecutive:
        return 'Executives / Sr. Executives';
      case EmployeeGrade.assistant:
      case EmployeeGrade.assistantManager:
        return 'Assistant Managers';
      case EmployeeGrade.manager:
      case EmployeeGrade.seniorManager:
        return 'Managers / Sr. Managers';
      case EmployeeGrade.agm:
      case EmployeeGrade.gm:
      case EmployeeGrade.plantHead:
      case EmployeeGrade.vp:
      case EmployeeGrade.director:
        return 'AGM / GM / VP / CXO';
    }
  }
}

/// Travel allowance limits per category and grade
/// Based on BENZ Packaging Travel Policy
class TravelAllowanceLimits {
  // ============================================================
  // HOTEL STAY ENTITLEMENTS (Per Night)
  // All bookings via Corporate Make My Trip (CMMT)
  // ============================================================
  static double getHotelNightLimit(EmployeeGrade grade) {
    switch (grade) {
      case EmployeeGrade.executive:
      case EmployeeGrade.seniorExecutive:
        return 2000.0; // Budget (3-Star, Standard Rooms)
      case EmployeeGrade.assistant:
      case EmployeeGrade.assistantManager:
        return 3000.0; // 3-Star / Business Hotels
      case EmployeeGrade.manager:
      case EmployeeGrade.seniorManager:
        return 3500.0; // 3-4 Star Hotels
      case EmployeeGrade.agm:
      case EmployeeGrade.gm:
      case EmployeeGrade.plantHead:
      case EmployeeGrade.vp:
      case EmployeeGrade.director:
        return 4000.0; // 4-5 Star Hotels
    }
  }

  /// Get hotel category for grade
  static String getHotelCategory(EmployeeGrade grade) {
    switch (grade) {
      case EmployeeGrade.executive:
      case EmployeeGrade.seniorExecutive:
        return 'Budget (3-Star, Standard Rooms)';
      case EmployeeGrade.assistant:
      case EmployeeGrade.assistantManager:
        return '3-Star / Business Hotels';
      case EmployeeGrade.manager:
      case EmployeeGrade.seniorManager:
        return '3-4 Star Hotels';
      case EmployeeGrade.agm:
      case EmployeeGrade.gm:
      case EmployeeGrade.plantHead:
      case EmployeeGrade.vp:
      case EmployeeGrade.director:
        return '4-5 Star Hotels';
    }
  }

  // ============================================================
  // FOOD & DAILY ALLOWANCE (Per Day)
  // Applicable for travel beyond 50 km or requiring overnight stay
  // ============================================================
  static double getFoodDailyLimit(EmployeeGrade grade) {
    switch (grade) {
      case EmployeeGrade.executive:
      case EmployeeGrade.seniorExecutive:
        return 600.0; // ₹600/day - No alcohol reimbursed
      case EmployeeGrade.assistant:
      case EmployeeGrade.assistantManager:
        return 800.0; // ₹800/day - Bills mandatory
      case EmployeeGrade.manager:
      case EmployeeGrade.seniorManager:
        return 1000.0; // ₹1,000/day
      case EmployeeGrade.agm:
      case EmployeeGrade.gm:
      case EmployeeGrade.plantHead:
      case EmployeeGrade.vp:
      case EmployeeGrade.director:
        return 1500.0; // ₹1,500/day
    }
  }

  /// Get food allowance notes for display
  static String getFoodAllowanceNote(EmployeeGrade grade) {
    switch (grade) {
      case EmployeeGrade.executive:
      case EmployeeGrade.seniorExecutive:
        return 'No alcohol reimbursed';
      case EmployeeGrade.assistant:
      case EmployeeGrade.assistantManager:
        return 'Bills mandatory';
      default:
        return '';
    }
  }

  // ============================================================
  // LOCAL TRAVEL DAILY LIMITS
  // Band-wise Travel Entitlements (Within City / Factory / Client Visits)
  // ============================================================
  static double getLocalDailyLimit(EmployeeGrade grade) {
    switch (grade) {
      case EmployeeGrade.executive:
        return 300.0; // ₹300/day - Auto, Bus, Shared Cab
      case EmployeeGrade.seniorExecutive:
      case EmployeeGrade.assistant:
        return 500.0; // ₹500/day - Auto, Cab (Ola/Uber), Bus
      case EmployeeGrade.assistantManager:
        return 700.0; // ₹700/day - Cab (Ola/Uber)
      case EmployeeGrade.manager:
      case EmployeeGrade.seniorManager:
        return 1000.0; // ₹1,000/day - Cab, Personal Car, Bike
      case EmployeeGrade.agm:
      case EmployeeGrade.gm:
      case EmployeeGrade.plantHead:
      case EmployeeGrade.vp:
      case EmployeeGrade.director:
        return -1; // Actuals with justification (no limit)
    }
  }

  // ============================================================
  // FUEL REIMBURSEMENT (Per KM)
  // ============================================================
  static double getFuelRatePerKm(EmployeeGrade grade) {
    // Managers and above: ₹7.5/km for car
    switch (grade) {
      case EmployeeGrade.manager:
      case EmployeeGrade.seniorManager:
      case EmployeeGrade.agm:
      case EmployeeGrade.gm:
      case EmployeeGrade.plantHead:
      case EmployeeGrade.vp:
      case EmployeeGrade.director:
        return 7.5; // ₹7.5/km for car
      default:
        return 0; // Lower grades use company transport
    }
  }

  // Bike Fuel Rate per KM
  static double getBikeRatePerKm(EmployeeGrade grade) {
    switch (grade) {
      case EmployeeGrade.manager:
      case EmployeeGrade.seniorManager:
      case EmployeeGrade.agm:
      case EmployeeGrade.gm:
      case EmployeeGrade.plantHead:
      case EmployeeGrade.vp:
      case EmployeeGrade.director:
        return 5.0; // ₹5/km for bike
      default:
        return 0;
    }
  }

  // ============================================================
  // MISCELLANEOUS ALLOWANCES
  // ============================================================
  
  /// Laundry allowance (if stay > 3 nights)
  static double getLaundryDailyLimit() => 300.0; // Max ₹300/day

  /// Internet/Connectivity - Actuals with bill (no limit)
  static double getInternetLimit() => -1; // Actuals

  /// Toll/Parking - Actuals (no limit)
  static double getTollLimit() => -1; // Actuals

  // ============================================================
  // TRANSPORT MODES
  // ============================================================
  static List<String> getAllowedTransportModes(EmployeeGrade grade) {
    switch (grade) {
      case EmployeeGrade.executive:
        return ['Auto', 'Bus', 'Shared Cab'];
      case EmployeeGrade.seniorExecutive:
      case EmployeeGrade.assistant:
        return ['Auto', 'Cab (Ola/Uber)', 'Bus'];
      case EmployeeGrade.assistantManager:
        return ['Cab (Ola/Uber)'];
      case EmployeeGrade.manager:
      case EmployeeGrade.seniorManager:
        return ['Cab', 'Personal Car (Fuel Reimbursement @₹7.5/km)', 'Bike (@₹5/km)'];
      case EmployeeGrade.agm:
      case EmployeeGrade.gm:
      case EmployeeGrade.plantHead:
      case EmployeeGrade.vp:
      case EmployeeGrade.director:
        return ['Cab', 'Personal Car', 'Personal Driver'];
    }
  }

  // ============================================================
  // OUTSTATION TRAVEL MODES
  // ============================================================
  static String getOutstationTravelMode(EmployeeGrade grade) {
    switch (grade) {
      case EmployeeGrade.executive:
      case EmployeeGrade.seniorExecutive:
      case EmployeeGrade.assistant:
        return 'Sleeper / 3AC (Train), Bus (Volvo)\n(Flight only if >800km & urgent)';
      case EmployeeGrade.assistantManager:
        return '3AC (Train), Volvo, Economy Flight (case-to-case)\nManager approval mandatory';
      case EmployeeGrade.manager:
      case EmployeeGrade.seniorManager:
        return 'Economy Flight / 2AC\nMust be booked via TOC';
      case EmployeeGrade.agm:
      case EmployeeGrade.gm:
      case EmployeeGrade.plantHead:
      case EmployeeGrade.vp:
      case EmployeeGrade.director:
        return 'Economy Flight, 2AC\nNeed FH approval';
    }
  }

  // ============================================================
  // LIMIT CHECKING UTILITIES
  // ============================================================
  
  /// Check if expense exceeds limit
  static bool exceedsLimit({
    required EmployeeGrade grade,
    required String category,
    required double amount,
  }) {
    double limit = getLimitForCategory(grade: grade, category: category) ?? -1;
    if (limit < 0) return false; // -1 means actuals accepted
    return amount > limit;
  }

  /// Get warning message if expense exceeds limit
  static String? getWarningMessage({
    required EmployeeGrade grade,
    required String category,
    required double amount,
  }) {
    if (!exceedsLimit(grade: grade, category: category, amount: amount)) {
      return null;
    }

    double? limit = getLimitForCategory(grade: grade, category: category);
    if (limit == null || limit < 0) return null;

    String limitType = _getLimitTypeForCategory(category);

    return 'Amount exceeds your $limitType of ₹${limit.toInt()}\n'
           'For ${grade.bandName}. Skip-level approval required.';
  }

  static String _getLimitTypeForCategory(String category) {
    final lowered = category.toLowerCase();
    if (lowered == 'accommodation' || lowered == 'hotel') {
      return 'nightly hotel allowance';
    } else if (lowered == 'food' || lowered == 'food & meals' || lowered == 'food_da') {
      return 'daily food allowance';
    } else if (lowered == 'laundry') {
      return 'daily laundry allowance';
    }
    return 'daily travel allowance';
  }

  /// Check if category has daily limits
  static bool hasDailyLimit(String category) {
    final lowered = category.toLowerCase();
    return lowered == 'travel' || 
           lowered == 'conveyance' || 
           lowered == 'local_conveyance' ||
           lowered == 'food' || 
           lowered == 'food_da' ||
           lowered == 'food & meals' ||
           lowered == 'accommodation' ||
           lowered == 'hotel' ||
           lowered == 'laundry';
  }

  /// Get the limit for a specific category and grade
  static double? getLimitForCategory({
    required EmployeeGrade grade,
    required String category,
  }) {
    final lowered = category.toLowerCase();
    
    // Local Travel
    if (lowered == 'travel' || lowered == 'conveyance' || lowered == 'local_conveyance' ||
        lowered == 'travel_allowance' || lowered == 'transport_expense') {
      final limit = getLocalDailyLimit(grade);
      return limit < 0 ? null : limit; // null means actuals
    }
    
    // Food DA
    if (lowered == 'food' || lowered == 'food_da' || lowered == 'food & meals') {
      return getFoodDailyLimit(grade);
    }
    
    // Accommodation
    if (lowered == 'accommodation' || lowered == 'hotel') {
      return getHotelNightLimit(grade);
    }

    // Laundry
    if (lowered == 'laundry') {
      return getLaundryDailyLimit();
    }
    
    return null; // No limit for other categories (Toll, Parking, Internet, etc.)
  }

  /// Get limit info text for display
  static String getLimitInfoText({
    required EmployeeGrade grade,
    required String category,
  }) {
    final limit = getLimitForCategory(grade: grade, category: category);
    
    if (limit == null) {
      return 'Actuals with bill for ${grade.bandName}';
    }
    
    final lowered = category.toLowerCase();
    String period = 'per day';
    if (lowered == 'accommodation' || lowered == 'hotel') {
      period = 'per night';
    }
    
    return 'Limit: ₹${limit.toInt()} $period for ${grade.bandName}';
  }

  /// Calculate remaining allowance for the day
  static double getRemainingAllowance({
    required EmployeeGrade grade,
    required String category,
    required double alreadySpent,
  }) {
    final limit = getLimitForCategory(grade: grade, category: category);
    if (limit == null) return double.infinity;
    return (limit - alreadySpent).clamp(0, limit);
  }

  /// Get warning with daily spent considered
  static String? getWarningWithDailySpent({
    required EmployeeGrade grade,
    required String category,
    required double amount,
    required double alreadySpentToday,
  }) {
    final limit = getLimitForCategory(grade: grade, category: category);
    if (limit == null) return null; // No limit
    
    final totalToday = alreadySpentToday + amount;
    
    if (totalToday > limit) {
      final exceeded = totalToday - limit;
      return 'Exceeds daily limit by ₹${exceeded.toInt()}\n'
             'Today\'s total: ₹${totalToday.toInt()} / ₹${limit.toInt()} limit\n'
             'Skip-level approval required.';
    }
    
    return null;
  }
}

/// Expense category with limit info
class ExpenseCategoryInfo {
  final String name;
  final String displayName;
  final String icon;
  final bool hasDailyLimit;
  final bool isTravelRelated;
  final String? description;

  const ExpenseCategoryInfo({
    required this.name,
    required this.displayName,
    required this.icon,
    required this.hasDailyLimit,
    required this.isTravelRelated,
    this.description,
  });

  /// All expense categories aligned with BENZ Travel Policy
  static const List<ExpenseCategoryInfo> allCategories = [
    // ========================================
    // TRAVEL & TRANSPORT
    // ========================================
    ExpenseCategoryInfo(
      name: 'local_conveyance',
      displayName: 'Local Conveyance',
      icon: '🚗',
      hasDailyLimit: true,
      isTravelRelated: true,
      description: 'Auto, Bus, Cab for local travel',
    ),
    ExpenseCategoryInfo(
      name: 'fuel',
      displayName: 'Fuel',
      icon: '⛽',
      hasDailyLimit: false,
      isTravelRelated: true,
      description: 'Car @₹7.5/km, Bike @₹5/km (Mgrs+)',
    ),
    ExpenseCategoryInfo(
      name: 'toll',
      displayName: 'Toll / Parking',
      icon: '🛣️',
      hasDailyLimit: false,
      isTravelRelated: true,
      description: 'Actuals with receipt',
    ),
    ExpenseCategoryInfo(
      name: 'outstation_travel',
      displayName: 'Outstation Travel',
      icon: '✈️',
      hasDailyLimit: false,
      isTravelRelated: true,
      description: 'Flight / Train / Bus tickets',
    ),

    // ========================================
    // DAILY ALLOWANCES (Outstation)
    // ========================================
    ExpenseCategoryInfo(
      name: 'food_da',
      displayName: 'Food & Daily Allowance',
      icon: '🍽️',
      hasDailyLimit: true,
      isTravelRelated: true,
      description: 'For travel >50km or overnight',
    ),
    ExpenseCategoryInfo(
      name: 'accommodation',
      displayName: 'Hotel / Accommodation',
      icon: '🏨',
      hasDailyLimit: true,
      isTravelRelated: true,
      description: 'Book via Corporate MMT',
    ),
    ExpenseCategoryInfo(
      name: 'laundry',
      displayName: 'Laundry',
      icon: '👔',
      hasDailyLimit: true,
      isTravelRelated: true,
      description: 'Max ₹300/day if stay >3 nights',
    ),

    // ========================================
    // MISCELLANEOUS (Actuals)
    // ========================================
    ExpenseCategoryInfo(
      name: 'internet',
      displayName: 'Internet / Connectivity',
      icon: '📶',
      hasDailyLimit: false,
      isTravelRelated: false,
      description: 'Actuals with bill',
    ),
    ExpenseCategoryInfo(
      name: 'mobile',
      displayName: 'Mobile Recharge',
      icon: '📱',
      hasDailyLimit: false,
      isTravelRelated: false,
      description: 'Work-related only',
    ),

    // ========================================
    // BUSINESS EXPENSES
    // ========================================
    ExpenseCategoryInfo(
      name: 'petty_cash',
      displayName: 'Petty Cash',
      icon: '💵',
      hasDailyLimit: false,
      isTravelRelated: false,
      description: 'Small office expenses',
    ),
    ExpenseCategoryInfo(
      name: 'advance_request',
      displayName: 'Advance Request',
      icon: '💳',
      hasDailyLimit: false,
      isTravelRelated: false,
      description: 'Pre-approved advances',
    ),
    ExpenseCategoryInfo(
      name: 'stationary',
      displayName: 'Stationary',
      icon: '✏️',
      hasDailyLimit: false,
      isTravelRelated: false,
      description: 'Office supplies',
    ),
    ExpenseCategoryInfo(
      name: 'medical',
      displayName: 'Medical',
      icon: '🏥',
      hasDailyLimit: false,
      isTravelRelated: false,
      description: 'Emergency medical expenses',
    ),
    ExpenseCategoryInfo(
      name: 'other',
      displayName: 'Other',
      icon: '📋',
      hasDailyLimit: false,
      isTravelRelated: false,
      description: 'Miscellaneous expenses',
    ),
  ];

  /// Get travel-related categories
  static List<ExpenseCategoryInfo> get travelCategories =>
      allCategories.where((c) => c.isTravelRelated).toList();

  /// Get non-travel categories
  static List<ExpenseCategoryInfo> get otherCategories =>
      allCategories.where((c) => !c.isTravelRelated).toList();

  /// Find category by name
  static ExpenseCategoryInfo? findByName(String name) {
    try {
      return allCategories.firstWhere(
        (c) => c.name == name || c.displayName.toLowerCase() == name.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }
}
