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
- **Managers/AccountSession.swift**: Per-account state wrapper with monitoring timer and auto-ping logic
- **Managers/TrackerService.swift**: WKWebView-based scraper that executes JS to fetch org/usage/tier data from Claude's APIs
- **Managers/AuthManager.swift**: Handles OAuth-style login flow via embedded WebKit browser
- **Models/Models.swift**: `UsageData` (parsed usage metrics) and `ClaudeAccount` (persisted account with cookie serialization)
- **UI/UsageView.swift**: Circular session gauge and linear weekly gauge with color-coded thresholds
- **UI/SettingsView.swift**: Refresh interval picker, auto-wake toggle, account removal

### Cookie Persistence

Cookies are serialized to `[String: String]` dictionaries via `HTTPCookie.toCodable()` extension (CookieHelper.swift) and stored in UserDefaults. On load, they're reconstructed back to `HTTPCookie` objects.

### Settings (UserDefaults keys)

- `refreshInterval`: Double (seconds between auto-refresh, default 300)
- `autoWakeUp`: Bool (auto-ping sessions when usage hits 0%)
- `savedAccounts`: Data (encoded `[ClaudeAccount]` array)
