import Foundation

/// Reads a secret from the Keychain once per launch and keeps it in memory.
///
/// Every Keychain read from an ad-hoc signed build triggers its own
/// authorization prompt, because the signature changes with each rebuild and no
/// stored ACL matches it. Reading the key per HTTP request therefore meant one
/// password prompt per request. The value is held only for the process lifetime
/// and never written anywhere.
public actor CachedCredential {
    private let load: @Sendable () async throws -> String?

    private var cached: String?
    private var hasLoaded = false

    public init(load: @escaping @Sendable () async throws -> String?) {
        self.load = load
    }

    public init(keychain: KeychainStore, key: KeychainStore.CredentialKey) {
        self.init { try await keychain.secret(for: key) }
    }

    public func value() async throws -> String? {
        if hasLoaded { return cached }

        let loaded = try await load()
        cached = loaded
        hasLoaded = true
        return loaded
    }

    /// Call after the credential is changed or removed, so the next read is fresh.
    public func invalidate() {
        cached = nil
        hasLoaded = false
    }
}
