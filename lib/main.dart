import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:github_release_apk_updater/github_release_apk_updater.dart';

// ================= THEME NOTIFIER =================
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

// ================= APP CONFIG =================
const String kGithubOwner = 'sonnamidevs';
const String kGithubRepo = 'sonnamidevs.github.io';
const String kApkAssetName = 'WeatherHub.apk';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  try {
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
  } catch (e) {
    debugPrint('Timezone setup failed: $e');
  }
  runApp(const WeatherHubApp());
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
          title: 'Weather Hub',
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

// ================= ENHANCED FORECAST MODELS =================
class ForecastDay {
  final DateTime date;
  final double temp;
  final double maxTemp;
  final double minTemp;
  final double feelsLikeMax;
  final double feelsLikeMin;
  final String condition;
  final String detailedCondition;
  final int weatherCode;
  final double precipitationProbability;
  final double uvIndex;
  final double windSpeedMax;
  final double humidityAvg;
  final DateTime? sunrise;
  final DateTime? sunset;

  ForecastDay({
    required this.date,
    required this.temp,
    required this.maxTemp,
    required this.minTemp,
    required this.feelsLikeMax,
    required this.feelsLikeMin,
    required this.condition,
    required this.detailedCondition,
    required this.weatherCode,
    required this.precipitationProbability,
    required this.uvIndex,
    required this.windSpeedMax,
    required this.humidityAvg,
    this.sunrise,
    this.sunset,
  });
}

class HourlyForecast {
  final DateTime time;
  final double temp;
  final String condition;
  final double precipitationProbability;
  final double humidity;
  HourlyForecast({
    required this.time,
    required this.temp,
    required this.condition,
    required this.precipitationProbability,
    required this.humidity,
  });
}

