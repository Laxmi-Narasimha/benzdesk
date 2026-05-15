import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Position of the pill on the map. The pill snaps to one of the four
/// safe-area corners on drag-release. Stored in SharedPreferences so the
/// next session opens with the same corner the rep picked.
enum PillCorner {
  topLeft('top-left'),
  topRight('top-right'),
  bottomLeft('bottom-left'),
  bottomRight('bottom-right');

  final String value;
  const PillCorner(this.value);

  static PillCorner fromString(String s) {
    for (final c in PillCorner.values) {
      if (c.value == s) return c;
    }
    return PillCorner.bottomRight;
  }
}

/// Floating session-info pill that the user drags around on the live
/// map screen. Two states:
///
///   - **Expanded**: distance + duration + speed + Pause/Resume +
///     Work Done. Default. Tap the minimize chevron to collapse.
///   - **Collapsed**: a compact distance-only chip. Tap to expand.
///
/// Both states are draggable. On release the pill animates to the
/// nearest of the four safe-area corners. The chosen corner +
/// collapsed-flag are persisted so a returning user gets the same
/// placement.
///
/// Action buttons emit callbacks rather than touching session state
/// directly — keeps this widget reusable and easy to test.
class DraggableSessionPill extends StatefulWidget {
  /// Live distance in km.
  final double distanceKm;

  /// Live session duration.
  final Duration duration;

  /// Current speed in km/h. Optional — hidden when null/<=0.
  final double? speedKmh;

  /// Whether the session is currently paused (drives the Pause/Resume
  /// button label + icon).
  final bool isPaused;

  /// Name of the destination the rep picked at session start (shown
  /// as a subtitle in expanded mode). Null if no destination chosen.
  final String? destinationName;

  /// Distance to destination in km. Optional — hidden when null.
  /// We show this in expanded mode so the rep can glance at "how
  /// much further" without reading the map scale.
  final double? distanceToDestinationKm;

  /// Whether the user has already entered the destination geofence.
  /// When true the destination subtitle gets a green check.
  final bool arrived;

  final VoidCallback onPauseResume;
  final VoidCallback onWorkDone;

  /// User-selectable starting corner. The widget then manages its own
  /// drag state from there. Pass the value loaded from prefs.
  final PillCorner initialCorner;

  /// Pre-collapsed flag loaded from prefs.
  final bool initialCollapsed;

  /// Callback when the user changes corner via drag.
  final ValueChanged<PillCorner> onCornerChanged;

  /// Callback when the user expands/collapses.
  final ValueChanged<bool> onCollapsedChanged;

  const DraggableSessionPill({
    super.key,
    required this.distanceKm,
    required this.duration,
    this.speedKmh,
    required this.isPaused,
    this.destinationName,
    this.distanceToDestinationKm,
    this.arrived = false,
    required this.onPauseResume,
    required this.onWorkDone,
    this.initialCorner = PillCorner.bottomRight,
    this.initialCollapsed = false,
    required this.onCornerChanged,
    required this.onCollapsedChanged,
  });

  @override
  State<DraggableSessionPill> createState() => _DraggableSessionPillState();
}

