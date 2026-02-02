import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/timeline_engine.dart';
import '../../data/models/location_point_model.dart';
import '../../data/repositories/location_repository.dart';

/// My Timeline Screen - Employee's personal timeline view
/// Shows stops (5+ min), moves, and daily stats
class MyTimelineScreen extends StatefulWidget {
  const MyTimelineScreen({super.key});

  @override
  State<MyTimelineScreen> createState() => _MyTimelineScreenState();
}

class _MyTimelineScreenState extends State<MyTimelineScreen> {
  final LocationRepository _locationRepo = GetIt.I<LocationRepository>();
  
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  String? _error;
  
  List<TimelineEvent> _events = [];
  double _totalDistanceKm = 0;
  int _stopsCount = 0;
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
      // Get location points for the selected date
      final startOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final points = await _locationRepo.getLocationPointsForDateRange(
        startOfDay,
        endOfDay,
      );

      if (points.isEmpty) {
        setState(() {
          _isLoading = false;
          _events = [];
          _totalDistanceKm = 0;
          _stopsCount = 0;
          _totalDuration = Duration.zero;
        });
        return;
      }

      // Generate timeline events using the engine
      final events = TimelineEngine.generateTimeline(points);

      // Calculate stats
      double totalDistance = 0;
      int stops = 0;
      int totalSeconds = 0;

      for (final event in events) {
        totalSeconds += event.durationSec;
        if (event.type == TimelineEventType.stop) {
          stops++;
        } else {
          totalDistance += event.distanceKm ?? 0;
        }
      }

      setState(() {
        _isLoading = false;
        _events = events;
        _totalDistanceKm = totalDistance;
        _stopsCount = stops;
        _totalDuration = Duration(seconds: totalSeconds);
      });
    } catch (e) {
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
                      : _events.isEmpty
                          ? _buildEmptyView()
                          : _buildTimelineList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    final dateFormat = DateFormat('EEEE, MMMM d, yyyy');
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    
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
                    isToday ? 'Today' : dateFormat.format(_selectedDate),
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
            onPressed: DateUtils.isSameDay(_selectedDate, DateTime.now())
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
              icon: Icons.location_on,
              value: '$_stopsCount',
              label: 'Stops',
              color: Colors.orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              icon: Icons.timer,
              value: _formatDuration(_totalDuration),
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

  Widget _buildTimelineList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _events.length,
      itemBuilder: (context, index) => _buildTimelineItem(_events[index], index),
    );
  }

  Widget _buildTimelineItem(TimelineEvent event, int index) {
    final isStop = event.type == TimelineEventType.stop;
    final color = isStop ? Colors.orange : Colors.blue;
    final timeFormat = DateFormat('h:mm a');
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: color.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isStop && event.centerLat != null && event.centerLng != null
            ? () => _openInMaps(event.centerLat!, event.centerLng!)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isStop ? Icons.location_on : Icons.directions_car,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isStop ? 'Stop' : 'Moving',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: color,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          event.durationFormatted,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${timeFormat.format(event.startTime)} - ${timeFormat.format(event.endTime)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    if (!isStop && event.distanceKm != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${event.distanceKm!.toStringAsFixed(1)} km traveled',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.blue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (isStop) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.open_in_new,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Tap to view on map',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
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
              'No Activity',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No location data recorded for this day',
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

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}
