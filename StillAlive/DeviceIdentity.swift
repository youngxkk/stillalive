import Foundation
import Security

/// Device credentials used to authenticate with the backend.
/// Stored in the Keychain so they survive app reinstalls and the server record stays owned by this device.
enum DeviceIdentity {
    private static let service = "com.superaistorm.StillAlive.device"
    private static let idAccount = "deviceId"
    private static let secretAccount = "deviceSecret"

    static var deviceId: String {
        loadOrCreate(account: idAccount) { UUID().uuidString.lowercased() }
    }

    static var deviceSecret: String {
        loadOrCreate(account: secretAccount) { randomHex(bytes: 32) }
    }

    private static func loadOrCreate(account: String, make: () -> String) -> String {
        if let existing = load(account: account) {
            return existing
        }
        let value = make()
        save(value, account: account)
        return value
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            print("Keychain save failed: \(status)")
        }
    }

    private static func randomHex(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            // Fall back to UUIDs if the system RNG is unavailable
            return (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
