import Foundation

public final class CredentialPool {
    public struct CredentialEntry {
        public let providerID: String
        public let apiKey: String?
        public let isEnabled: Bool
        public let disabledAt: Date?

        public init(providerID: String, apiKey: String?, isEnabled: Bool = true, disabledAt: Date? = nil) {
            self.providerID = providerID
            self.apiKey = apiKey
            self.isEnabled = isEnabled
            self.disabledAt = disabledAt
        }
    }

    private var credentialsByProviderID: [String: CredentialEntry] = [:]

    public init() {}

    public func load(credentials: [String: CredentialEntry]) {
        credentialsByProviderID = credentials
    }

    public func credential(forProviderID providerID: String) -> CredentialEntry? {
        credentialsByProviderID[providerID]
    }

    public func activeAPIKey(forProviderID providerID: String) -> String? {
        guard let entry = credentialsByProviderID[providerID], entry.isEnabled else { return nil }
        return entry.apiKey
    }

    public func isEnabled(providerID: String) -> Bool {
        credentialsByProviderID[providerID]?.isEnabled ?? false
    }

    public func allActiveCredentials() -> [String: CredentialEntry] {
        credentialsByProviderID.filter { $0.value.isEnabled }
    }

    public func disable(providerID: String, at date: Date = Date()) {
        guard let entry = credentialsByProviderID[providerID] else { return }
        credentialsByProviderID[providerID] = CredentialEntry(
            providerID: entry.providerID,
            apiKey: entry.apiKey,
            isEnabled: false,
            disabledAt: date
        )
    }

    public func reenable(providerID: String) {
        guard let entry = credentialsByProviderID[providerID] else { return }
        credentialsByProviderID[providerID] = CredentialEntry(
            providerID: entry.providerID,
            apiKey: entry.apiKey,
            isEnabled: true,
            disabledAt: nil
        )
    }
}
