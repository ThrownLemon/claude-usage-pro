import AppKit
import Combine
import SwiftUI

/// Observable class that tracks system appearance and user color scheme preferences.
/// Uses AppKit to reliably detect system appearance changes for MenuBarExtra windows.
@MainActor
class AppearanceManager: ObservableObject {
    @Published var systemColorScheme: ColorScheme = .dark
    @Published var colorSchemeMode: String {
        didSet {
            UserDefaults.standard.set(colorSchemeMode, forKey: ThemeManager.colorSchemeModeKey)
        }
    }

    private var appearanceObserver: NSKeyValueObservation?
    private var userDefaultsObserver: NSObjectProtocol?

    init() {
        // Load initial color scheme mode from UserDefaults
        self.colorSchemeMode =
            UserDefaults.standard.string(forKey: ThemeManager.colorSchemeModeKey)
            ?? ColorSchemeMode.system.rawValue

        // Detect initial system appearance
        updateSystemColorScheme()

        // Observe system appearance changes via NSApp
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor in
                self?.updateSystemColorScheme()
            }
        }

        // Observe UserDefaults changes (from SettingsView's @AppStorage)
        // Note: Even though queue is .main, the closure is not MainActor-isolated,
        // so we use MainActor.assumeIsolated for safe property access
        userDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                let newMode =
                    UserDefaults.standard.string(forKey: ThemeManager.colorSchemeModeKey)
                    ?? ColorSchemeMode.system.rawValue
                if self.colorSchemeMode != newMode {
                    self.colorSchemeMode = newMode
                }
            }
        }
    }

    deinit {
        appearanceObserver?.invalidate()
        if let observer = userDefaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func updateSystemColorScheme() {
        let appearance = NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        systemColorScheme = isDark ? .dark : .light
    }

    /// The effective color scheme combining user preference with system setting
    var effectiveColorScheme: ColorScheme {
        let mode = ColorSchemeMode(rawValue: colorSchemeMode) ?? .system
        return mode.effectiveColorScheme(systemScheme: systemColorScheme)
    }

    /// The color scheme preference to pass to SwiftUI (nil means follow system)
    var preferredColorScheme: ColorScheme? {
        let mode = ColorSchemeMode(rawValue: colorSchemeMode) ?? .system
        return mode.colorScheme
    }
}
