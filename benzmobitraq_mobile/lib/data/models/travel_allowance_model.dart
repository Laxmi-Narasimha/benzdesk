/// Travel allowance limits based on employee grade
/// Based on BENZ Packaging Travel Policy

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
    if (lowered.contains('general manager') || lowered.contains('gm')) return EmployeeGrade.gm;
    if (lowered.contains('agm') || lowered.contains('assistant general manager')) return EmployeeGrade.agm;
    if (lowered.contains('senior manager')) return EmployeeGrade.seniorManager;
    if (lowered.contains('manager') && !lowered.contains('assistant')) return EmployeeGrade.manager;
    if (lowered.contains('assistant manager')) return EmployeeGrade.assistantManager;
    if (lowered.contains('assistant')) return EmployeeGrade.assistant;
    if (lowered.contains('senior executive') || lowered.contains('sr. executive')) return EmployeeGrade.seniorExecutive;
    
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
}

/// Travel allowance limits per category and grade
class TravelAllowanceLimits {
  // Local Travel Daily Limits
  static double getLocalDailyLimit(EmployeeGrade grade) {
    switch (grade) {
      case EmployeeGrade.executive:
        return 300.0; // ₹300/day
      case EmployeeGrade.seniorExecutive:
      case EmployeeGrade.assistant:
        return 500.0; // ₹500/day
      case EmployeeGrade.assistantManager:
        return 700.0; // ₹700/day
      case EmployeeGrade.manager:
      case EmployeeGrade.seniorManager:
        return 1000.0; // ₹1,000/day
      case EmployeeGrade.agm:
      case EmployeeGrade.gm:
      case EmployeeGrade.plantHead:
      case EmployeeGrade.vp:
      case EmployeeGrade.director:
        return -1; // Actuals with justification (no limit)
    }
  }

  // Outstation Hotel Night Limits
  static double getHotelNightLimit(EmployeeGrade grade) {
    switch (grade) {
      case EmployeeGrade.executive:
      case EmployeeGrade.seniorExecutive:
      case EmployeeGrade.assistant:
        return 1500.0; // ₹1,500/night
      case EmployeeGrade.assistantManager:
        return 2000.0; // ₹2,000/night
      case EmployeeGrade.manager:
      case EmployeeGrade.seniorManager:
        return 3000.0; // ₹3,000/night
      case EmployeeGrade.agm:
      case EmployeeGrade.gm:
        return 4000.0; // ₹4,000/night
      case EmployeeGrade.plantHead:
      case EmployeeGrade.vp:
      case EmployeeGrade.director:
        return 5000.0; // ₹5,000/night
    }
  }

  // Outstation Food Daily Limits
  static double getFoodDailyLimit(EmployeeGrade grade) {
    switch (grade) {
      case EmployeeGrade.executive:
      case EmployeeGrade.seniorExecutive:
      case EmployeeGrade.assistant:
        return 300.0; // ₹300/day
      case EmployeeGrade.assistantManager:
        return 400.0; // ₹400/day
      case EmployeeGrade.manager:
      case EmployeeGrade.seniorManager:
        return 500.0; // ₹500/day
      case EmployeeGrade.agm:
      case EmployeeGrade.gm:
      case EmployeeGrade.plantHead:
      case EmployeeGrade.vp:
      case EmployeeGrade.director:
        return 700.0; // ₹700/day
    }
  }

