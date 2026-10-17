import Foundation

struct LocalConfigurationFile: Codable {
    var formatVersion = 1
    var workspace: Workspace
    var credentials: CredentialVault.StoreFile

    static func decode(_ data: Data) throws -> LocalConfigurationFile {
        let file: LocalConfigurationFile
        do { file = try JSONDecoder().decode(LocalConfigurationFile.self, from: data) }
        catch { throw LocalConfigurationError.invalidFormat }
        guard file.formatVersion == 1 else { throw LocalConfigurationError.unsupportedVersion }
        try file.validateWorkspace()
        let references = Set(file.workspace.resources.compactMap(\.credentialReference))
        guard references.count == file.workspace.resources.compactMap(\.credentialReference).count,
              file.workspace.resources.allSatisfy({ $0.credentialReference?.isEmpty != true }) else {
            throw LocalConfigurationError.invalidWorkspace
        }
        try CredentialVault().validate(file.credentials, credentialReferences: references)
        return file
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    private func validateWorkspace() throws {
        let projectIDs = workspace.projects.map(\.id)
        let environmentIDs = workspace.environments.map(\.id)
        let projectEnvironmentIDs = workspace.projects.flatMap(\.environments).map(\.id)
        let serviceIDs = workspace.projects.flatMap(\.environments).flatMap(\.services).map(\.id)
        let resources = workspace.resources
        let resourceIDs = resources.map(\.id)
        guard Self.hasUniqueValues(projectIDs), Self.hasUniqueValues(environmentIDs),
              workspace.projects.allSatisfy({ Self.hasUniqueValues($0.environments.map(\.id)) }),
              projectEnvironmentIDs.allSatisfy(Set(environmentIDs).contains),
              Self.hasUniqueValues(serviceIDs), Self.hasUniqueValues(resourceIDs) else {
            throw LocalConfigurationError.invalidWorkspace
        }

        let projectEnvironmentKeys = Set(workspace.projects.flatMap { project in
            project.environments.map { "\(project.id.uuidString):\($0.id.uuidString)" }
        })
        for environment in workspace.projects.flatMap(\.environments) {
            let localServiceIDs = Set(environment.services.map(\.id))
            guard environment.groups.allSatisfy({ Set($0.serviceIDs).isSubset(of: localServiceIDs) }) else {
                throw LocalConfigurationError.invalidWorkspace
            }
        }
        let resourceIDSet = Set(resourceIDs)
        guard workspace.projects.flatMap(\.environments).flatMap(\.services)
            .compactMap(\.runtimeResourceID).allSatisfy(resourceIDSet.contains) else {
            throw LocalConfigurationError.invalidWorkspace
        }
        guard workspace.bindings.allSatisfy({ binding in
            projectEnvironmentKeys.contains("\(binding.projectID.uuidString):\(binding.environmentID.uuidString)")
                && resourceIDSet.contains(binding.resourceID)
        }) else { throw LocalConfigurationError.invalidWorkspace }
        let bindingKeys = workspace.bindings.map {
            "\($0.projectID.uuidString):\($0.environmentID.uuidString):\($0.resourceID.uuidString)"
        }
        guard Self.hasUniqueValues(bindingKeys) else { throw LocalConfigurationError.invalidWorkspace }
    }

    private static func hasUniqueValues<Value: Hashable>(_ values: [Value]) -> Bool {
        Set(values).count == values.count
    }
}

private enum LocalConfigurationError: LocalizedError {
    case invalidFormat
    case unsupportedVersion
    case invalidWorkspace

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "配置文件不是有效的花生服务管理器 JSON 文件，当前配置未更改。"
        case .unsupportedVersion: return "配置文件版本不受支持，当前配置未更改。"
        case .invalidWorkspace: return "配置文件中的项目、服务或资源关联无效，当前配置未更改。"
        }
    }
}
