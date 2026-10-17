import CryptoKit
import Foundation

/// Stores only encrypted resource secrets in the local application-support folder.
public struct CredentialVault {
    struct StoreFile: Codable, Equatable {
        var formatVersion = 1
        var encryptionKey: String
        var secrets: [String: Data] = [:]
    }

    public init() { }

    public enum VaultError: Error, LocalizedError {
        case invalidCredentialReference
        case bindingMismatch
        case credentialAlreadyExists
        case invalidEncryptionKey
        case unsupportedStoreVersion
        case configurationMissingCredentials

        public var errorDescription: String? {
            switch self {
            case .invalidCredentialReference: return "资源没有有效的凭据引用。"
            case .bindingMismatch: return "读取密码时必须匹配资源、项目和环境绑定。"
            case .credentialAlreadyExists: return "该资源密码已存在，请使用更新操作修改。"
            case .invalidEncryptionKey: return "加密 key 不能为空。"
            case .unsupportedStoreVersion: return "本机密码文件版本不受支持，原文件已保留。"
            case .configurationMissingCredentials: return "配置文件缺少已登记资源对应的加密密码。"
            }
        }
    }

    public func encryptionKey() throws -> String {
        try loadStore().encryptionKey
    }

    func exportedConfiguration() throws -> StoreFile { try loadStore() }

    func validate(_ configuration: StoreFile, credentialReferences: Set<String>) throws {
        guard configuration.formatVersion == 1 else { throw VaultError.unsupportedStoreVersion }
        guard !configuration.encryptionKey.isEmpty else { throw VaultError.invalidEncryptionKey }
        guard credentialReferences.isSubset(of: Set(configuration.secrets.keys)) else {
            throw VaultError.configurationMissingCredentials
        }
        for encrypted in configuration.secrets.values {
            _ = try WorkspaceCipher.decryptCredential(encrypted, key: configuration.encryptionKey)
        }
    }

    func replaceConfiguration(with configuration: StoreFile) throws { try save(configuration) }

    /// The key itself is intentionally stored as readable local configuration.
    public func setEncryptionKey(_ newKey: String) throws {
        guard !newKey.isEmpty else { throw VaultError.invalidEncryptionKey }
        let current = try loadStore()
        guard newKey != current.encryptionKey else { return }
        var next = StoreFile(formatVersion: current.formatVersion, encryptionKey: newKey)
        for (reference, encrypted) in current.secrets {
            let plaintext = try WorkspaceCipher.decryptCredential(encrypted, key: current.encryptionKey)
            next.secrets[reference] = try WorkspaceCipher.encryptCredential(plaintext, key: newKey)
        }
        try save(next)
    }

    public func add(_ secret: Data, for resource: ResourceRecord) throws {
        let reference = try credentialReference(for: resource)
        var store = try loadStore()
        guard store.secrets[reference] == nil else { throw VaultError.credentialAlreadyExists }
        store.secrets[reference] = try WorkspaceCipher.encryptCredential(secret, key: store.encryptionKey)
        try save(store)
    }

    public func update(_ secret: Data, for resource: ResourceRecord) throws {
        let reference = try credentialReference(for: resource)
        var store = try loadStore()
        store.secrets[reference] = try WorkspaceCipher.encryptCredential(secret, key: store.encryptionKey)
        try save(store)
    }

    public func delete(for resource: ResourceRecord) throws {
        let reference = try credentialReference(for: resource)
        var store = try loadStore()
        store.secrets.removeValue(forKey: reference)
        try save(store)
    }

    public func read(
        for resource: ResourceRecord,
        binding: ProjectEnvironmentBinding,
        projectID: UUID,
        environmentID: UUID
    ) throws -> Data? {
        guard resource.id == binding.resourceID,
              binding.projectID == projectID,
              binding.environmentID == environmentID else { throw VaultError.bindingMismatch }
        guard let reference = resource.credentialReference else { throw VaultError.invalidCredentialReference }
        return try read(reference: reference)
    }

    private func read(reference: String) throws -> Data? {
        let store = try loadStore()
        guard let encrypted = store.secrets[reference] else { return nil }
        return try WorkspaceCipher.decryptCredential(encrypted, key: store.encryptionKey)
    }

    private func credentialReference(for resource: ResourceRecord) throws -> String {
        guard let reference = resource.credentialReference, !reference.isEmpty else {
            throw VaultError.invalidCredentialReference
        }
        return reference
    }

    private func loadStore() throws -> StoreFile {
        let url = storeURL
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: storeDirectory.path)
        if FileManager.default.fileExists(atPath: url.path) {
            let store = try JSONDecoder().decode(StoreFile.self, from: Data(contentsOf: url))
            guard store.formatVersion == 1 else { throw VaultError.unsupportedStoreVersion }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return store
        }
        let store = StoreFile(encryptionKey: "123456")
        try save(store)
        return store
    }

    private func save(_ store: StoreFile) throws {
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: storeDirectory.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try WorkspaceCipher.writeSecurely(encoder.encode(store), to: storeURL)
    }

    private var storeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("PeanutServiceManager", isDirectory: true)
    }

    private var storeURL: URL { storeDirectory.appendingPathComponent("credential-store.json") }

}
