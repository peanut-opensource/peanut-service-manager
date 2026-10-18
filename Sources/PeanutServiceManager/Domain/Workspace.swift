import Foundation
import Darwin

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
    var host: String? = nil
    var domains: [String]? = nil
    var port: Int? = nil

    var hasValidBindingHost: Bool {
        guard let host = AccessAddress.nonempty(host) else { return true }
        return AccessAddress.isIPAddress(host)
    }

    var hasValidAccessDomains: Bool {
        (domains ?? []).allSatisfy { domain in
            guard let domain = AccessAddress.nonempty(domain) else { return false }
            return AccessAddress.url(address: domain) != nil
        }
    }

    var accessURLs: [URL] {
        let domains = AccessAddress.normalizedDomains(domains ?? [])
        if !domains.isEmpty {
            var seen = Set<URL>()
            return domains.compactMap { domain in
                AccessAddress.url(address: domain, port: domain.contains("://") ? nil : port)
            }.filter { seen.insert($0).inserted }
        }
        guard let address = bindingAccessAddress,
              let url = AccessAddress.url(address: address, port: port) else { return [] }
        return [url]
    }

    private var bindingAccessAddress: String? {
        guard let host = AccessAddress.nonempty(host) else { return port == nil ? nil : "127.0.0.1" }
        switch host {
        case "0.0.0.0": return "127.0.0.1"
        case "::", "[::]": return "::1"
        default: return host
        }
    }
}

enum AccessAddress {
    static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func normalizedDomains(_ domains: [String]) -> [String] {
        var seen = Set<String>()
        return domains.compactMap(nonempty).filter { seen.insert($0).inserted }
    }

    static func isIPAddress(_ address: String) -> Bool {
        guard !address.utf8.contains(0) else { return false }
        let bracketed = address.hasPrefix("[") && address.hasSuffix("]")
        let address = bracketed ? String(address.dropFirst().dropLast()) : address
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return address.withCString { (!bracketed && inet_pton(AF_INET, $0, &ipv4) == 1) || inet_pton(AF_INET6, $0, &ipv6) == 1 }
    }

    static func url(address: String, port: Int? = nil) -> URL? {
        var address = address
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
