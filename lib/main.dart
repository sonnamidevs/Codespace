import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Global Theme Notifier
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WeatherHubApp());
  // Initialize notifications AFTER runApp so it never blocks the UI.
  NotificationService().init();
}

class WeatherHubApp extends StatelessWidget {
  const WeatherHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'Weatherhub',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF5F5F5),
            colorScheme: const ColorScheme.light(
              surface: Color(0xFFF5F5F5),
              onSurface: Colors.black87,
              onSurfaceVariant: Colors.black54,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF121212),
            colorScheme: const ColorScheme.dark(
              surface: Color(0xFF121212),
              onSurface: Colors.white,
              onSurfaceVariant: Colors.grey,
            ),
          ),
          home: const WeatherScreen(),
        );
      },
    );
  }
}

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  // 🔴 REPLACE THIS WITH YOUR ACTUAL OPENWEATHERMAP API KEY
  static const String apiKey = 'dc09ecccd1c2202e86924f13c2458d90';

  String _cityName = 'Loading...';
  double _temperature = 0.0;
  String _condition = '';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    if (apiKey == 'YOUR_OPENWEATHERMAP_API_KEY') {
      setState(() {
        _errorMessage = 'Please add your API Key in main.dart';
        _isLoading = false;
      });
      return;
    }

    try {
      // Increased timeout to 15 seconds to allow High Accuracy to lock on
      final position = await _determinePosition()
          .timeout(const Duration(seconds: 15));
      await _fetchWeather(position.latitude, position.longitude);
    } catch (e) {
      // If high accuracy fails or times out, try the last known location
      try {
        Position? lastPosition = await Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          await _fetchWeather(lastPosition.latitude, lastPosition.longitude);
          return;
        }
      } catch (_) {}

      // Final fallback to Accra if everything else fails
      if (mounted) {
        setState(() {
          _errorMessage = 'Using Accra, Ghana (location unavailable)';
        });
      }
      await _fetchWeather(5.6037, -0.1870);
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('Location services disabled');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> _fetchWeather(double lat, double lon) async {
    final url = Uri.parse(
      'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey&units=metric',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final condition = data['weather'][0]['main'] ?? 'Clear';

        if (mounted) {
          setState(() {
            _cityName = data['name'] ?? 'Unknown';
            _temperature = (data['main']['temp'] as num).toDouble();
            _condition = condition;
            _isLoading = false;
            _errorMessage = null;
          });
        }
        _checkWeatherAndNotify(condition);
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'API Error: ${response.statusCode}. Check your API key.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Network error. Check your connection.';
          _isLoading = false;
        });
      }
    }
  }

  void _checkWeatherAndNotify(String condition) {
    final c = condition.toLowerCase();
    if (c == 'rain' || c == 'thunderstorm' || c == 'drizzle') {
      NotificationService().showNotification(
        'Weather Alert in $_cityName',
        "It's $condition outside. Don't forget your umbrella!",
      );
    }
  }

  String _getLottieAnimation(String condition, double temp) {
    switch (condition.toLowerCase()) {
      case 'clear':
        return 'assets/Weather-sunny.json';
      case 'clouds':
        return 'assets/Weather-windy.json';
      case 'rain':
      case 'drizzle':
        return 'assets/Weather-partly-shower.json';
      case 'thunderstorm':
        return 'assets/Weather-storm.json';
      default:
        return temp > 25
            ? 'assets/Weather-sunny.json'
            : 'assets/Weather-windy.json';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // AppBar holds the theme toggle and info button cleanly
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
            color: colorScheme.onSurfaceVariant,
            onPressed: () {
              themeNotifier.value =
                  isDarkMode ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            color: colorScheme.onSurfaceVariant,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InfoPage()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                // Center ensures everything is perfectly in the middle
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDarkMode
                                  ? Colors.orangeAccent
                                  : Colors.orange[800],
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      Icon(
                        Icons.location_on,
                        color: colorScheme.onSurfaceVariant,
                        size: 24,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _cityName.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          letterSpacing: 2.0,
                          fontWeight: FontWeight.w300,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 30),
                      
                      // Responsive Lottie Container
                      LayoutBuilder(
                        builder: (context, constraints) {
                          double size = constraints.maxWidth * 0.7;
                          if (size > 300) size = 300; // Max size
                          return Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDarkMode
                                  ? const Color(0xFF1E1E1E)
                                  : const Color(0xFFE0E0E0),
                            ),
                            child: Lottie.asset(
                              _getLottieAnimation(_condition, _temperature),
                              fit: BoxFit.contain,
                              repeat: true,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.cloud,
                                size: size * 0.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                      
                      const SizedBox(height: 30),
                      Text(
                        '${_temperature.toStringAsFixed(0)}°',
                        style: TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.w200,
                          color: colorScheme.onSurface,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _condition,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w400,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

// ---------- Separate Clean Info Page ----------
class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud, size: 80, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 20),
            Text(
              'Bismark NK',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'at Sonnami Develops Ghana',
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 40),
            Text(
              '© 2026 Sonnami Develops',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Notification Service ----------
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    try {
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const InitializationSettings settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(settings: settings);

      _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  Future<void> showNotification(String title, String body) async {
    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'weather_channel',
        'Weather Alerts',
        channelDescription: 'Notifications for weather updates',
        importance: Importance.max,
        priority: Priority.high,
      );
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();
      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _plugin.show(
        id: 0,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('Notification show failed: $e');
    }
  }
}
