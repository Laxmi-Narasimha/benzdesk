import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:benzmobitraq_mobile/presentation/widgets/places_autocomplete_field.dart';

/// What the start-session sheet returns when the user confirms.
///
/// Carries the free-text purpose (always present, even if empty) plus
/// the optional Google Place metadata when the user picked a Places
/// Autocomplete suggestion. Downstream (SessionManager.startSession)
/// uses these to populate shift_sessions.purpose + start_place_id +
/// primary_customer_id (the customer-matching is done server-side by
/// the enrich-trip Edge Function).
class StartSessionResult {
  final String purpose;
  final String? placeId;
  final String? placeName;
  final String? placeAddress;
  final double? placeLatitude;
  final double? placeLongitude;

  const StartSessionResult({
    required this.purpose,
    this.placeId,
    this.placeName,
    this.placeAddress,
    this.placeLatitude,
    this.placeLongitude,
  });
}

/// Bottom sheet shown when the user taps Present.
///
/// Two parts:
///   1. A **Places Autocomplete** field for capturing the **purpose**
///      of the session. Picking a suggestion binds a Google Place ID
///      so the trip can be matched to a customer record. Typing free
///      text still works (e.g. "Personal errand", "Lunch break") —
///      it just lands as `purpose` without a Place ID.
///   2. A **swipe-to-start** confirm gesture instead of a plain
///      button. Forces a deliberate motion so an accidental tap in
///      a pocket can never start tracking the user's whole day.
///
/// Returns a [StartSessionResult] on confirm. Returns `null` if the
/// user dismissed the sheet without confirming.
class StartSessionSheet extends StatefulWidget {
  /// Optional starting GPS so Places Autocomplete biases its
  /// suggestions to where the user actually is. Without this, results
  /// can be skewed toward big cities far from the user.
  final double? biasLatitude;
  final double? biasLongitude;

  const StartSessionSheet({
    super.key,
    this.biasLatitude,
    this.biasLongitude,
  });

  static Future<StartSessionResult?> show(
    BuildContext context, {
    double? biasLatitude,
    double? biasLongitude,
  }) {
    return showModalBottomSheet<StartSessionResult?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: StartSessionSheet(
          biasLatitude: biasLatitude,
          biasLongitude: biasLongitude,
        ),
      ),
    );
  }

  @override
  State<StartSessionSheet> createState() => _StartSessionSheetState();
}

class _StartSessionSheetState extends State<StartSessionSheet> {
  PlacesSelection _selection = const PlacesSelection();

  void _onConfirm() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(StartSessionResult(
      purpose: _selection.displayLabel,
      placeId: _selection.placeId,
      placeName: _selection.name,
      placeAddress: _selection.address,
      placeLatitude: _selection.latitude,
      placeLongitude: _selection.longitude,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grabber
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.play_circle_filled,
                    color: scheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start a new session',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tracking will run continuously until you tap Work Done.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Purpose / customer search
          Text(
            'Where are you headed?',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          PlacesAutocompleteField(
            biasLatitude: widget.biasLatitude,
            biasLongitude: widget.biasLongitude,
            hintText: 'Customer name, place, or short purpose',
            onChanged: (sel) => _selection = sel,
          ),
          const SizedBox(height: 6),
          Text(
            'Pick a customer/place to auto-tag this trip, or just type a purpose. Optional but helps the timeline match real customers.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.55),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 22),

          // Swipe-to-start
          _SwipeToStart(onConfirm: _onConfirm),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SWIPE TO START
// ============================================================

class _SwipeToStart extends StatefulWidget {
  final VoidCallback onConfirm;
  const _SwipeToStart({required this.onConfirm});

  @override
  State<_SwipeToStart> createState() => _SwipeToStartState();
}

class _SwipeToStartState extends State<_SwipeToStart>
    with SingleTickerProviderStateMixin {
  static const double _thumbSize = 56;
  static const double _trackHeight = 64;
  double _dragX = 0;
  double _trackWidth = 0;
  bool _confirmed = false;
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  double get _maxDrag => math.max(0, _trackWidth - _thumbSize);
  double get _progress => _maxDrag == 0 ? 0 : (_dragX / _maxDrag).clamp(0, 1);

  void _onDragUpdate(DragUpdateDetails d) {
    if (_confirmed) return;
    setState(() {
      _dragX = (_dragX + d.delta.dx).clamp(0, _maxDrag);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_confirmed) return;
    if (_progress >= 0.92) {
      setState(() {
        _dragX = _maxDrag;
        _confirmed = true;
      });
      widget.onConfirm();
    } else {
      // Snap back
      setState(() => _dragX = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      _trackWidth = constraints.maxWidth;
      final progressOpacity = 0.65 + 0.35 * _progress;
      return Container(
        height: _trackHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_trackHeight / 2),
          gradient: LinearGradient(
            colors: [
              scheme.primary.withValues(alpha: progressOpacity),
              scheme.secondary.withValues(alpha: progressOpacity),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Label
            Positioned.fill(
              child: Center(
                child: AnimatedBuilder(
                  animation: _shimmer,
                  builder: (context, _) {
                    return Opacity(
                      opacity: (1 - _progress).clamp(0.0, 1.0),
                      child: ShaderMask(
                        shaderCallback: (bounds) {
                          final t = _shimmer.value;
                          return LinearGradient(
                            colors: const [
                              Colors.white70,
                              Colors.white,
                              Colors.white70,
                            ],
                            stops: [
                              (t - 0.3).clamp(0.0, 1.0),
                              t.clamp(0.0, 1.0),
                              (t + 0.3).clamp(0.0, 1.0),
                            ],
                          ).createShader(bounds);
                        },
                        child: const Text(
                          '›  Slide to start tracking  ›',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // Thumb
            Positioned(
              left: 4 + _dragX,
              top: (_trackHeight - _thumbSize) / 2,
              child: GestureDetector(
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: Container(
                  width: _thumbSize,
                  height: _thumbSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    _confirmed ? Icons.check : Icons.chevron_right,
                    size: 30,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
