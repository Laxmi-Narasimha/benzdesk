import 'package:flutter/material.dart';

import '../blocs/session/session_bloc.dart';
import 'loading_button.dart';

/// Card widget for displaying session status and controls
class SessionCard extends StatelessWidget {
  final SessionState sessionState;
  final VoidCallback onPresentTapped;
  final VoidCallback onWorkDoneTapped;

  const SessionCard({
    super.key,
    required this.sessionState,
    required this.onPresentTapped,
    required this.onWorkDoneTapped,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = sessionState.isActive;
    final isLoading = sessionState.isLoading;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isActive
              ? [
                  const Color(0xFF10B981), // Green
                  const Color(0xFF059669),
                ]
              : [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.secondary,
                ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isActive
                    ? const Color(0xFF10B981)
                    : Theme.of(context).colorScheme.primary)
                .withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status indicator
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isActive ? Colors.greenAccent : Colors.white54,
                  shape: BoxShape.circle,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: Colors.greenAccent.withOpacity(0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isActive ? 'Session Active' : 'Not Tracking',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              if (isActive) ...[
                const Icon(
                  Icons.gps_fixed,
                  color: Colors.white70,
                  size: 18,
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          
          // Distance display
          if (isActive) ...[
            Text(
              'Distance Traveled',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  sessionState.distanceFormatted,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8, left: 4),
                  child: Text(
                    'km',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Duration
            Row(
              children: [
                const Icon(Icons.timer_outlined, color: Colors.white70, size: 16),
                const SizedBox(width: 4),
                Text(
                  _formatDuration(sessionState.duration),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ] else ...[
            // Inactive state display
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.location_off_outlined,
                    size: 48,
                    color: Colors.white.withOpacity(0.6),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap Present to start tracking',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          const SizedBox(height: 20),
          
          // Action button
          if (isActive)
            LoadingButton(
              onPressed: onWorkDoneTapped,
              isLoading: isLoading,
              label: 'Work Done',
              icon: Icons.stop_circle_outlined,
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF059669),
            )
          else
            LoadingButton(
              onPressed: onPresentTapped,
              isLoading: isLoading,
              label: 'Present',
              icon: Icons.play_circle_outline,
              backgroundColor: Colors.white,
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    // Ensure positive duration
    final d = duration.isNegative ? Duration.zero : duration;
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}
