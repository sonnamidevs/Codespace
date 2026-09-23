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

// ================= DEBUG METRICS SERVICE =================
class DebugMetrics {
  static final DebugMetrics _i = DebugMetrics._internal();
  factory DebugMetrics() => _i;
  DebugMetrics._internal();

  DateTime? lastUpdateCheck;
  DateTime? lastWeatherFetch;
  DateTime? lastForecastFetch;
  DateTime? lastConfidenceFetch;
  int? lastWeatherFetchMs;
  int? lastForecastFetchMs;
  int? lastUpdateCheckMs;
  int? lastConfidenceFetchMs;
  String? lastWeatherStatus;
  String? lastForecastStatus;
  String? latestAvailableVersion;
  int delightCacheHits = 0;
  int delightCacheMisses = 0;
  int notificationCount = 0;
  int cacheRestores = 0;

  void reset() {
    lastUpdateCheck = null;
    lastWeatherFetch = null;
    lastForecastFetch = null;
    lastConfidenceFetch = null;
    lastWeatherFetchMs = null;
    lastForecastFetchMs = null;
    lastUpdateCheckMs = null;
    lastConfidenceFetchMs = null;
    lastWeatherStatus = null;
    lastForecastStatus = null;
    latestAvailableVersion = null;
    delightCacheHits = 0;
    delightCacheMisses = 0;
    notificationCount = 0;
    cacheRestores = 0;
  }
}

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

// ================= FORECAST MODELS =================
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

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'temp': temp,
        'maxTemp': maxTemp,
        'minTemp': minTemp,
        'feelsLikeMax': feelsLikeMax,
        'feelsLikeMin': feelsLikeMin,
        'condition': condition,
        'detailedCondition': detailedCondition,
        'weatherCode': weatherCode,
        'precipitationProbability': precipitationProbability,
        'uvIndex': uvIndex,
        'windSpeedMax': windSpeedMax,
        'humidityAvg': humidityAvg,
        'sunrise': sunrise?.toIso8601String(),
        'sunset': sunset?.toIso8601String(),
      };

  factory ForecastDay.fromJson(Map<String, dynamic> j) => ForecastDay(
        date: DateTime.parse(j['date'] as String),
        temp: (j['temp'] as num).toDouble(),
        maxTemp: (j['maxTemp'] as num).toDouble(),
        minTemp: (j['minTemp'] as num).toDouble(),
        feelsLikeMax: (j['feelsLikeMax'] as num).toDouble(),
        feelsLikeMin: (j['feelsLikeMin'] as num).toDouble(),
        condition: j['condition'] as String,
        detailedCondition: j['detailedCondition'] as String,
        weatherCode: j['weatherCode'] as int,
        precipitationProbability:
            (j['precipitationProbability'] as num).toDouble(),
        uvIndex: (j['uvIndex'] as num).toDouble(),
        windSpeedMax: (j['windSpeedMax'] as num).toDouble(),
        humidityAvg: (j['humidityAvg'] as num).toDouble(),
        sunrise: j['sunrise'] != null
            ? DateTime.parse(j['sunrise'] as String)
            : null,
        sunset:
            j['sunset'] != null ? DateTime.parse(j['sunset'] as String) : null,
      );
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

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'temp': temp,
        'condition': condition,
        'precipitationProbability': precipitationProbability,
        'humidity': humidity,
      };

  factory HourlyForecast.fromJson(Map<String, dynamic> j) => HourlyForecast(
        time: DateTime.parse(j['time'] as String),
        temp: (j['temp'] as num).toDouble(),
        condition: j['condition'] as String,
        precipitationProbability:
            (j['precipitationProbability'] as num).toDouble(),
        humidity: (j['humidity'] as num).toDouble(),
      );
}

// ================= CONFIDENCE MODELS =================
enum ForecastConfidence { high, medium, low, unknown }

extension ForecastConfidenceLabel on ForecastConfidence {
  String get label {
    switch (this) {
      case ForecastConfidence.high:
        return 'HIGH';
      case ForecastConfidence.medium:
        return 'MEDIUM';
      case ForecastConfidence.low:
        return 'LOW';
      case ForecastConfidence.unknown:
        return '—';
    }
  }

