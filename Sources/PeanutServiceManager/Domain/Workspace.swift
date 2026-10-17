import Foundation

struct Workspace: Codable, Equatable {
    var projects: [Project] = []
    var resources: [ResourceRecord] = []
    var bindings: [ProjectEnvironmentBinding] = []
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
