import Foundation
import AppKit
import CryptoKit
import os

/// Handles the OAuth PKCE login flow for Anthropic/Claude.
/// Opens the native browser for authentication; user copies and pastes the code.
@MainActor
class AnthropicOAuthLogin: ObservableObject {
    private let category = Log.Category.auth

    // MARK: - OAuth Configuration (from Constants)

    private var clientId: String { Constants.OAuth.clientId }
    private var authURL: String { Constants.OAuth.authURL }
    private var tokenURL: String { Constants.OAuth.tokenURL }
    private var redirectURI: String { Constants.OAuth.redirectURI }
    private var scopes: String { Constants.OAuth.scopes }

    // MARK: - PKCE State
    // Note: In Claude's OAuth, the state parameter IS the code verifier

    private var codeVerifier: String?
    private var codeChallenge: String?

    // MARK: - Published State

    @Published var isAuthenticating = false
    @Published var errorMessage: String?
    @Published var awaitingCode = false  // True when waiting for user to paste code

    // MARK: - Callbacks

    /// Called when OAuth login succeeds with the access token and optional refresh token
    var onLoginSuccess: ((_ accessToken: String, _ refreshToken: String?) -> Void)?

    // MARK: - Public API

    /// Starts the OAuth login flow.
    /// Opens the native browser to Claude's authorization page.
    func startLogin() {
        Log.debug(category, "Starting OAuth login flow (native browser)...")

        // Generate PKCE code verifier and challenge
        generatePKCE()

        guard let challenge = codeChallenge else {
            Log.error(category, "Failed to generate PKCE parameters")
            errorMessage = "Failed to initialize login"
            return
        }

        // Build authorization URL
        guard let authorizationURL = buildAuthorizationURL(challenge: challenge) else {
            Log.error(category, "Failed to build authorization URL")
            errorMessage = "Failed to build authorization URL"
            return
        }

        // Open in default browser - user will copy the code and paste it back
        Log.debug(category, "Opening browser for OAuth: \(authorizationURL.absoluteString)")
        NSWorkspace.shared.open(authorizationURL)
        awaitingCode = true
        errorMessage = nil
    }

    /// Submits the authorization code that the user copied from the browser.
    func submitCode(_ rawCode: String) {
        let trimmedCode = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            errorMessage = "Please enter the authorization code"
            return
        }

        awaitingCode = false
        Log.debug(category, "User submitted authorization code")

        // Claude's OAuth returns code in format: "actualCode#state"
        let parts = trimmedCode.split(separator: "#", maxSplits: 1)
        let authCode = String(parts[0])
        let returnedState = parts.count > 1 ? String(parts[1]) : nil

        // Verify state matches the verifier (CSRF protection)
        if let returnedState = returnedState, returnedState != codeVerifier {
            Log.error(category, "State mismatch - possible CSRF attack")
            errorMessage = "Security error: state mismatch"
            clearPKCEState()
            return
        }

        Log.info(category, "Processing authorization code")
        exchangeCodeForToken(code: authCode, state: returnedState)
    }

    /// Cancels the current OAuth flow.
    func cancelLogin() {
        awaitingCode = false
        isAuthenticating = false
        errorMessage = nil
        clearPKCEState()
        Log.debug(category, "OAuth login cancelled")
    }

    // MARK: - PKCE Implementation

    /// Generates PKCE code verifier and challenge using S256 method.
    /// Note: In Claude's OAuth, the state parameter IS the code verifier.
    private func generatePKCE() {
        // Generate 32 random bytes for code verifier
        var randomBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)

        // Base64URL encode the random bytes
        codeVerifier = Data(randomBytes).base64URLEncoded()

        // Create SHA256 hash of verifier for challenge
        guard let verifier = codeVerifier,
              let verifierData = verifier.data(using: .utf8) else {
            return
        }

        let hash = SHA256.hash(data: verifierData)
        codeChallenge = Data(hash).base64URLEncoded()

        Log.debug(category, "Generated PKCE verifier (length: \(verifier.count))")
    }

    /// Builds the OAuth authorization URL with all required parameters.
    /// Note: Claude's OAuth requires `code=true` and uses the verifier as the state.
    private func buildAuthorizationURL(challenge: String) -> URL? {
        var components = URLComponents(string: authURL)
        components?.queryItems = [
            URLQueryItem(name: "code", value: "true"),  // Required by Claude's OAuth
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: codeVerifier),  // State IS the verifier
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components?.url
    }

    // MARK: - Token Exchange

    /// Exchanges the authorization code for an access token.
    private func exchangeCodeForToken(code: String, state: String?) {
        guard let verifier = codeVerifier else {
            Log.error(category, "No code verifier available for token exchange")
            errorMessage = "Internal error: missing code verifier"
            return
        }

        isAuthenticating = true
        Log.debug(category, "Exchanging authorization code for token...")

        Task {
            do {
                let tokenResponse = try await performTokenExchange(code: code, state: state, verifier: verifier)
                await MainActor.run {
                    self.isAuthenticating = false
                    self.clearPKCEState()
                    Log.info(self.category, "OAuth login successful!")
                    if tokenResponse.refreshToken != nil {
                        Log.debug(self.category, "Received refresh token")
                    }
                    self.onLoginSuccess?(tokenResponse.accessToken, tokenResponse.refreshToken)
                }
            } catch {
                await MainActor.run {
                    self.isAuthenticating = false
                    self.clearPKCEState()
                    Log.error(self.category, "Token exchange failed: \(error.localizedDescription)")
                    self.errorMessage = "Failed to complete login: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Clears PKCE state after authentication attempt.
    private func clearPKCEState() {
        codeVerifier = nil
        codeChallenge = nil
    }

    /// Performs the token exchange request using JSON body.
    /// Claude's OAuth expects JSON with code, state, grant_type, client_id, redirect_uri, code_verifier.
    private func performTokenExchange(code: String, state: String?, verifier: String) async throws -> TokenResponse {
        guard let url = URL(string: tokenURL) else {
            throw OAuthLoginError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Constants.Timeouts.networkRequestTimeout

        // Build JSON body - Claude's OAuth expects JSON, not form-encoded
        var bodyParams: [String: String] = [
            "code": code,
            "grant_type": "authorization_code",
            "client_id": clientId,
            "redirect_uri": redirectURI,
            "code_verifier": verifier
        ]

        // Include state if present
        if let state = state {
            bodyParams["state"] = state
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyParams)

        Log.debug(category, "Token exchange request to: \(tokenURL)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthLoginError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            Log.error(category, "Token exchange HTTP error \(httpResponse.statusCode): \(errorBody)")
            throw OAuthLoginError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse token response
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        Log.debug(category, "Received access token (expires in: \(tokenResponse.expiresIn ?? 0)s)")

        return tokenResponse
    }
}

// MARK: - Supporting Types

/// Errors that can occur during OAuth login.
enum OAuthLoginError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid OAuth URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let message):
            return "HTTP error \(code): \(message)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        }
    }
}

/// OAuth token response structure.
/// Used for both initial token exchange and token refresh operations.
struct OAuthTokenResponse: Codable {
    /// The access token for API calls
    let accessToken: String
    /// The token type (typically "Bearer")
    let tokenType: String?
    /// Seconds until the access token expires
    let expiresIn: Int?
    /// Optional refresh token for obtaining new access tokens
    let refreshToken: String?
    /// The granted scopes
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

// Type alias for backwards compatibility within this file
private typealias TokenResponse = OAuthTokenResponse

// MARK: - Base64URL Encoding Extension

private extension Data {
    /// Encodes data as base64url (URL-safe base64 without padding).
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
