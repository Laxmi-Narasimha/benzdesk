import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Centralized error handling for industry-grade reliability
/// 
/// Provides:
/// - Error classification (network, auth, validation, etc.)
/// - User-friendly error messages
/// - Logging and reporting
/// - Retry policies
class ErrorHandler {
  static final Logger _logger = Logger();
  
  // Error callbacks for reporting
  static Function(AppError error)? onError;
  
  /// Handle any error and return a user-friendly AppError
  static AppError handle(dynamic error, [StackTrace? stackTrace]) {
    final appError = _classify(error);
    
    // Log the error
    _logger.e(
      'Error: ${appError.message}',
      error: error,
      stackTrace: stackTrace,
    );
    
    // Call error callback if set
    onError?.call(appError);
    
    return appError;
  }
  
  /// Classify error into appropriate type
  static AppError _classify(dynamic error) {
    // Already an AppError
    if (error is AppError) return error;
    
    // Network errors
    if (error is SocketException) {
      return AppError(
        type: ErrorType.network,
        message: 'No internet connection. Please check your network.',
        originalError: error,
        isRetryable: true,
      );
    }
    
    if (error is TimeoutException) {
      return AppError(
        type: ErrorType.timeout,
        message: 'Request timed out. Please try again.',
        originalError: error,
        isRetryable: true,
      );
    }
    
    if (error is HttpException) {
      return AppError(
        type: ErrorType.server,
        message: 'Server error. Please try again later.',
        originalError: error,
        isRetryable: true,
      );
    }
    
    // String errors (from API responses)
    if (error is String) {
      if (error.toLowerCase().contains('network') ||
          error.toLowerCase().contains('connection')) {
        return AppError(
          type: ErrorType.network,
          message: 'Network error. Please check your connection.',
          originalError: error,
          isRetryable: true,
        );
      }
      
      if (error.toLowerCase().contains('unauthorized') ||
          error.toLowerCase().contains('auth')) {
        return AppError(
          type: ErrorType.authentication,
          message: 'Session expired. Please login again.',
          originalError: error,
          isRetryable: false,
        );
      }
      
      if (error.toLowerCase().contains('permission')) {
        return AppError(
          type: ErrorType.permission,
          message: 'Permission required. Please grant access.',
          originalError: error,
          isRetryable: true,
        );
      }
      
      return AppError(
        type: ErrorType.unknown,
        message: error,
        originalError: error,
        isRetryable: false,
      );
    }
    
    // FormatException (parsing errors)
    if (error is FormatException) {
      return AppError(
        type: ErrorType.parsing,
        message: 'Data format error. Please try again.',
        originalError: error,
        isRetryable: false,
      );
    }
    
    // Generic Exception
    if (error is Exception) {
      return AppError(
        type: ErrorType.unknown,
        message: 'Something went wrong. Please try again.',
        originalError: error,
        isRetryable: true,
      );
    }
    
    // Fallback
    return AppError(
      type: ErrorType.unknown,
      message: 'An unexpected error occurred.',
      originalError: error,
      isRetryable: false,
    );
  }
  
  /// Execute with automatic retry on failure
  static Future<T> withRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
    bool exponentialBackoff = true,
  }) async {
    int attempts = 0;
    Duration delay = initialDelay;
    
    while (true) {
      try {
        return await operation();
      } catch (error, stack) {
        attempts++;
        final appError = handle(error, stack);
        
        if (!appError.isRetryable || attempts >= maxRetries) {
          throw appError;
        }
        
        _logger.w('Retry $attempts/$maxRetries after ${delay.inSeconds}s');
        await Future.delayed(delay);
        
        if (exponentialBackoff) {
          delay = Duration(milliseconds: (delay.inMilliseconds * 2).clamp(0, 30000));
        }
      }
    }
  }
  
  /// Safe execution that returns null on error instead of throwing
  static Future<T?> safeExecute<T>(
    Future<T> Function() operation, {
    T? fallback,
  }) async {
    try {
      return await operation();
    } catch (e) {
      _logger.w('Safe execution failed: $e');
      return fallback;
    }
  }
}

/// Classified application error
class AppError implements Exception {
  final ErrorType type;
  final String message;
  final dynamic originalError;
  final bool isRetryable;
  
  const AppError({
    required this.type,
    required this.message,
    this.originalError,
    this.isRetryable = false,
  });
  
  @override
  String toString() => message;
  
  /// Check if error requires re-authentication
  bool get requiresReAuth => type == ErrorType.authentication;
  
  /// Check if error is network-related
  bool get isNetworkError => 
      type == ErrorType.network || type == ErrorType.timeout;
}

/// Error type classification
enum ErrorType {
  network,      // No internet, connection lost
  timeout,      // Request timeout
  server,       // Server errors (5xx)
  authentication, // Auth errors (401, 403)
  validation,   // Input validation errors
  permission,   // Missing permissions
  parsing,      // Data parsing errors
  notFound,     // Resource not found (404)
  conflict,     // Data conflicts
  unknown,      // Unknown errors
}