class _DraggableSessionPillState extends State<DraggableSessionPill>
    with TickerProviderStateMixin {
  late PillCorner _corner;
  late bool _collapsed;
  Offset? _dragPosition; // null when not actively dragging; corner-anchored otherwise

  // Inset from screen edge in logical pixels.
  static const double _edgeInset = 14;

  @override
  void initState() {
    super.initState();
    _corner = widget.initialCorner;
    _collapsed = widget.initialCollapsed;
  }

  void _toggleCollapsed() {
    HapticFeedback.lightImpact();
    setState(() => _collapsed = !_collapsed);
    widget.onCollapsedChanged(_collapsed);
  }

  void _onPanStart(DragStartDetails d) {
    HapticFeedback.selectionClick();
    setState(() => _dragPosition = d.globalPosition);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _dragPosition = d.globalPosition);
  }

  void _onPanEnd(DragEndDetails _) {
    final size = MediaQuery.of(context).size;
    final pos = _dragPosition;
    if (pos == null) return;

    // Snap to nearest corner based on which screen-quadrant the user
    // released in. Cheap and predictable; physics-based snapping would
    // be overkill for a 4-cell decision.
    final cx = size.width / 2;
    final cy = size.height / 2;
    final PillCorner snapTo;
    if (pos.dx < cx && pos.dy < cy) {
      snapTo = PillCorner.topLeft;
    } else if (pos.dx >= cx && pos.dy < cy) {
      snapTo = PillCorner.topRight;
    } else if (pos.dx < cx && pos.dy >= cy) {
      snapTo = PillCorner.bottomLeft;
    } else {
      snapTo = PillCorner.bottomRight;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _corner = snapTo;
      _dragPosition = null;
    });
    widget.onCornerChanged(snapTo);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final pill = _collapsed ? _buildCollapsed(context) : _buildExpanded(context);

    // While dragging we render via Positioned at the cursor.
    if (_dragPosition != null) {
      // Center the pill around the drag point so it feels like the
      // user is holding it directly. Estimate width/height by the
      // collapsed/expanded state.
      final estW = _collapsed ? 110.0 : 320.0;
      final estH = _collapsed ? 48.0 : 156.0;
      final left = (_dragPosition!.dx - estW / 2)
          .clamp(_edgeInset, size.width - estW - _edgeInset);
      final top = (_dragPosition!.dy - estH / 2)
          .clamp(padding.top + _edgeInset, size.height - estH - padding.bottom - _edgeInset);
      return Positioned(
        left: left.toDouble(),
        top: top.toDouble(),
        child: Opacity(opacity: 0.92, child: pill),
      );
    }

    // Anchored to one of the four corners with safe-area-aware insets.
    final positioned = switch (_corner) {
      PillCorner.topLeft =>
        Positioned(top: padding.top + _edgeInset, left: _edgeInset, child: pill),
      PillCorner.topRight =>
        Positioned(top: padding.top + _edgeInset, right: _edgeInset, child: pill),
      PillCorner.bottomLeft =>
        Positioned(bottom: padding.bottom + _edgeInset, left: _edgeInset, child: pill),
      PillCorner.bottomRight =>
        Positioned(bottom: padding.bottom + _edgeInset, right: _edgeInset, child: pill),
    };
    return positioned;
  }

  // ---------------------------------------------------------------------------
  // COLLAPSED — small distance-only chip
  // ---------------------------------------------------------------------------
  Widget _buildCollapsed(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onTap: _toggleCollapsed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.isPaused
                ? [Colors.amber.shade600, Colors.amber.shade800]
                : [scheme.primary, scheme.primary.withValues(alpha: 0.85)],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.isPaused ? Icons.pause_circle_filled : Icons.directions_run,
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              '${widget.distanceKm.toStringAsFixed(2)} km',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.unfold_more, size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // EXPANDED — full stats + actions
  // ---------------------------------------------------------------------------
  Widget _buildExpanded(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle + minimize button
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 6, 0),
                child: Row(
                  children: [
                    // Drag affordance: 4 horizontal dots ~ pill grip
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _toggleCollapsed,
                      icon: const Icon(Icons.unfold_less, size: 20),
                      tooltip: 'Minimize',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ),
              // Destination subtitle
              if (widget.destinationName != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: Row(
                    children: [
                      Icon(
                        widget.arrived ? Icons.check_circle : Icons.flag_outlined,
                        size: 14,
                        color: widget.arrived ? Colors.green : scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.destinationName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: widget.arrived ? Colors.green.shade700 : Colors.grey.shade700,
                          ),
                        ),
                      ),
                      if (widget.distanceToDestinationKm != null && !widget.arrived)
                        Text(
                          widget.distanceToDestinationKm! < 1
                              ? '${(widget.distanceToDestinationKm! * 1000).round()} m'
                              : '${widget.distanceToDestinationKm!.toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
              // Stats row
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                child: Row(
                  children: [
                    _StatBlock(
                      label: 'Distance',
                      value: widget.distanceKm.toStringAsFixed(2),
                      unit: 'km',
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    _StatBlock(
                      label: 'Duration',
                      value: _fmtDuration(widget.duration),
                      unit: '',
                      color: Colors.indigo,
                    ),
                    if (widget.speedKmh != null && widget.speedKmh! >= 0) ...[
                      const SizedBox(width: 8),
                      _StatBlock(
                        label: 'Speed',
                        value: widget.speedKmh!.toStringAsFixed(0),
                        unit: 'km/h',
                        color: Colors.teal,
                      ),
                    ],
                  ],
                ),
              ),
              // Action buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: widget.isPaused ? Icons.play_arrow : Icons.pause,
                        label: widget.isPaused ? 'Resume' : 'Pause',
                        primary: widget.isPaused,
                        onTap: widget.onPauseResume,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.stop_circle_outlined,
                        label: 'Work Done',
                        primary: !widget.isPaused,
                        emphasis: true,
                        onTap: widget.onWorkDone,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  const _StatBlock({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700,
                color: color.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: 2),
                    Text(
                      unit,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: color.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final bool emphasis;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = emphasis
        ? scheme.primary
        : primary
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.grey.shade100;
    final fg = emphasis
        ? Colors.white
        : primary
            ? scheme.primary
            : Colors.grey.shade800;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
