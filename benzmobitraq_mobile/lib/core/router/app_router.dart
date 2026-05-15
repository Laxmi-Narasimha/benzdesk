import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:benzmobitraq_mobile/core/di/injection.dart';
import 'package:benzmobitraq_mobile/presentation/blocs/chat/chat_bloc.dart';
import 'package:benzmobitraq_mobile/presentation/screens/splash_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/login_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/home_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/session_history_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/expenses_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/add_expense_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/expense_detail_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/profile_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/notifications_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/my_timeline_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/my_trips_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/create_trip_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/create_trip_expense_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/faq_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/debug_distance_test_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/trip_map_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/live_session_map_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/product_guide_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/chat_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/weekly_wrapped_screen.dart';
import 'package:benzmobitraq_mobile/presentation/screens/achievements_screen.dart';
import 'package:benzmobitraq_mobile/data/models/trip_model.dart';

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
  static const String myTimeline = '/timeline';
  static const String myTrips = '/trips';
  static const String createTrip = '/trips/create';
  static const String createTripExpense = '/trips/expense/create';
  static const String faq = '/faq';
  static const String debugDistanceTest = '/debug/distance';
  static const String tripMap = '/trip/map';
  static const String liveSessionMap = '/session/map';
  static const String productGuide = '/products/guide';
  static const String chat = '/chat';
  static const String weeklyWrapped = '/weekly-wrapped';
  static const String achievements = '/achievements';

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
          ExpenseDetailScreen(
            claimId: args?.claimId ?? '',
            category: args?.category,
            amount: args?.amount,
            status: args?.status,
          ),
        );

      case profile:
        return _buildRoute(
          settings,
          const ProfileScreen(),
        );

      case myTimeline:
        return _buildRoute(
          settings,
          const MyTimelineScreen(),
        );

      case myTrips:
        return _buildRoute(
          settings,
          const MyTripsScreen(),
        );

      case createTrip:
        return _buildRoute(
          settings,
          const CreateTripScreen(),
        );

      case createTripExpense:
        final trip = settings.arguments as TripModel;
        return _buildRoute(
          settings,
          CreateTripExpenseScreen(trip: trip),
        );

      case faq:
        return _buildRoute(
          settings,
          const FaqScreen(),
        );

      case debugDistanceTest:
        return _buildRoute(
          settings,
          const DebugDistanceTestScreen(),
        );

      case tripMap:
        final args = settings.arguments as TripMapArguments?;
        return _buildRoute(
          settings,
          TripMapScreen(
            latitude: args?.latitude ?? 0,
            longitude: args?.longitude ?? 0,
            showNearby: args?.showNearby ?? true,
          ),
        );

      case liveSessionMap:
        return _buildRoute(
          settings,
          const LiveSessionMapScreen(),
        );

      case productGuide:
        final args = settings.arguments as ProductGuideArguments?;
        return _buildRoute(
          settings,
          ProductGuideScreen(
            initialIndustry: args?.industry,
          ),
        );

      case chat:
        final args = settings.arguments as ChatArguments?;
        return _buildRoute(
          settings,
          BlocProvider<ChatBloc>(
            create: (_) => getIt<ChatBloc>(),
            child: ChatScreen(
              claimId: args?.claimId ?? '',
              title: args?.title ?? 'Chat',
              subtitle: args?.subtitle,
            ),
          ),
        );

      case weeklyWrapped:
        return _buildRoute(
          settings,
          const WeeklyWrappedScreen(),
        );

      case achievements:
        return _buildRoute(
          settings,
          const AchievementsScreen(),
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
  final String? category;
  final double? amount;
  final String? status;

  const ExpenseDetailArguments({
    required this.claimId,
    this.category,
    this.amount,
    this.status,
  });
}

/// Arguments for TripMapScreen
class TripMapArguments {
  final double latitude;
  final double longitude;
  final bool showNearby;

  const TripMapArguments({
    required this.latitude,
    required this.longitude,
    this.showNearby = true,
  });
}

/// Arguments for ProductGuideScreen
class ProductGuideArguments {
  final String? industry;

  const ProductGuideArguments({this.industry});
}

/// Arguments for ChatScreen
class ChatArguments {
  final String claimId;
  final String title;
  final String? subtitle;

  const ChatArguments({
    required this.claimId,
    required this.title,
    this.subtitle,
  });
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
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
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
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
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
