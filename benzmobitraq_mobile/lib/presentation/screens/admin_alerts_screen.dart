import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/alerts_engine.dart';

/// Admin Alerts Screen - View and manage employee alerts
/// Per industry-grade specification Section 10
class AdminAlertsScreen extends StatefulWidget {
  const AdminAlertsScreen({super.key});

  @override
  State<AdminAlertsScreen> createState() => _AdminAlertsScreenState();
}

class _AdminAlertsScreenState extends State<AdminAlertsScreen> {
  final _supabase = Supabase.instance.client;
  
  List<MobiTraqAlert> _alerts = [];
  bool _isLoading = true;
  String? _error;
  
  // Filter state
  String _filterType = 'all';
  bool _showOpenOnly = true;

  RealtimeChannel? _alertsChannel;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _subscribeToAlerts();
  }

  @override
  void dispose() {
    _alertsChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToAlerts() {
    _alertsChannel = _supabase
        .channel('public:mobitraq_alerts')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'mobitraq_alerts',
          callback: (payload) {
            // Reload alerts on any change
            _loadAlerts();
          },
        )
        .subscribe();
  }

  Future<void> _loadAlerts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Build query with filters applied conditionally
      dynamic query = _supabase
          .from('mobitraq_alerts')
          .select('*, employees!inner(name)');

      if (_showOpenOnly) {
        query = query.eq('is_open', true);
      }

      if (_filterType != 'all') {
        query = query.eq('alert_type', _filterType);
      }

      query = query.order('created_at', ascending: false).limit(100);

      final response = await query;
      
      final alerts = (response as List).map((json) {
        final alert = MobiTraqAlert.fromJson(json);
        // Add employee name to metadata for display
        return alert.copyWith(
          message: '${json['employees']['name']}: ${alert.message}',
        );
      }).toList();

      setState(() {
        _alerts = alerts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load alerts: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _acknowledgeAlert(MobiTraqAlert alert) async {
    if (alert.id == null) return; // Guard against null ID
    
    try {
      await _supabase.from('mobitraq_alerts').update({
        'is_open': false,
        'end_time': DateTime.now().toUtc().toIso8601String(),
        'acknowledged_by': _supabase.auth.currentUser?.id,
        'acknowledged_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', alert.id!);

      _loadAlerts();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alert acknowledged')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to acknowledge: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAlerts,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters
          _buildFilters(),
          
          // Alert list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorView()
                    : _alerts.isEmpty
                        ? _buildEmptyView()
                        : _buildAlertList(),
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
          ),
        ],
      ),
      child: Row(
        children: [
          // Type filter
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _filterType,
              decoration: const InputDecoration(
                labelText: 'Alert Type',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Types')),
                DropdownMenuItem(value: 'stuck', child: Text('Stuck')),
                DropdownMenuItem(value: 'no_signal', child: Text('No Signal')),
                DropdownMenuItem(value: 'mock_location', child: Text('Mock Location')),
                DropdownMenuItem(value: 'clock_drift', child: Text('Clock Drift')),
              ],
              onChanged: (value) {
                setState(() => _filterType = value ?? 'all');
                _loadAlerts();
              },
            ),
          ),
          const SizedBox(width: 16),
          // Open only toggle
          FilterChip(
            label: const Text('Open Only'),
            selected: _showOpenOnly,
            onSelected: (selected) {
              setState(() => _showOpenOnly = selected);
              _loadAlerts();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAlertList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _alerts.length,
      itemBuilder: (context, index) {
        return _buildAlertCard(_alerts[index]);
      },
    );
  }

  Widget _buildAlertCard(MobiTraqAlert alert) {
    final color = _getAlertColor(alert);
    final icon = _getAlertIcon(alert);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: alert.isOpen ? color : Colors.grey.shade300,
          width: alert.isOpen ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            alert.type.displayName.toUpperCase(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: color,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getSeverityColor(alert.severity).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              alert.severity.value.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _getSeverityColor(alert.severity),
                              ),
                            ),
                          ),
                          if (!alert.isOpen) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'CLOSED',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM dd, HH:mm').format(alert.startTime),
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              alert.message,
              style: const TextStyle(fontSize: 14),
            ),
            if (alert.lat != null && alert.lng != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    '${alert.lat?.toStringAsFixed(6)}, ${alert.lng?.toStringAsFixed(6)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
            if (alert.isOpen) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _acknowledgeAlert(alert),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Acknowledge'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getAlertColor(MobiTraqAlert alert) {
    switch (alert.type) {
      case AlertType.stuck:
        return Colors.orange;
      case AlertType.noSignal:
        return Colors.red;
      case AlertType.mockLocation:
        return Colors.purple;
      case AlertType.clockDrift:
        return Colors.amber;
      case AlertType.forceStop:
        return Colors.grey;
      case AlertType.lowBattery:
        return Colors.yellow.shade800;
      default:
        return Colors.blue;
    }
  }

  IconData _getAlertIcon(MobiTraqAlert alert) {
    switch (alert.type) {
      case AlertType.stuck:
        return Icons.warning;
      case AlertType.noSignal:
        return Icons.signal_wifi_off;
      case AlertType.mockLocation:
        return Icons.gps_off;
      case AlertType.clockDrift:
        return Icons.schedule;
      case AlertType.forceStop:
        return Icons.stop_circle;
      case AlertType.lowBattery:
        return Icons.battery_alert;
      default:
        return Icons.info;
    }
  }

  Color _getSeverityColor(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.info:
        return Colors.blue;
      case AlertSeverity.warn:
        return Colors.orange;
      case AlertSeverity.critical:
        return Colors.red;
    }
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 64, color: Colors.green.shade400),
          const SizedBox(height: 16),
          Text(
            _showOpenOnly ? 'No open alerts' : 'No alerts',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'All tracking is running smoothly',
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
            onPressed: _loadAlerts,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
