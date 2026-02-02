import 'package:flutter/material.dart';

import '../../presentation/screens/splash_screen.dart';
import '../../presentation/screens/login_screen.dart';
import '../../presentation/screens/home_screen.dart';
import '../../presentation/screens/session_history_screen.dart';
import '../../presentation/screens/expenses_screen.dart';
import '../../presentation/screens/add_expense_screen.dart';
import '../../presentation/screens/profile_screen.dart';
import '../../presentation/screens/notifications_screen.dart';

/// Application router for named route navigation
class AppRouter {
  AppRouter._();

  // ============================================================
  // ROUTE NAMES
  // ============================================================
  
  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String session = '/session';
  static const String sessionHistory = '/session/history';
  static const String notifications = '/notifications';
  static const String expenses = '/expenses';
  static const String addExpense = '/expenses/add';
  static const String expenseDetail = '/expenses/detail';
  static const String profile = '/profile';

  // ============================================================
  // ROUTE GENERATOR
  // ============================================================
  
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return _buildRoute(
          settings,
          const SplashScreen(),
        );

      case login:
        return _buildRoute(
          settings,
          const LoginScreen(),
        );

      case home:
        return _buildRoute(
          settings,
          const HomeScreen(),
        );

      case session:
        return _buildRoute(
          settings,
          const _PlaceholderScreen(title: 'Session'),
        );

      case sessionHistory:
        return _buildRoute(
          settings,
          const SessionHistoryScreen(),
        );

      case notifications:
        return _buildRoute(
          settings,
          const NotificationsScreen(),
        );

      case expenses:
        return _buildRoute(
          settings,
          const ExpensesScreen(),
        );

      case addExpense:
        return _buildRoute(
          settings,
          const AddExpenseScreen(),
        );

      case expenseDetail:
        final args = settings.arguments as ExpenseDetailArguments?;
        return _buildRoute(
          settings,
          _PlaceholderScreen(title: 'Expense: ${args?.claimId ?? "Unknown"}'),
        );

      case profile:
        return _buildRoute(
          settings,
          const ProfileScreen(),
        );

      default:
        return _buildRoute(
          settings,
          const _NotFoundScreen(),
        );
    }
  }

  /// Build a material page route with consistent transitions
  static PageRoute<T> _buildRoute<T>(
    RouteSettings settings,
    Widget page,
  ) {
    return MaterialPageRoute<T>(
      settings: settings,
      builder: (_) => page,
    );
  }

  // ============================================================
  // NAVIGATION HELPERS
  // ============================================================
  
  /// Navigate to a route
  static Future<T?> navigateTo<T>(BuildContext context, String routeName, {Object? arguments}) {
    return Navigator.pushNamed<T>(context, routeName, arguments: arguments);
  }

  /// Replace current route
  static Future<T?> replaceTo<T>(BuildContext context, String routeName, {Object? arguments}) {
    return Navigator.pushReplacementNamed<T, void>(context, routeName, arguments: arguments);
  }

  /// Navigate and clear stack
  static Future<T?> navigateAndClear<T>(BuildContext context, String routeName, {Object? arguments}) {
    return Navigator.pushNamedAndRemoveUntil<T>(
      context,
      routeName,
      (route) => false,
      arguments: arguments,
    );
  }

  /// Go back
  static void goBack<T>(BuildContext context, [T? result]) {
    Navigator.pop<T>(context, result);
  }
}

// ============================================================
// ROUTE ARGUMENTS
// ============================================================

/// Arguments for AddExpenseScreen
class AddExpenseArguments {
  final String? claimId;

  const AddExpenseArguments({this.claimId});
}

/// Arguments for ExpenseDetailScreen
class ExpenseDetailArguments {
  final String claimId;

  const ExpenseDetailArguments({required this.claimId});
}

// ============================================================
// PLACEHOLDER SCREEN (for screens not yet implemented)
// ============================================================

class _PlaceholderScreen extends StatelessWidget {
  final String title;
  
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'This screen is coming soon!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 404 SCREEN
// ============================================================

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Not Found'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'The requested page does not exist.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => AppRouter.navigateAndClear(context, AppRouter.home),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    );
  }
}
