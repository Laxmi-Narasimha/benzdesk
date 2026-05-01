import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/constants/theme_constants.dart';
import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'presentation/blocs/auth/auth_bloc.dart';
import 'presentation/blocs/session/session_bloc.dart';
import 'presentation/blocs/notification/notification_bloc.dart';
import 'presentation/blocs/expense/expense_bloc.dart';

import '../../data/repositories/trip_repository.dart';

/// Root widget for the BenzMobiTraq application
class BenzMobiTraqApp extends StatelessWidget {
  const BenzMobiTraqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<TripRepository>(
          create: (_) => getIt<TripRepository>(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          // Auth BLoC - handles authentication state
          BlocProvider<AuthBloc>(
            create: (_) => getIt<AuthBloc>()..add(AuthCheckRequested()),
          ),
          
          // Session BLoC - handles work session tracking
          BlocProvider<SessionBloc>(
            create: (_) => getIt<SessionBloc>()..add(const SessionInitialize()),
          ),
          
          // Notification BLoC - handles push notifications
          BlocProvider<NotificationBloc>(
            create: (_) => getIt<NotificationBloc>(),
          ),
          
          // Expense BLoC - handles expense claims
          BlocProvider<ExpenseBloc>(
            create: (_) => getIt<ExpenseBloc>(),
            lazy: true,
          ),
        ],
        child: MaterialApp(
          title: 'BenzMobiTraq',
          debugShowCheckedModeBanner: false,
          
          // Navigation Key for background deep linking
          navigatorKey: getIt<GlobalKey<NavigatorState>>(),
          
          // Theme configuration
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          
          // Routing
          initialRoute: AppRouter.splash,
          onGenerateRoute: AppRouter.onGenerateRoute,
          
          // Global builder to handle Auth state changes (like logout)
          builder: (context, child) {
            return BlocListener<AuthBloc, AuthState>(
              listener: (context, state) {
                if (state is AuthUnauthenticated) {
                  // Use the navigator key to navigate globally
                  getIt<GlobalKey<NavigatorState>>().currentState?.pushNamedAndRemoveUntil(
                    AppRouter.login,
                    (route) => false,
                  );
                }
              },
              child: child!,
            );
          },
        ),
      ),
    );
  }
}
