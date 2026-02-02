import 'package:flutter/material.dart';
import '../../core/router/app_router.dart';

class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        if (index == currentIndex) return;
        
        switch (index) {
          case 0:
            AppRouter.navigateAndClear(context, AppRouter.home);
            break;
          case 1:
            AppRouter.navigateTo(context, AppRouter.myTimeline);
            break;
          case 2:
            AppRouter.navigateTo(context, AppRouter.expenses);
            break;
          case 3:
            AppRouter.navigateTo(context, AppRouter.profile);
            break;
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.timeline_outlined),
          activeIcon: Icon(Icons.timeline),
          label: 'Timeline',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.receipt_long_outlined),
          activeIcon: Icon(Icons.receipt_long),
          label: 'Expenses',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }
}
