import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/constants/theme_constants.dart';
import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'presentation/blocs/auth/auth_bloc.dart';
import 'presentation/blocs/session/session_bloc.dart';
import 'presentation/blocs/notification/notification_bloc.dart';
import 'presentation/blocs/expense/expense_bloc.dart';

/// Root widget for the BenzMobiTraq application
class BenzMobiTraqApp extends StatelessWidget {
  const BenzMobiTraqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        // Auth BLoC - handles authentication state
        BlocProvider<AuthBloc>(
          create: (_) => getIt<AuthBloc>()..add(AuthCheckRequested()),
        ),
        
        // Session BLoC - handles work session tracking
        // Initializes automatically to check for active sessions
        BlocProvider<SessionBloc>(
          create: (_) => getIt<SessionBloc>()..add(const SessionInitialize()),
        ),
        
        // Notification BLoC - handles push notifications
        BlocProvider<NotificationBloc>(
          create: (_) => getIt<NotificationBloc>(),
        ),
        
        // Expense BLoC - handles expense claims
        // Created lazily when needed
        BlocProvider<ExpenseBloc>(
          create: (_) => getIt<ExpenseBloc>(),
          lazy: true,
        ),
      ],
      child: MaterialApp(
        title: 'BenzMobiTraq',
        debugShowCheckedModeBanner: false,
        
        // Theme configuration
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        
        // Routing
        initialRoute: AppRouter.splash,
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
  }
}
