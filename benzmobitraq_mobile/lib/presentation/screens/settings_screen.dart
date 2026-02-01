import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../data/datasources/local/preferences_local.dart';
import '../../data/models/notification_settings.dart';

/// Elegant settings screen for notification frequency configuration
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final PreferencesLocal _prefs = PreferencesLocal();
  NotificationSettings _settings = NotificationSettings.defaults();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _prefs.init();
    final json = _prefs.notificationSettingsJson;
    if (json != null) {
      try {
        _settings = NotificationSettings.fromJson(jsonDecode(json));
      } catch (_) {
        _settings = NotificationSettings.defaults();
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    await _prefs.setNotificationSettingsJson(jsonEncode(_settings.toJson()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Settings saved'),
          backgroundColor: const Color(0xFF1A1A2E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: GoogleFonts.inter(
            color: const Color(0xFF1A1A2E),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Text(
                    'Notification Frequency',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Configure when you want to receive tracking updates',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Distance Settings Card
                  _buildSettingsCard(
                    icon: Icons.straighten_rounded,
                    iconColor: const Color(0xFFC9A227),
                    title: 'Distance Alerts',
                    subtitle: 'Get notified every ${_settings.distanceKm.toStringAsFixed(1)} km',
                    enabled: _settings.distanceEnabled,
                    onToggle: (value) {
                      setState(() {
                        _settings = _settings.copyWith(distanceEnabled: value);
                      });
                      _saveSettings();
                    },
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '1 km',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                            Text(
                              '${_settings.distanceKm.toStringAsFixed(1)} km',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1A1A2E),
                              ),
                            ),
                            Text(
                              '10 km',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: const Color(0xFFC9A227),
                            inactiveTrackColor: const Color(0xFFE2E8F0),
                            thumbColor: const Color(0xFFC9A227),
                            overlayColor: const Color(0x29C9A227),
                            trackHeight: 4,
                          ),
                          child: Slider(
                            value: _settings.distanceKm,
                            min: NotificationSettings.minDistanceKm,
                            max: NotificationSettings.maxDistanceKm,
                            divisions: 9,
                            onChanged: _settings.distanceEnabled
                                ? (value) {
                                    setState(() {
                                      _settings = _settings.copyWith(distanceKm: value);
                                    });
                                  }
                                : null,
                            onChangeEnd: (_) => _saveSettings(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Time Settings Card
                  _buildSettingsCard(
                    icon: Icons.timer_outlined,
                    iconColor: const Color(0xFF1A1A2E),
                    title: 'Time Alerts',
                    subtitle: 'Get notified every ${_settings.timeMinutes} minutes',
                    enabled: _settings.timeEnabled,
                    onToggle: (value) {
                      setState(() {
                        _settings = _settings.copyWith(timeEnabled: value);
                      });
                      _saveSettings();
                    },
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '10 min',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                            Text(
                              '${_settings.timeMinutes} min',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1A1A2E),
                              ),
                            ),
                            Text(
                              '60 min',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: const Color(0xFF1A1A2E),
                            inactiveTrackColor: const Color(0xFFE2E8F0),
                            thumbColor: const Color(0xFF1A1A2E),
                            overlayColor: const Color(0x291A1A2E),
                            trackHeight: 4,
                          ),
                          child: Slider(
                            value: _settings.timeMinutes.toDouble(),
                            min: NotificationSettings.minTimeMinutes.toDouble(),
                            max: NotificationSettings.maxTimeMinutes.toDouble(),
                            divisions: 5,
                            onChanged: _settings.timeEnabled
                                ? (value) {
                                    setState(() {
                                      _settings = _settings.copyWith(timeMinutes: value.round());
                                    });
                                  }
                                : null,
                            onChangeEnd: (_) => _saveSettings(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Info Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Color(0xFF64748B),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Notifications help you stay updated on your tracking progress without opening the app.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required Widget child,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled ? iconColor.withOpacity(0.3) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: enabled,
                onChanged: onToggle,
                activeColor: iconColor,
              ),
            ],
          ),
          if (enabled) child,
        ],
      ),
    );
  }
}
