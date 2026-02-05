import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/distance_engine.dart';
import '../../core/timeline_engine.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/location_point_model.dart';
import '../../data/models/session_model.dart';
import '../../data/repositories/location_repository.dart';
import '../../data/repositories/session_repository.dart';

/// Admin Timeline Screen - View employee routes and stops by session
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

/// Session with its timeline events and points grouped together
class SessionTimelineData {
  final SessionModel session;
  final List<LocationPointModel> points;
  final List<TimelineEvent> events;
  final double totalDistanceKm;
  final int stopsCount;
  final double averageSpeedKmh;

  SessionTimelineData({
    required this.session,
    required this.points,
    required this.events,
    required this.totalDistanceKm,
    required this.stopsCount,
    required this.averageSpeedKmh,
  });
}

class _AdminTimelineScreenState extends State<AdminTimelineScreen> {
  final LocationRepository _locationRepo = GetIt.instance<LocationRepository>();
  final SessionRepository _sessionRepo = GetIt.instance<SessionRepository>();
  final MapController _mapController = MapController();

  String? _selectedEmployeeId;
  DateTime _selectedDate = DateTime.now();
  
  List<SessionTimelineData> _sessionData = [];
  String? _selectedSessionId; // When clicked, show this session's map
  bool _isLoading = false;
  String? _error;

  // Employee list for picker
  List<Map<String, dynamic>> _employees = [];

