import Foundation
import Security

protocol CloudSessionTokenStore {
    func loadTokens() -> CloudSessionTokensDTO?
    func saveTokens(_ tokens: CloudSessionTokensDTO)
    func clearTokens()
}

final class KeychainCloudSessionTokenStore: CloudSessionTokenStore {
    static let shared = KeychainCloudSessionTokenStore()

    private let service = (Bundle.main.bundleIdentifier ?? "SuggestMeSome") + ".cloud-session"
    private let account = "primary-account"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadTokens() -> CloudSessionTokensDTO? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let tokens = try? decoder.decode(CloudSessionTokensDTO.self, from: data) else {
            return nil
        }
        return tokens
    }

    func saveTokens(_ tokens: CloudSessionTokensDTO) {
        guard let data = try? encoder.encode(tokens) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard updateStatus != errSecSuccess else { return }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func clearTokens() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class InMemoryCloudSessionTokenStore: CloudSessionTokenStore {
    private var tokens: CloudSessionTokensDTO?

    init(tokens: CloudSessionTokensDTO? = nil) {
        self.tokens = tokens
    }

    func loadTokens() -> CloudSessionTokensDTO? {
        tokens
    }

    func saveTokens(_ tokens: CloudSessionTokensDTO) {
        self.tokens = tokens
    }

    func clearTokens() {
        tokens = nil
    }
}
