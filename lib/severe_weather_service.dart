import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart' show NotificationService;

/// Severity levels for weather alerts.
enum SevereLevel { watch, warning, emergency }

/// A single severe weather alert.
class SevereAlert {
  final String id;
  final String title;
  final String body;
  final SevereLevel level;
  final IconData icon;
  final Color color;

  SevereAlert({
    required this.id,
    required this.title,
    required this.body,
    required this.level,
    required this.icon,
    required this.color,
  });
}

/// Detects severe weather conditions from forecast data and sends
/// emergency notifications (once per day per alert type).
class SevereWeatherService {
  /// Analyze current conditions and return any applicable alerts.
  /// Thresholds are tuned for Ghana's climate:
  /// - Thunderstorm: WMO codes 95–99
  /// - High wind: ≥ 40 km/h
  /// - Extreme heat: ≥ 35°C
  /// - Heavy rain: ≥ 80% precipitation probability
  /// - Extreme UV: ≥ 10
  static List<SevereAlert> detect({
    required double temp,
    required double windSpeed,
    required double precipProbability,
    required int weatherCode,
    required double uvIndex,
  }) {
    final alerts = <SevereAlert>[];

    // Thunderstorm
    if (weatherCode >= 95 && weatherCode <= 99) {
      alerts.add(SevereAlert(
        id: 'thunderstorm',
        title: '⛈️ Thunderstorm Warning',
        body:
            'Lightning and heavy rain are expected. Stay indoors and unplug sensitive electronics.',
        level: SevereLevel.emergency,
        icon: Icons.flash_on,
        color: const Color(0xFF9575CD),
      ));
    }

    // High wind
    if (windSpeed >= 40) {
      alerts.add(SevereAlert(
        id: 'high_wind',
        title: '💨 High Wind Warning',
        body:
            'Winds of ${windSpeed.toStringAsFixed(0)} km/h. Secure loose items outdoors.',
        level: SevereLevel.warning,
        icon: Icons.air,
        color: const Color(0xFF4FC3F7),
      ));
    }

    // Extreme heat
    if (temp >= 35) {
      alerts.add(SevereAlert(
        id: 'extreme_heat',
        title: '🔥 Extreme Heat Warning',
        body:
            'Temperatures of ${temp.toStringAsFixed(0)}°C. Drink water frequently, avoid direct sun between 10am–4pm.',
        level: SevereLevel.warning,
        icon: Icons.thermostat,
        color: const Color(0xFFFF7043),
      ));
    }

    // Heavy rain
    if (precipProbability >= 80 && weatherCode < 95) {
      alerts.add(SevereAlert(
        id: 'heavy_rain',
        title: '🌧️ Heavy Rain Alert',
        body:
            '${precipProbability.toStringAsFixed(0)}% chance of heavy rainfall. Localised flooding may occur.',
        level: SevereLevel.watch,
        icon: Icons.umbrella,
        color: const Color(0xFF29B6F6),
      ));
    }

    // Extreme UV
    if (uvIndex >= 10) {
      alerts.add(SevereAlert(
        id: 'extreme_uv',
        title: '☀️ Extreme UV Index',
        body:
            'UV index of ${uvIndex.toStringAsFixed(0)}. Avoid sun exposure. Apply SPF 50+ if you must go out.',
        level: SevereLevel.warning,
        icon: Icons.wb_sunny,
        color: const Color(0xFFF44336),
      ));
    }

    return alerts;
  }

  /// Sends a notification for each alert. Won't repeat the same alert
  /// twice within the same day.
  static Future<void> notifyAlerts(List<SevereAlert> alerts) async {
    if (alerts.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];

    int idx = 100; // notification ID range for severe alerts
    for (final alert in alerts) {
      final key = 'alert_sent_${alert.id}_$today';
      if (prefs.getBool(key) == true) {
        idx++;
        continue;
      }
      final isEmergency = alert.level == SevereLevel.emergency;
      await NotificationService().showNotification(
        alert.title,
        alert.body,
        id: idx,
        isPersistent: isEmergency,
      );
      await prefs.setBool(key, true);
      idx++;
    }
  }
}
