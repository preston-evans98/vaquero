import Foundation
import Security
import VaqueroKit

/// Where the control service is. The address lives in user defaults and the token in the Keychain.
/// For development, `VAQUERO_URL` and `VAQUERO_TOKEN` in the environment override both.
public struct ServerSettings: Equatable, Sendable {
    public var url: String
    public var token: String

    public init(url: String, token: String) {
        self.url = url
        self.token = token
    }

    public var client: Client? {
        guard let base = URL(string: url), base.scheme != nil, !token.isEmpty else { return nil }
        return Client(baseURL: base, token: token)
    }

    public static func load() -> ServerSettings {
        let environment = ProcessInfo.processInfo.environment
        return ServerSettings(
            url: environment["VAQUERO_URL"] ?? UserDefaults.standard.string(forKey: urlKey) ?? "http://127.0.0.1:8080",
            token: environment["VAQUERO_TOKEN"] ?? Keychain.read() ?? ""
        )
    }

    public func save() {
        UserDefaults.standard.set(url, forKey: Self.urlKey)
        Keychain.write(token)
    }

    private static let urlKey = "serverURL"
}

private enum Keychain {
    static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "vaquero",
            kSecAttrAccount as String: "token",
        ]
    }

    static func read() -> String? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func write(_ token: String) {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
