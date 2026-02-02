import 'package:equatable/equatable.dart';

/// Employee model representing a user in the system
class EmployeeModel extends Equatable {
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String role; // 'employee', 'admin', or 'super_admin'
  final String? deviceToken;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EmployeeModel({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.role = 'employee',
    this.deviceToken,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create an empty employee (placeholder)
  factory EmployeeModel.empty() {
    return EmployeeModel(
      id: '',
      name: '',
      role: 'employee',
      isActive: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Create from JSON map (handles snake_case from Supabase)
  factory EmployeeModel.fromJson(Map<String, dynamic> json) {
    return EmployeeModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      role: json['role'] as String? ?? 'employee',
      deviceToken: json['device_token'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  /// Helper to parse DateTime from various formats
  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'phone': phone,
    'role': role,
    'device_token': deviceToken,
    'is_active': isActive,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  /// Create a copy with modified fields
  EmployeeModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? role,
    String? deviceToken,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmployeeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      deviceToken: deviceToken ?? this.deviceToken,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Check if this employee is an admin or super admin
  bool get isAdmin => role == 'admin' || role == 'super_admin';

  @override
  List<Object?> get props => [
    id,
    name,
    email,
    phone,
    role,
    deviceToken,
    isActive,
    createdAt,
    updatedAt,
  ];
}
