import Foundation

/// On-disk descriptor that identifies a vault. Persisted to
/// `<container>/.meta/vault.json` and treated as the authoritative source of the
/// vault id. `UserDefaults(SNVaultId)` is only a fast cache of the same value.
///
/// Before this existed the vault id was minted fresh on every cold launch, which
/// stranded the Keychain key (keyed by vault id) and dropped every encrypted note
/// to "locked". See P0-1.
nonisolated struct VaultDescriptor: Codable, Equatable {
    let vaultId: String
    let createdAt: Date
    var schemaVersion: Int
}

@MainActor
final class VaultIdentityStore {
    static let vaultIdDefaultsKey = "SNVaultId"
    static let currentSchemaVersion = 1
    private static let metaDirName = ".meta"
    private static let descriptorFileName = "vault.json"

    private let defaults: UserDefaults
    private let keyStore: KeyStore

    init(defaults: UserDefaults = .standard, keyStore: KeyStore = KeychainStore.shared) {
        self.defaults = defaults
        self.keyStore = keyStore
    }

    /// Resolve the stable vault id. Called from `VaultStore.initialize()` once the
    /// note index has loaded. Resolution order:
    /// 1. `vault.json` is authoritative. If the Keychain key lives under a stale id
    ///    (cache disagreement), migrate it to the descriptor id (iOS only).
    /// 2. No descriptor but a cached id in UserDefaults → adopt it and write a descriptor.
    /// 3. iOS only, when encrypted data exists: adopt a legacy Keychain account whose
    ///    key decrypts an existing encrypted note (`validate`). Non-validating
    ///    candidates are left untouched as inert orphans.
    /// 4. Nothing to go on → mint a fresh UUID and persist it.
    func resolveVaultId(containerURL: URL?, index: NoteIndex, validate: (String) -> Bool) -> String {
        if let descriptor = loadDescriptor(containerURL: containerURL) {
            reconcileKeychain(to: descriptor.vaultId)
            defaults.set(descriptor.vaultId, forKey: Self.vaultIdDefaultsKey)
            return descriptor.vaultId
        }

        if let cached = defaults.string(forKey: Self.vaultIdDefaultsKey), !cached.isEmpty {
            persist(vaultId: cached, containerURL: containerURL)
            return cached
        }

        #if os(iOS)
        let hasEncryptedData = index.entries.contains { $0.mode == .encrypted }
        if hasEncryptedData {
            for candidate in keyStore.allVaultIdCandidates() where validate(candidate) {
                persist(vaultId: candidate, containerURL: containerURL)
                return candidate
            }
        }
        #endif

        let fresh = UUID().uuidString
        persist(vaultId: fresh, containerURL: containerURL)
        return fresh
    }

    // MARK: - Persistence

    private func persist(vaultId: String, containerURL: URL?) {
        defaults.set(vaultId, forKey: Self.vaultIdDefaultsKey)
        writeDescriptor(
            VaultDescriptor(vaultId: vaultId, createdAt: Date(), schemaVersion: Self.currentSchemaVersion),
            containerURL: containerURL
        )
    }

    private func descriptorURL(containerURL: URL?) -> URL? {
        containerURL?
            .appendingPathComponent(Self.metaDirName)
            .appendingPathComponent(Self.descriptorFileName)
    }

    private func loadDescriptor(containerURL: URL?) -> VaultDescriptor? {
        guard let url = descriptorURL(containerURL: containerURL),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder.default.decode(VaultDescriptor.self, from: data)
    }

    private func writeDescriptor(_ descriptor: VaultDescriptor, containerURL: URL?) {
        guard let url = descriptorURL(containerURL: containerURL) else { return }
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if let data = try? JSONEncoder.default.encode(descriptor) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Keychain reconciliation (iOS)

    /// When `vault.json` names an id the Keychain key is not stored under, move the
    /// key from the stale cached id to the descriptor id so decryption keeps working.
    private func reconcileKeychain(to descriptorId: String) {
        #if os(iOS)
        guard !keyStore.hasKey(forVaultId: descriptorId) else { return }
        guard let stale = defaults.string(forKey: Self.vaultIdDefaultsKey),
              stale != descriptorId,
              keyStore.hasKey(forVaultId: stale),
              let material = try? keyStore.loadKey(forVaultId: stale) else {
            return
        }
        do {
            try keyStore.saveKey(
                material,
                forVaultId: descriptorId,
                keyId: keyStore.loadKeyId(forVaultId: stale),
                keyFingerprint: keyStore.loadKeyFingerprint(forVaultId: stale)
            )
            try keyStore.deleteKey(forVaultId: stale)
        } catch {
            // Leave the stale entry intact on failure; no data is lost — the user
            // can re-import the key. Never delete before a confirmed copy.
        }
        #endif
    }
}
