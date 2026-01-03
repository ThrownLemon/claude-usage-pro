# Claude Usage Pro

![macOS](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![License](https://img.shields.io/badge/license-MIT-green)

**Claude Usage Pro** is a native macOS menu bar application that helps you monitor your Claude.ai API usage across multiple accounts in real-time. Stay on top of your session and weekly usage limits with beautiful visual gauges that change color as you approach your limits.

Whether you're managing a single Claude account or juggling multiple accounts across different organizations, Claude Usage Pro provides an at-a-glance view of your remaining capacity with session (5-hour) and weekly (7-day) usage tracking. The app features persistent cookie storage for seamless multi-account management and can automatically wake up sessions when usage resets, ensuring you never miss a beat.

## Features

- 🖥️ **Menu Bar Integration** – Quick access from your macOS menu bar without cluttering your dock
- ⏱️ **Session Usage Tracking** – Monitor your 5-hour rolling session usage limit in real-time
- 📊 **Weekly Usage Tracking** – Keep track of your 7-day rolling weekly usage limits
- 👥 **Multi-Account Support** – Manage and monitor multiple Claude accounts simultaneously
- 🎨 **Visual Gauges with Color-Coded Thresholds** – Intuitive green/yellow/red indicators show your usage status at a glance
- 🔔 **Auto-Ping/Wake-Up** – Automatically ping sessions when usage resets to 0% to keep them active
- 💾 **Persistent Cookie Storage** – Securely stores session cookies locally for seamless authentication
- ⚙️ **Configurable Refresh Intervals** – Customize how frequently usage data is fetched to balance accuracy and performance

## Requirements

- **macOS 13 (Ventura) or later** – The app requires macOS 13+ to run
- **Swift 5.9+** – Required for building from source
- **Xcode 15+** (optional) – Recommended for development, but not required for building with Swift CLI

## Installation

### Building from Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/claude-usage-pro.git
   cd claude-usage-pro
   ```

2. **Build the application**

   For a release build (recommended):
   ```bash
   swift build -c release
   ```

   Or for a debug build:
   ```bash
   swift build
   ```

3. **Locate the built executable**

   After building, the executable will be located at:
   - **Release build**: `.build/release/ClaudeUsagePro`
   - **Debug build**: `.build/debug/ClaudeUsagePro`

4. **Run the application**
   ```bash
   .build/release/ClaudeUsagePro
   ```

### Optional: Install for Convenient Access

To make the app more accessible, you can:

- **Copy to Applications folder** (recommended):
  ```bash
  cp .build/release/ClaudeUsagePro /Applications/
  ```

  Then launch it from Spotlight or your Applications folder.

- **Add to Login Items** for auto-start on login:
  1. Open **System Settings** → **General** → **Login Items**
  2. Click the **+** button under "Open at Login"
  3. Navigate to and select `ClaudeUsagePro` (from `/Applications` or your build directory)
  4. The app will now launch automatically when you log in

## Usage

### Getting Started

1. **Launch the application**

   Run the app using one of the methods from the Installation section above. Once launched, you'll see a new icon appear in your macOS menu bar.

2. **Click the menu bar icon**

   Click the Claude Usage Pro icon in your menu bar to open the main interface.

3. **Add your first account**

   - Click the **"Add Account"** button (or the **"+"** button if you already have accounts)
   - A WebKit browser window will open showing the Claude.ai login page

4. **Authenticate with Claude.ai**

   - Log in to your Claude.ai account using your credentials in the WebKit browser window
   - Once authentication is successful, the browser window will automatically close
   - Your account will now appear in the app with its usage data

5. **View your usage metrics**

   Once authenticated, you'll see two visual gauges for each account:

   - **Session Usage (Circular Gauge)** – Shows your current 5-hour rolling session usage
   - **Weekly Usage (Linear Bar)** – Displays your 7-day rolling weekly usage

   Both gauges update automatically based on your configured refresh interval (default: 5 minutes).

### Understanding the Color-Coded Thresholds

The visual gauges use intuitive color coding to help you monitor your usage at a glance:

- **🟢 Green (0-70%)** – You have plenty of capacity remaining. Use Claude freely!
- **🟡 Yellow (70-90%)** – You're approaching your limit. Consider moderating your usage.
- **🔴 Red (90-100%)** – You're very close to or at your limit. Usage may be restricted soon.

These thresholds apply to both session and weekly usage gauges, making it easy to see your status across both time windows.

### Managing Multiple Accounts

If you work with multiple Claude.ai accounts across different organizations:

1. Click the **"+"** button to add additional accounts
2. Each account will appear in the interface with its own usage gauges
3. Switch between accounts to view their individual usage metrics
4. Remove accounts by accessing the Settings panel (gear icon)

## Settings

Claude Usage Pro offers several configurable options to customize your monitoring experience. Access the Settings panel by clicking the **gear icon** (⚙️) in the app interface.

### Refresh Interval

The refresh interval controls how frequently the app fetches updated usage data from Claude.ai.

- **Default**: 5 minutes (300 seconds)
- **Purpose**: Balance between real-time accuracy and system performance
- **Customization**: Adjust the interval based on your needs:
  - **Shorter intervals** (e.g., 2-3 minutes) – Get more frequent updates if you're actively monitoring usage
  - **Longer intervals** (e.g., 10-15 minutes) – Reduce system resources and network requests if you only need periodic checks

**How to configure**: In the Settings panel, use the refresh interval picker to select your preferred update frequency.

### Auto-Wake / Auto-Ping

The auto-wake feature automatically pings your Claude.ai sessions when usage resets to 0%, helping keep your sessions active.

- **Default**: Configurable (off by default)
- **Purpose**: Automatically "wake up" sessions when your usage limits reset, ensuring you can resume work immediately
- **Behavior**: When your session or weekly usage returns to 0% (indicating a reset), the app will automatically send a ping to Claude.ai to refresh the session

**How to configure**: In the Settings panel, toggle the "Auto-Wake" switch to enable or disable this feature.

**Use case**: If you want to ensure your sessions are always ready when usage resets (e.g., at the start of a new 5-hour period or 7-day cycle), enable this feature. This is particularly useful if you work with Claude during specific time windows and want seamless access when limits refresh.

### Account Management

The Settings panel also provides account management capabilities:

- **Add Accounts**: Click the **"+"** button to authenticate and add new Claude.ai accounts
- **Remove Accounts**: In the Settings panel, you can remove accounts you no longer need to monitor
- **View All Accounts**: See all your configured accounts in one place with their current usage status

**Cookie Storage**: All account credentials are stored locally on your Mac using secure cookie persistence. Your authentication data never leaves your device.
