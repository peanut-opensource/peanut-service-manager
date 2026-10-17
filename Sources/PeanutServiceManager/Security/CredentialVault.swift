import Foundation
import Security

/// Stores resource credentials in the user's macOS Keychain.
public struct CredentialVault {
    private let service: String

    public init(service: String = "PeanutServiceManager.resource-credentials") {
        self.service = service
    }

    public enum VaultError: Error, LocalizedError {
        case invalidCredentialReference
        case bindingMismatch
        case keychain(operation: String, status: OSStatus)

        public var errorDescription: String? {
            switch self {
            case .invalidCredentialReference:
                return "The resource has no valid credential reference."
            case .bindingMismatch:
                return "Credential access requires a matching resource, project, and environment binding."
            case let .keychain(operation, status):
                return "Keychain operation \(operation) failed (OSStatus \(status))."
            }
        }
    }

    /// Adds a secret under the resource's opaque credential reference.
    public func add(_ secret: Data, for resource: ResourceRecord) throws {
        let account = try credentialAccount(for: resource)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = secret
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VaultError.keychain(operation: "add", status: status)
        }
    }

    /// Replaces the secret stored under the resource's opaque credential reference.
    public func update(_ secret: Data, for resource: ResourceRecord) throws {
        let account = try credentialAccount(for: resource)
        let query = baseQuery(account: account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: secret] as CFDictionary)
        guard status == errSecSuccess else {
            throw VaultError.keychain(operation: "update", status: status)
        }
    }

    /// Deletes the secret stored under the resource's opaque credential reference.
    public func delete(for resource: ResourceRecord) throws {
        let account = try credentialAccount(for: resource)
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess else {
            throw VaultError.keychain(operation: "delete", status: status)
        }
    }

    /// Reads a secret only after verifying the complete project/environment binding.
    public func read(
        for resource: ResourceRecord,
        binding: ProjectEnvironmentBinding,
        projectID: UUID,
        environmentID: UUID
    ) throws -> Data? {
        guard resource.id == binding.resourceID,
              binding.projectID == projectID,
              binding.environmentID == environmentID else {
            throw VaultError.bindingMismatch
        }

        let account = try credentialAccount(for: resource)
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw VaultError.keychain(operation: "read", status: status)
        }
        guard let data = result as? Data else {
            throw VaultError.keychain(operation: "read", status: errSecDecode)
        }
        return data
    }

    private func credentialAccount(for resource: ResourceRecord) throws -> String {
        guard let reference = resource.credentialReference, !reference.isEmpty else {
            throw VaultError.invalidCredentialReference
        }
        return reference
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
