import Foundation

struct KeychainService {
    private static let defaults = UserDefaults.standard

    static func save(_ value: String, account: String) throws {
        defaults.set(value, forKey: account)
    }

    static func load(account: String) throws -> String {
        guard let value = defaults.string(forKey: account), !value.isEmpty else {
            throw AdminError.missingKey
        }
        return value
    }

    static func delete(account: String) {
        defaults.removeObject(forKey: account)
    }
}
