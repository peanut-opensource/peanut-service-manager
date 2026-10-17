import Foundation

public enum SupervisorIPC {
    public static let machServiceName = "org.peanutopensource.PeanutServiceManager.supervisor"
}

@objc public protocol SupervisorXPCProtocol {
    func send(_ requestData: Data, reply: @escaping (Data) -> Void)
}

public struct ServiceLaunchRequest: Codable, Equatable {
    public var serviceID: UUID
    public var projectID: UUID
    public var environmentID: UUID
    public var name: String
    public var workingDirectory: String
    public var command: String
    public var arguments: [String]
    public var environment: [String: String]

    public init(
        serviceID: UUID,
        projectID: UUID,
        environmentID: UUID,
        name: String,
        workingDirectory: String,
        command: String,
        arguments: [String],
        environment: [String: String]
    ) {
        self.serviceID = serviceID
        self.projectID = projectID
        self.environmentID = environmentID
        self.name = name
        self.workingDirectory = workingDirectory
        self.command = command
        self.arguments = arguments
        self.environment = environment
    }
}

public enum SupervisorAction: Codable {
    case start(ServiceLaunchRequest)
    case stop(serviceID: UUID, force: Bool)
    case list
    case logs(serviceID: UUID, afterSequence: UInt64)
}

public struct SupervisorRequest: Codable {
    public var id: UUID
    public var action: SupervisorAction

    public init(id: UUID = UUID(), action: SupervisorAction) {
        self.id = id
        self.action = action
    }
}

public enum SupervisorProcessState: String, Codable, Equatable {
    case starting
    case running
    case stopping
    case exited
    case failed
    case unknown
}

public struct SupervisorServiceSnapshot: Codable, Equatable, Identifiable {
    public var id: UUID
    public var projectID: UUID
    public var environmentID: UUID
    public var name: String
    public var state: SupervisorProcessState
    public var pid: Int32?
    public var exitCode: Int32?
    public var message: String?
    public var nextLogSequence: UInt64

    public init(id: UUID, projectID: UUID, environmentID: UUID, name: String, state: SupervisorProcessState, pid: Int32? = nil, exitCode: Int32? = nil, message: String? = nil, nextLogSequence: UInt64 = 0) {
        self.id = id
        self.projectID = projectID
        self.environmentID = environmentID
        self.name = name
        self.state = state
        self.pid = pid
        self.exitCode = exitCode
        self.message = message
        self.nextLogSequence = nextLogSequence
    }
}

public struct SupervisorLogEntry: Codable, Equatable, Identifiable {
    public var id: UInt64 { sequence }
    public var sequence: UInt64
    public var stream: String
    public var text: String

    public init(sequence: UInt64, stream: String, text: String) {
        self.sequence = sequence
        self.stream = stream
        self.text = text
    }
}

public enum SupervisorResult: Codable {
    case accepted(SupervisorServiceSnapshot)
    case services([SupervisorServiceSnapshot])
    case logs(entries: [SupervisorLogEntry], nextSequence: UInt64)
    case failure(code: String, message: String)
}

public struct SupervisorReply: Codable {
    public var id: UUID
    public var result: SupervisorResult

    public init(id: UUID, result: SupervisorResult) {
        self.id = id
        self.result = result
    }
}
