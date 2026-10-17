import Foundation

/// A reference to an existing runtime, tool, service, or container.
/// Secrets are stored elsewhere; `credentialReference` is only an opaque lookup key.
public struct ResourceRecord: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var type: ResourceType
    public var version: String?
    public var source: String?
    public var purpose: String?
    public var notes: String?

    /// Set for locally installed runtimes and tools such as PHP or Node.js.
    public var executablePath: String?

    /// Set for network resources using a host and port.
    public var host: String?
    public var port: Int?
    public var database: String?
    public var username: String?
    public var credentialReference: String?

    /// Docker identity fields are descriptive only; they do not imply lifecycle control.
    public var dockerContext: String?
    public var containerID: String?
    public var containerName: String?

    public init(
        id: UUID = UUID(),
        name: String,
        type: ResourceType,
        version: String? = nil,
        source: String? = nil,
        purpose: String? = nil,
        notes: String? = nil,
        executablePath: String? = nil,
        host: String? = nil,
        port: Int? = nil,
        database: String? = nil,
        username: String? = nil,
        credentialReference: String? = nil,
        dockerContext: String? = nil,
        containerID: String? = nil,
        containerName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.version = version
        self.source = source
        self.purpose = purpose
        self.notes = notes
        self.executablePath = executablePath
        self.host = host
        self.port = port
        self.database = database
        self.username = username
        self.credentialReference = credentialReference
        self.dockerContext = dockerContext
        self.containerID = containerID
        self.containerName = containerName
    }
}

public enum ResourceType: String, Codable, CaseIterable, Hashable {
    case mysql
    case redis
    case php
    case node
    case other
    case dockerContainer
}

/// Associates a reusable resource with one project's environment.
public struct ProjectEnvironmentBinding: Codable, Identifiable, Hashable {
    public var projectID: UUID
    public var environmentID: UUID
    public var resourceID: UUID
    public var purpose: String?

    public var id: BindingID {
        BindingID(projectID: projectID, environmentID: environmentID, resourceID: resourceID)
    }

    public init(projectID: UUID, environmentID: UUID, resourceID: UUID, purpose: String? = nil) {
        self.projectID = projectID
        self.environmentID = environmentID
        self.resourceID = resourceID
        self.purpose = purpose
    }

    public struct BindingID: Codable, Hashable {
        public var projectID: UUID
        public var environmentID: UUID
        public var resourceID: UUID
    }
}

/// Safe, compact data for resource lists; it never exposes the credential reference.
public struct ResourceListItem: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var type: ResourceType
    public var version: String?
    public var purpose: String?
    public var host: String?
    public var port: Int?
    public var hasCredential: Bool
    public var dockerContext: String?
    public var containerID: String?
    public var containerName: String?

    public init(resource: ResourceRecord) {
        id = resource.id
        name = resource.name
        type = resource.type
        version = resource.version
        purpose = resource.purpose
        host = resource.host
        port = resource.port
        hasCredential = resource.credentialReference != nil
        dockerContext = resource.dockerContext
        containerID = resource.containerID
        containerName = resource.containerName
    }
}