  Color get color {
    switch (this) {
      case ForecastConfidence.high:
        return const Color(0xFF4CAF50);
      case ForecastConfidence.medium:
        return const Color(0xFFFFC107);
      case ForecastConfidence.low:
        return const Color(0xFFFF5252);
      case ForecastConfidence.unknown:
        return const Color(0xFF9E9E9E);
    }
  }
}

class ForecastConfidenceData {
  final ForecastConfidence level;
  final int agreementPercent;
  final String detail;

  ForecastConfidenceData({
    required this.level,
    required this.agreementPercent,
    required this.detail,
  });

  static ForecastConfidenceData unknown() => ForecastConfidenceData(
        level: ForecastConfidence.unknown,
        agreementPercent: 0,
        detail: 'Confidence data unavailable',
      );
}

// ================= OFFLINE CACHE SERVICE =================
class WeatherCache {
  static const String _keyWeather = 'cache_weather';
  static const String _keyForecast = 'cache_forecast';
  static const String _keyTimestamp = 'cache_timestamp';
  static const String _keyConfidence = 'cache_confidence';

  static Future<void> saveWeather(dynamic weatherData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWeather, json.encode(weatherData));
  }

  static Future<void> saveForecast({
    required List<ForecastDay> daily,
    required List<HourlyForecast> hourly,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyForecast,
      json.encode({
        'daily': daily.map((d) => d.toJson()).toList(),
        'hourly': hourly.map((h) => h.toJson()).toList(),
      }),
    );
    await prefs.setInt(_keyTimestamp, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> saveConfidence(ForecastConfidenceData c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyConfidence,
      '${c.agreementPercent}|${c.level.name}|${c.detail}',
    );
  }

  static Future<Map<String, dynamic>?> loadWeather() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyWeather);
    if (raw == null) return null;
    try {
      return json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> loadForecast() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyForecast);
    if (raw == null) return null;
    try {
      return json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<ForecastConfidenceData?> loadConfidence() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyConfidence);
    if (raw == null) return null;
    final parts = raw.split('|');
    if (parts.length < 3) return null;
    final pct = int.tryParse(parts[0]) ?? 0;
    ForecastConfidence level;
    switch (parts[1]) {
      case 'high':
        level = ForecastConfidence.high;
        break;
      case 'medium':
        level = ForecastConfidence.medium;
        break;
      case 'low':
        level = ForecastConfidence.low;
        break;
      default:
        level = ForecastConfidence.unknown;
    }
    return ForecastConfidenceData(
      level: level,
      agreementPercent: pct,
      detail: parts.sublist(2).join('|'),
    );
  }

  static Future<DateTime?> lastUpdated() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_keyTimestamp);
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts);
  }

  static String relativeTime(DateTime? t) {
    if (t == null) return 'just now';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
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
  DateTime? _cacheTimestamp;

  DateTime? _sunrise;
  DateTime? _sunset;

  List<ForecastDay> _forecast = [];
  List<HourlyForecast> _hourly = [];
  ForecastConfidenceData _confidence = ForecastConfidenceData.unknown();

  double _lastLat = 0.0;
  double _lastLon = 0.0;
  String? _lastCity;

  Map<String, String>? _delights;

  final _updater = GithubReleaseApkUpdater();
  final _apiService = GithubApiService();
  final _downloaderService = ApkDownloaderService();
  final _versionComparator = VersionComparator();
  final _metrics = DebugMetrics();

  @override
  void initState() {
    super.initState();
    _loadWeather();
    _loadDelights();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  // ================= IN-APP UPDATE =================
  Future<void> _checkForUpdates({
    bool showNoUpdateMessage = false,
    BuildContext? context,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final supportedAbis = await _updater.getSupportedAbis() ?? <String>[];
      final release = await _apiService.getLatestGithubAPKRelease(
        ownerGithub: kGithubOwner,
        repositoryGithub: kGithubRepo,
        apkKeyName: kApkAssetName,
        supportedAbis: supportedAbis,
      );
      sw.stop();

      _metrics.lastUpdateCheck = DateTime.now();
      _metrics.lastUpdateCheckMs = sw.elapsedMilliseconds;

      if (release == null) {
        if (showNoUpdateMessage && context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not reach GitHub. Check your connection.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      _metrics.latestAvailableVersion = release.version;

      final currentVersion = await _updater.getCurrentAppVersion();
      final isNewer = _versionComparator.isNewerVersion(
        release.version,
        currentVersion,
      );

      if (isNewer && mounted) {
        _showUpdateDialog(release);
      } else if (showNoUpdateMessage && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You are on the latest version (v$currentVersion) ✨'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      sw.stop();
      _metrics.lastUpdateCheck = DateTime.now();
      _metrics.lastUpdateCheckMs = sw.elapsedMilliseconds;
      debugPrint('Update check failed: $e');
      if (showNoUpdateMessage && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Update check failed. Please try again later.'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
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

  // ================= LOAD WEATHER (CACHE-FIRST) =================
  Future<void> _loadWeather({String? cityQuery}) async {
    bool hadCache = false;

    // ⚡ OFFLINE-FIRST: Load cache instantly (only if no specific city requested)
    if (cityQuery == null || cityQuery.trim().isEmpty) {
      final cachedWeather = await WeatherCache.loadWeather();
      final cachedForecast = await WeatherCache.loadForecast();
      final cachedConfidence = await WeatherCache.loadConfidence();
      final ts = await WeatherCache.lastUpdated();

      if (cachedWeather != null) {
        _applyCurrentWeather(cachedWeather, saveToCache: false);
        if (cachedForecast != null) {
          _restoreForecastFromCache(cachedForecast);
        }
        if (cachedConfidence != null) {
          _confidence = cachedConfidence;
        }
        if (mounted) {
          setState(() {
            _isLoading = false;
            _cacheTimestamp = ts;
          });
          hadCache = true;
          _metrics.cacheRestores++;
        }
      }
    }

    if (!hadCache) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

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
      if (mounted && !hadCache) {
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
    final sw = Stopwatch()..start();
    final unit = _isCelsius ? 'metric' : 'imperial';
    final url = Uri.parse(
      'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey&units=$unit',
    );
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      sw.stop();
      _metrics.lastWeatherFetch = DateTime.now();
      _metrics.lastWeatherFetchMs = sw.elapsedMilliseconds;
      _metrics.lastWeatherStatus = 'HTTP ${res.statusCode}';

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
      sw.stop();
      _metrics.lastWeatherFetch = DateTime.now();
      _metrics.lastWeatherFetchMs = sw.elapsedMilliseconds;
      _metrics.lastWeatherStatus = 'ERROR';
      if (mounted) {
        setState(() {
          _errorMessage = 'Network error.';
          _isLoading = false;
        });
      }
    }
  }

  void _applyCurrentWeather(dynamic data, {bool saveToCache = true}) {
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
    if (saveToCache) {
      WeatherCache.saveWeather(data);
    }
  }

  void _restoreForecastFromCache(Map<String, dynamic> cached) {
    try {
      final daily = (cached['daily'] as List)
          .map((e) => ForecastDay.fromJson(e as Map<String, dynamic>))
          .toList();
      final hourly = (cached['hourly'] as List)
          .map((e) => HourlyForecast.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _forecast = daily;
          _hourly = hourly;
        });
      }
    } catch (e) {
      debugPrint('Forecast cache restore failed: $e');
    }
  }

  // ================= ENHANCED FORECAST FETCH =================
  Future<void> _fetchForecast(double lat, double lon) async {
    final sw = Stopwatch()..start();
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
      sw.stop();
      _metrics.lastForecastFetch = DateTime.now();
      _metrics.lastForecastFetchMs = sw.elapsedMilliseconds;
      _metrics.lastForecastStatus = 'HTTP ${res.statusCode}';

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
            _cacheTimestamp = DateTime.now();
          });
        }

        // 💾 Save to cache
        await WeatherCache.saveForecast(
          daily: forecastList,
          hourly: hourlyList,
        );

        await _checkForecastChanges(forecastList);
        _scheduleNotifications();

        // 🎯 Fetch confidence in background (non-blocking)
        _fetchConfidenceInBackground(lat, lon);
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      sw.stop();
      _metrics.lastForecastFetch = DateTime.now();
      _metrics.lastForecastFetchMs = sw.elapsedMilliseconds;
      _metrics.lastForecastStatus = 'ERROR';
      debugPrint('Forecast fetch failed: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ================= CONFIDENCE METER =================
  Future<void> _fetchConfidenceInBackground(double lat, double lon) async {
    final sw = Stopwatch()..start();
    final result = await ForecastConfidenceService().fetchConfidence(
      lat: lat,
      lon: lon,
      isCelsius: _isCelsius,
    );
    sw.stop();
    _metrics.lastConfidenceFetch = DateTime.now();
    _metrics.lastConfidenceFetchMs = sw.elapsedMilliseconds;

    if (mounted) {
      setState(() => _confidence = result);
    }
    await WeatherCache.saveConfidence(result);
  }

  void _showConfidenceDetail() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final colorScheme = Theme.of(context).colorScheme;

        return Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    color: _confidence.level.color,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Forecast Confidence',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: CircularProgressIndicator(
                        value: _confidence.agreementPercent / 100,
                        strokeWidth: 8,
                        backgroundColor:
                            colorScheme.onSurfaceVariant.withOpacity(0.1),
                        valueColor:
                            AlwaysStoppedAnimation(_confidence.level.color),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_confidence.agreementPercent}%',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: _confidence.level.color,
                          ),
                        ),
                        Text(
                          _confidence.level.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _confidence.detail,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              Divider(color: colorScheme.onSurfaceVariant.withOpacity(0.2)),
              const SizedBox(height: 16),
              Text(
                'HOW THIS WORKS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This score compares forecasts from 3 leading weather models. '
                'When they agree, the forecast is highly reliable. When they '
                'disagree, expect changes.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _legendItem('ECMWF', 'European', colorScheme),
                  const SizedBox(width: 8),
                  _legendItem('GFS', 'American', colorScheme),
                  const SizedBox(width: 8),
                  _legendItem('ICON', 'German', colorScheme),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _legendItem(String name, String origin, ColorScheme colorScheme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: colorScheme.onSurfaceVariant.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              origin,
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
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
            isPersistent: true,
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
    int count = 0;

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
        isPersistent: true,
      );
      count++;
    }

    NotificationService().scheduleMorningBriefing(
      city: _cityName,
      temp: _temperature,
      condition: _condition,
      tip: _getHealthTip(_condition, _temperature),
    );
    count++;

    NotificationService().scheduleAfternoonCheck(
      city: _cityName,
      temp: _temperature,
      condition: _condition,
    );
    count++;

    if (_forecast.isNotEmpty) {
      final tomorrow = _forecast.first;
      NotificationService().scheduleTomorrowPreview(
        city: _cityName,
        condition: tomorrow.condition,
        temp: tomorrow.temp,
      );
      count++;
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
      count += 2;
    }

    NotificationService().scheduleHealthTip(
      city: _cityName,
      condition: _condition,
      temp: _temperature,
      tip: _getHealthTip(_condition, _temperature),
    );
    count++;

    if (_delights != null &&
        _delights!['quote'] != null &&
        _delights!['fact'] != null) {
      NotificationService().scheduleDailyDelight(
        quote: _delights!['quote']!,
        fact: _delights!['fact']!,
      );
      count++;
    }

    _metrics.notificationCount = count;
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

  LinearGradient _getForecastCardGradient(String condition, bool isDark) {
    final baseColor = _forecastColor(condition);
    if (isDark) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          baseColor.withOpacity(0.25),
          const Color(0xFF1E1E1E).withOpacity(0.9),
        ],
      );
    } else {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          baseColor.withOpacity(0.15),
          Colors.white.withOpacity(0.95),
        ],
      );
    }
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
                    onCheckForUpdates: (ctx) => _checkForUpdates(
                      showNoUpdateMessage: true,
                      context: ctx,
                    ),
                    currentVersionGetter: () => _updater.getCurrentAppVersion(),
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

                            // Last Updated Badge
                            if (_cacheTimestamp != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Builder(builder: (context) {
                                  final age = DateTime.now()
                                      .difference(_cacheTimestamp!);
                                  final isStale = age.inMinutes > 30;
                                  return Text(
                                    'Updated ${WeatherCache.relativeTime(_cacheTimestamp)}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10,
                                      letterSpacing: 0.5,
                                      color: isStale
                                          ? Colors.orangeAccent
                                          : colorScheme.onSurfaceVariant
                                              .withOpacity(0.6),
                                    ),
                                  );
                                }),
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

                            // 🎯 Forecast Confidence Pill
                            if (_confidence.level != ForecastConfidence.unknown)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: GestureDetector(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      _showConfidenceDetail();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: _confidence.level.color
                                            .withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: _confidence.level.color
                                              .withOpacity(0.35),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: _confidence.level.color,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${_confidence.agreementPercent}% CONFIDENCE',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.2,
                                              color: _confidence.level.color,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.chevron_right,
                                            size: 14,
                                            color: _confidence.level.color
                                                .withOpacity(0.7),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 12),

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
                                height: 140,
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
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF4FC3F7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastCard(
      ForecastDay day, ColorScheme colorScheme, bool isDark) {
    final gradient = _getForecastCardGradient(day.condition, isDark);
    final accentColor = _forecastColor(day.condition);

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
              accentColor: accentColor,
            ),
          ),
        );
      },
      child: Container(
        width: 104,
        margin: const EdgeInsets.only(right: 14),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: accentColor.withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.15),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _dayName(day.date).toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            Icon(
              _forecastIcon(day.condition),
              color: accentColor,
              size: 32,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.maxTemp.toStringAsFixed(0)}°',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${day.minTemp.toStringAsFixed(0)}°',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                  ),
                ),
              ],
            ),
            if (day.precipitationProbability > 20)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF4FC3F7).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${day.precipitationProbability.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF4FC3F7),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}

