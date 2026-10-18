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

    var accessURL: URL? {
        var address = domain?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !address.isEmpty || port != nil else { return nil }
        if address.isEmpty { address = "127.0.0.1" }
        if !address.contains("://") {
            if address.filter({ $0 == ":" }).count > 1 && !address.hasPrefix("[") && !address.contains("/") {
                address = "[\(address)]"
            }
            address = "http://" + address
        }
        guard var components = URLComponents(string: address),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              !host.contains(where: { $0.isWhitespace }),
              components.user == nil, components.password == nil else { return nil }
        components.scheme = scheme
        if let port {
            guard (1...65535).contains(port) else { return nil }
            components.port = port
        }
        if let port = components.port, !(1...65535).contains(port) { return nil }
        return components.url
    }

    var accessAddress: String? {
        if let accessURL { return accessURL.absoluteString }
        let address = domain?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return address.isEmpty ? nil : address
    }
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
