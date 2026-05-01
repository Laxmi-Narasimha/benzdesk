import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:convert';

import '../datasources/local/preferences_local.dart';
import '../models/employee_model.dart';


/// Repository for handling authentication operations
class AuthRepository {
  final SupabaseClient _supabaseClient;
  final PreferencesLocal _preferences;
  final Logger _logger = Logger();

  AuthRepository({
    required SupabaseClient supabaseClient,
    required PreferencesLocal preferences,
  })  : _supabaseClient = supabaseClient,
        _preferences = preferences;

  /// Get the current authenticated user
  User? get currentUser => _supabaseClient.auth.currentUser;

  /// Check if user is authenticated
  bool get isAuthenticated => currentUser != null;

  /// Get current user ID
  String? get currentUserId => currentUser?.id;

  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges => _supabaseClient.auth.onAuthStateChange;

  /// Sign in with email and password
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      _logger.i('Attempting sign in for: $email');

      final response = await _supabaseClient.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        return AuthResult.failure('Invalid credentials');
      }

      // Fetch employee profile
      final employee = await _getOrCreateEmployeeProfile(response.user!);

      // Store auth data locally
      await _preferences.setLoggedIn(true);
      await _preferences.setUserId(response.user!.id);
      await _preferences.setUserId(response.user!.id);
      await _preferences.setUserRole(employee.role);
      await _preferences.setCachedEmployeeProfileJson(jsonEncode(employee.toJson())); // Cache for offline

      _logger.i('Sign in successful for: ${response.user!.email}');
      return AuthResult.success(employee);
    } on AuthException catch (e) {
      _logger.e('Auth exception during sign in: ${e.message}');
      return AuthResult.failure(_mapAuthError(e));
    } catch (e) {
      _logger.e('Unexpected error during sign in: $e');
      return AuthResult.failure('An unexpected error occurred');
    }
  }

  /// Sign in with Magic Link (OTP)
  Future<AuthResult> signInWithMagicLink({
    required String email,
  }) async {
    try {
      _logger.i('Attempting magic link sign in for: $email');

      await _supabaseClient.auth.signInWithOtp(
        email: email,
        emailRedirectTo: 'io.supabase.flutter://login-callback',
      );

      _logger.i('Magic link sent to: $email');
      return AuthResult.success(EmployeeModel.empty()); // Return empty model as placeholder
    } on AuthException catch (e) {
      _logger.e('Auth exception during magic link: ${e.message}');
      return AuthResult.failure(_mapAuthError(e));
    } catch (e) {
      _logger.e('Unexpected error during magic link: $e');
      return AuthResult.failure('An unexpected error occurred');
    }
  }

  bool _isGoogleSignInInitialized = false;

  /// Sign in with Google
  Future<AuthResult> signInWithGoogle() async {
    try {
      _logger.i('Attempting Google Sign-In');
      
      final googleSignIn = GoogleSignIn(
        // IMPORTANT: The Web Client ID from Google Cloud Console MUST be placed here 
        // for Supabase authentication to work on Android.
        // E.g., '1234567890-abcdefg.apps.googleusercontent.com'
        serverClientId: '337286635510-7bttaefo3askvou30kq0em84hh8l0gnp.apps.googleusercontent.com', 
      );
      
      if (!_isGoogleSignInInitialized) {
        // ... handled implicitly now, or we can just authenticate directly.
      }
      
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
          _logger.w('Google Sign-In canceled by user');
          return AuthResult.failure('Sign-in canceled');
      }
      
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        _logger.e('Google Sign-In failed: Missing ID token');
        return AuthResult.failure('Failed to get authentication tokens from Google');
      }

      final response = await _supabaseClient.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );

      if (response.user == null) {
        return AuthResult.failure('Authentication with Supabase failed');
      }

      // Fetch or auto-create employee profile based on existing triggers
      final employee = await _getOrCreateEmployeeProfile(response.user!);

      // Store auth data locally
      await _preferences.setLoggedIn(true);
      await _preferences.setUserId(response.user!.id);
      await _preferences.setUserRole(employee.role);
      await _preferences.setCachedEmployeeProfileJson(jsonEncode(employee.toJson())); // Cache for offline

      _logger.i('Google Sign-In successful for: ${response.user!.email}');
      return AuthResult.success(employee);
    } catch (e) {
      _logger.e('Unexpected error during Google Sign-In: $e');
      return AuthResult.failure('Google Sign-In Error: $e');
    }
  }

  /// Sign up with email and password
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) async {
    try {
      _logger.i('Attempting sign up for: $email');

      final response = await _supabaseClient.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user == null) {
        return AuthResult.failure('Failed to create account');
      }

      // Create employee profile
      final now = DateTime.now();
      final employee = EmployeeModel(
        id: response.user!.id,
        name: name,
        phone: phone,
        role: 'employee', // Default role
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      final Map<String, dynamic> data = employee.toJson();
      data['mobitraq_enrolled_at'] = now.toUtc().toIso8601String();

      await _supabaseClient
          .from('employees')
          .insert(data);

      // Store auth data locally
      await _preferences.setLoggedIn(true);
      await _preferences.setUserId(response.user!.id);
      await _preferences.setUserRole(employee.role);

      _logger.i('Sign up successful for: ${response.user!.email}');
      return AuthResult.success(employee);
    } on AuthException catch (e) {
      _logger.e('Auth exception during sign up: ${e.message}');
      return AuthResult.failure(_mapAuthError(e));
    } catch (e) {
      _logger.e('Unexpected error during sign up: $e');
      return AuthResult.failure('An unexpected error occurred');
    }
  }

  /// Sign out the current user
  Future<void> signOut() async {
    try {
      _logger.i('Signing out user');
      
      await _supabaseClient.auth.signOut();
      
      // Also sign out from Google so the user can choose a different account next time
      try {
        await GoogleSignIn().signOut();
      } catch (e) {
        _logger.w('Failed to sign out from Google (non-fatal): $e');
      }

      await _preferences.clearAuthData();
      
      _logger.i('Sign out successful');
    } catch (e) {
      _logger.e('Error during sign out: $e');
      // Still clear local data
      await _preferences.clearAuthData();
    }
  }

  /// Check current auth status and return employee if authenticated
  Future<EmployeeModel?> checkAuthStatus() async {
    try {
      final session = _supabaseClient.auth.currentSession;
      
      if (session == null) {
        _logger.i('No active session found');
        await _preferences.clearAuthData();
        return null;
      }

      // Session exists, fetch employee profile
      final response = await _supabaseClient
          .from('employees')
          .select()
          .eq('id', session.user.id)
          .maybeSingle();

      if (response == null) {
        _logger.w('User authenticated but no employee profile found');
        return null;
      }

      final employee = EmployeeModel.fromJson(response);
      
      // Update local preferences
      await _preferences.setLoggedIn(true);
      await _preferences.setUserId(employee.id);
      await _preferences.setUserId(employee.id);
      await _preferences.setUserRole(employee.role);
      await _preferences.setCachedEmployeeProfileJson(jsonEncode(employee.toJson())); // Cache for offline

      _logger.i('Auth status check: User authenticated as ${employee.name}');
      return employee;
    } catch (e) {
      _logger.e('Error checking auth status: $e');
      _logger.e('Error checking auth status: $e');
      
      // OFFLINE FALLBACK
      final cachedJson = _preferences.cachedEmployeeProfileJson;
      if (cachedJson != null) {
        try {
          final cachedEmployee = EmployeeModel.fromJson(jsonDecode(cachedJson));
          _logger.w('OFFLINE MODE: Using cached employee profile');
          return cachedEmployee;
        } catch (parseError) {
          _logger.e('Error parsing cached profile: $parseError');
        }
      }
      
      return null;
    }
  }

  /// Get current employee profile
  Future<EmployeeModel?> getCurrentEmployee() async {
    final userId = currentUserId;
    if (userId == null) return null;

    try {
      final response = await _supabaseClient
          .from('employees')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response == null) return null;
      return EmployeeModel.fromJson(response);
    } catch (e) {
      _logger.e('Error fetching current employee: $e');
      return null;
    }
  }

  /// Update employee profile
  Future<EmployeeModel?> updateProfile({
    String? name,
    String? phone,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;

    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (name != null) updates['name'] = name;
      if (phone != null) updates['phone'] = phone;

      final response = await _supabaseClient
          .from('employees')
          .update(updates)
          .eq('id', userId)
          .select()
          .single();

      return EmployeeModel.fromJson(response);
    } catch (e) {
      _logger.e('Error updating profile: $e');
      return null;
    }
  }

  /// Update device token for push notifications
  Future<void> updateDeviceToken(String token) async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      await _supabaseClient
          .from('employees')
          .update({
            'device_token': token,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', userId);

      await _preferences.setDeviceToken(token);
      _logger.i('Device token updated successfully');
    } catch (e) {
      _logger.e('Error updating device token: $e');
    }
  }

  /// Reset password
  Future<bool> resetPassword(String email) async {
    try {
      await _supabaseClient.auth.resetPasswordForEmail(email);
      _logger.i('Password reset email sent to: $email');
      return true;
    } catch (e) {
      _logger.e('Error sending password reset: $e');
      return false;
    }
  }

  /// Exchange hash component for session (Deep Link Handler)
  Future<void> handleDeepLink(Uri uri) async {
    try {
      // Supabase handles the session exchange automatically 
      // if the deep link is configured correctly.
      // We just need to check auth status.
      await checkAuthStatus();
    } catch (e) {
      _logger.e('Error handling deep link: $e');
    }
  }

  /// Get or create employee profile for authenticated user
  Future<EmployeeModel> _getOrCreateEmployeeProfile(User user) async {
    final response = await _supabaseClient
        .from('employees')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (response != null) {
      if (response['mobitraq_enrolled_at'] == null) {
        await _supabaseClient.from('employees').update({
          'mobitraq_enrolled_at': DateTime.now().toUtc().toIso8601String()
        }).eq('id', user.id);
      }
      return EmployeeModel.fromJson(response);
    }

    // Create profile if it doesn't exist
    final now = DateTime.now();
    final employee = EmployeeModel(
      id: user.id,
      name: user.email?.split('@').first ?? 'User',
      role: 'employee',
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    final Map<String, dynamic> data = employee.toJson();
    data['mobitraq_enrolled_at'] = now.toUtc().toIso8601String();

    await _supabaseClient
        .from('employees')
        .insert(data);

    return employee;
  }

  /// Map Supabase auth errors to user-friendly messages
  String _mapAuthError(AuthException e) {
    if (e.message.contains('Invalid login credentials')) {
      return 'Invalid email or password';
    }
    if (e.message.contains('Email not confirmed')) {
      return 'Please verify your email address';
    }
    if (e.message.contains('User already registered')) {
      return 'An account with this email already exists';
    }
    if (e.message.contains('Password')) {
      return 'Password must be at least 6 characters';
    }
    return e.message;
  }
}

/// Result class for authentication operations
class AuthResult {
  final bool success;
  final EmployeeModel? employee;
  final String? error;

  const AuthResult._({
    required this.success,
    this.employee,
    this.error,
  });

  factory AuthResult.success(EmployeeModel employee) {
    return AuthResult._(success: true, employee: employee);
  }

  factory AuthResult.failure(String error) {
    return AuthResult._(success: false, error: error);
  }
}
