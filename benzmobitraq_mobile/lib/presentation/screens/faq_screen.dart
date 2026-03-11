import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text('Help & FAQ', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: 'Getting Started', icon: Icons.rocket_launch),
          const _FaqItem(
            question: 'How do I start using BenzMobiTraq?',
            answer: 'After signing in (with Google or email/password), your profile is auto-created. '
                'You can immediately start GPS tracking sessions by tapping "Present" on the Home screen. '
                'Your admin assigns your band (Executive, Manager, etc.), which sets your expense limits.',
          ),
          const _FaqItem(
            question: 'How does GPS session tracking work?',
            answer: 'Tap "Present" to start a session. Your phone tracks your movement via GPS and calculates distance. '
                'When done, tap "Work Done". If you traveled >0 km, you\'ll be prompted to log a fuel expense. '
                'All sessions sync to the admin Timeline for verification.',
          ),

          const SizedBox(height: 16),
          _SectionHeader(title: 'Trips & Expenses', icon: Icons.receipt_long),
          const _FaqItem(
            question: 'How do I create a Trip?',
            answer: 'Go to the Trips tab and tap "New Trip". Enter your origin, destination, reason, and vehicle type (Car/Bike). '
                'Once created, you can add expenses under this trip. The trip groups your expenses for easy review.',
          ),
          const _FaqItem(
            question: 'How do I add expenses?',
            answer: 'Two ways:\n\n'
                '1. Under a Trip — Open a trip from the Trips tab and tap "Add Expense". Categories match the travel policy.\n'
                '2. Standalone — Go to the Expenses tab and submit an expense directly.\n\n'
                'Both go to the same admin queue in BenzDesk for review.',
          ),
          const _FaqItem(
            question: 'What categories are available?',
            answer: '• Food DA — Daily food allowance\n'
                '• Hotel — Per night accommodation\n'
                '• Local Travel — Per day local transport\n'
                '• Fuel (Car) — ₹7.5/km auto-calculated\n'
                '• Fuel (Bike) — ₹5.0/km auto-calculated\n'
                '• Laundry — Max ₹300/day (for stays >3 nights)\n'
                '• Internet — Actual charges\n'
                '• Toll/Parking — Actual charges\n'
                '• Other — Custom category with title',
          ),
          const _FaqItem(
            question: 'How are fuel limits calculated?',
            answer: 'Fuel limits are per-km, not a flat daily rate.\n\n'
                'Formula: Rate × Kilometers traveled\n\n'
                'Example: If you drove 100 km by car:\n'
                '₹7.5/km × 100 km = ₹750 limit\n\n'
                'After ending a GPS session, the app auto-calculates this for you and pre-fills the amount.',
          ),
          const _FaqItem(
            question: 'What happens if I exceed my limit?',
            answer: 'You can still submit the expense, but it\'s flagged with a red "Over Limit" badge. '
                'Admins see this in BenzDesk and may request justification or reject the excess amount. '
                'You can add a message/note explaining the reason.',
          ),

          const SizedBox(height: 16),
          _SectionHeader(title: 'Messaging & Approvals', icon: Icons.chat),
          const _FaqItem(
            question: 'How does the chat/messaging work?',
            answer: 'Each expense has a built-in chat. Tap any expense in the Expenses tab to open it. '
                'You can send messages, and admins can reply from BenzDesk web. All messages are synced in real-time. '
                'This is the same conversation visible on both the mobile app and BenzDesk.',
          ),
          const _FaqItem(
            question: 'How are expenses approved or rejected?',
            answer: 'All expenses are sent to the admin queue in BenzDesk. Admins review each request, '
                'check attachments and km details, then approve or reject. You receive a push notification '
                'when the status changes, and can see it in the Expenses tab.',
          ),
          const _FaqItem(
            question: 'How do push notifications work?',
            answer: 'You get notified when:\n'
                '• An expense is approved or rejected\n'
                '• An admin replies to your message\n'
                '• Your trip status changes\n\n'
                'Make sure notifications are enabled in your phone settings for BenzMobiTraq.',
          ),

          const SizedBox(height: 16),
          _SectionHeader(title: 'BenzDesk Web', icon: Icons.language),
          const _FaqItem(
            question: 'Can I access BenzDesk from the web?',
            answer: 'Yes! Go to BenzDesk web portal and sign in with Google (the same Google account you use in the app). '
                'You can view all your trips, expenses, messages, and status updates. '
                'The same data is synced across both platforms.',
          ),
          const _FaqItem(
            question: 'What can admins do on BenzDesk?',
            answer: 'Admins can:\n'
                '• View all employee requests in one queue\n'
                '• Approve/Reject expenses with comments\n'
                '• See GPS session data for verification\n'
                '• Manage employee bands and limits\n'
                '• View trip details with route and km\n'
                '• Download expense reports',
          ),

          const SizedBox(height: 16),
          _SectionHeader(title: 'Bands & Limits', icon: Icons.shield),
          const _FaqItem(
            question: 'What are bands?',
            answer: 'Bands represent your employment level (Executive, Manager, Director, etc.). '
                'Each band has specific daily limits for Food, Hotel, Travel, and Fuel as per the BENZ Travel Policy. '
                'Your admin assigns your band. You can see it in your Profile.',
          ),
          const _FaqItem(
            question: 'Where can I see my limits?',
            answer: 'Your limits are shown whenever you create an expense:\n\n'
                '• For flat-rate categories (Food, Hotel): Shows "₹X / day" or "₹X / night"\n'
                '• For fuel: Shows "₹X/km × Y km = ₹Z" based on your session distance\n'
                '• For "Actuals" categories: No strict limit — actual charges are reimbursed\n\n'
                'You can also check your band on the Profile screen.',
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              'Still have questions? Contact your admin.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: Colors.blue.shade600),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          question,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        children: [
          Text(
            answer,
            style: GoogleFonts.inter(
              color: Colors.grey.shade700,
              height: 1.6,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