  // Day totals for summary
  double _dayTotalDistance = 0;
  int _dayTotalSessions = 0;
  Duration _dayTotalDuration = Duration.zero;

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
        if (_selectedEmployeeId == null && employees.isNotEmpty) {
          _selectedEmployeeId = employees.first['id'];
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
      _selectedSessionId = null;
    });

    try {
      // Get sessions for the selected employee/date
      // Use IST day boundaries but query in UTC (TIMESTAMPTZ-safe)
      const istOffset = Duration(hours: 5, minutes: 30);
      final startOfDayUtc = DateTime.utc(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ).subtract(istOffset);
      final endOfDayUtc = startOfDayUtc.add(const Duration(days: 1));

      // Get all location points for the day
      final allPoints = await _locationRepo.getPointsByEmployeeAndDateRange(
        employeeId: _selectedEmployeeId!,
        startDate: startOfDayUtc,
        endDate: endOfDayUtc,
      );

      // Group points by session_id
      final sessionPointsMap = <String, List<LocationPointModel>>{};
      final sessionIds = <String>{};
      
      for (final point in allPoints) {
        final sessionId = point.sessionId;
        if (!sessionPointsMap.containsKey(sessionId)) {
          sessionPointsMap[sessionId] = [];
          sessionIds.add(sessionId);
        }
        sessionPointsMap[sessionId]!.add(point);
      }

      // Build session data for each session
      final sessionDataList = <SessionTimelineData>[];
      double dayDistance = 0;
      Duration dayDuration = Duration.zero;

      for (final sessionId in sessionIds) {
        final points = sessionPointsMap[sessionId]!;
        points.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

        // Try to get session model
        final session = await _sessionRepo.getSession(sessionId);
        if (session == null) continue;

        // Generate timeline events
        final events = TimelineEngine.generateTimeline(points);

        // Calculate stats
        final distance = session.totalKm > 0 
            ? session.totalKm 
            : DistanceEngine.calculateTotalDistance(points);
        final stopsCount = events.where((e) => e.type == TimelineEventType.stop).length;
        
        // Calculate average speed (km/h)
        final durationHours = session.duration.inSeconds / 3600;
        final avgSpeed = durationHours > 0 ? distance / durationHours : 0.0;

        sessionDataList.add(SessionTimelineData(
          session: session,
          points: points,
          events: events,
          totalDistanceKm: distance,
          stopsCount: stopsCount,
          averageSpeedKmh: avgSpeed,
        ));

        dayDistance += distance;
        dayDuration += session.duration;
      }

      // Sort by start time
      sessionDataList.sort((a, b) => a.session.startTime.compareTo(b.session.startTime));

      setState(() {
        _sessionData = sessionDataList;
        _dayTotalDistance = dayDistance;
        _dayTotalSessions = sessionDataList.length;
        _dayTotalDuration = dayDuration;
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

  void _selectSession(String? sessionId) {
    setState(() {
      _selectedSessionId = sessionId;
    });
  }

  void _openInMaps(double lat, double lng) async {
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  /// Convert UTC to IST for display
  String _formatTimeIST(DateTime utcTime) {
    return DateTimeUtils.formatTime(utcTime);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Timeline'),
        actions: [
          if (_selectedSessionId != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => _selectSession(null),
              tooltip: 'Back to Overview',
            ),
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
          
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorView()
                    : _sessionData.isEmpty
                        ? _buildEmptyView()
                        : _selectedSessionId != null
                            ? _buildSessionDetailView()
                            : _buildDayOverview(),
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
            color: Colors.black.withValues(alpha: 0.05),
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
                    DateFormat('MMM dd').format(DateTimeUtils.toIST(_selectedDate)),
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

  Widget _buildDayOverview() {
    return Column(
      children: [
        // Day summary stats
        _buildDaySummary(),
        
        // Session list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _sessionData.length,
            itemBuilder: (context, index) {
              final data = _sessionData[index];
              return _buildSessionCard(data, index + 1);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDaySummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            icon: Icons.work_history,
            label: 'Sessions',
            value: '$_dayTotalSessions',
          ),
          _buildStatItem(
            icon: Icons.straighten,
            label: 'Distance',
            value: '${_dayTotalDistance.toStringAsFixed(1)} km',
          ),
          _buildStatItem(
            icon: Icons.timer,
            label: 'Duration',
            value: DateTimeUtils.formatDuration(_dayTotalDuration),
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

  Widget _buildSessionCard(SessionTimelineData data, int sessionNumber) {
    final session = data.session;
    final isActive = session.status == SessionStatus.active;
    final startTime = _formatTimeIST(session.startTime);
    final endTime = session.endTime != null ? _formatTimeIST(session.endTime!) : 'Active';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive ? Colors.green.withValues(alpha: 0.5) : Colors.grey.withValues(alpha: 0.2),
          width: isActive ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => _selectSession(session.id),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Session number badge
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isActive 
                        ? [Colors.green, Colors.green.shade700]
                        : [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    '#$sessionNumber',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$startTime - $endTime',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.route, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 4),
                        Text(
                          '${data.totalDistanceKm.toStringAsFixed(1)} km',
                          style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 16),
                        Icon(Icons.timer, size: 16, color: Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(session.duration),
                          style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600),
                        ),
                        if (data.stopsCount > 0) ...[
                          const SizedBox(width: 16),
                          Icon(Icons.pause_circle, size: 16, color: Colors.orange.shade700),
                          const SizedBox(width: 4),
                          Text(
                            '${data.stopsCount} stops',
                            style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              
              // Arrow icon
              Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionDetailView() {
    final data = _sessionData.firstWhere(
      (d) => d.session.id == _selectedSessionId,
      orElse: () => _sessionData.first,
    );
    final session = data.session;
    final sessionNumber = _sessionData.indexOf(data) + 1;

    return Column(
      children: [
        // Map view
        Expanded(
          flex: 3,
          child: _buildMapView(data),
        ),
        
        // Session summary
        Expanded(
          flex: 2,
          child: _buildSessionSummary(data, sessionNumber),
        ),
      ],
    );
  }

  Widget _buildMapView(SessionTimelineData data) {
    if (data.points.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        child: const Center(child: Text('No location data')),
      );
    }

    // Build route polyline
    final routePoints = data.points
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    // Find bounds to center map
    double minLat = routePoints.first.latitude;
    double maxLat = routePoints.first.latitude;
    double minLng = routePoints.first.longitude;
    double maxLng = routePoints.first.longitude;

    for (final point in routePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

    // Build markers for stops
    final markers = <Marker>[];
    
    // Start marker
    if (routePoints.isNotEmpty) {
      markers.add(Marker(
        point: routePoints.first,
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _openInMaps(routePoints.first.latitude, routePoints.first.longitude),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 24),
          ),
        ),
      ));
    }

    // End marker
    if (routePoints.length > 1) {
      markers.add(Marker(
        point: routePoints.last,
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _openInMaps(routePoints.last.latitude, routePoints.last.longitude),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: const Icon(Icons.flag, color: Colors.white, size: 24),
          ),
        ),
      ));
    }

    // Stop markers from events
    for (final event in data.events) {
      if (event.type == TimelineEventType.stop && event.centerLat != null && event.centerLng != null) {
        markers.add(Marker(
          point: LatLng(event.centerLat!, event.centerLng!),
          width: 36,
          height: 36,
          child: GestureDetector(
            onTap: () => _openInMaps(event.centerLat!, event.centerLng!),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: Center(
                child: Text(
                  event.durationFormatted,
                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ));
      }
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 14,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.benzmobitraq_mobile',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: routePoints,
              strokeWidth: 4,
              color: Colors.blue.shade700,
            ),
          ],
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _buildSessionSummary(SessionTimelineData data, int sessionNumber) {
    final session = data.session;
    final isActive = session.status == SessionStatus.active;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session header
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      '#$sessionNumber',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Session #$sessionNumber', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          if (isActive)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(8)),
                              child: const Text('ACTIVE', style: TextStyle(color: Colors.white, fontSize: 10)),
                            ),
                        ],
                      ),
                      Text(
                        DateFormat('EEEE, MMMM d').format(DateTimeUtils.toIST(session.startTime)),
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            const Divider(),
            
            // Stats row
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMiniStat(Icons.route, '${data.totalDistanceKm.toStringAsFixed(1)} km', 'Distance', Colors.blue),
                  _buildMiniStat(Icons.timer, _formatDuration(session.duration), 'Duration', Colors.green),
                  _buildMiniStat(Icons.speed, '${data.averageSpeedKmh.toStringAsFixed(1)} km/h', 'Avg Speed', Colors.purple),
                  _buildMiniStat(Icons.pause_circle, '${data.stopsCount}', 'Stops', Colors.orange),
                ],
              ),
            ),
            
            const Divider(),
            const SizedBox(height: 12),
            
            // Start/End details
            _buildLocationDetail(
              icon: Icons.play_arrow,
              color: Colors.green,
              title: 'Started',
              time: _formatTimeIST(session.startTime),
              location: session.startAddress ?? 'Location available on map',
            ),
            const SizedBox(height: 12),
            _buildLocationDetail(
              icon: Icons.flag,
              color: Colors.red,
              title: isActive ? 'In Progress' : 'Ended',
              time: session.endTime != null ? _formatTimeIST(session.endTime!) : '--:--',
              location: session.endAddress ?? 'Location available on map',
            ),
            
            // Stops list (if any)
            if (data.stopsCount > 0) ...[
              const SizedBox(height: 16),
              const Text('Stops', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ...data.events
                  .where((e) => e.type == TimelineEventType.stop)
                  .map((event) => _buildStopItem(event)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildLocationDetail({
    required IconData icon,
    required Color color,
    required String title,
    required String time,
    required String location,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
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
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                  const Spacer(),
                  Text(time, style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
              Text(
                location,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStopItem(TimelineEvent event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.pause, color: Colors.orange, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_formatTimeIST(event.startTime)} - ${_formatTimeIST(event.endTime)}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  'Duration: ${event.durationFormatted}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (event.centerLat != null && event.centerLng != null)
            IconButton(
              icon: const Icon(Icons.map, color: Colors.orange),
              onPressed: () => _openInMaps(event.centerLat!, event.centerLng!),
              tooltip: 'Open in Maps',
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
            'No sessions for this date',
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

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}
