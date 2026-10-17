import Foundation
import Darwin
import PeanutServiceIPC

public enum SupervisorClientError: LocalizedError {
    case helperNotFound
    case launchAgentConfigurationExists
    case launchctlFailed(operation: String, status: Int32)
    case connectionInvalidated
    case encodingFailed
    case invalidReply

    public var errorDescription: String? {
        switch self {
        case .helperNotFound:
            return "找不到同包的 peanut-service-supervisor。"
        case .launchAgentConfigurationExists:
            return "已有 LaunchAgent 配置与当前应用安装不匹配，未覆盖现有文件。"
        case let .launchctlFailed(operation, status):
            return "launchctl \(operation) 失败（退出码 \(status)）。"
        case .connectionInvalidated:
            return "与服务管理器的连接已断开。"
        case .encodingFailed:
            return "无法编码服务管理请求。"
        case .invalidReply:
            return "服务管理器返回了无效响应。"
        }
    }
}

/// Owns only the UI process's XPC connection. The per-user supervisor remains
/// loaded when this client is released or the UI exits.
public final class SupervisorClient {
    private static let launchAgentLabel = SupervisorIPC.machServiceName

    private let connection: NSXPCConnection
    private let encoder = JSONEncoder()
    private let encoderQueue = DispatchQueue(label: "org.peanutopensource.PeanutServiceManager.supervisor-client")

    public init() throws {
        try Self.ensureLaunchAgent()

        let connection = NSXPCConnection(machServiceName: SupervisorIPC.machServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: SupervisorXPCProtocol.self)
        self.connection = connection
        connection.resume()
    }

    /// Sends one action to the user's persistent supervisor process.
    public func request(
        _ action: SupervisorAction,
        completion: @escaping (Result<SupervisorResult, SupervisorClientError>) -> Void
    ) {
        encoderQueue.async { [weak self] in
            guard let self else {
                completion(.failure(.connectionInvalidated))
                return
            }

            let request = SupervisorRequest(action: action)
            guard let requestData = try? self.encoder.encode(request) else {
                completion(.failure(.encodingFailed))
                return
            }

            let proxy = self.connection.remoteObjectProxyWithErrorHandler { _ in
                completion(.failure(.connectionInvalidated))
            }
            guard let remote = proxy as? SupervisorXPCProtocol else {
                completion(.failure(.connectionInvalidated))
                return
            }

            remote.send(requestData) { responseData in
                guard
                    let response = try? JSONDecoder().decode(SupervisorReply.self, from: responseData),
                    response.id == request.id
                else {
                    completion(.failure(.invalidReply))
                    return
                }
                completion(.success(response.result))
            }
        }
    }

    private static func ensureLaunchAgent() throws {
        let uid = getuid()
        let domain = "gui/\(uid)"
        let target = "\(domain)/\(launchAgentLabel)"

        // A loaded job is authoritative. Never replace or unload a running job,
        // even if its plist was created by another installation.
        if runLaunchctl(arguments: ["print", target]) == 0 {
            return
        }

        let fileManager = FileManager.default
        let helperURL = helperExecutableURL()
        guard fileManager.isExecutableFile(atPath: helperURL.path) else {
            throw SupervisorClientError.helperNotFound
        }

        let launchAgentsURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
        try fileManager.createDirectory(at: launchAgentsURL, withIntermediateDirectories: true)

        let plistURL = launchAgentsURL.appendingPathComponent("\(launchAgentLabel).plist")
        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [helperURL.path],
            "MachServices": [SupervisorIPC.machServiceName: true],
            "RunAtLoad": false,
            "KeepAlive": false
        ]
        if fileManager.fileExists(atPath: plistURL.path) {
            guard launchAgentConfiguration(at: plistURL, matches: plist) else {
                if runLaunchctl(arguments: ["print", target]) == 0 { return }
                throw SupervisorClientError.launchAgentConfigurationExists
            }
        } else {
            let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            do {
                try createPlistWithoutReplacingExisting(plistData, at: plistURL)
            } catch SupervisorClientError.launchAgentConfigurationExists {
                // Another client may have created and loaded the job between the
                // initial check and exclusive plist creation.
                if runLaunchctl(arguments: ["print", target]) == 0 { return }
                guard launchAgentConfiguration(at: plistURL, matches: plist) else {
                    throw SupervisorClientError.launchAgentConfigurationExists
                }
            }
        }

        let status = runLaunchctl(arguments: ["bootstrap", domain, plistURL.path])
        guard status == 0 || runLaunchctl(arguments: ["print", target]) == 0 else {
            throw SupervisorClientError.launchctlFailed(operation: "bootstrap", status: status)
        }
    }

    private static func launchAgentConfiguration(at url: URL, matches expected: [String: Any]) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let existing = propertyList as? [String: Any],
              existing["Label"] as? String == expected["Label"] as? String,
              existing["ProgramArguments"] as? [String] == expected["ProgramArguments"] as? [String],
              existing["MachServices"] as? [String: Bool] == expected["MachServices"] as? [String: Bool],
              existing["RunAtLoad"] as? Bool == false,
              existing["KeepAlive"] as? Bool == false else { return false }
        return true
    }

    private static func helperExecutableURL() -> URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
                .appendingPathComponent("Contents/Library/LaunchServices", isDirectory: true)
                .appendingPathComponent("peanut-service-supervisor", isDirectory: false)
        }

        let executableURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0], isDirectory: false)
        let executableDirectory = executableURL.deletingLastPathComponent()
        let contentsDirectory = executableDirectory.lastPathComponent == "MacOS"
            ? executableDirectory.deletingLastPathComponent()
            : executableDirectory
        let bundledHelper = contentsDirectory
            .appendingPathComponent("Library/LaunchServices", isDirectory: true)
            .appendingPathComponent("peanut-service-supervisor", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: bundledHelper.path) { return bundledHelper }
        return executableDirectory.appendingPathComponent("peanut-service-supervisor", isDirectory: false)
    }

    /// Uses O_EXCL so a pre-existing user plist is never replaced.
    private static func createPlistWithoutReplacingExisting(_ data: Data, at url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            if errno == EEXIST {
                throw SupervisorClientError.launchAgentConfigurationExists
            }
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }

        defer { close(descriptor) }
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = write(descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
                guard written > 0 else {
                    throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
                }
                offset += written
            }
        }
    }

    /// Returns only the exit status; launchctl output is deliberately excluded
    /// from surfaced errors so diagnostics cannot echo private process data.
    private static func runLaunchctl(arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
