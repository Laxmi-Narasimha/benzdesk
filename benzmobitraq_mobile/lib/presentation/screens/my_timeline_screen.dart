import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/timeline_engine.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/session_model.dart';
import '../../data/repositories/location_repository.dart';
import '../../data/repositories/session_repository.dart';

/// My Timeline Screen - Employee's personal timeline view
/// Shows sessions with expandable details containing stops, moves, and stats
class MyTimelineScreen extends StatefulWidget {
  const MyTimelineScreen({super.key});

  @override
  State<MyTimelineScreen> createState() => _MyTimelineScreenState();
}

/// Session with its timeline events grouped together
class SessionTimelineGroup {
  final SessionModel session;
  final List<TimelineEvent> events;
  final double totalDistanceKm;
  final int stopsCount;

  SessionTimelineGroup({
    required this.session,
    required this.events,
    required this.totalDistanceKm,
    required this.stopsCount,
  });
}

class _MyTimelineScreenState extends State<MyTimelineScreen> {
  final LocationRepository _locationRepo = GetIt.I<LocationRepository>();
  final SessionRepository _sessionRepo = GetIt.I<SessionRepository>();
  
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  String? _error;
  
  List<SessionTimelineGroup> _sessionGroups = [];
  Set<String> _expandedSessions = {};
  double _totalDistanceKm = 0;
  int _totalStopsCount = 0;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadTimelineData();
  }

  Future<void> _loadTimelineData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get sessions for the selected date
      final isToday = DateTimeUtils.isToday(_selectedDate);
      final sessions = isToday
          ? await _sessionRepo.getTodaySessions()
          : await _sessionRepo.getSessionHistory(limit: 50);
      
      // Filter sessions for selected date (for non-today)
      final filteredSessions = sessions.where((s) {
        return DateTimeUtils.isSameDay(s.startTime, _selectedDate);
      }).toList();

      // Sort by start time (earliest first)
      filteredSessions.sort((a, b) => a.startTime.compareTo(b.startTime));

      if (filteredSessions.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _sessionGroups = [];
          _totalDistanceKm = 0;
          _totalStopsCount = 0;
          _totalDuration = Duration.zero;
        });
        return;
      }

      // Load timeline events for each session
      final groups = <SessionTimelineGroup>[];
      double dayTotalDistance = 0;
      int dayTotalStops = 0;
      Duration dayTotalDuration = Duration.zero;

      for (final session in filteredSessions) {
        // Get location points for this session
        final points = await _locationRepo.getSessionLocations(session.id);
        
        // Generate timeline events
        final events = points.isEmpty ? <TimelineEvent>[] : TimelineEngine.generateTimeline(points);
        
        // Calculate session stats
        double sessionDistance = 0;
        int sessionStops = 0;
        
        for (final event in events) {
          if (event.type == TimelineEventType.stop) {
            sessionStops++;
          } else if (event.type == TimelineEventType.move) {
            sessionDistance += event.distanceKm ?? 0;
          }
        }

        // Use session's stored totalKm if available (calculated by database trigger)
        final actualDistance = session.totalKm > 0 ? session.totalKm : sessionDistance;

        groups.add(SessionTimelineGroup(
          session: session,
          events: events,
          totalDistanceKm: actualDistance,
          stopsCount: sessionStops,
        ));

        dayTotalDistance += actualDistance;
        dayTotalStops += sessionStops;
        dayTotalDuration += session.duration;
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _sessionGroups = groups;
        _totalDistanceKm = dayTotalDistance;
        _totalStopsCount = dayTotalStops;
        _totalDuration = dayTotalDuration;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load timeline: $e';
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadTimelineData();
    }
  }

  void _toggleSession(String sessionId) {
    setState(() {
      if (_expandedSessions.contains(sessionId)) {
        _expandedSessions.remove(sessionId);
      } else {
        _expandedSessions.add(sessionId);
      }
    });
  }

  void _openInMaps(double lat, double lng) async {
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Timeline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDate,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTimelineData,
        child: Column(
          children: [
            // Date selector bar
            _buildDateSelector(),
            
            // Stats cards
            _buildStatsCards(),
            
            // Timeline content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildErrorView()
                      : _sessionGroups.isEmpty
                          ? _buildEmptyView()
                          : _buildSessionList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    final isToday = DateTimeUtils.isToday(_selectedDate);
    
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _selectedDate = _selectedDate.subtract(const Duration(days: 1));
              });
              _loadTimelineData();
            },
          ),
          Expanded(
            child: GestureDetector(
              onTap: _selectDate,
              child: Column(
                children: [
                  Text(
                    isToday ? 'Today' : DateFormat('EEEE, MMMM d, yyyy').format(DateTimeUtils.toIST(_selectedDate)),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!isToday)
                    Text(
                      'Tap to change date',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: DateTimeUtils.isToday(_selectedDate)
                ? null
                : () {
                    setState(() {
                      _selectedDate = _selectedDate.add(const Duration(days: 1));
                    });
                    _loadTimelineData();
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              icon: Icons.route,
              value: '${_totalDistanceKm.toStringAsFixed(1)} km',
              label: 'Distance',
              color: Colors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              icon: Icons.work_history,
              value: '${_sessionGroups.length}',
              label: 'Sessions',
              color: Colors.purple,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              icon: Icons.timer,
              value: DateTimeUtils.formatDuration(_totalDuration),
              label: 'Duration',
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _sessionGroups.length,
      itemBuilder: (context, index) => _buildSessionCard(_sessionGroups[index], index + 1),
    );
  }

  Widget _buildSessionCard(SessionTimelineGroup group, int sessionNumber) {
    final isExpanded = _expandedSessions.contains(group.session.id);
    final startTimeStr = DateTimeUtils.formatTime(session.startTime);
    final endTimeStr = session.endTime != null 
        ? DateTimeUtils.formatTime(session.endTime!) 
        : 'Active';
    final isActive = session.status == SessionStatus.active;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive ? Colors.green.withOpacity(0.5) : Colors.grey.withOpacity(0.2),
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Session header (always visible, clickable to expand)
          InkWell(
            onTap: () => _toggleSession(session.id),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Session number badge
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isActive 
                            ? [Colors.green, Colors.green.shade700]
                            : [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        '#$sessionNumber',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Session info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Session #$sessionNumber',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (isActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$startTimeStr - $endTimeStr',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.route, size: 14, color: Colors.blue.shade700),
                            const SizedBox(width: 4),
                            Text(
                              '${group.totalDistanceKm.toStringAsFixed(1)} km',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Icon(Icons.timer, size: 14, color: Colors.green.shade700),
                            const SizedBox(width: 4),
                            Text(
                              DateTimeUtils.formatDuration(session.duration),
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            if (group.stopsCount > 0) ...[
                              const SizedBox(width: 16),
                              Icon(Icons.location_on, size: 14, color: Colors.orange.shade700),
                              const SizedBox(width: 4),
                              Text(
                                '${group.stopsCount} stops',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Expand/collapse indicator
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          
          // Expanded content - timeline events
          if (isExpanded) ...[
            const Divider(height: 1),
            if (group.events.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No detailed location data available for this session',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: group.events.length,
                itemBuilder: (context, index) => _buildTimelineEventItem(group.events[index]),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineEventItem(TimelineEvent event) {
    final isStart = event.type == TimelineEventType.start;
    final isEnd = event.type == TimelineEventType.end;
    final isStop = event.type == TimelineEventType.stop;
    final isMove = event.type == TimelineEventType.move;

    final color = isStart
        ? Colors.green
        : isEnd
            ? Colors.red
            : isStop
                ? Colors.orange
                : Colors.blue;

    final title = isStart
        ? 'Start'
        : isEnd
            ? 'End'
            : isStop
                ? 'Stop'
                : 'Moving';

    final icon = isStart
        ? Icons.play_arrow
        : isEnd
            ? Icons.flag
            : isStop
                ? Icons.location_on
                : Icons.directions_car;

    // Time format removed, using DateTimeUtils
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: (isStart || isEnd || isStop) && event.centerLat != null && event.centerLng != null
            ? () => _openInMaps(event.centerLat!, event.centerLng!)
            : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: color,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          event.durationFormatted,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${DateTimeUtils.formatTime(event.startTime)} - ${DateTimeUtils.formatTime(event.endTime)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                    if (isMove && event.distanceKm != null && event.distanceKm! > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${event.distanceKm!.toStringAsFixed(2)} km traveled',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.blue,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if ((isStart || isEnd || isStop) && event.centerLat != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.open_in_new,
                            size: 12,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'View on map',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No Sessions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No work sessions recorded for this day',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to Load',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error occurred',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTimelineData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // _formatDuration removed in favor of DateTimeUtils.formatDuration
}
