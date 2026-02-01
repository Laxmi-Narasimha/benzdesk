import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logger/logger.dart';

/// Real-time connectivity monitoring service
/// 
/// Provides:
/// - Network state changes
/// - Offline detection
/// - Pending operation queue
class ConnectivityService {
  static final Logger _logger = Logger();
  static final Connectivity _connectivity = Connectivity();
  
  static List<ConnectivityResult> _currentStatus = [ConnectivityResult.none];
  static StreamController<bool>? _onlineController;
  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  
  // Pending operations to execute when online
  static final List<Future<void> Function()> _pendingOperations = [];
  
  /// Get current online status
  static bool get isOnline => !_currentStatus.contains(ConnectivityResult.none);
  
  /// Stream of online status changes
  static Stream<bool> get onlineChanges {
    _onlineController ??= StreamController<bool>.broadcast();
    return _onlineController!.stream;
  }
  
  /// Initialize connectivity monitoring
  static Future<void> initialize() async {
    try {
      // Get initial status
      _currentStatus = await _connectivity.checkConnectivity();
      
      _logger.i('Initial connectivity: $_currentStatus');
      
      // Listen for changes
      _subscription = _connectivity.onConnectivityChanged.listen((results) {
        final wasOffline = _currentStatus.contains(ConnectivityResult.none);
        _currentStatus = results;
        
        _logger.i('Connectivity changed: $results');
        _onlineController?.add(isOnline);
        
        // Execute pending operations when coming back online
        if (wasOffline && isOnline) {
          _executePendingOperations();
        }
      });
    } catch (e) {
      _logger.e('Connectivity init error: $e');
    }
  }
  
  /// Add operation to pending queue (for offline execution)
  static void addPendingOperation(Future<void> Function() operation) {
    _pendingOperations.add(operation);
    _logger.i('Added pending operation. Queue size: ${_pendingOperations.length}');
  }
  
  /// Execute all pending operations
  static Future<void> _executePendingOperations() async {
    if (_pendingOperations.isEmpty) return;
    
    _logger.i('Executing ${_pendingOperations.length} pending operations');
    
    final operations = List<Future<void> Function()>.from(_pendingOperations);
    _pendingOperations.clear();
    
    for (final operation in operations) {
      try {
        await operation();
      } catch (e) {
        _logger.e('Pending operation failed: $e');
        // Re-add failed operation
        _pendingOperations.add(operation);
      }
    }
  }
  
  /// Wait for online status with timeout
  static Future<bool> waitForOnline({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (isOnline) return true;
    
    try {
      await onlineChanges
          .where((online) => online)
          .first
          .timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }
  
  /// Dispose resources
  static void dispose() {
    _subscription?.cancel();
    _onlineController?.close();
    _onlineController = null;
  }
}