// ================= UPDATE DIALOG =================
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

  String _getDayTip(String condition, double temp, double uv) {
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

// ================= SMALL DELIGHTS SERVICE =================
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
          DebugMetrics().delightCacheHits++;
          return {'quote': parts[0], 'fact': parts[1]};
        }
      }
    }

    DebugMetrics().delightCacheMisses++;

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

// ================= 🎯 FORECAST CONFIDENCE SERVICE =================
class ForecastConfidenceService {
  static final ForecastConfidenceService _i =
      ForecastConfidenceService._internal();
  factory ForecastConfidenceService() => _i;
  ForecastConfidenceService._internal();

  static const List<String> _models = [
    'ecmwf_ifs04',
    'gfs_seamless',
    'icon_seamless',
  ];

  Future<ForecastConfidenceData> fetchConfidence({
    required double lat,
    required double lon,
    required bool isCelsius,
  }) async {
    try {
      final tempUnit = isCelsius ? 'celsius' : 'fahrenheit';
      final modelsParam = _models.join(',');

      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat'
        '&longitude=$lon'
        '&daily=temperature_2m_max'
        '&models=$modelsParam'
        '&forecast_days=3'
        '&temperature_unit=$tempUnit'
        '&timezone=auto',
      );

      final res = await http.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return ForecastConfidenceData.unknown();

      final data = json.decode(res.body);
      final daily = data['daily'];
      if (daily == null) return ForecastConfidenceData.unknown();

      final Map<String, List<double>> modelTemps = {};
      for (final model in _models) {
        final key = 'temperature_2m_max_$model';
        if (daily[key] != null) {
          final list = (daily[key] as List)
              .where((v) => v != null)
              .map((v) => (v as num).toDouble())
              .toList();
          if (list.isNotEmpty) modelTemps[model] = list;
        }
      }

      if (modelTemps.length < 2) return ForecastConfidenceData.unknown();

      int highDays = 0;
      int mediumDays = 0;
      int lowDays = 0;
      int totalDays = 0;

      for (int dayIdx = 0; dayIdx < 3; dayIdx++) {
        final values = <double>[];
        for (final entry in modelTemps.entries) {
          if (dayIdx < entry.value.length) {
            values.add(entry.value[dayIdx]);
          }
        }
        if (values.length < 2) continue;

        final maxV = values.reduce((a, b) => a > b ? a : b);
        final minV = values.reduce((a, b) => a < b ? a : b);
        final spread = maxV - minV;

        final thresholdHigh = isCelsius ? 2.0 : 3.6;
        final thresholdMedium = isCelsius ? 5.0 : 9.0;

        if (spread <= thresholdHigh) {
          highDays++;
        } else if (spread <= thresholdMedium) {
          mediumDays++;
        } else {
          lowDays++;
        }
        totalDays++;
      }

      if (totalDays == 0) return ForecastConfidenceData.unknown();

      final int agreementPercent =
          ((highDays * 100 + mediumDays * 60 + lowDays * 25) / totalDays)
              .round();

      ForecastConfidence level;
      if (highDays >= totalDays) {
        level = ForecastConfidence.high;
      } else if (lowDays == 0) {
        level = ForecastConfidence.medium;
      } else {
        level = ForecastConfidence.low;
      }

      final modelsUsed = modelTemps.length;
      final String detail;
      if (level == ForecastConfidence.high) {
        detail = '$modelsUsed/$modelsUsed models agree within '
            '${isCelsius ? "2°C" : "3.6°F"}';
      } else if (level == ForecastConfidence.medium) {
        detail = '$highDays of $totalDays days agree — minor disagreement '
            'on the rest';
      } else {
        detail =
            '$lowDays of $totalDays days disagree — forecast is uncertain';
      }

      return ForecastConfidenceData(
        level: level,
        agreementPercent: agreementPercent,
        detail: detail,
      );
    } catch (e) {
      debugPrint('Confidence fetch failed: $e');
      return ForecastConfidenceData.unknown();
    }
  }
}

