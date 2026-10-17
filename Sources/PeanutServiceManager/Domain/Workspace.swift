import Foundation

struct Workspace: Codable, Equatable {
    var projects: [Project] = []
    var environments: [WorkspaceEnvironment] = []
    var resources: [ResourceRecord] = []
    var bindings: [ProjectEnvironmentBinding] = []

    private enum CodingKeys: String, CodingKey { case projects, environments, resources, bindings }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        resources = try container.decodeIfPresent([ResourceRecord].self, forKey: .resources) ?? []
        bindings = try container.decodeIfPresent([ProjectEnvironmentBinding].self, forKey: .bindings) ?? []
        if let catalog = try container.decodeIfPresent([WorkspaceEnvironment].self, forKey: .environments) {
            environments = catalog
        } else {
            var seen = Set<UUID>()
            environments = projects.flatMap(\.environments).compactMap { projectEnvironment in
                guard seen.insert(projectEnvironment.id).inserted else { return nil }
                return WorkspaceEnvironment(id: projectEnvironment.id, name: projectEnvironment.name)
            }
        }
    }
}

struct WorkspaceEnvironment: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
}

struct Project: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var environments: [ProjectEnvironment] = []
}

struct ProjectEnvironment: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var services: [Service] = []
    var groups: [ServiceGroup] = []
}

struct Service: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var description: String = ""
    var workingDirectory: String
    var command: String
    var arguments: [String] = []
    var environment: [String: String] = [:]
    var runtimeResourceID: UUID?
    var startsWithManager: Bool = false
    var domain: String? = nil
    var port: Int? = nil
}

struct ServiceGroup: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var serviceIDs: Set<UUID> = []
}

struct ServiceTarget: Hashable {
    let projectID: UUID
    let environmentID: UUID
    let serviceID: UUID
}

enum ServiceRunState: Equatable {
    case stopped
    case starting
    case running(pid: Int32)
    case stopping(pid: Int32)
    case exited(code: Int32)
    case failed(reason: String)
}

enum ServiceSelection {
    static func uniqueServices(_ services: [Service]) -> [Service] {
        var seen = Set<UUID>()
        return services.filter { seen.insert($0.id).inserted }
    }
}
