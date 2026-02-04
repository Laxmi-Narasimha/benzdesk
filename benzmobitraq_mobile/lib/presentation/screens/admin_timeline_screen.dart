import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import '../../core/distance_engine.dart';
import '../../core/timeline_engine.dart';
import '../../data/models/location_point_model.dart';
import '../../data/repositories/location_repository.dart';
import '../../data/repositories/session_repository.dart';

/// Admin Timeline Screen - View employee routes and stops
/// Per industry-grade specification Section 9
class AdminTimelineScreen extends StatefulWidget {
  final String? initialEmployeeId;
  final DateTime? initialDate;

  const AdminTimelineScreen({
    super.key,
    this.initialEmployeeId,
    this.initialDate,
  });

  @override
  State<AdminTimelineScreen> createState() => _AdminTimelineScreenState();
}

class _AdminTimelineScreenState extends State<AdminTimelineScreen> {
  final LocationRepository _locationRepo = GetIt.instance<LocationRepository>();
  final SessionRepository _sessionRepo = GetIt.instance<SessionRepository>();

  String? _selectedEmployeeId;
  DateTime _selectedDate = DateTime.now();
  
  List<LocationPointModel> _points = [];
  List<TimelineEvent> _events = [];
  double _totalDistance = 0;
  bool _isLoading = false;
  String? _error;

  // Employee list for picker
  List<Map<String, dynamic>> _employees = [];

  @override
  void initState() {
    super.initState();
    _selectedEmployeeId = widget.initialEmployeeId;
    _selectedDate = widget.initialDate ?? DateTime.now();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    try {
      final employees = await _sessionRepo.getActiveEmployees();
      setState(() {
        _employees = employees;
        // Only set default if NO selection and NO initial ID passed
        if (_selectedEmployeeId == null) {
            if (employees.isNotEmpty) {
               _selectedEmployeeId = employees.first['id'];
            }
        }
      });
      if (_selectedEmployeeId != null) {
        _loadTimelineData();
      }
    } catch (e) {
      setState(() => _error = 'Failed to load employees: $e');
    }
  }

  Future<void> _loadTimelineData() async {
    if (_selectedEmployeeId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get location points for selected date
      // Use IST day boundaries but query in UTC (TIMESTAMPTZ-safe)
      const istOffset = Duration(hours: 5, minutes: 30);
      final startOfDayUtc = DateTime.utc(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ).subtract(istOffset);
      final endOfDayUtc = startOfDayUtc.add(const Duration(days: 1));

      final points = await _locationRepo.getPointsByEmployeeAndDateRange(
        employeeId: _selectedEmployeeId!,
        startDate: startOfDayUtc,
        endDate: endOfDayUtc,
      );

      // Sort by recorded time
      points.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

      // Generate timeline events
      final events = TimelineEngine.generateTimeline(points);

      // Calculate total distance
      final totalDistance = DistanceEngine.calculateTotalDistance(points);

      setState(() {
        _points = points;
        _events = events;
        _totalDistance = totalDistance;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load timeline: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 35)),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadTimelineData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Timeline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDate,
            tooltip: 'Select Date',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTimelineData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters
          _buildFilters(),
          
          // Stats summary
          if (_points.isNotEmpty) _buildStatsSummary(),
          
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorView()
                    : _points.isEmpty
                        ? _buildEmptyView()
                        : _buildTimelineContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Employee picker
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedEmployeeId,
              decoration: const InputDecoration(
                labelText: 'Employee',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: _employees.map((e) {
                return DropdownMenuItem(
                  value: e['id'] as String,
                  child: Text(e['name'] as String? ?? 'Unknown'),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedEmployeeId = value);
                _loadTimelineData();
              },
            ),
          ),
          const SizedBox(width: 16),
          // Date display
          InkWell(
            onTap: _selectDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('MMM dd, yyyy').format(_selectedDate),
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSummary() {
    final stopCount = _events.where((e) => e.type == TimelineEventType.stop).length;
    final moveCount = _events.where((e) => e.type == TimelineEventType.move).length;
    final totalStopDuration = _events
        .where((e) => e.type == TimelineEventType.stop)
        .fold<int>(0, (sum, e) => sum + e.durationSec);

    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            icon: Icons.straighten,
            label: 'Distance',
            value: '${_totalDistance.toStringAsFixed(1)} km',
          ),
          _buildStatItem(
            icon: Icons.location_on,
            label: 'Points',
            value: '${_points.length}',
          ),
          _buildStatItem(
            icon: Icons.pause_circle,
            label: 'Stops',
            value: '$stopCount',
          ),
          _buildStatItem(
            icon: Icons.timer,
            label: 'Stop Time',
            value: _formatDuration(totalStopDuration),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
      ],
    );
  }

  Widget _buildTimelineContent() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _events.length,
      itemBuilder: (context, index) {
        final event = _events[index];
        return _buildTimelineEventCard(event, index);
      },
    );
  }

  Widget _buildTimelineEventCard(TimelineEvent event, int index) {
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

    final label = isStart
        ? 'START'
        : isEnd
            ? 'END'
            : isStop
                ? 'STOP'
                : 'MOVE';

    final icon = isStart
        ? Icons.play_arrow
        : isEnd
            ? Icons.flag
            : isStop
                ? Icons.pause
                : Icons.directions_car;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
              ),
              if (index < _events.length - 1)
                Container(
                  width: 2,
                  height: 60,
                  color: Colors.grey.shade300,
                ),
            ],
          ),
          const SizedBox(width: 12),
          // Card content
          Expanded(
            child: Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: color,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          event.durationFormatted,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 16, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          '${DateFormat('HH:mm').format(event.startTime)} - ${DateFormat('HH:mm').format(event.endTime)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                    if (isMove && event.distanceKm != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.straighten, size: 16, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            event.distanceFormatted,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ],
                    if ((isStart || isEnd || isStop) && event.centerLat != null && event.centerLng != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_on, size: 16, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${event.centerLat?.toStringAsFixed(6)}, ${event.centerLng?.toStringAsFixed(6)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timeline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No location data for this date',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Try selecting a different date or employee',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
          const SizedBox(height: 16),
          Text(
            _error ?? 'An error occurred',
            style: TextStyle(fontSize: 16, color: Colors.red.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadTimelineData,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}