// ================= INFO PAGE (WITH HIDDEN DEBUG GESTURE) =================
class InfoPage extends StatefulWidget {
  final void Function(BuildContext)? onCheckForUpdates;
  final Future<String> Function()? currentVersionGetter;

  const InfoPage({
    super.key,
    this.onCheckForUpdates,
    this.currentVersionGetter,
  });

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  int _titleTapCount = 0;
  DateTime? _lastTapTime;
  String _currentVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    if (widget.currentVersionGetter != null) {
      try {
        final v = await widget.currentVersionGetter!();
        if (mounted) setState(() => _currentVersion = v);
      } catch (_) {}
    }
  }

  void _handleTitleTap() {
    final now = DateTime.now();
    if (_lastTapTime == null ||
        now.difference(_lastTapTime!) > const Duration(seconds: 2)) {
      _titleTapCount = 0;
    }
    _lastTapTime = now;
    _titleTapCount++;

    HapticFeedback.selectionClick();

    if (_titleTapCount == 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keep tapping... 👀'),
          duration: Duration(seconds: 1),
        ),
      );
    }

    if (_titleTapCount >= 7) {
      _titleTapCount = 0;
      HapticFeedback.heavyImpact();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DebugPanelPage()),
      );
    }
  }

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
              GestureDetector(
                onTap: _handleTitleTap,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  'Weather Hub',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _currentVersion.isEmpty
                    ? 'Version ...'
                    : 'Version $_currentVersion',
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
              if (widget.onCheckForUpdates != null)
                OutlinedButton.icon(
                  onPressed: () => widget.onCheckForUpdates!(context),
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

// ================= DEBUG PANEL =================
class DebugPanelPage extends StatefulWidget {
  const DebugPanelPage({super.key});

  @override
  State<DebugPanelPage> createState() => _DebugPanelPageState();
}

class _DebugPanelPageState extends State<DebugPanelPage> {
  final _api = GithubApiService();
  final _updater = GithubReleaseApkUpdater();
  String _currentVersion = '...';
  List<String> _abis = [];
  String? _latestRemoteVersion;
  String? _latestAssetName;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final v = await _updater.getCurrentAppVersion();
      final abis = await _updater.getSupportedAbis() ?? <String>[];
      String? latest;
      String? asset;
      try {
        final release = await _api.getLatestGithubAPKRelease(
          ownerGithub: kGithubOwner,
          repositoryGithub: kGithubRepo,
          apkKeyName: kApkAssetName,
          supportedAbis: abis,
        );
        latest = release?.version;
        asset = release?.apkUrl.split('/').last;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _currentVersion = v;
          _abis = abis;
          _latestRemoteVersion = latest;
          _latestAssetName = asset;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _currentVersion = 'Unknown');
    }
  }

  String _fmtTime(DateTime? t) {
    if (t == null) return '—';
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final m = DebugMetrics();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bug_report, size: 20),
            SizedBox(width: 8),
            Text('Developer Console'),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildBadge('PRIVATE DIAGNOSTICS · NOT FOR PRODUCTION USE'),
          const SizedBox(height: 20),
          _sectionHeader('BUILD INFO'),
          _row('App Version', _currentVersion),
          _row('Package', '$kGithubOwner/$kGithubRepo'),
          _row('Asset Name', kApkAssetName),
          _row('Supported ABIs', _abis.isEmpty ? '—' : _abis.join(', ')),
          const SizedBox(height: 20),
          _sectionHeader('RUNTIME METRICS'),
          _row(
            'Last Update Check',
            '${_fmtTime(m.lastUpdateCheck)}'
                '${m.lastUpdateCheckMs != null ? '  (${m.lastUpdateCheckMs}ms)' : ''}',
          ),
          _row(
            'Last Weather Fetch',
            '${_fmtTime(m.lastWeatherFetch)}'
                '${m.lastWeatherFetchMs != null ? '  (${m.lastWeatherFetchMs}ms)' : ''}',
          ),
          _row('Weather Status', m.lastWeatherStatus ?? '—'),
          _row(
            'Last Forecast Fetch',
            '${_fmtTime(m.lastForecastFetch)}'
                '${m.lastForecastFetchMs != null ? '  (${m.lastForecastFetchMs}ms)' : ''}',
          ),
          _row('Forecast Status', m.lastForecastStatus ?? '—'),
          _row(
            'Last Confidence Fetch',
            '${_fmtTime(m.lastConfidenceFetch)}'
                '${m.lastConfidenceFetchMs != null ? '  (${m.lastConfidenceFetchMs}ms)' : ''}',
          ),
          _row('Scheduled Notifications', '${m.notificationCount}'),
          _row('Cache Restores', '${m.cacheRestores}'),
          const SizedBox(height: 20),
          _sectionHeader('REMOTE STATE'),
          _row('Latest Remote Version', _latestRemoteVersion ?? 'Fetching...'),
          _row('Latest Asset', _latestAssetName ?? '—'),
          _row('Auto Update Enabled', 'Yes'),
          const SizedBox(height: 20),
          _sectionHeader('CACHE'),
          _row('Daily Delight Hits', '${m.delightCacheHits}'),
          _row('Daily Delight Misses', '${m.delightCacheMisses}'),
          const SizedBox(height: 20),
          _sectionHeader('DATA SOURCES'),
          _row('Current Weather', 'OpenWeatherMap API v2.5'),
          _row('Forecast', 'Open-Meteo API v1 (multi-model)'),
          _row('Confidence', 'ECMWF + GFS + ICON ensemble'),
          _row('Quotes', 'ZenQuotes + Quotable'),
          _row('Facts', 'UselessFacts + CatFact'),
          const SizedBox(height: 20),
          _sectionHeader('ACTIONS'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.clear();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('All cached data cleared.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear Cache'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() => m.reset());
                    _loadInfo();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Metrics reset.')),
                    );
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reset'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Center(
            child: Text(
              'Sonnami Internal Build · v${_currentVersion.isEmpty ? "..." : _currentVersion}',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildBadge(String text) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFF6B6B).withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFF6B6B).withOpacity(0.4)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color: Color(0xFFFF6B6B),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          color: Color(0xFF4FC3F7),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
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
      {int id = 0, bool isPersistent = false}) async {
    try {
      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'weather_channel',
        'Weather Alerts',
        channelDescription: 'Notifications for weather updates',
        importance: Importance.max,
        priority: Priority.max,
        ongoing: isPersistent,
        autoCancel: !isPersistent,
      );
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();
      final NotificationDetails details = NotificationDetails(
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
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
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
