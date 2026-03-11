import 'package:equatable/equatable.dart';

/// Trip model representing a planned business trip
class TripModel extends Equatable {
  final String id;
  final String employeeId;
  final String fromLocation;
  final String toLocation;
  final String? reason;
  final String vehicleType;
  final String status; // requested, approved, active, completed, cancelled, rejected
  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final double totalKm;
  final double totalExpenses;
  final String? notes;

  const TripModel({
    required this.id,
    required this.employeeId,
    required this.fromLocation,
    required this.toLocation,
    this.reason,
    this.vehicleType = 'car',
    this.status = 'requested',
    required this.createdAt,
    this.approvedAt,
    this.startedAt,
    this.endedAt,
    this.totalKm = 0,
    this.totalExpenses = 0,
    this.notes,
  });

  factory TripModel.fromJson(Map<String, dynamic> json) {
    return TripModel(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      fromLocation: json['from_location'] as String,
      toLocation: json['to_location'] as String,
      reason: json['reason'] as String?,
      vehicleType: json['vehicle_type'] as String? ?? 'car',
      status: json['status'] as String? ?? 'requested',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      approvedAt: json['approved_at'] != null ? DateTime.tryParse(json['approved_at']) : null,
      startedAt: json['started_at'] != null ? DateTime.tryParse(json['started_at']) : null,
      endedAt: json['ended_at'] != null ? DateTime.tryParse(json['ended_at']) : null,
      totalKm: (json['total_km'] as num?)?.toDouble() ?? 0,
      totalExpenses: (json['total_expenses'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'employee_id': employeeId,
    'from_location': fromLocation,
    'to_location': toLocation,
    'reason': reason,
    'vehicle_type': vehicleType,
    'status': status,
    'notes': notes,
  };

  bool get isActive => status == 'active';
  bool get isPending => status == 'requested';
  bool get isCompleted => status == 'completed';

  String get statusLabel {
    switch (status) {
      case 'requested': return 'Starting...';
      case 'approved': return 'Ready';
      case 'active': return 'Active';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      case 'rejected': return 'Stopped';
      default: return status;
    }
  }

  @override
  List<Object?> get props => [id, employeeId, fromLocation, toLocation, status, createdAt];
}

/// Trip expense model
class TripExpenseModel extends Equatable {
  final String id;
  final String tripId;
  final String employeeId;
  final String category;
  final double amount;
  final String? description;
  final String? receiptPath;
  final DateTime date;
  final String status;
  final double? limitAmount;
  final bool exceedsLimit;
  final DateTime createdAt;

  const TripExpenseModel({
    required this.id,
    required this.tripId,
    required this.employeeId,
    required this.category,
    required this.amount,
    this.description,
    this.receiptPath,
    required this.date,
    this.status = 'pending',
    this.limitAmount,
    this.exceedsLimit = false,
    required this.createdAt,
  });

  factory TripExpenseModel.fromJson(Map<String, dynamic> json) {
    return TripExpenseModel(
      id: json['id'] as String,
      tripId: json['trip_id'] as String,
      employeeId: json['employee_id'] as String,
      category: json['category'] as String,
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] as String?,
      receiptPath: json['receipt_path'] as String?,
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      status: json['status'] as String? ?? 'pending',
      limitAmount: (json['limit_amount'] as num?)?.toDouble(),
      exceedsLimit: json['exceeds_limit'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'trip_id': tripId,
    'employee_id': employeeId,
    'category': category,
    'amount': amount,
    'description': description,
    'receipt_path': receiptPath,
    'date': date.toIso8601String().split('T').first,
    'limit_amount': limitAmount,
    'exceeds_limit': exceedsLimit,
  };

  String get categoryLabel {
    switch (category) {
      case 'hotel': return 'Hotel';
      case 'food_da': return 'Food DA';
      case 'local_travel': return 'Local Travel';
      case 'fuel': return 'Fuel';
      case 'toll': return 'Toll/Parking';
      case 'laundry': return 'Laundry';
      case 'internet': return 'Internet';
      case 'other': return 'Other';
      default: return category;
    }
  }

  @override
  List<Object?> get props => [id, tripId, category, amount, status];
}

/// Band limit reference
class BandLimit {
  final String band;
  final String category;
  final double dailyLimit;
  final String unit;

  const BandLimit({
    required this.band,
    required this.category,
    required this.dailyLimit,
    this.unit = 'per_day',
  });

  factory BandLimit.fromJson(Map<String, dynamic> json) {
    return BandLimit(
      band: json['band'] as String,
      category: json['category'] as String,
      dailyLimit: (json['daily_limit'] as num).toDouble(),
      unit: json['unit'] as String? ?? 'per_day',
    );
  }
}
