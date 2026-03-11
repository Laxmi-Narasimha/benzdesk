import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';

import '../models/trip_model.dart';

/// Repository for trip operations
class TripRepository {
  final SupabaseClient _client;
  final Logger _logger = Logger();

  TripRepository({required SupabaseClient supabaseClient}) : _client = supabaseClient;

  String? get _userId => _client.auth.currentUser?.id;

  // ── Trips ──────────────────────────────────────────────────────────

  /// Get the current active trip for this employee
  Future<TripModel?> getActiveTrip() async {
    try {
      final data = await _client
          .from('trips')
          .select()
          .eq('employee_id', _userId!)
          .inFilter('status', ['active', 'approved'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) return null;
      return TripModel.fromJson(data);
    } catch (e) {
      _logger.e('Error getting active trip: $e');
      return null;
    }
  }

  /// Get all trips for this employee
  Future<List<TripModel>> getMyTrips() async {
    try {
      final data = await _client
          .from('trips')
          .select()
          .eq('employee_id', _userId!)
          .order('created_at', ascending: false);

      return (data as List).map((json) => TripModel.fromJson(json)).toList();
    } catch (e) {
      _logger.e('Error getting trips: $e');
      return [];
    }
  }

  /// Create a new trip request
  Future<TripModel?> createTrip({
    required String fromLocation,
    required String toLocation,
    String? reason,
    String vehicleType = 'car',
  }) async {
    try {
      final data = await _client
          .from('trips')
          .insert({
            'employee_id': _userId!,
            'from_location': fromLocation,
            'to_location': toLocation,
            'reason': reason,
            'vehicle_type': vehicleType,
            'status': 'requested',
          })
          .select()
          .single();

      _logger.i('Trip created: ${data['id']}');
      return TripModel.fromJson(data);
    } catch (e) {
      _logger.e('Error creating trip: $e');
      return null;
    }
  }

  /// Start an approved trip (set status to active)
  Future<bool> startTrip(String tripId) async {
    try {
      await _client
          .from('trips')
          .update({
            'status': 'active',
            'started_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', tripId)
          .eq('employee_id', _userId!);

      return true;
    } catch (e) {
      _logger.e('Error starting trip: $e');
      return false;
    }
  }

  /// Complete an active trip
  Future<bool> completeTrip(String tripId) async {
    try {
      await _client
          .from('trips')
          .update({
            'status': 'completed',
            'ended_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', tripId)
          .eq('employee_id', _userId!);

      return true;
    } catch (e) {
      _logger.e('Error completing trip: $e');
      return false;
    }
  }

  // ── Trip Expenses ──────────────────────────────────────────────────

  /// Get expenses for a trip
  Future<List<TripExpenseModel>> getTripExpenses(String tripId) async {
    try {
      final data = await _client
          .from('trip_expenses')
          .select()
          .eq('trip_id', tripId)
          .order('date', ascending: false);

      return (data as List).map((json) => TripExpenseModel.fromJson(json)).toList();
    } catch (e) {
      _logger.e('Error getting trip expenses: $e');
      return [];
    }
  }

  /// Add an expense to a trip
  Future<TripExpenseModel?> addTripExpense({
    required String tripId,
    required String category,
    required double amount,
    String? description,
    String? receiptPath,
    DateTime? date,
  }) async {
    try {
      // Fetch band limit for this category
      final employee = await _client
          .from('employees')
          .select('band')
          .eq('id', _userId!)
          .single();
      
      final band = employee['band'] as String? ?? 'executive';
      
      // Get limit
      final limitData = await _client
          .from('band_limits')
          .select('daily_limit')
          .eq('band', band)
          .eq('category', category)
          .maybeSingle();

      final double? limit = limitData != null ? (limitData['daily_limit'] as num).toDouble() : null;
      final bool exceeds = limit != null && amount > limit;

      final data = await _client
          .from('trip_expenses')
          .insert({
            'trip_id': tripId,
            'employee_id': _userId!,
            'category': category,
            'amount': amount,
            'description': description,
            'receipt_path': receiptPath,
            'date': (date ?? DateTime.now()).toIso8601String().split('T').first,
            'limit_amount': limit,
            'exceeds_limit': exceeds,
          })
          .select()
          .single();

      _logger.i('Trip expense added: ${data['id']}');
      return TripExpenseModel.fromJson(data);
    } catch (e) {
      _logger.e('Error adding trip expense: $e');
      return null;
    }
  }

  // ── Band Limits ────────────────────────────────────────────────────

  /// Get all band limits for the current employee's band
  Future<List<BandLimit>> getMyBandLimits() async {
    try {
      final employee = await _client
          .from('employees')
          .select('band')
          .eq('id', _userId!)
          .single();
      
      final band = employee['band'] as String? ?? 'executive';

      final data = await _client
          .from('band_limits')
          .select()
          .eq('band', band);

      return (data as List).map((json) => BandLimit.fromJson(json)).toList();
    } catch (e) {
      _logger.e('Error getting band limits: $e');
      return [];
    }
  }

  // ── Enroll in MobiTraq ─────────────────────────────────────────────

  /// Mark current user as enrolled in MobiTraq
  Future<void> enrollInMobiTraq() async {
    try {
      await _client
          .from('employees')
          .update({
            'mobitraq_enrolled_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', _userId!)
          .isFilter('mobitraq_enrolled_at', null);
    } catch (e) {
      _logger.w('Could not set mobitraq_enrolled_at (column may not exist): $e');
    }
  }
}
