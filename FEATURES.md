# ClaudeUsagePro - Planned Features

This document tracks planned features for future implementation.

---

## Feature 1: Auto-Update Notifications

**Status:** Planned
**Priority:** High
**Effort:** Low (~2-3 hours)

**Description:** Check GitHub releases on app launch and notify users when a new version is available.

### Components to Create

| File | Purpose |
|------|---------|
| `Managers/UpdateManager.swift` | GitHub API client, version comparison logic |
| `UI/UpdateAlertView.swift` | Modal/banner showing update available |

### Implementation Details

- Fetch `https://api.github.com/repos/{owner}/{repo}/releases/latest` on launch
- Compare `tag_name` with `Bundle.main.infoDictionary["CFBundleShortVersionString"]`
- Use semantic versioning comparison (1.2.3 format)
- Store "skip this version" preference in UserDefaults
- Show non-intrusive banner with "Download" and "Skip" buttons
- Link to GitHub releases page or direct `.dmg` download

### UserDefaults Keys

- `lastUpdateCheck`: Date of last check (throttle to once per day)
- `skippedVersion`: Version string user chose to skip

---

## Feature 2: WCAG-Compliant Color Themes

**Status:** Planned
**Priority:** Medium
**Effort:** Medium (~4-5 hours)

**Description:** Accessibility-first color system ensuring 4.5:1 contrast ratios and colorblind-friendly palettes.

### Components to Create

| File | Purpose |
|------|---------|
| `UI/Theme/ColorPalette.swift` | Centralized color definitions |
| `UI/Theme/AccessibleColors.swift` | WCAG-compliant color sets |

### Implementation Details

- Define semantic colors (success, warning, critical, danger) with accessible variants
- Replace hardcoded colors in `UsageView.swift` gauge gradients
- Support both light and dark mode with proper contrast
- Colorblind-friendly: avoid red/green-only distinctions, use shapes/patterns as secondary indicators

### Color Palette (WCAG AA Compliant)

| Semantic | Light Mode | Dark Mode | Use Case |
|----------|------------|-----------|----------|
| Success | `#1B7D3E` | `#4ADE80` | 0-50% usage |
| Warning | `#B45309` | `#FBBF24` | 50-70% usage |
| Critical | `#C2410C` | `#FB923C` | 70-85% usage |
| Danger | `#B91C1C` | `#F87171` | 85-100% usage |

### Accessibility Features

- Add icons alongside colors (checkmark, warning triangle, etc.)
- Support reduced motion preference
- VoiceOver labels for all gauges

---

## Feature 3: ML-Based Usage Predictions

**Status:** Planned
**Priority:** Low
**Effort:** High (~8-10 hours)

**Description:** Predict when users will hit limits based on historical usage patterns.

### Components to Create

| File | Purpose |
|------|---------|
| `Managers/UsageHistoryStore.swift` | Persist historical usage data points |
| `Managers/PredictionEngine.swift` | Rolling average, trend analysis |
| `Models/UsagePrediction.swift` | Prediction result model |

### Implementation Details

- Store usage snapshots: `(timestamp, sessionPercentage, weeklyPercentage, accountId)`
- Keep 30 days of hourly samples (max ~720 per account)
- Calculate metrics:
  - **Daily average:** Mean usage per day over last 7 days
  - **P90 percentile:** 90th percentile daily usage (for "heavy day" predictions)
  - **Trend slope:** Linear regression on recent 24h to detect acceleration
- Prediction formula: `daysUntilLimit = (1.0 - currentUsage) / dailyAverageUsage`

### UI Display

- In UsageView: "At current pace: ~2.5 days until weekly reset"
- Warning if predicted to hit limit before natural reset

### Data Models

```swift
struct UsageSnapshot: Codable {
    let timestamp: Date
    let accountId: UUID
    let sessionPercentage: Double
    let weeklyPercentage: Double
}

struct UsagePrediction {
    let daysUntilSessionLimit: Double?
    let daysUntilWeeklyLimit: Double?
    let confidence: Double // 0-1 based on data availability
    let trend: Trend // .stable, .increasing, .decreasing
}
```

### Storage

**Recommended:** JSON file in Application Support for simplicity.
- JSON is sufficient for ~720 records per account (30 days × 24 hours)
- SQLite/SwiftData only if adding complex queries or relationships later
- File location: `~/Library/Application Support/ClaudeUsagePro/usage_history.json`

---

## Future Ideas (From Research)

These features were identified from analyzing similar projects but not yet planned:

| Feature | Source Project | Notes |
|---------|---------------|-------|
| CSV Export | masorange/ClaudeUsageTracker | Export usage data for expense reports |
| 4-Tier Alert System | budlion/genai-code-usage-monitor | INFO/WARNING/CRITICAL/DANGER levels |
| Claude Code Local History | masorange/ClaudeUsageTracker | Parse `~/.claude/projects/` for CLI users |
| Currency Conversion | masorange/ClaudeUsageTracker | USD/EUR with daily exchange rates |
| Cache Token Tracking | budlion/genai-code-usage-monitor | Show 90% cache savings |
| Conversation Turn Grouping | masorange/ClaudeUsageTracker | Accurate cost for tool-heavy workflows |
| Context-Aware Pricing | masorange/ClaudeUsageTracker | Standard vs Long context (>200K) rates |

---

## Research Sources

- [masorange/ClaudeUsageTracker](https://github.com/masorange/ClaudeUsageTracker) - macOS Swift app
- [budlion/genai-code-usage-monitor](https://github.com/budlion/genai-code-usage-monitor) - Python CLI
- [yagil/tokmon](https://github.com/yagil/tokmon) - CLI token monitor
- [ocodista/claude-usage](https://github.com/ocodista/claude-usage) - Web dashboard
