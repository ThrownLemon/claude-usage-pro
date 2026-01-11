import Foundation
import SQLite3

/// Errors that can occur when tracking Cursor usage.
enum CursorTrackerError: Error, LocalizedError {
    /// Authentication token not found in the local Cursor database
    case authNotFound
    /// Network request failed
    case fetchFailed(Error)
    /// Server returned non-200 status code
    case badResponse(statusCode: Int)
    /// Failed to parse JSON response
    case invalidJSONResponse(Error)
    /// API URL is malformed
    case invalidAPIURL

    var errorDescription: String? {
        switch self {
        case .authNotFound:
            return "Cursor authentication token not found in the local database."
        case .fetchFailed(let error):
            return "Failed to fetch usage summary: \(error.localizedDescription)"
        case .badResponse(let statusCode):
            return "Received an invalid server response (Status Code: \(statusCode))."
        case .invalidJSONResponse(let error):
            return "Failed to parse the JSON response: \(error.localizedDescription)"
        case .invalidAPIURL:
            return "The API endpoint URL is invalid."
        }
    }
}

private struct CursorAPIResponse: Codable {
    let individualUsage: IndividualUsage
    let membershipType: String?
}

private struct IndividualUsage: Codable {
    let plan: Plan
}

private struct Plan: Codable {
    let used: Int
    let limit: Int
    let remaining: Int
}

/// Authentication data extracted from Cursor's local database.
struct CursorAuthData {
    /// OAuth access token for API calls
    let accessToken: String?
    /// User's email address
    let email: String?
    /// Subscription type (e.g., "pro", "free")
    let membershipType: String?
}

/// Usage information for a Cursor account.
struct CursorUsageInfo {
    /// User's email address
    let email: String?
    /// Number of requests used in current period
    let planUsed: Int
    /// Maximum requests allowed in current period
    let planLimit: Int
    /// Remaining requests in current period
    let planRemaining: Int
    /// Plan type (e.g., "pro", "free")
    let planType: String?
}

/// Service for fetching Cursor IDE usage statistics from the local installation.
class CursorTrackerService {
    private let cursorAPIBase = "https://api2.cursor.sh"
    private let stateDBPath = "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb"

    init() {}

    /// Checks if Cursor is installed on this machine.
    /// - Returns: True if the Cursor state database exists
    func isInstalled() -> Bool {
        let path = NSString(string: "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb").expandingTildeInPath
        return FileManager.default.fileExists(atPath: path)
    }
    
    /// Fetches current usage statistics from the Cursor API.
    /// - Returns: Usage information including requests used and limits
    /// - Throws: CursorTrackerError if authentication or fetch fails
    func fetchCursorUsage() async throws -> CursorUsageInfo {
        guard let auth = readAuthFromStateDB(), let token = auth.accessToken else {
            throw CursorTrackerError.authNotFound
        }
        
        guard let url = URL(string: "\(cursorAPIBase)/auth/usage-summary") else {
            throw CursorTrackerError.invalidAPIURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorTrackerError.badResponse(statusCode: 0)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw CursorTrackerError.badResponse(statusCode: httpResponse.statusCode)
        }
        
        do {
            let apiResponse = try JSONDecoder().decode(CursorAPIResponse.self, from: data)
            let plan = apiResponse.individualUsage.plan
            
            return CursorUsageInfo(
                email: auth.email,
                planUsed: plan.used,
                planLimit: plan.limit,
                planRemaining: plan.remaining,
                planType: apiResponse.membershipType ?? auth.membershipType
            )
        } catch {
            throw CursorTrackerError.invalidJSONResponse(error)
        }
    }
    
    private func readAuthFromStateDB() -> CursorAuthData? {
        let path = NSString(string: stateDBPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        
        let uri = "file://\(path)?mode=ro&immutable=1"
        var db: OpaquePointer?
        
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }
        
        var accessToken: String?
        var email: String?
        var membershipType: String?
        
        let query = "SELECT key, value FROM ItemTable WHERE key LIKE 'cursorAuth/%'"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let keyPtr = sqlite3_column_text(stmt, 0),
                   let valuePtr = sqlite3_column_text(stmt, 1) {
                    let key = String(cString: keyPtr)
                    let value = String(cString: valuePtr)
                    
                    switch key {
                    case "cursorAuth/accessToken": accessToken = value
                    case "cursorAuth/cachedEmail": email = value
                    case "cursorAuth/stripeMembershipType": membershipType = value
                    default: break
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
        
        return CursorAuthData(accessToken: accessToken, email: email, membershipType: membershipType)
    }
}
