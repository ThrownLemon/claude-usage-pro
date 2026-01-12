# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in AI Usage Pro, please report it responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities
2. Email the maintainer directly or use GitHub's private vulnerability reporting feature
3. Include as much detail as possible:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will acknowledge receipt within 48 hours and provide a more detailed response within 7 days.

## Security Considerations

### Credential Storage

- **Keychain**: OAuth tokens, API keys, and session cookies are stored in the macOS Keychain
- **UserDefaults**: Only non-sensitive account metadata is stored in UserDefaults
- Credentials never leave your device

### Network Security

- All API communication uses HTTPS
- No data is sent to third-party servers
- Authentication flows use official OAuth endpoints

### Local Processing

- All usage data processing happens locally on your Mac
- No telemetry or analytics are collected
- No external tracking services are used

## Best Practices for Users

1. Keep your macOS and the app updated
2. Don't share your OAuth tokens or session cookies
3. Remove accounts you no longer use via Settings
4. Use the "Reset All Data" option if you suspect credential compromise
