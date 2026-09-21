import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Global Theme Notifier
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  runApp(const WeatherHubApp());
}

class WeatherHubApp extends StatelessWidget {
  const WeatherHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'Weather Hub by Sonnami Develops',
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
  // Replace with your actual OpenWeatherMap API Key
  static const String apiKey = 'YOUR_OPENWEATHERMAP_API_KEY';

  String _cityName = 'Locating...';
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
    try {
      Position position = await _determinePosition();
      await _fetchWeather(position.latitude, position.longitude);
    } catch (e) {
      setState(() {
        _errorMessage = 'Location denied. Showing Accra, GH.';
      });
      await _fetchWeather(5.6037, -0.1870); // Fallback to Accra
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('Location services are disabled.');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied.');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.low,
    );
  }

  Future<void> _fetchWeather(double lat, double lon) async {
    final url = Uri.parse(
      'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey&units=metric',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final condition = data['weather'][0]['main'] ?? 'Clear';

        setState(() {
          _cityName = data['name'] ?? 'Unknown Location';
          _temperature = (data['main']['temp'] as num).toDouble();
          _condition = condition;
          _isLoading = false;
          _errorMessage = null;
        });

        // Trigger Notification if weather is bad
        _checkWeatherAndNotify(condition);
      } else {
        setState(() {
          _errorMessage = 'Failed to load weather (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error. Please check your connection.';
        _isLoading = false;
      });
    }
  }

  void _checkWeatherAndNotify(String condition) {
    if (condition.toLowerCase() == 'rain' ||
        condition.toLowerCase() == 'thunderstorm' ||
        condition.toLowerCase() == 'drizzle') {
      NotificationService().showNotification(
        'Weather Alert in $_cityName',
        'It looks like $condition outside. Don\'t forget your umbrella!',
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
        return 'assets/Weather-partly shower.json';
      case 'thunderstorm':
        return 'assets/Weather-storm.json';
      default:
        if (temp > 25) return 'assets/Weather-sunny.json';
        return 'assets/Weather-windy.json';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Main Content
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(height: 60), // Top spacer
                      
                      // Weather Content
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: isDarkMode ? Colors.orangeAccent : Colors.orange[800],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          Icon(Icons.location_on, color: colorScheme.onSurfaceVariant, size: 20),
                          const SizedBox(height: 4),
                          Text(
                            _cityName.toUpperCase(),
                            style: TextStyle(
                              fontSize: 18,
                              letterSpacing: 2.0,
                              fontWeight: FontWeight.w300,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          // Lottie Animation with background circle for visibility in light mode
                          Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFE0E0E0),
                            ),
                            child: Lottie.asset(
                              _getLottieAnimation(_condition, _temperature),
                              fit: BoxFit.contain,
                              repeat: true,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(Icons.cloud, size: 100, color: colorScheme.onSurfaceVariant);
                              },
                            ),
                          ),
                          
                          const SizedBox(height: 20),
                          Text(
                            '${_temperature.toStringAsFixed(0)}°',
                            style: TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.w200,
                              color: colorScheme.onSurface,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _condition,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w400,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),

                      // Footer / Credits
                      Column(
                        children: [
                          Text(
                            'Bismark NK at Sonnami Develops Ghana',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '© 2026 Sonnami Develops',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w300,
                              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ],
                  ),
            
            // Theme Toggle Button (Top Right)
            Positioned(
              top: 10,
              right: 15,
              child: IconButton(
                icon: Icon(
                  isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed: () {
                  themeNotifier.value = isDarkMode ? ThemeMode.light : ThemeMode.dark;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Notification Service Helper Class
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true);
    
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);

    // Request Android 13+ Permission
    _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }

  Future<void> showNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
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

    await _plugin.show(0, title, body, details);
  }
}
