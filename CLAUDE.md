# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Usage Pro is a macOS menu bar application that tracks Claude.ai API usage across multiple accounts. It displays session (5-hour) and weekly (7-day) usage limits with visual gauges, supports multi-account management with persistent cookie storage, and can auto-ping sessions to wake them up when usage resets.

## Build Commands

```bash
# Build the app
swift build

# Build and run
swift run

# Build release version
swift build -c release
```

## Architecture

### Core Data Flow

1. **AuthManager** opens a WebKit window to claude.ai/login, captures session cookies on successful auth
2. **AppState** receives cookies, creates a **ClaudeAccount** with cookie storage, wraps it in an **AccountSession**
3. **AccountSession** owns a **TrackerService** that periodically fetches usage via hidden WKWebView
4. **TrackerService** injects JavaScript to call Claude's internal APIs (`/api/organizations`, `/api/organizations/{id}/usage`, `/api/bootstrap/{id}/statsig`)
5. Usage data flows back through callbacks to update the published `ClaudeAccount.usageData`

### Key Components

- **App.swift**: Entry point, contains `AppState` (session management, persistence via UserDefaults), `ContentView` (main UI shell), and reusable button components
- **Managers/AccountSession.swift**: Per-account state wrapper with monitoring timer, auto-ping logic, and threshold crossing detection for notifications
- **Managers/TrackerService.swift**: WKWebView-based scraper that executes JS to fetch org/usage/tier data from Claude's APIs
- **Managers/AuthManager.swift**: Handles OAuth-style login flow via embedded WebKit browser
- **Managers/NotificationManager.swift**: Singleton wrapper for UserNotifications framework with permission management, typed notifications, and rate limiting
- **Models/Models.swift**: `UsageData` (parsed usage metrics) and `ClaudeAccount` (persisted account with cookie serialization)
- **Models/NotificationSettings.swift**: UserDefaults-backed settings model for notification preferences with helper methods
- **UI/UsageView.swift**: Circular session gauge and linear weekly gauge with color-coded thresholds
- **UI/SettingsView.swift**: Refresh interval picker, auto-wake toggle, notification settings, account removal

### Cookie Persistence

Cookies are serialized to `[String: String]` dictionaries via `HTTPCookie.toCodable()` extension (CookieHelper.swift) and stored in UserDefaults. On load, they're reconstructed back to `HTTPCookie` objects.

### Settings (UserDefaults keys)

- `refreshInterval`: Double (seconds between auto-refresh, default 300)
- `autoWakeUp`: Bool (auto-ping sessions when usage hits 0%)
- `savedAccounts`: Data (encoded `[ClaudeAccount]` array)

#### Notification Settings

- `notificationsEnabled`: Bool (master toggle for all notifications, default true)
- `notificationSessionThreshold1Enabled`: Bool (session threshold 1 alert, default true)
- `notificationSessionThreshold2Enabled`: Bool (session threshold 2 alert, default true)
- `notificationSessionReadyEnabled`: Bool (session ready alert, default true)
- `notificationWeeklyThreshold1Enabled`: Bool (weekly threshold 1 alert, default true)
- `notificationWeeklyThreshold2Enabled`: Bool (weekly threshold 2 alert, default true)

#### Threshold Values

- `threshold1Value`: Double (first threshold percentage, default 0.75)
- `threshold2Value`: Double (second threshold percentage, default 0.90)

Note: Threshold values are shared between session and weekly alerts. Users configure once, applies to both.

### Notification System

The app sends macOS notifications when usage crosses configurable thresholds, alerting users to session/weekly usage milestones and session ready states.

#### NotificationManager

**Location:** `Managers/NotificationManager.swift`

Singleton class that wraps the UserNotifications framework with:

- **Permission Management**: Requests notification authorization on first launch, tracks authorization status, provides callbacks for granted/denied/error states
- **Notification Types**: Five distinct notification categories:
  - `sessionThreshold75`: Session usage reached 75%
  - `sessionThreshold90`: Session usage reached 90%
  - `weeklyThreshold75`: Weekly usage reached 75%
  - `weeklyThreshold90`: Weekly usage reached 90%
  - `sessionReady`: Session reset to 0% with "Ready" status
- **Rate Limiting**: 5-minute cooldown per notification type per account to prevent spam during rapid refreshes. Tracks last notification time using key format: `"accountName:notificationType.identifier"`
- **Foreground Support**: Implements `UNUserNotificationCenterDelegate` to show banners even when app is in foreground
- **Callback Pattern**: Follows existing TrackerService pattern with `onPermissionGranted`, `onPermissionDenied`, and `onError` callbacks

#### NotificationSettings & ThresholdDefinitions

**Location:** `Models/NotificationSettings.swift`

Centralized configuration for all notification thresholds:

- **ThresholdConfig**: Struct containing threshold configuration (value, UserDefaults keys, notification type, enabled default, labels)
- **ThresholdDefinitions**: Enum with all threshold configurations (sessionThreshold1/2, weeklyThreshold1/2), default values, and UserDefaults keys
- **NotificationSettings**: Static helper struct with keys, defaults, and `shouldSend(type:)` method to check if notifications are enabled

Threshold values are user-configurable via sliders in Settings (default 75%/90%). Session and weekly thresholds share the same value keys for unified configuration.

Used in `SettingsView` with `@AppStorage` property wrappers for automatic persistence and reactive UI updates.

#### Threshold Detection Logic

**Location:** `Managers/AccountSession.swift`

Threshold crossing detection is implemented in AccountSession to trigger notifications when usage transitions across thresholds:

1. **Previous Value Tracking**: `previousSessionPercentage` and `previousWeeklyPercentage` store usage values from the previous update
2. **Crossing Detection**: `didCrossThreshold(previous:current:threshold:)` returns true when usage transitions from below to at-or-above a threshold (e.g., 74% → 76% crosses the configured threshold)
3. **Ready State Detection**: `didTransitionToReady(previousPercentage:currentPercentage:currentReset:)` returns true when session transitions from non-zero usage to 0% with "Ready" status
4. **Centralized Threshold Iteration**: `checkThresholdCrossingsAndNotify(usageData:)` iterates over `ThresholdDefinitions.sessionThresholds` and `ThresholdDefinitions.weeklyThresholds`, reading the current threshold value from UserDefaults via each config's `threshold` computed property
5. **Launch Edge Case Handling**: `hasReceivedFirstUpdate` flag prevents notifications from firing on app launch with cached data. Previous values remain nil on first update, causing detection methods to return false. Only subsequent updates can trigger notifications.

This approach ensures notifications fire only on actual usage changes at user-configured thresholds, and prevents spam through both user-configurable settings and automatic rate limiting.
