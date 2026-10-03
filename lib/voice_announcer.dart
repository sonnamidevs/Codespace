import 'package:flutter_tts/flutter_tts.dart';

/// Lightweight wrapper around flutter_tts for weather announcements.
/// Uses the device's built-in text-to-speech engine.
class VoiceAnnouncer {
  static final VoiceAnnouncer _i = VoiceAnnouncer._internal();
  factory VoiceAnnouncer() => _i;
  VoiceAnnouncer._internal();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Full weather announcement with greeting, current conditions,
  /// high/low, and optional rain-soon warning.
  Future<void> announceWeather({
    required String city,
    required double temp,
    required String condition,
    String? rainSoon,
    double? high,
    double? low,
  }) async {
    await _init();
    if (!_ready) return;
    try {
      await _tts.stop();

      final buf = StringBuffer();
      buf.write(_greeting());
      buf.write('. In $city, it is currently ');
      buf.write('${temp.toStringAsFixed(0)} degrees ');
      buf.write('with ${_humanCondition(condition)}.');

      if (high != null && low != null) {
        buf.write(' Today\'s high is ${high.toStringAsFixed(0)}, ');
        buf.write('low ${low.toStringAsFixed(0)}.');
      }

      if (rainSoon != null) {
        buf.write(' $rainSoon');
      }

      await _tts.speak(buf.toString());
    } catch (_) {}
  }

  /// Speak any custom text.
  Future<void> speakText(String text) async {
    await _init();
    if (!_ready) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _humanCondition(String c) {
    final l = c.toLowerCase();
    if (l.contains('clear')) return 'clear skies';
    if (l.contains('cloud')) return 'cloudy conditions';
    if (l.contains('drizzle')) return 'light drizzle';
    if (l.contains('rain')) return 'rain';
    if (l.contains('thunder')) return 'thunderstorms';
    if (l.contains('snow')) return 'snow';
    if (l.contains('fog')) return 'foggy conditions';
    if (l.contains('mist')) return 'misty conditions';
    return c;
  }
}
