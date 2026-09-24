import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:github_release_apk_updater/github_release_apk_updater.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Silent background updater that:
/// 1. Checks GitHub for a newer release
/// 2. Downloads it in the background
/// 3. Shows a persistent notification with live progress
/// 4. Triggers the system installer when done
/// 5. Enforces update after N refusals
class BackgroundUpdateService {
  static final BackgroundUpdateService _i =
      BackgroundUpdateService._internal();
  factory BackgroundUpdateService() => _i;
  BackgroundUpdateService._internal();

  static const int _notificationId = 9999;
  static const int _maxSkipsBeforeForce = 3;
  static const String _prefsSkipCount = 'update_skip_count';
  static const String _prefsLastCheckedVersion = 'last_checked_version';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final GithubReleaseApkUpdater _updater = GithubReleaseApkUpdater();
  final GithubApiService _api = GithubApiService();
  final ApkDownloaderService _downloader = ApkDownloaderService();
  final VersionComparator _comparator = VersionComparator();

  bool _isChecking = false;
  bool _isDownloading = false;

  // ================= INIT =================
  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _notifications.initialize(settings);
  }

  // ================= CHECK + AUTO DOWNLOAD =================
  Future<void> checkAndUpdateSilently({
    required String ownerGithub,
    required String repositoryGithub,
    required String apkKeyName,
  }) async {
    if (_isChecking || _isDownloading) return;
    _isChecking = true;

    try {
      final abis = await _updater.getSupportedAbis() ?? <String>[];

      final release = await _api.getLatestGithubAPKRelease(
        ownerGithub: ownerGithub,
        repositoryGithub: repositoryGithub,
        apkKeyName: apkKeyName,
        supportedAbis: abis,
      );
      if (release == null) {
        _isChecking = false;
        return;
      }

      final currentVersion = await _updater.getCurrentAppVersion();
      final isNewer = _comparator.isNewerVersion(
        release.version,
        currentVersion,
      );
      if (!isNewer) {
        _isChecking = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefsSkipCount);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final lastChecked = prefs.getString(_prefsLastCheckedVersion);
      if (lastChecked == release.version) {
        final skipCount = prefs.getInt(_prefsSkipCount) ?? 0;
        if (skipCount >= _maxSkipsBeforeForce) {
          await _forcePromptInstall(release);
        }
        _isChecking = false;
        return;
      }

      await _downloadAndInstall(release);
    } catch (e) {
      debugPrint('Background update failed: $e');
    } finally {
      _isChecking = false;
    }
  }

  // ================= DOWNLOAD + INSTALL =================
  Future<void> _downloadAndInstall(GithubAPKRelease release) async {
    _isDownloading = true;
    final prefs = await SharedPreferences.getInstance();

    await _showDownloadNotification(
      title: 'Updating Weather Hub',
      body: 'Downloading version ${release.version}...',
      progress: 0,
    );

    try {
      final filePath = await _downloader.downloadAPK(
        release.apkUrl,
        null,
        (received, total) {
          if (total <= 0) return;
          final progress = received / total;
          final pct = (progress * 100).toStringAsFixed(0);
          final mbReceived = (received / 1024 / 1024).toStringAsFixed(1);
          final mbTotal = (total / 1024 / 1024).toStringAsFixed(1);
          _showDownloadNotification(
            title: 'Updating Weather Hub',
            body: '$mbReceived / $mbTotal MB  •  $pct%',
            progress: progress,
          );
        },
      );

      if (filePath == null) {
        await _showDownloadNotification(
          title: 'Update failed',
          body: 'Could not download the update. Will retry later.',
          progress: 0,
          isError: true,
        );
        _isDownloading = false;
        return;
      }

      await prefs.setString(_prefsLastCheckedVersion, release.version);

      await _showDownloadNotification(
        title: 'Update ready',
        body: 'Tap the system prompt to install version ${release.version}.',
        progress: 1.0,
      );

      await _updater.installApk(filePath);

      final skipCount = (prefs.getInt(_prefsSkipCount) ?? 0) + 1;
      await prefs.setInt(_prefsSkipCount, skipCount);

      await _showDownloadNotification(
        title: 'Weather Hub updated',
        body: 'Version ${release.version} is ready. Restarting...',
        progress: 1.0,
        isComplete: true,
      );

      await Future.delayed(const Duration(seconds: 3));
      await _cancelNotification();
    } catch (e) {
      debugPrint('Download+install failed: $e');
      await _showDownloadNotification(
        title: 'Update failed',
        body: 'Try again later.',
        progress: 0,
        isError: true,
      );
    } finally {
      _isDownloading = false;
    }
  }

  // ================= FORCE PROMPT AFTER N SKIPS =================
  Future<void> _forcePromptInstall(GithubAPKRelease release) async {
    await _showDownloadNotification(
      title: 'Update required',
      body: 'Please install version ${release.version} to continue.',
      progress: 1.0,
    );
  }

  /// Call when user taps "Later" — increments the skip count.
  static Future<void> registerSkip() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_prefsSkipCount) ?? 0) + 1;
    await prefs.setInt(_prefsSkipCount, count);
  }

  /// Reset skip count (call after successful update).
  static Future<void> resetSkip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsSkipCount);
  }

  /// Returns true if the user has skipped too many times.
  static Future<bool> shouldForceUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_prefsSkipCount) ?? 0;
    return count >= _maxSkipsBeforeForce;
  }

  // ================= NOTIFICATION HELPERS =================
  Future<void> _showDownloadNotification({
    required String title,
    required String body,
    required double progress,
    bool isError = false,
    bool isComplete = false,
  }) async {
    final android = AndroidNotificationDetails(
      'auto_update_channel',
      'Automatic Updates',
      channelDescription: 'Background app update downloads',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: !isComplete && !isError,
      autoCancel: isComplete || isError,
      showProgress: true,
      maxProgress: 100,
      progress: (progress * 100).toInt(),
      onlyAlertOnce: true,
      indeterminate: progress <= 0 && !isError,
      icon: '@mipmap/ic_launcher',
    );
    final details = NotificationDetails(android: android, iOS: null);

    await _notifications.show(_notificationId, title, body, details);
  }

  Future<void> _cancelNotification() async {
    await _notifications.cancel(_notificationId);
  }
}
