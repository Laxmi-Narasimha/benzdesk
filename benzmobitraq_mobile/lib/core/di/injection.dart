import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/local/preferences_local.dart';
import '../../data/datasources/local/location_queue_local.dart';
import '../../data/datasources/local/expense_queue_local.dart';
import '../../data/datasources/remote/supabase_client.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/location_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../services/notification_service.dart';
import '../../services/permission_service.dart';
import '../../services/session_manager.dart';
import '../../services/notification_scheduler.dart';
import '../../presentation/blocs/auth/auth_bloc.dart';
import '../../presentation/blocs/session/session_bloc.dart';
import '../../presentation/blocs/notification/notification_bloc.dart';
import '../../presentation/blocs/expense/expense_bloc.dart';

final GetIt getIt = GetIt.instance;

/// Configure all dependencies for the application
/// 
/// This sets up all services, repositories, and blocs in the correct order.
/// Dependencies are registered as singletons or factories as appropriate.
Future<void> configureDependencies() async {
  // ============================================================
  // EXTERNAL SERVICES
  // ============================================================
  
  // Supabase client (already initialized in main.dart)
  getIt.registerLazySingleton<SupabaseClient>(
    () => Supabase.instance.client,
  );

  // ============================================================
  // LOCAL DATA SOURCES
  // ============================================================
  
  getIt.registerLazySingleton<PreferencesLocal>(
    () => PreferencesLocal(),
  );
  
  // Initialize preferences
  await getIt<PreferencesLocal>().init();
  
  getIt.registerLazySingleton<LocationQueueLocal>(
    () => LocationQueueLocal(),
  );
  
  // Initialize location queue database
  await getIt<LocationQueueLocal>().init();

  getIt.registerLazySingleton<ExpenseQueueLocal>(
    () => ExpenseQueueLocal(),
  );

  // Initialize expense queue database
  await getIt<ExpenseQueueLocal>().init();

  // ============================================================
  // REMOTE DATA SOURCES
  // ============================================================
  
  getIt.registerLazySingleton<SupabaseDataSource>(
    () => SupabaseDataSource(getIt<SupabaseClient>()),
  );

  // ============================================================
  // REPOSITORIES
  // ============================================================
  
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepository(
      supabaseClient: getIt<SupabaseClient>(),
      preferences: getIt<PreferencesLocal>(),
    ),
  );
  
  getIt.registerLazySingleton<SessionRepository>(
    () => SessionRepository(
      dataSource: getIt<SupabaseDataSource>(),
      preferences: getIt<PreferencesLocal>(),
    ),
  );
  
  getIt.registerLazySingleton<LocationRepository>(
    () => LocationRepository(
      dataSource: getIt<SupabaseDataSource>(),
      localQueue: getIt<LocationQueueLocal>(),
    ),
  );
  
  getIt.registerLazySingleton<NotificationRepository>(
    () => NotificationRepository(
      dataSource: getIt<SupabaseDataSource>(),
    ),
  );
  
  getIt.registerLazySingleton<ExpenseRepository>(
    () => ExpenseRepository(
      dataSource: getIt<SupabaseDataSource>(),
      supabaseClient: getIt<SupabaseClient>(),
      localQueue: getIt<ExpenseQueueLocal>(),
    ),
  );

  // ============================================================
  // SERVICES
  // ============================================================
  
  getIt.registerLazySingleton<NotificationService>(
    () => NotificationService(),
  );
  
  getIt.registerLazySingleton<PermissionService>(
    () => PermissionService(),
  );
  
  // Notification Scheduler - handles periodic session notifications
  getIt.registerLazySingleton<NotificationScheduler>(
    () => NotificationScheduler(getIt<NotificationService>()),
  );
  
  // Session Manager - The main tracking orchestrator
  getIt.registerLazySingleton<SessionManager>(
    () => SessionManager(
      sessionRepository: getIt<SessionRepository>(),
      locationRepository: getIt<LocationRepository>(),
      preferences: getIt<PreferencesLocal>(),
      permissionService: getIt<PermissionService>(),
      notificationScheduler: getIt<NotificationScheduler>(),
      expenseRepository: getIt<ExpenseRepository>(),
    ),
  );

  // ============================================================
  // BLOCS
  // ============================================================
  
  getIt.registerFactory<AuthBloc>(
    () => AuthBloc(
      authRepository: getIt<AuthRepository>(),
      notificationService: getIt<NotificationService>(),
    ),
  );
  
  getIt.registerFactory<SessionBloc>(
    () => SessionBloc(
      sessionManager: getIt<SessionManager>(),
      sessionRepository: getIt<SessionRepository>(),
    ),
  );
  
  getIt.registerFactory<NotificationBloc>(
    () => NotificationBloc(
      notificationRepository: getIt<NotificationRepository>(),
    ),
  );
  
  getIt.registerFactory<ExpenseBloc>(
    () => ExpenseBloc(
      expenseRepository: getIt<ExpenseRepository>(),
      preferences: getIt<PreferencesLocal>(),
    ),
  );
}

/// Reset all dependencies (useful for testing)
Future<void> resetDependencies() async {
  await getIt.reset();
}
