import Foundation

struct LocalConfigurationFile: Codable {
    var formatVersion = 2
    var workspace: Workspace
    /// Export files intentionally contain readable passwords keyed by stable resource ID.
    var passwords: [String: String]

    struct Imported {
        var workspace: Workspace
        var passwords: [UUID: Data]
    }

    static func make(workspace: Workspace, vault: CredentialVault) throws -> LocalConfigurationFile {
        var passwords: [String: String] = [:]
        var exportedWorkspace = workspace
        for resource in workspace.resources {
            guard resource.credentialReference != nil else { continue }
            guard let bytes = try vault.readLocally(for: resource), let password = String(data: bytes, encoding: .utf8) else {
                throw LocalConfigurationError.invalidWorkspace
            }
            passwords[resource.id.uuidString] = password
        }
        for index in exportedWorkspace.resources.indices { exportedWorkspace.resources[index].credentialReference = nil }
        try validateWorkspace(exportedWorkspace)
        return LocalConfigurationFile(workspace: exportedWorkspace, passwords: passwords)
    }

    static func decode(_ data: Data) throws -> Imported {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = root["formatVersion"] as? Int else { throw LocalConfigurationError.invalidFormat }
        if version == 2 {
            guard let file = try? JSONDecoder().decode(LocalConfigurationFile.self, from: data) else { throw LocalConfigurationError.invalidFormat }
            try validateWorkspace(file.workspace)
            var passwords: [UUID: Data] = [:]
            for (key, value) in file.passwords {
                guard let id = UUID(uuidString: key), file.workspace.resources.contains(where: { $0.id == id }), passwords[id] == nil else {
                    throw LocalConfigurationError.invalidWorkspace
                }
                passwords[id] = Data(value.utf8)
            }
            return Imported(workspace: file.workspace, passwords: passwords)
        }
        if version == 1 {
            let legacy: LegacyConfigurationFile
            do { legacy = try JSONDecoder().decode(LegacyConfigurationFile.self, from: data) }
            catch { throw LocalConfigurationError.invalidFormat }
            try validateWorkspace(legacy.workspace)
            let references = Set(legacy.workspace.resources.compactMap(\.credentialReference))
            guard references.count == legacy.workspace.resources.compactMap(\.credentialReference).count,
                  legacy.workspace.resources.allSatisfy({ $0.credentialReference?.isEmpty != true }) else { throw LocalConfigurationError.invalidWorkspace }
            try CredentialVault().validate(legacy.credentials, credentialReferences: references)
            var passwords: [UUID: Data] = [:]
            for resource in legacy.workspace.resources {
                guard let reference = resource.credentialReference, let encrypted = legacy.credentials.secrets[reference] else { continue }
                passwords[resource.id] = try WorkspaceCipher.decryptCredential(encrypted, key: legacy.credentials.encryptionKey)
            }
            return Imported(workspace: legacy.workspace, passwords: passwords)
        }
        throw LocalConfigurationError.unsupportedVersion
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    private static func validateWorkspace(_ workspace: Workspace) throws {
        let projectIDs = workspace.projects.map(\.id), environmentIDs = workspace.environments.map(\.id)
        let projectEnvironmentIDs = workspace.projects.flatMap(\.environments).map(\.id)
        let serviceIDs = workspace.projects.flatMap(\.environments).flatMap(\.services).map(\.id)
        let resources = workspace.resources, resourceIDs = resources.map(\.id)
        guard unique(projectIDs), unique(environmentIDs), workspace.projects.allSatisfy({ unique($0.environments.map(\.id)) }),
              projectEnvironmentIDs.allSatisfy(Set(environmentIDs).contains), unique(serviceIDs), unique(resourceIDs) else {
            throw LocalConfigurationError.invalidWorkspace
        }
        let projectEnvironmentKeys = Set(workspace.projects.flatMap { project in project.environments.map { "\(project.id.uuidString):\($0.id.uuidString)" } })
        for project in workspace.projects {
            for environment in project.environments {
            let serviceIDs = Set(environment.services.map(\.id))
            guard environment.groups.allSatisfy({ Set($0.serviceIDs).isSubset(of: serviceIDs) }) else { throw LocalConfigurationError.invalidWorkspace }
            let boundIDs = Set(workspace.bindings.filter { $0.projectID == project.id && $0.environmentID == environment.id }.map(\.resourceID))
            guard environment.services.allSatisfy({ Set($0.resourceIDs).isSubset(of: boundIDs) }) else { throw LocalConfigurationError.invalidWorkspace }
            }
        }
        let resourceIDSet = Set(resourceIDs)
        let services = workspace.projects.flatMap(\.environments).flatMap(\.services)
        guard services.compactMap(\.runtimeResourceID).allSatisfy(resourceIDSet.contains),
              services.flatMap(\.resourceIDs).allSatisfy(resourceIDSet.contains),
              services.allSatisfy({ unique($0.resourceIDs) }),
              workspace.bindings.allSatisfy({ projectEnvironmentKeys.contains("\($0.projectID.uuidString):\($0.environmentID.uuidString)") && resourceIDSet.contains($0.resourceID) }) else {
            throw LocalConfigurationError.invalidWorkspace
        }
        let bindingKeys = workspace.bindings.map { "\($0.projectID.uuidString):\($0.environmentID.uuidString):\($0.resourceID.uuidString)" }
        guard unique(bindingKeys) else { throw LocalConfigurationError.invalidWorkspace }
    }

    private static func unique<T: Hashable>(_ values: [T]) -> Bool { Set(values).count == values.count }
}

private struct LegacyConfigurationFile: Decodable {
    var formatVersion: Int
    var workspace: Workspace
    var credentials: CredentialVault.StoreFile
}

private enum LocalConfigurationError: LocalizedError {
    case invalidFormat, unsupportedVersion, invalidWorkspace
    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "配置文件不是有效的花生服务管理器 JSON 文件，当前配置未更改。"
        case .unsupportedVersion: return "配置文件版本不受支持，当前配置未更改。"
        case .invalidWorkspace: return "配置文件中的项目、服务或资源关联无效，当前配置未更改。"
        }
    }
}
