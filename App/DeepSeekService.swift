import Foundation
import Security

enum DailyRecapPreferences {
    static let consentKey = "deepseek.allowRecapAdvice"
    static let promptKey = "deepseek.recapPrompt"
}

enum DeepSeekKey {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "app.foodfit") + ".deepseek",
         kSecAttrAccount as String: "api-key"]
    }

    static func load() throws -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let result = SecItemCopyMatching(lookup as CFDictionary, &item)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { throw KeyIssue.unavailable }
        return key
    }

    static func save(_ text: String) throws {
        let key = text.trimmed
        guard !key.isEmpty, key.utf8.count <= 512,
              key.utf8.allSatisfy({ (33...126).contains($0) }) else { throw KeyIssue.invalid }
        let values: [String: Any] = [kSecValueData as String: Data(key.utf8),
                                     kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(values) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw KeyIssue.unavailable }
        } else if status != errSecSuccess {
            throw KeyIssue.unavailable
        }
    }

    static func remove() throws {
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw KeyIssue.unavailable }
    }

    private enum KeyIssue: LocalizedError {
        case invalid, unavailable

        var errorDescription: String? {
            switch self {
            case .invalid: "请粘贴有效的 API Key。"
            case .unavailable: "设备钥匙串暂时不可用，请解锁后重试。"
            }
        }
    }
}

enum DeepSeekService {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForResource = 50
        return URLSession(configuration: config, delegate: StopRedirects(), delegateQueue: nil)
    }()

    private final class StopRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static func estimate(notes: String, photo: Data?, referencePhotos: [Data]) async throws -> CalorieEstimate {
        let request = try DeepSeekRequest.make(key: key(), notes: notes, photo: photo, referencePhotos: referencePhotos)
        let (data, status) = try await send(request)
        return try DeepSeekRequest.decode(data, status: status)
    }

    static func recap(_ input: DailyRecapInput, prompt: String) async throws -> String {
        let request = try DeepSeekRequest.makeRecap(key: key(), input: input, prompt: prompt)
        let (data, status) = try await send(request)
        return try DeepSeekRequest.decodeRecap(data, status: status)
    }

    static func checkConnection() async throws {
        let (data, status) = try await send(DeepSeekRequest.makeConnectionCheck(key: key()))
        try DeepSeekRequest.checkConnection(data, status: status)
    }

    private static func key() throws -> String {
        guard let key = try DeepSeekKey.load() else { throw DeepSeekIssue.noKey }
        return key
    }

    private static func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw DeepSeekIssue.unavailable }
            return (data, http.statusCode)
        } catch let error as URLError {
            try Task.checkCancellation()
            throw error.code == .timedOut ? DeepSeekIssue.timedOut : DeepSeekIssue.unavailable
        }
    }
}
