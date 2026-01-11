import XCTest
@testable import ClaudeUsagePro

final class KeychainServiceTests: XCTestCase {
    private let testKey = "test_keychain_key_\(UUID().uuidString)"
    private let nonexistentKey = "nonexistent_key_\(UUID().uuidString)"

    override func tearDownWithError() throws {
        // Clean up after each test
        try? KeychainService.delete(forKey: testKey)
        try? KeychainService.delete(forKey: nonexistentKey)
    }

    func testSaveAndLoadData() throws {
        // Given
        let testData = Data("Hello, Keychain!".utf8)

        // When
        try KeychainService.save(testData, forKey: testKey)
        let loadedData = try KeychainService.load(forKey: testKey)

        // Then
        XCTAssertEqual(loadedData, testData)
    }

    func testSaveAndLoadString() throws {
        // Given
        let testString = "Test String Value"

        // When
        try KeychainService.save(testString, forKey: testKey)
        let loadedString = try KeychainService.loadString(forKey: testKey)

        // Then
        XCTAssertEqual(loadedString, testString)
    }

    func testLoadNonexistentKey() throws {
        // When
        let result = try KeychainService.load(forKey: nonexistentKey)

        // Then
        XCTAssertNil(result)
    }

    func testDeleteKey() throws {
        // Given
        let testData = Data("Delete me".utf8)
        try KeychainService.save(testData, forKey: testKey)

        // When
        try KeychainService.delete(forKey: testKey)
        let loadedData = try KeychainService.load(forKey: testKey)

        // Then
        XCTAssertNil(loadedData)
    }

    func testOverwriteExistingKey() throws {
        // Given
        let originalData = Data("Original".utf8)
        let newData = Data("Updated".utf8)

        // When
        try KeychainService.save(originalData, forKey: testKey)
        try KeychainService.save(newData, forKey: testKey)
        let loadedData = try KeychainService.load(forKey: testKey)

        // Then
        XCTAssertEqual(loadedData, newData)
    }

    func testCookiesKey() {
        // Given
        let accountId = UUID()

        // When
        let key = KeychainService.cookiesKey(for: accountId)

        // Then
        XCTAssertEqual(key, "cookies_\(accountId.uuidString)")
    }

    func testApiTokenKey() {
        // Given
        let accountId = UUID()

        // When
        let key = KeychainService.apiTokenKey(for: accountId)

        // Then
        XCTAssertEqual(key, "apiToken_\(accountId.uuidString)")
    }

    func testSaveAndLoadCodable() throws {
        // Given - a Codable struct to round-trip
        struct TestCredential: Codable, Equatable {
            let username: String
            let token: String
            let expiresAt: Date
        }

        let credential = TestCredential(
            username: "testuser",
            token: "secret_token_123",
            expiresAt: Date(timeIntervalSince1970: 1704067200) // Fixed date for reproducibility
        )

        // When
        try KeychainService.save(credential, forKey: testKey)
        let loadedCredential: TestCredential? = try KeychainService.load(forKey: testKey)

        // Then
        XCTAssertEqual(loadedCredential, credential)
    }

    func testSaveAndLoadCodableArray() throws {
        // Given - an array of dictionaries (similar to cookie props storage)
        let cookieProps: [[String: String]] = [
            ["name": "session", "value": "abc123", "domain": "example.com"],
            ["name": "auth", "value": "xyz789", "domain": "example.com"]
        ]

        // When
        try KeychainService.save(cookieProps, forKey: testKey)
        let loadedProps: [[String: String]]? = try KeychainService.load(forKey: testKey)

        // Then
        XCTAssertEqual(loadedProps, cookieProps)
    }
}
