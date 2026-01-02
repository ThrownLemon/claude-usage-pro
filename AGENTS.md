# AGENTS.md

This file provides guidance for AI agents working in the ClaudeUsagePro codebase.

## Build & Test Commands

```bash
# Build the project
swift build

# Build and run the app
swift run

# Build release version
swift build -c release
```

**Note**: This project has no test infrastructure. No test targets or test commands exist.

## Project Structure

```
Sources/ClaudeUsagePro/
├── App.swift              # Entry point, AppState, ContentView, reusable UI components
├── Managers/
│   ├── AccountSession.swift  # Per-account monitoring and state wrapper
│   ├── AuthManager.swift     # OAuth login flow via WebKit
│   └── TrackerService.swift  # Usage fetching via WKWebView JavaScript injection
├── Models/
│   ├── Models.swift       # UsageData, ClaudeAccount data structures
│   └── CookieHelper.swift  # HTTPCookie serialization for UserDefaults
└── UI/
    ├── UsageView.swift    # Session/weekly gauge display
    └── SettingsView.swift # Settings with @AppStorage bindings
```

## Code Style Guidelines

### Naming Conventions
- **Types**: `UpperCamelCase` (e.g., `AccountSession`, `UsageData`)
- **Functions/Variables**: `lowerCamelCase` (e.g., `fetchUsage`, `sessionPercentage`)
- **Properties**: Descriptive, no abbreviations (e.g., `cookieProps`, `refreshInterval`)

### Import Patterns
- UI files: `import SwiftUI`
- Manager files: `import Foundation`, `import WebKit`, `import Combine`
- Model files: `import Foundation`, `import WebKit` (for HTTPCookie types)

### SwiftUI State Management
- **@StateObject**: Owns lifecycle (e.g., `AppState` in `App.swift`)
- **@ObservedObject**: Observes passed objects (e.g., `ContentView`, `UsageView`)
- **@Published**: Triggers UI updates in `ObservableObject` classes
- **@AppStorage**: Direct UserDefaults binding for simple settings
- **@State**: Local view state only (hover effects, animations)
- **@EnvironmentObject**: Injected at root, accessed down the view hierarchy

### Concurrency Patterns
- **DispatchQueue.main.async**: Return to main thread for UI updates
- **DispatchQueue.main.asyncAfter**: Delayed execution (e.g., post-ping refresh)
- **Timer.scheduledTimer**: Periodic background refreshes
- **Timer.publish**: UI-side countdowns and animations
- **DispatchGroup**: Synchronize async operations (cookie injection)
- **Note**: Native async/await is used only in JavaScript strings executed via WKWebView

### Error Handling
- **Callbacks**: Optional closure properties (e.g., `var onError: ((Error) -> Void)?`)
- **Print logging**: `[DEBUG]` and `[ERROR]` prefixes for console output
- **Silent failures**: `try?` for serialization; no custom error enums
- **Do-catch**: Used in JS execution, errors logged to console

### Persistence (UserDefaults)
- **Manual access**: `UserDefaults.standard` for complex objects (encode/decode as Data)
- **@AppStorage**: Simple settings (e.g., `refreshInterval`, `autoWakeUp`)
- **Cookie storage**: Serialized to `[String: String]` arrays via `CookieHelper`

### UI Patterns
- **Material backgrounds**: `.background(Material.regular)`, `.background(Material.bar)`
- **Rounded corners**: `.cornerRadius(8)` or `.cornerRadius(12)`
- **Hover states**: `@State private var isHovering` with `.onHover`
- **Animations**: `.animation(.easeInOut(duration: X), value: isHovering)`
- **SF Symbols**: `Image(systemName:)` for icons
- **Font design**: `.system(.design(.rounded))` used throughout
- **No type suppression**: Never use `as any`, `@ts-ignore`, or `@ts-expect-error`

## Platform & Dependencies
- **Target**: macOS 13.0+
- **Package Manager**: Swift Package Manager (SPM)
- **No external dependencies**: Uses only Apple frameworks
- **No linting tools**: SwiftLint/SwiftFormat not configured

## Architecture Notes
- **Menu bar app**: Uses `MenuBarExtra` with `.menuBarExtraStyle(.window)`
- **WebKit for data**: Hidden WKWebViews execute JavaScript to fetch Claude API data
- **Multi-account**: Each account wrapped in `AccountSession` with independent monitoring
- **Cookie-based auth**: Session cookies captured via WebKit login, stored in UserDefaults
