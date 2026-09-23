# Changelog

All notable changes to **Weather Hub** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## 📱 About Weather Hub

A minimal, accurate weather app built for Ghana and the world. Features a 5-day forecast, hourly updates, health tips, daily inspiration, and — uniquely — a Forecast Confidence Meter powered by an ensemble of three global weather models.

- **Developer:** Bismark NK · Sonnami Develops Ghana
- **Platform:** Android 5.0+
- **Framework:** Flutter (Dart)
- **Distribution:** Direct APK via GitHub Releases

---

## [Unreleased]

Planned for future releases:
- Twi language support (Ghanaian localisation)
- Home screen widget
- Air quality index (Harmattan season alerts)
- UV index daily summary
- Multi-city favorites

---

## [1.2.0] — 2026-09-23

### Added
- **Forecast Confidence Meter** — Compares forecasts from three world-class weather models (ECMWF, GFS, ICON) and displays a real-time confidence score (0–100%).
  - 🟢 High confidence (80–100%): all models agree
  - 🟡 Medium confidence (50–79%): minor disagreement
  - 🔴 Low confidence (below 50%): models disagree, forecast is uncertain
  - Tap the confidence pill to open a detailed breakdown sheet
- **Offline-first caching** — Weather, forecast, and confidence data are now cached locally.
  - Instant app launch with no loading spinner
  - Works offline when there is no internet connection
  - "Last updated X min ago" badge, turning orange when data is over 30 minutes old
- **Hidden Developer Console** — Tap the "Weather Hub" title 7 times on the Info page to unlock a private diagnostics panel.
  - Real-time API latency metrics
  - Cache hit/miss ratios
  - Supported CPU ABIs
  - Remote GitHub version info
  - Actions: clear cache, reset metrics

### Changed
- Forecast cards now use weather-adaptive gradients that match each day's condition
- Rain alerts are now persistent (`ongoing: true`) and cannot be swiped away
- Notifications now use `exactAllowWhileIdle` for precise delivery
- Forecast card width increased and icon size enlarged for better readability
- Hourly cards now show precipitation probability

### Fixed
- "Check for Updates" no longer navigates back to the home screen; shows a clean SnackBar instead
- Daily Delight quotes and facts now refresh properly (ZenQuotes primary, Quotable fallback)
- Cache restoration handles malformed JSON gracefully

---

## [1.1.2] — 2026-09-22

### Changed
- Version display now reads dynamically from the installed build instead of hardcoded strings
- Debug console footer uses live version data

### Notes
- This version was superseded by v1.2.0 before public distribution.

---

## [1.1.1] — 2026-09-22

### Added
- **Hidden Developer Debug Panel** — unlockable via 7 taps on the "Weather Hub" title in the Info page
- `DebugMetrics` service tracking runtime performance (fetch latency, cache stats, notification count)
- "Keep tapping... 👀" hint after 5 taps

### Fixed
- "Check for Updates" no longer kicks the user back to the home screen
- Success and error states now display as a SnackBar on the Info page

### Improved
- Rain notifications are now persistent
- Scheduled notifications use exact alarm mode for reliable delivery

---

## [1.1.0] — 2026-09-22

### Added
- **In-app APK updater** — checks GitHub Releases on launch and prompts users when a new version is available
  - Progress bar during download
  - Automatic install with FileProvider support
- **Enhanced 5-day forecast** with rich data per day:
  - UV index (with color-coded severity labels)
  - Precipitation probability
  - Feels-like high / low
  - Wind speed
  - Average humidity
  - Sunrise and sunset times
- **Forecast change alerts** — compares new forecast to previous and sends notifications when conditions shift significantly
- **Forecast Detail Page** with Lottie animation for each day
- Precipitation probability displayed on hourly and daily forecast cards
- Daily Delight refresh button for manual quote/fact fetch

### Changed
- Forecast API migrated to **Open-Meteo** for improved Ghana accuracy (multi-model ensemble)
- Forecast cards redesigned with weather-adaptive styling
- Notification persistence improved

### Fixed
- Daily Delight quotes now fetch from **ZenQuotes** (primary) with **Quotable** as fallback
- Facts fetch from **UselessFacts** with **CatFact** as fallback
- Expanded fallback pools to avoid repetitive content

---

## [1.0.0] — 2026-09-21

### Added
- **Initial public release**
- Current weather display using OpenWeatherMap API
- 5-day forecast via Open-Meteo
- Next 24 hours hourly forecast
- Location-based weather with high-accuracy GPS
- Auto-fallback to Accra, Ghana when location is unavailable
- Light / dark theme with system-wide toggle
- Search for any city worldwide
- °C / °F unit toggle
- Lottie animations for weather conditions:
  - Sunny
  - Cloudy / windy
  - Partly shower
  - Storm
- Sunrise and sunset cards
- Health tips tailored to current conditions
- Daily Delight — motivational quote + fun fact, cached daily
- Weather-adaptive gradient backgrounds
- Smart summary line ("Rain expected around 3 PM")
- Scheduled notifications:
  - 🌧️ Rain incoming alerts
  - 🌅 Morning briefing (7:00 AM)
  - ☀️ Afternoon weather update (3:00 PM)
  - 🌙 Tomorrow's weather preview (8:00 PM)
  - 🌅 Sunrise reminder (15 min before)
  - 🌇 Sunset reminder (15 min before)
  - 💡 Health tip (9:00 AM)
  - 📖 Daily Delight (1:00 PM)
- Info page with developer credits
- Pull-to-refresh
- Haptic feedback on interactions
- Responsive design for all screen sizes

---

## Version History Summary

| Version | Date | Highlights |
|---------|------|------------|
| **v1.2.0** | 2026-09-23 | Confidence Meter, Offline Cache, Dev Console |
| v1.1.2 | 2026-09-22 | Dynamic version display (superseded) |
| v1.1.1 | 2026-09-22 | Hidden Debug Panel, Persistent Alerts |
| v1.1.0 | 2026-09-22 | In-App Updates, Enhanced Forecast |
| **v1.0.0** | 2026-09-21 | First Public Release |

---

## Links

- **Portfolio:** [sonnamidevs.github.io](https://sonnamidevs.github.io/)
- **Latest Release:** [Download WeatherHub.apk](https://github.com/sonnamidevs/sonnamidevs.github.io/releases/latest/download/WeatherHub.apk)
- **All Releases:** [Releases page](https://github.com/sonnamidevs/sonnamidevs.github.io/releases)
- **Developer:** [Bismark NK on GitHub](https://github.com/sonnamidevs)

---

© 2026 Sonnami Develops · Built with care in Ghana 🇬🇭