// ================= MAIN SCREEN =================
class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  static const String apiKey = 'dc09ecccd1c2202e86924f13c2458d90';

  String _cityName = 'Loading...';
  double _temperature = 0.0;
  double _feelsLike = 0.0;
  double _humidity = 0.0;
  double _windSpeed = 0.0;
  String _condition = '';
  bool _isLoading = true;
  bool _isCelsius = true;
  String? _errorMessage;

  DateTime? _sunrise;
  DateTime? _sunset;

  List<ForecastDay> _forecast = [];
  List<HourlyForecast> _hourly = [];

  double _lastLat = 0.0;
  double _lastLon = 0.0;
  String? _lastCity;

  Map<String, String>? _delights;

  // Update service
  final _updater = GithubReleaseApkUpdater();
  final _apiService = GithubApiService();
  final _downloaderService = ApkDownloaderService();
  final _versionComparator = VersionComparator();

  @override
  void initState() {
    super.initState();
    _loadWeather();
    _loadDelights();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  // ================= IN-APP UPDATE =================
  Future<void> _checkForUpdates() async {
    try {
      final supportedAbis = await _updater.getSupportedAbis();
      final release = await _apiService.getLatestGithubAPKRelease(
        ownerGithub: kGithubOwner,
        repositoryGithub: kGithubRepo,
        apkKeyName: kApkAssetName,
        supportedAbis: supportedAbis,
      );
      if (release == null) return;

      final currentVersion = await _updater.getCurrentAppVersion();
      final isNewer = _versionComparator.isNewerVersion(
        release.version,
        currentVersion,
      );

      if (isNewer && mounted) {
        _showUpdateDialog(release);
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  void _showUpdateDialog(GithubAPKRelease release) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateDialog(
        release: release,
        downloaderService: _downloaderService,
        updaterPlugin: _updater,
      ),
    );
  }

  // ================= LOAD DELIGHTS =================
  Future<void> _loadDelights({bool forceRefresh = false}) async {
    final data = await SmallDelightsService()
        .fetchDailyDelight(forceRefresh: forceRefresh);
    if (mounted) {
      setState(() => _delights = data);
      if (data['quote'] != null && data['fact'] != null) {
        NotificationService().scheduleDailyDelight(
          quote: data['quote']!,
          fact: data['fact']!,
        );
      }
    }
  }

  // ================= GREETING =================
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 21) return 'Good evening';
    return 'Good night';
  }

  // ================= SMART SUMMARY =================
  String _getSmartSummary() {
    final c = _condition.toLowerCase();
    final temp = _temperature;
    String base;

    if (c.contains('rain') || c.contains('drizzle')) {
      base = 'Rainy conditions right now';
    } else if (c.contains('thunder')) {
      base = 'Thunderstorms in your area';
    } else if (c.contains('clear') && temp >= 30) {
      base = 'Hot and sunny outside';
    } else if (c.contains('clear')) {
      base = 'Clear skies and pleasant';
    } else if (c.contains('cloud')) {
      base = 'Cloudy skies today';
    } else {
      base = 'Current conditions: $_condition';
    }

    final rainSoon = _hourly.take(3).where((h) {
      final cond = h.condition.toLowerCase();
      return cond.contains('rain') ||
          cond.contains('drizzle') ||
          cond.contains('thunder');
    }).toList();

    if (rainSoon.isNotEmpty && !c.contains('rain')) {
      base += '. Rain expected around ${_formatTime(rainSoon.first.time)}';
    }

    return base;
  }

  // ================= LOAD WEATHER =================
  Future<void> _loadWeather({String? cityQuery}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (cityQuery != null && cityQuery.trim().isNotEmpty) {
        _lastCity = cityQuery.trim();
        final unit = _isCelsius ? 'metric' : 'imperial';
        final url = Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather?q=${_lastCity}&appid=$apiKey&units=$unit',
        );
        final res = await http.get(url).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          _lastLat = (data['coord']['lat'] as num).toDouble();
          _lastLon = (data['coord']['lon'] as num).toDouble();
          _applyCurrentWeather(data);
          await _fetchForecast(_lastLat, _lastLon);
        } else if (res.statusCode == 404) {
          setState(() {
            _errorMessage = 'City not found. Try another one.';
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = 'API Error ${res.statusCode}.';
            _isLoading = false;
          });
        }
      } else {
        _lastCity = null;
        final pos =
            await _determinePosition().timeout(const Duration(seconds: 15));
        _lastLat = pos.latitude;
        _lastLon = pos.longitude;
        await _fetchCurrent(_lastLat, _lastLon);
        await _fetchForecast(_lastLat, _lastLon);
      }
    } catch (e) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          _lastLat = last.latitude;
          _lastLon = last.longitude;
          await _fetchCurrent(_lastLat, _lastLon);
          await _fetchForecast(_lastLat, _lastLon);
          return;
        }
      } catch (_) {}
      if (mounted) {
        setState(() => _errorMessage = 'Using Accra, Ghana (GPS unavailable)');
      }
      _lastLat = 5.6037;
      _lastLon = -0.1870;
      await _fetchCurrent(_lastLat, _lastLon);
      await _fetchForecast(_lastLat, _lastLon);
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

  Future<void> _fetchCurrent(double lat, double lon) async {
    final unit = _isCelsius ? 'metric' : 'imperial';
    final url = Uri.parse(
      'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey&units=$unit',
    );
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        _applyCurrentWeather(json.decode(res.body));
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'API Error ${res.statusCode}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Network error.';
          _isLoading = false;
        });
      }
    }
  }

  void _applyCurrentWeather(dynamic data) {
    final condition = data['weather'][0]['main'] ?? 'Clear';
    if (mounted) {
      setState(() {
        _cityName = data['name'] ?? 'Unknown';
        _temperature = (data['main']['temp'] as num).toDouble();
        _feelsLike = (data['main']['feels_like'] as num).toDouble();
        _humidity = (data['main']['humidity'] as num).toDouble();
        _windSpeed = (data['wind']['speed'] as num).toDouble();
        _condition = condition;
        _errorMessage = null;
        try {
          _sunrise = DateTime.fromMillisecondsSinceEpoch(
              (data['sys']['sunrise'] as int) * 1000);
          _sunset = DateTime.fromMillisecondsSinceEpoch(
              (data['sys']['sunset'] as int) * 1000);
        } catch (_) {}
      });
    }
  }

  // ================= ENHANCED FORECAST FETCH =================
  Future<void> _fetchForecast(double lat, double lon) async {
    final tempUnit = _isCelsius ? 'celsius' : 'fahrenheit';
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat'
      '&longitude=$lon'
      '&daily=weather_code,temperature_2m_max,temperature_2m_min,'
      'apparent_temperature_max,apparent_temperature_min,'
      'precipitation_probability_max,uv_index_max,wind_speed_10m_max,sunrise,sunset'
      '&hourly=temperature_2m,weather_code,relative_humidity_2m,'
      'precipitation_probability,apparent_temperature,wind_speed_10m'
      '&timezone=auto'
      '&forecast_days=7'
      '&temperature_unit=$tempUnit',
    );

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final daily = data['daily'];
        final hourly = data['hourly'];

        final List<ForecastDay> forecastList = [];
        final List<HourlyForecast> hourlyList = [];

        final dates = daily['time'] as List;
        final codes = daily['weather_code'] as List;
        final maxTemps = daily['temperature_2m_max'] as List;
        final minTemps = daily['temperature_2m_min'] as List;
        final feelsMax = daily['apparent_temperature_max'] as List;
        final feelsMin = daily['apparent_temperature_min'] as List;
        final precipProb = daily['precipitation_probability_max'] as List;
        final uvIndex = daily['uv_index_max'] as List;
        final windMax = daily['wind_speed_10m_max'] as List;
        final sunriseList = daily['sunrise'] as List;
        final sunsetList = daily['sunset'] as List;

        final hTimes = hourly['time'] as List;
        final hHumidity = hourly['relative_humidity_2m'] as List;
        final Map<String, List<double>> humidityByDate = {};
        for (int i = 0; i < hTimes.length; i++) {
          final dateKey = (hTimes[i] as String).split('T')[0];
          humidityByDate.putIfAbsent(dateKey, () => []);
          if (hHumidity[i] != null) {
            humidityByDate[dateKey]!.add((hHumidity[i] as num).toDouble());
          }
        }

        for (int i = 1; i < dates.length && forecastList.length < 5; i++) {
          final dateKey = dates[i] as String;
          final humidityList = humidityByDate[dateKey] ?? [];
          final avgHumidity = humidityList.isEmpty
              ? 0.0
              : humidityList.reduce((a, b) => a + b) / humidityList.length;

          forecastList.add(ForecastDay(
            date: DateTime.parse(dateKey),
            temp: ((maxTemps[i] as num) + (minTemps[i] as num)) / 2,
            maxTemp: (maxTemps[i] as num).toDouble(),
            minTemp: (minTemps[i] as num).toDouble(),
            feelsLikeMax: (feelsMax[i] as num?)?.toDouble() ?? 0.0,
            feelsLikeMin: (feelsMin[i] as num?)?.toDouble() ?? 0.0,
            condition: _wmoCodeToCondition(codes[i] as int),
            detailedCondition: _wmoCodeToDescription(codes[i] as int),
            weatherCode: codes[i] as int,
            precipitationProbability:
                (precipProb[i] as num?)?.toDouble() ?? 0.0,
            uvIndex: (uvIndex[i] as num?)?.toDouble() ?? 0.0,
            windSpeedMax: (windMax[i] as num?)?.toDouble() ?? 0.0,
            humidityAvg: avgHumidity,
            sunrise: sunriseList[i] != null
                ? DateTime.tryParse(sunriseList[i] as String)
                : null,
            sunset: sunsetList[i] != null
                ? DateTime.tryParse(sunsetList[i] as String)
                : null,
          ));
        }

        final hTemps = hourly['temperature_2m'] as List;
        final hCodes = hourly['weather_code'] as List;
        final hPrecip = hourly['precipitation_probability'] as List;

        for (int i = 0; i < hTimes.length && hourlyList.length < 8; i += 3) {
          hourlyList.add(HourlyForecast(
            time: DateTime.parse(hTimes[i] as String),
            temp: (hTemps[i] as num).toDouble(),
            condition: _wmoCodeToCondition(hCodes[i] as int),
            precipitationProbability:
                (hPrecip[i] as num?)?.toDouble() ?? 0.0,
            humidity: (hHumidity[i] as num?)?.toDouble() ?? 0.0,
          ));
        }

        if (mounted) {
          setState(() {
            _hourly = hourlyList;
            _forecast = forecastList;
            _isLoading = false;
          });
        }

        await _checkForecastChanges(forecastList);
        _scheduleNotifications();
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Forecast fetch failed: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ================= FORECAST CHANGE DETECTION =================
  Future<void> _checkForecastChanges(List<ForecastDay> newForecast) async {
    if (newForecast.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();

    final signature = newForecast
        .map((d) =>
            '${d.date.day}:${d.condition}:${d.maxTemp.toStringAsFixed(0)}')
        .join('|');

    final lastSignature = prefs.getString('last_forecast_signature');
    await prefs.setString('last_forecast_signature', signature);

    if (lastSignature == null || lastSignature == signature) return;

    final oldParts = lastSignature.split('|');
    final newParts = signature.split('|');

    for (int i = 0; i < newParts.length && i < oldParts.length; i++) {
      final oldSeg = oldParts[i].split(':');
      final newSeg = newParts[i].split(':');
      if (oldSeg.length < 3 || newSeg.length < 3) continue;

      final oldCond = oldSeg[1];
      final newCond = newSeg[1];
      final oldTemp = double.tryParse(oldSeg[2]) ?? 0;
      final newTemp = double.tryParse(newSeg[2]) ?? 0;

      final day = newForecast[i];

      if (oldCond != newCond) {
        if (newCond.toLowerCase().contains('rain') &&
            !oldCond.toLowerCase().contains('rain')) {
          NotificationService().showNotification(
            '🌧️ Forecast Update for ${_dayName(day.date)}',
            'Rain is now expected. Precipitation probability: ${day.precipitationProbability.toStringAsFixed(0)}%',
            id: 20 + i,
          );
        } else if (newCond.toLowerCase().contains('clear') &&
            !oldCond.toLowerCase().contains('clear')) {
          NotificationService().showNotification(
            '☀️ Forecast Update for ${_dayName(day.date)}',
            'Skies are now expected to clear up.',
            id: 20 + i,
          );
        }
      }

      if ((newTemp - oldTemp).abs() >= 5) {
        NotificationService().showNotification(
          '🌡️ Temperature Change for ${_dayName(day.date)}',
          'High of ${newTemp.toStringAsFixed(0)}° (was ${oldTemp.toStringAsFixed(0)}°). Plan accordingly.',
          id: 30 + i,
        );
      }
    }
  }

  // ================= WMO CODE MAPPING =================
  String _wmoCodeToCondition(int code) {
    if (code == 0) return 'Clear';
    if (code >= 1 && code <= 3) return 'Clouds';
    if (code == 45 || code == 48) return 'Fog';
    if (code >= 51 && code <= 57) return 'Drizzle';
    if (code >= 61 && code <= 67) return 'Rain';
    if (code >= 71 && code <= 77) return 'Snow';
    if (code >= 80 && code <= 82) return 'Rain';
    if (code >= 85 && code <= 86) return 'Snow';
    if (code >= 95 && code <= 99) return 'Thunderstorm';
    return 'Clouds';
  }

  String _wmoCodeToDescription(int code) {
    const map = {
      0: 'Clear sky',
      1: 'Mainly clear',
      2: 'Partly cloudy',
      3: 'Overcast',
      45: 'Fog',
      48: 'Depositing rime fog',
      51: 'Light drizzle',
      53: 'Moderate drizzle',
      55: 'Dense drizzle',
      56: 'Light freezing drizzle',
      57: 'Dense freezing drizzle',
      61: 'Slight rain',
      63: 'Moderate rain',
      65: 'Heavy rain',
      66: 'Light freezing rain',
      67: 'Heavy freezing rain',
      71: 'Slight snow fall',
      73: 'Moderate snow fall',
      75: 'Heavy snow fall',
      77: 'Snow grains',
      80: 'Slight rain showers',
      81: 'Moderate rain showers',
      82: 'Violent rain showers',
      85: 'Slight snow showers',
      86: 'Heavy snow showers',
      95: 'Thunderstorm',
      96: 'Thunderstorm with slight hail',
      99: 'Thunderstorm with heavy hail',
    };
    return map[code] ?? 'Unknown';
  }

  // ================= NOTIFICATIONS =================
  void _scheduleNotifications() {
    final rainSoon = _hourly.take(3).where((h) {
      final c = h.condition.toLowerCase();
      return c.contains('rain') ||
          c.contains('drizzle') ||
          c.contains('thunder');
    }).toList();

    if (rainSoon.isNotEmpty) {
      NotificationService().showNotification(
        '🌧️ Rain incoming in $_cityName',
        "Rain expected around ${_formatTime(rainSoon.first.time)}. Carry an umbrella!",
        id: 10,
      );
    }

    NotificationService().scheduleMorningBriefing(
      city: _cityName,
      temp: _temperature,
      condition: _condition,
      tip: _getHealthTip(_condition, _temperature),
    );

    NotificationService().scheduleAfternoonCheck(
      city: _cityName,
      temp: _temperature,
      condition: _condition,
    );

    if (_forecast.isNotEmpty) {
      final tomorrow = _forecast.first;
      NotificationService().scheduleTomorrowPreview(
        city: _cityName,
        condition: tomorrow.condition,
        temp: tomorrow.temp,
      );
    }

    if (_sunrise != null && _sunset != null) {
      NotificationService().scheduleSunriseReminder(
        city: _cityName,
        sunriseTime: _sunrise!,
      );
      NotificationService().scheduleSunsetReminder(
        city: _cityName,
        sunsetTime: _sunset!,
      );
    }

    NotificationService().scheduleHealthTip(
      city: _cityName,
      condition: _condition,
      temp: _temperature,
      tip: _getHealthTip(_condition, _temperature),
    );

    if (_delights != null &&
        _delights!['quote'] != null &&
        _delights!['fact'] != null) {
      NotificationService().scheduleDailyDelight(
        quote: _delights!['quote']!,
        fact: _delights!['fact']!,
      );
    }
  }

  String _formatTime(DateTime t) {
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$h12 $ampm';
  }

  // ================= HEALTH TIPS =================
  String _getHealthTip(String condition, double temp) {
    final c = condition.toLowerCase();
    if (c.contains('thunder')) {
      return 'Thunderstorm alert! Stay indoors, avoid open fields and unplug sensitive electronics.';
    }
    if (c.contains('rain') || c.contains('drizzle')) {
      return 'Rainy day — carry an umbrella, wear non-slip shoes, and drink warm fluids to stay cozy.';
    }
    if (c.contains('snow')) {
      return 'Snowy conditions — dress in warm layers and watch out for slippery paths.';
    }
    if (c.contains('clear') && temp >= 30) {
      return 'Hot and sunny — drink at least 8 glasses of water and apply SPF 30+ sunscreen.';
    }
    if (c.contains('clear') && temp <= 15) {
      return 'Clear but cool — a light jacket and warm tea will keep you comfortable.';
    }
    if (c.contains('clear')) {
      return "Beautiful clear skies — perfect for a walk, but don't forget your sunglasses!";
    }
    if (c.contains('cloud') || c.contains('mist') || c.contains('fog')) {
      return 'Overcast skies — great for outdoor activity without harsh sun. Stay hydrated!';
    }
    return 'Have a wonderful day! Stay hydrated and take care of yourself.';
  }

  IconData _getTipIcon(String condition) {
    final c = condition.toLowerCase();
    if (c.contains('thunder')) return Icons.warning_amber_rounded;
    if (c.contains('rain') || c.contains('drizzle')) return Icons.umbrella;
    if (c.contains('snow')) return Icons.ac_unit;
    if (c.contains('clear')) return Icons.wb_sunny;
    return Icons.favorite;
  }

  // ================= LOTTIE MAPPING =================
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

  IconData _forecastIcon(String condition) {
    final c = condition.toLowerCase();
    if (c.contains('clear')) return Icons.wb_sunny;
    if (c.contains('cloud')) return Icons.cloud;
    if (c.contains('rain') || c.contains('drizzle')) return Icons.grain;
    if (c.contains('thunder')) return Icons.flash_on;
    if (c.contains('snow')) return Icons.ac_unit;
    return Icons.cloud;
  }

  Color _forecastColor(String condition) {
    final c = condition.toLowerCase();
    if (c.contains('clear')) return const Color(0xFFFFB300);
    if (c.contains('cloud')) return const Color(0xFF90A4AE);
    if (c.contains('rain') || c.contains('drizzle')) {
      return const Color(0xFF4FC3F7);
    }
    if (c.contains('thunder')) return const Color(0xFF9575CD);
    if (c.contains('snow')) return const Color(0xFF81D4FA);
    return const Color(0xFF90A4AE);
  }

  String _dayName(DateTime d) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[d.weekday - 1];
  }

  // ================= BACKGROUND GRADIENT =================
  LinearGradient _getBackgroundGradient(String condition, bool isDark) {
    final c = condition.toLowerCase();
    if (isDark) {
      if (c.contains('clear')) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A2E), Color(0xFF121212)],
        );
      }
      if (c.contains('rain') || c.contains('drizzle')) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F2027), Color(0xFF121212)],
        );
      }
      if (c.contains('thunder')) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B1B2F), Color(0xFF121212)],
        );
      }
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1F1F1F), Color(0xFF121212)],
      );
    } else {
      if (c.contains('clear')) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF3E0), Color(0xFFF5F5F5)],
        );
      }
      if (c.contains('rain') || c.contains('drizzle')) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE3F2FD), Color(0xFFF5F5F5)],
        );
      }
      if (c.contains('thunder')) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEDE7F6), Color(0xFFF5F5F5)],
        );
      }
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFECEFF1), Color(0xFFF5F5F5)],
      );
    }
  }

  // ================= SEARCH DIALOG =================
  void _showSearchDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Search City'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g., Kumasi, London, Tokyo',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              Navigator.pop(context);
              if (value.trim().isNotEmpty) _loadWeather(cityQuery: value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                if (controller.text.trim().isNotEmpty) {
                  _loadWeather(cityQuery: controller.text);
                }
              },
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
  }

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() => _isCelsius = !_isCelsius);
              _loadWeather(cityQuery: _lastCity);
            },
            child: Text(
              _isCelsius ? '°C' : '°F',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            color: colorScheme.onSurfaceVariant,
            onPressed: () {
              HapticFeedback.lightImpact();
              _showSearchDialog();
            },
          ),
          IconButton(
            icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
            color: colorScheme.onSurfaceVariant,
            onPressed: () {
              HapticFeedback.lightImpact();
              themeNotifier.value =
                  isDarkMode ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            color: colorScheme.onSurfaceVariant,
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => InfoPage(
                    onCheckForUpdates: _checkForUpdates,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: _getBackgroundGradient(_condition, isDarkMode),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => _loadWeather(cityQuery: _lastCity),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_errorMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isDarkMode
                                        ? Colors.orangeAccent
                                        : Colors.orange[800],
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),

                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _getGreeting(),
                                style: TextStyle(
                                  fontSize: 14,
                                  letterSpacing: 0.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.location_on,
                                    color: colorScheme.onSurfaceVariant,
                                    size: 18),
                                const SizedBox(width: 4),
                                Text(
                                  _cityName.toUpperCase(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    letterSpacing: 2.5,
                                    fontWeight: FontWeight.w400,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            LayoutBuilder(
                              builder: (context, constraints) {
                                double size = constraints.maxWidth * 0.5;
                                if (size > 200) size = 200;
                                return Center(
                                  child: SizedBox(
                                    width: size,
                                    height: size,
                                    child: Lottie.asset(
                                      _getLottieAnimation(
                                          _condition, _temperature),
                                      fit: BoxFit.contain,
                                      repeat: true,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.cloud,
                                        size: size * 0.5,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 6),

                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: _temperature),
                              duration: const Duration(milliseconds: 900),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) {
                                return Center(
                                  child: Text(
                                    '${value.toStringAsFixed(0)}°',
                                    style: TextStyle(
                                      fontSize: 84,
                                      fontWeight: FontWeight.w200,
                                      color: colorScheme.onSurface,
                                      height: 1.0,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 4),
                            Center(
                              child: Text(
                                _condition.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 14,
                                  letterSpacing: 2.0,
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? const Color(0xFF1E1E1E)
                                    : Colors.white.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.auto_awesome,
                                    size: 18,
                                    color: _forecastColor(_condition),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _getSmartSummary(),
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.4,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildDetailItem(
                                  Icons.thermostat,
                                  'Feels Like',
                                  '${_feelsLike.toStringAsFixed(0)}°',
                                  colorScheme,
                                ),
                                _buildDetailItem(
                                  Icons.water_drop_outlined,
                                  'Humidity',
                                  '${_humidity.toStringAsFixed(0)}%',
                                  colorScheme,
                                ),
                                _buildDetailItem(
                                  Icons.air,
                                  'Wind',
                                  '${_windSpeed.toStringAsFixed(1)}',
                                  colorScheme,
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            if (_sunrise != null && _sunset != null) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildSunCard(
                                      'Sunrise',
                                      _formatTime(_sunrise!),
                                      Icons.wb_twilight,
                                      const Color(0xFFFFB300),
                                      colorScheme,
                                      isDarkMode,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildSunCard(
                                      'Sunset',
                                      _formatTime(_sunset!),
                                      Icons.nights_stay_outlined,
                                      const Color(0xFF5C6BC0),
                                      colorScheme,
                                      isDarkMode,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                            ],

                            if (_hourly.isNotEmpty) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'NEXT 24 HOURS',
                                  style: TextStyle(
                                    fontSize: 12,
                                    letterSpacing: 2.0,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 110,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _hourly.length,
                                  itemBuilder: (context, index) {
                                    return _buildHourlyCard(
                                        _hourly[index],
                                        colorScheme,
                                        isDarkMode);
                                  },
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

                            if (_forecast.isNotEmpty) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '5-DAY FORECAST  •  TAP FOR DETAILS',
                                  style: TextStyle(
                                    fontSize: 12,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 130,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _forecast.length,
                                  itemBuilder: (context, index) {
                                    return _buildForecastCard(
                                        _forecast[index],
                                        colorScheme,
                                        isDarkMode);
                                  },
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? const Color(0xFF1E1E1E)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: isDarkMode
                                        ? Colors.black26
                                        : Colors.black.withOpacity(0.05),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: _forecastColor(_condition)
                                          .withOpacity(0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _getTipIcon(_condition),
                                      color: _forecastColor(_condition),
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Health Tip',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _getHealthTip(
                                              _condition, _temperature),
                                          style: TextStyle(
                                            fontSize: 13,
                                            height: 1.5,
                                            color:
                                                colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),

                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? const Color(0xFF1E1E1E)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: isDarkMode
                                        ? Colors.black26
                                        : Colors.black.withOpacity(0.05),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.auto_stories,
                                          size: 18,
                                          color: _forecastColor(_condition)),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Daily Delight',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(Icons.refresh,
                                            size: 18),
                                        color: colorScheme.onSurfaceVariant,
                                        onPressed: () {
                                          HapticFeedback.lightImpact();
                                          _loadDelights(forceRefresh: true);
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  if (_delights == null)
                                    Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 20),
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color:
                                                colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    )
                                  else ...[
                                    Text(
                                      _delights!['quote'] ?? '',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic,
                                        height: 1.5,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Divider(
                                        color: colorScheme.onSurfaceVariant
                                            .withOpacity(0.2)),
                                    const SizedBox(height: 14),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.lightbulb_outline,
                                            size: 16,
                                            color: Color(0xFFFFB300)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _delights!['fact'] ?? '',
                                            style: TextStyle(
                                              fontSize: 12,
                                              height: 1.5,
                                              color: colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 30),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(
      IconData icon, String label, String value, ColorScheme colorScheme) {
    return Column(
      children: [
        Icon(icon, color: colorScheme.onSurfaceVariant, size: 24),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildSunCard(String label, String time, IconData icon, Color accent,
      ColorScheme colorScheme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                time,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyCard(
      HourlyForecast h, ColorScheme colorScheme, bool isDark) {
    return Container(
      width: 72,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _formatTime(h.time),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Icon(_forecastIcon(h.condition),
              color: _forecastColor(h.condition), size: 22),
          Text(
            '${h.temp.toStringAsFixed(0)}°',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          Text(
            '${h.precipitationProbability.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 10,
              color: const Color(0xFF4FC3F7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastCard(
      ForecastDay day, ColorScheme colorScheme, bool isDark) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ForecastDetailPage(
              day: day,
              colorScheme: colorScheme,
              isDark: isDark,
              isCelsius: _isCelsius,
              accentColor: _forecastColor(day.condition),
            ),
          ),
        );
      },
      child: Container(
        width: 88,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _dayName(day.date).toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Icon(_forecastIcon(day.condition),
                color: _forecastColor(day.condition), size: 26),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.maxTemp.toStringAsFixed(0)}°',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${day.minTemp.toStringAsFixed(0)}°',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                  ),
                ),
              ],
            ),
            if (day.precipitationProbability > 20)
              Text(
                '${day.precipitationProbability.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF4FC3F7),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ================= IN-APP UPDATE DIALOG (SAFE VERSION) =================
class _UpdateDialog extends StatefulWidget {
  final GithubAPKRelease release;
  final ApkDownloaderService downloaderService;
  final GithubReleaseApkUpdater updaterPlugin;

  const _UpdateDialog({
    required this.release,
    required this.downloaderService,
    required this.updaterPlugin,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;

  Future<void> _startDownloadAndInstall() async {
    setState(() => _isDownloading = true);
    final filePath = await widget.downloaderService.downloadAPK(
      widget.release.apkUrl,
      null,
      (received, total) {
        if (total != -1) {
          setState(() => _progress = received / total);
        }
      },
    );
    setState(() => _isDownloading = false);
    if (filePath != null) {
      await widget.updaterPlugin.installApk(filePath);
      if (mounted) Navigator.of(context).pop();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to download update.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: const [
          Icon(Icons.system_update, color: Color(0xFF4FC3F7)),
          SizedBox(width: 10),
          Text('Update Available'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Version ${widget.release.version}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'A new version of Weather Hub is available with improvements and bug fixes. Tap "Update Now" to install it.',
            style: TextStyle(fontSize: 13),
          ),
          if (_isDownloading) ...[
            const SizedBox(height: 20),
            const Text('Downloading...'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress),
          ],
        ],
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
        if (!_isDownloading)
          FilledButton(
            onPressed: _startDownloadAndInstall,
            child: const Text('Update Now'),
          ),
      ],
    );
  }
}

// ================= FORECAST DETAIL PAGE =================
class ForecastDetailPage extends StatelessWidget {
  final ForecastDay day;
  final ColorScheme colorScheme;
  final bool isDark;
  final bool isCelsius;
  final Color accentColor;

  const ForecastDetailPage({
    super.key,
    required this.day,
    required this.colorScheme,
    required this.isDark,
    required this.isCelsius,
    required this.accentColor,
  });

  String _formatDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _formatTime(DateTime t) {
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$h12 $ampm';
  }

  String _lottieFor(String condition, double temp) {
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

  String _getDayTip(String condition, double temp, double uv, double precip) {
    final c = condition.toLowerCase();
    if (c.contains('thunder')) {
      return 'Thunderstorms expected. Avoid outdoor activities and keep electronics unplugged.';
    }
    if (c.contains('rain') || c.contains('drizzle')) {
      return 'Rain likely. Carry an umbrella and wear waterproof footwear.';
    }
    if (uv >= 8) {
      return 'Very high UV index. Apply SPF 50+ and limit sun exposure between 10am–4pm.';
    }
    if (c.contains('clear') && temp >= 30) {
      return 'Very hot day. Drink plenty of water and apply sunscreen.';
    }
    if (c.contains('clear')) {
      return 'Clear skies expected. Great day for outdoor activities!';
    }
    if (c.contains('cloud')) {
      return 'Cloudy conditions. Comfortable for most outdoor plans.';
    }
    return 'Plan your day accordingly. Stay safe and hydrated.';
  }

  Color _uvColor(double uv) {
    if (uv <= 2) return const Color(0xFF4CAF50);
    if (uv <= 5) return const Color(0xFFFFEB3B);
    if (uv <= 7) return const Color(0xFFFF9800);
    if (uv <= 10) return const Color(0xFFF44336);
    return const Color(0xFF9C27B0);
  }

  String _uvLabel(double uv) {
    if (uv <= 2) return 'Low';
    if (uv <= 5) return 'Moderate';
    if (uv <= 7) return 'High';
    if (uv <= 10) return 'Very High';
    return 'Extreme';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF1A1A2E), const Color(0xFF121212)]
                : [const Color(0xFFFFF3E0), const Color(0xFFF5F5F5)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  _formatDate(day.date),
                  style: TextStyle(
                    fontSize: 16,
                    letterSpacing: 1.0,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: 160,
                  height: 160,
                  child: Lottie.asset(
                    _lottieFor(day.condition, day.temp),
                    fit: BoxFit.contain,
                    repeat: true,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.cloud,
                      size: 80,
                      color: accentColor,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  day.detailedCondition.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w500,
                    color: accentColor,
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  '${day.temp.toStringAsFixed(0)}°${isCelsius ? 'C' : 'F'}',
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w200,
                    color: colorScheme.onSurface,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 30),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatCard(
                      'High',
                      '${day.maxTemp.toStringAsFixed(0)}°',
                      Icons.arrow_upward,
                      const Color(0xFFFF7043),
                      colorScheme,
                      isDark,
                    ),
                    _buildStatCard(
                      'Low',
                      '${day.minTemp.toStringAsFixed(0)}°',
                      Icons.arrow_downward,
                      const Color(0xFF42A5F5),
                      colorScheme,
                      isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatCard(
                      'Feels Max',
                      '${day.feelsLikeMax.toStringAsFixed(0)}°',
                      Icons.thermostat,
                      const Color(0xFFFFA726),
                      colorScheme,
                      isDark,
                    ),
                    _buildStatCard(
                      'Feels Min',
                      '${day.feelsLikeMin.toStringAsFixed(0)}°',
                      Icons.thermostat,
                      const Color(0xFF29B6F6),
                      colorScheme,
                      isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black26
                            : Colors.black.withOpacity(0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Detailed Forecast',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        Icons.water_drop,
                        'Precipitation',
                        '${day.precipitationProbability.toStringAsFixed(0)}%',
                        colorScheme,
                      ),
                      _buildInfoRow(
                        Icons.wb_sunny,
                        'UV Index',
                        '${day.uvIndex.toStringAsFixed(1)} (${_uvLabel(day.uvIndex)})',
                        colorScheme,
                        valueColor: _uvColor(day.uvIndex),
                      ),
                      _buildInfoRow(
                        Icons.air,
                        'Wind Speed',
                        '${day.windSpeedMax.toStringAsFixed(1)} km/h',
                        colorScheme,
                      ),
                      _buildInfoRow(
                        Icons.opacity,
                        'Avg Humidity',
                        '${day.humidityAvg.toStringAsFixed(0)}%',
                        colorScheme,
                      ),
                      if (day.sunrise != null)
                        _buildInfoRow(
                          Icons.wb_twilight,
                          'Sunrise',
                          _formatTime(day.sunrise!),
                          colorScheme,
                        ),
                      if (day.sunset != null)
                        _buildInfoRow(
                          Icons.nights_stay_outlined,
                          'Sunset',
                          _formatTime(day.sunset!),
                          colorScheme,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black26
                            : Colors.black.withOpacity(0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.tips_and_updates,
                              size: 18, color: accentColor),
                          const SizedBox(width: 8),
                          Text(
                            'Preparation Tip',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _getDayTip(
                          day.condition,
                          day.temp,
                          day.uvIndex,
                          day.precipitationProbability,
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value,
    ColorScheme colorScheme, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color accent,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ================= SMALL DELIGHTS SERVICE (FIXED) =================
class SmallDelightsService {
  static final SmallDelightsService _instance =
      SmallDelightsService._internal();
  factory SmallDelightsService() => _instance;
  SmallDelightsService._internal();

  final List<String> _quoteApis = [
    'https://zenquotes.io/api/random',
    'https://api.quotable.io/random',
  ];

  final List<String> _factApis = [
    'https://uselessfacts.jsph.pl/api/v2/facts/random',
    'https://catfact.ninja/fact',
  ];

  Future<Map<String, String>> fetchDailyDelight(
      {bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final cacheKey = 'daily_delight_$today';

    if (!forceRefresh) {
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        final parts = cached.split('|||');
        if (parts.length == 2) {
          return {'quote': parts[0], 'fact': parts[1]};
        }
      }
    }

    final quote = await _fetchQuote() ??
        _fallbackQuotes[DateTime.now().millisecond % _fallbackQuotes.length];
    final fact = await _fetchFact() ??
        _fallbackFacts[DateTime.now().millisecond % _fallbackFacts.length];

    await prefs.setString(cacheKey, '$quote|||$fact');

    return {'quote': quote, 'fact': fact};
  }

  Future<String?> _fetchQuote() async {
    for (final api in _quoteApis) {
      try {
        final res =
            await http.get(Uri.parse(api)).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          if (data is List && data.isNotEmpty) {
            final q = data[0];
            if (q['q'] != null && q['a'] != null) {
              return '"${q['q']}" — ${q['a']}';
            }
          }
          if (data is Map && data['content'] != null) {
            return '"${data['content']}" — ${data['author']}';
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _fetchFact() async {
    for (final api in _factApis) {
      try {
        final res =
            await http.get(Uri.parse(api)).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          if (data is Map && data['text'] != null) return data['text'];
          if (data is Map && data['fact'] != null) return data['fact'];
        }
      } catch (_) {}
    }
    return null;
  }

  final List<String> _fallbackQuotes = [
    '"Every storm runs out of rain." — Maya Angelou',
    '"Wherever you go, no matter what the weather, always bring your own sunshine." — Anthony J. D\'Angelo',
    '"The sun is a daily reminder that we too can rise again from the darkness." — Unknown',
    '"Life isn\'t about waiting for the storm to pass, it\'s about learning to dance in the rain." — Vivian Greene',
    '"There is no such thing as bad weather, only different kinds of good weather." — John Ruskin',
    '"The best way to predict the future is to create it." — Peter Drucker',
    '"The only way to do great work is to love what you do." — Steve Jobs',
  ];

  final List<String> _fallbackFacts = [
    'Lightning strikes the Earth about 100 times every second.',
    'A single thunderstorm can contain the energy of a nuclear bomb.',
    'The coldest temperature ever recorded on Earth was -128.6°F (-89.2°C) in Antarctica.',
    'Raindrops are not tear-shaped — they look like small hamburgers.',
    'Snowflakes can fall as fast as 9 mph (14 km/h).',
    'The highest temperature ever recorded in Ghana was 43.1°C in Navrongo.',
    'A cumulonimbus cloud can hold over 1 million tons of water.',
    'The fastest wind speed ever recorded was 253 mph (407 km/h) in Australia.',
  ];
}

// ================= INFO PAGE =================
class InfoPage extends StatelessWidget {
  final VoidCallback? onCheckForUpdates;

  const InfoPage({super.key, this.onCheckForUpdates});

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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud, size: 90, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 24),
              Text(
                'Weather Hub',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Version 1.1.0',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 20),
              Text(
                'Developed by',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bismark NK',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'at Sonnami Develops Ghana',
                style: TextStyle(
                  fontSize: 15,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 30),
              if (onCheckForUpdates != null)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onCheckForUpdates!();
                  },
                  icon: const Icon(Icons.system_update, size: 18),
                  label: const Text('Check for Updates'),
                ),
              const SizedBox(height: 40),
              Text(
                '© 2026 Sonnami Develops',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= NOTIFICATION SERVICE =================
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

  Future<void> showNotification(String title, String body,
      {int id = 0}) async {
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
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('Notification show failed: $e');
    }
  }

  Future<void> _scheduleAt(
      int id, String title, String body, int hour, int minute) async {
    try {
      final now = tz.TZDateTime.now(tz.local);
      var scheduled =
          tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'weather_scheduled',
        'Scheduled Weather Updates',
        channelDescription: 'Daily weather briefings and reminders',
        importance: Importance.high,
        priority: Priority.high,
      );
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();
      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduled,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Scheduled notification failed: $e');
    }
  }

  Future<void> scheduleMorningBriefing({
    required String city,
    required double temp,
    required String condition,
    required String tip,
  }) async {
    final greeting =
        'Good morning! $city is ${temp.toStringAsFixed(0)}° with $condition.';
    await _scheduleAt(101, '🌅 Morning Briefing', '$greeting\n\n💡 $tip', 7, 0);
  }

  Future<void> scheduleAfternoonCheck({
    required String city,
    required double temp,
    required String condition,
  }) async {
    final body =
        '$city is ${temp.toStringAsFixed(0)}° with $condition. Stay safe and hydrated!';
    await _scheduleAt(102, '☀️ Afternoon Weather Update', body, 15, 0);
  }

  Future<void> scheduleTomorrowPreview({
    required String city,
    required String condition,
    required double temp,
  }) async {
    final body =
        'Tomorrow in $city: $condition, around ${temp.toStringAsFixed(0)}°. Plan ahead!';
    await _scheduleAt(103, '🌙 Tomorrow\'s Weather', body, 20, 0);
  }

  Future<void> scheduleSunriseReminder({
    required String city,
    required DateTime sunriseTime,
  }) async {
    final remindAt = sunriseTime.subtract(const Duration(minutes: 15));
    await _scheduleAt(
      104,
      '🌅 Golden Hour in $city',
      'Sunrise is in 15 minutes. Perfect time for photos or a morning walk!',
      remindAt.hour,
      remindAt.minute,
    );
  }

  Future<void> scheduleSunsetReminder({
    required String city,
    required DateTime sunsetTime,
  }) async {
    final remindAt = sunsetTime.subtract(const Duration(minutes: 15));
    await _scheduleAt(
      105,
      '🌇 Sunset Soon in $city',
      'Sunset in 15 minutes. Step outside and enjoy the view!',
      remindAt.hour,
      remindAt.minute,
    );
  }

  Future<void> scheduleHealthTip({
    required String city,
    required String condition,
    required double temp,
    required String tip,
  }) async {
    await _scheduleAt(106, '💡 Health Tip for $city', tip, 9, 0);
  }

  Future<void> scheduleDailyDelight({
    required String quote,
    required String fact,
  }) async {
    await _scheduleAt(107, '📖 Daily Delight', '$quote\n\n💡 $fact', 13, 0);
  }
}