  // Fuel Reimbursement Rate per KM
  static double getFuelRatePerKm(EmployeeGrade grade) {
    // Managers and above: ₹7.5/km for car, ₹5/km for bike
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

  /// Get allowed transport modes for grade
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
        return ['Cab', 'Personal Car (Fuel Reimbursement)', 'Bike'];
      case EmployeeGrade.agm:
      case EmployeeGrade.gm:
      case EmployeeGrade.plantHead:
      case EmployeeGrade.vp:
      case EmployeeGrade.director:
        return ['Cab', 'Personal Car', 'Personal Driver'];
    }
  }

  /// Get allowed outstation travel modes
  static String getOutstationTravelMode(EmployeeGrade grade) {
    switch (grade) {
      case EmployeeGrade.executive:
      case EmployeeGrade.seniorExecutive:
      case EmployeeGrade.assistant:
        return 'Sleeper / 3AC Train, Volvo Bus\n(Flight only if >800km & urgent)';
      case EmployeeGrade.assistantManager:
        return '3AC Train, Volvo Bus, Economy Flight (case-to-case)';
      case EmployeeGrade.manager:
      case EmployeeGrade.seniorManager:
        return 'Economy Flight, 2AC Train';
      case EmployeeGrade.agm:
      case EmployeeGrade.gm:
      case EmployeeGrade.plantHead:
      case EmployeeGrade.vp:
      case EmployeeGrade.director:
        return 'Economy Flight, 2AC Train (FH Approval)';
    }
  }

  /// Check if expense exceeds limit
  static bool exceedsLimit({
    required EmployeeGrade grade,
    required String category,
    required double amount,
  }) {
    double limit;
    
    switch (category.toLowerCase()) {
      case 'food':
      case 'food & meals':
        limit = getFoodDailyLimit(grade);
        break;
      case 'accommodation':
        limit = getHotelNightLimit(grade);
        break;
      case 'travel':
      case 'conveyance':
        limit = getLocalDailyLimit(grade);
        break;
      default:
        return false; // No limit for other categories
    }
    
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

    double limit;
    String limitType;
    
    switch (category.toLowerCase()) {
      case 'food':
      case 'food & meals':
        limit = getFoodDailyLimit(grade);
        limitType = 'daily food allowance';
        break;
      case 'accommodation':
        limit = getHotelNightLimit(grade);
        limitType = 'nightly hotel allowance';
        break;
      case 'travel':
      case 'conveyance':
        limit = getLocalDailyLimit(grade);
        limitType = 'daily travel allowance';
        break;
      default:
        return null;
    }

    return 'Amount exceeds your $limitType of ₹${limit.toInt()}\n'
           'For ${grade.displayName} grade. Skip-level approval may be required.';
  }

  /// Check if category has daily limits
  static bool hasDailyLimit(String category) {
    final lowered = category.toLowerCase();
    return lowered == 'travel' || 
           lowered == 'conveyance' || 
           lowered == 'local conveyance' ||
           lowered == 'food' || 
           lowered == 'food & meals' ||
           lowered == 'accommodation';
  }

  /// Get the limit for a specific category and grade
  static double? getLimitForCategory({
    required EmployeeGrade grade,
    required String category,
  }) {
    final lowered = category.toLowerCase();
    
    if (lowered == 'travel' || lowered == 'conveyance' || lowered == 'local conveyance') {
      final limit = getLocalDailyLimit(grade);
      return limit < 0 ? null : limit; // null means no limit
    }
    
    if (lowered == 'food' || lowered == 'food & meals') {
      return getFoodDailyLimit(grade);
    }
    
    if (lowered == 'accommodation') {
      return getHotelNightLimit(grade);
    }
    
    return null; // No limit for other categories
  }

  /// Get limit info text for display
  static String getLimitInfoText({
    required EmployeeGrade grade,
    required String category,
  }) {
    final limit = getLimitForCategory(grade: grade, category: category);
    
    if (limit == null) {
      return 'No daily limit for ${grade.displayName}';
    }
    
    final lowered = category.toLowerCase();
    String period = 'per day';
    if (lowered == 'accommodation') {
      period = 'per night';
    }
    
    return 'Limit: ₹${limit.toInt()} $period for ${grade.displayName}';
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

  const ExpenseCategoryInfo({
    required this.name,
    required this.displayName,
    required this.icon,
    required this.hasDailyLimit,
    required this.isTravelRelated,
  });

  /// All expense categories aligned with BenzDesk request types
  static const List<ExpenseCategoryInfo> allCategories = [
    // Travel & Transport (with daily limits)
    ExpenseCategoryInfo(
      name: 'travel_allowance',
      displayName: 'Travel Allowance (TA/DA)',
      icon: '🚗',
      hasDailyLimit: true,
      isTravelRelated: true,
    ),
    ExpenseCategoryInfo(
      name: 'transport_expense',
      displayName: 'Transport Expense',
      icon: '🚐',
      hasDailyLimit: true,
      isTravelRelated: true,
    ),
    ExpenseCategoryInfo(
      name: 'local_conveyance',
      displayName: 'Local Conveyance',
      icon: '🚌',
      hasDailyLimit: true,
      isTravelRelated: true,
    ),
    ExpenseCategoryInfo(
      name: 'fuel',
      displayName: 'Fuel',
      icon: '⛽',
      hasDailyLimit: false,
      isTravelRelated: true,
    ),
    ExpenseCategoryInfo(
      name: 'toll',
      displayName: 'Toll',
      icon: '🛣️',
      hasDailyLimit: false,
      isTravelRelated: true,
    ),
    // Daily Expenses (with daily limits)
    ExpenseCategoryInfo(
      name: 'food',
      displayName: 'Food & Meals',
      icon: '🍽️',
      hasDailyLimit: true,
      isTravelRelated: true,
    ),
    ExpenseCategoryInfo(
      name: 'accommodation',
      displayName: 'Accommodation',
      icon: '🏨',
      hasDailyLimit: true,
      isTravelRelated: true,
    ),
    // Business Expenses (no daily limits)
    ExpenseCategoryInfo(
      name: 'petty_cash',
      displayName: 'Petty Cash',
      icon: '💵',
      hasDailyLimit: false,
      isTravelRelated: false,
    ),
    ExpenseCategoryInfo(
      name: 'advance_request',
      displayName: 'Advance Expense',
      icon: '💳',
      hasDailyLimit: false,
      isTravelRelated: false,
    ),
    ExpenseCategoryInfo(
      name: 'mobile_internet',
      displayName: 'Mobile/Internet',
      icon: '📱',
      hasDailyLimit: false,
      isTravelRelated: false,
    ),
    ExpenseCategoryInfo(
      name: 'stationary',
      displayName: 'Stationary',
      icon: '✏️',
      hasDailyLimit: false,
      isTravelRelated: false,
    ),
    ExpenseCategoryInfo(
      name: 'medical',
      displayName: 'Medical',
      icon: '🏥',
      hasDailyLimit: false,
      isTravelRelated: false,
    ),
    ExpenseCategoryInfo(
      name: 'other',
      displayName: 'Other',
      icon: '📋',
      hasDailyLimit: false,
      isTravelRelated: false,
    ),
  ];


  static List<ExpenseCategoryInfo> get travelCategories =>
      allCategories.where((c) => c.isTravelRelated).toList();

  static List<ExpenseCategoryInfo> get otherCategories =>
      allCategories.where((c) => !c.isTravelRelated).toList();

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
