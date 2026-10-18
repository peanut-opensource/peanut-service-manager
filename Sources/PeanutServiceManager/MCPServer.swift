import AppKit
import CoreFoundation
import Foundation
import Network
import PeanutServiceIPC

/// A local, newline-delimited JSON-RPC transport. The reader is deliberately
/// independent of the AppKit main loop; all workspace operations use AppModel.
@MainActor
final class LocalMCPServer {
    private static var active: LocalMCPServer?
    private let model: AppModel
    private var client: SupervisorClient?
    private var initialized = false
    private var ready = false
    private let output = FileHandle.standardOutput

    static func start(model: AppModel) {
        guard active == nil else { return }
        let server = LocalMCPServer(model: model)
        active = server
        DispatchQueue(label: "org.peanutopensource.PeanutServiceManager.mcp-stdio").async {
            while let line = readLine(strippingNewline: true) {
                let completion = DispatchSemaphore(value: 0)
                Task { @MainActor in
                    await server.receive(line)
                    completion.signal()
                }
                completion.wait()
            }
            Task { @MainActor in NSApplication.shared.terminate(nil) }
        }
    }

    private init(model: AppModel) { self.model = model }

    private struct Tool {
        let name: String
        let description: String
        let fields: [String: String]
        let required: [String]
        var schema: [String: Any] {
            var properties: [String: Any] = [:]
            for (key, type) in fields {
                var field: [String: Any] = ["type": type]
                if type == "array" { field["items"] = ["type": "string"] }
                if type == "object" { field["additionalProperties"] = ["type": "string"] }
                if key.hasSuffix("ID"), key != "containerID", key != "runtimeResourceID" { field["format"] = "uuid" }
                properties[key] = field
            }
            return ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
        }
    }

    private static let tools: [Tool] = {
        let scope = ["projectID": "string", "environmentID": "string"]
        let serviceScope = scope.merging(["serviceID": "string"]) { _, new in new }
        func tool(_ name: String, _ description: String, _ fields: [String: String] = [:], _ required: [String] = []) -> Tool {
            Tool(name: name, description: description, fields: fields, required: required)
        }
        return [
            tool("target_search", "Search project, shared environment, group, service and resource names. Returns every candidate with stable IDs; mutations always require explicit IDs.", ["query": "string"], ["query"]),
            tool("workspace_list", "List projects, shared environments, services, groups and resource bindings with stable IDs and full paths. Service environment values are redacted."),
            tool("project_save", "Create a project, or rename a project by projectID.", ["projectID": "string", "name": "string"], ["name"]),
            tool("project_delete", "Delete a project and its bindings. Refuses while any owned service is active.", ["projectID": "string"], ["projectID"]),
            tool("environment_save", "Create a shared environment, or rename it and all project associations by environmentID.", ["environmentID": "string", "name": "string"], ["name"]),
            tool("environment_attach", "Associate an existing shared environment with a project. Services remain independent per project.", scope, ["projectID", "environmentID"]),
            tool("environment_detach", "Remove the project's environment association, services, groups and bindings; refuses active services.", scope, ["projectID", "environmentID"]),
            tool("environment_delete", "Delete an unassociated shared environment. Detach its project associations first.", ["environmentID": "string"], ["environmentID"]),
            tool("group_save", "Create/update a group. serviceIDs, if supplied, replaces its membership with services in this exact environment.", scope.merging(["groupID": "string", "name": "string", "serviceIDs": "array"]) { _, n in n }, ["projectID", "environmentID", "name"]),
            tool("group_delete", "Delete a group, preserving its services.", scope.merging(["groupID": "string"]) { _, n in n }, ["projectID", "environmentID", "groupID"]),
            tool("service_save", "Create/update a service by stable ID. Existing fields omitted on update are preserved. Use empty runtimeResourceID/host, domains [] or port 0 to clear optional fields. Host is the binding IPv4/IPv6 address; domains is the ordered list of tenant access domains or complete HTTP(S) URLs. The list replaces all domains; omitted domains preserves the list. These metadata fields do not change the launch command. Environment object replaces all environment variables.", scope.merging(["serviceID": "string", "name": "string", "description": "string", "workingDirectory": "string", "command": "string", "arguments": "array", "environment": "object", "runtimeResourceID": "string", "startsWithManager": "boolean", "host": "string", "domains": "array", "port": "integer"]) { _, n in n }, ["projectID", "environmentID", "name"]),
            tool("service_delete", "Delete an inactive service and remove it from all groups.", serviceScope, ["projectID", "environmentID", "serviceID"]),
            tool("service_start", "Start this exact service through the shared supervisor. Returns the actual supervisor acknowledgement.", serviceScope, ["projectID", "environmentID", "serviceID"]),
            tool("service_stop", "Request graceful stop only. Never force-kills a service.", serviceScope, ["projectID", "environmentID", "serviceID"]),
            tool("service_restart", "Gracefully stop, wait up to 10 seconds, then start. Returns an error without force-stop if still active.", serviceScope, ["projectID", "environmentID", "serviceID"]),
            tool("service_status", "Read live supervisor status for this exact service.", serviceScope, ["projectID", "environmentID", "serviceID"]),
            tool("service_logs", "Read recent in-memory logs. Logs may contain application secrets; request only when needed. afterSequence defaults to 0.", serviceScope.merging(["afterSequence": "integer"]) { _, n in n }, ["projectID", "environmentID", "serviceID"]),
            tool("resource_list", "List resource metadata with passwords and credential references excluded."),
            tool("resource_save", "Create/update registered resource metadata. Does not install software or manage Docker lifecycle. Empty strings clear optional fields; port 0 clears port.", ["resourceID": "string", "name": "string", "type": "string", "version": "string", "source": "string", "purpose": "string", "notes": "string", "executablePath": "string", "host": "string", "port": "integer", "database": "string", "username": "string", "dockerContext": "string", "containerID": "string", "containerName": "string"], ["name"]),
            tool("resource_delete", "Delete resource metadata, password, bindings and service runtime references.", ["resourceID": "string"], ["resourceID"]),
            tool("resource_status", "Check a resource in its explicit project/environment binding. Network checks use registered host/port; Docker is inspect-only.", scope.merging(["resourceID": "string"]) { _, n in n }, ["projectID", "environmentID", "resourceID"]),
            tool("resource_password_get", "Explicit secret retrieval for an exact registered project/environment/resource binding. Returns plaintext only for this tool.", scope.merging(["resourceID": "string"]) { _, n in n }, ["projectID", "environmentID", "resourceID"]),
            tool("resource_password_set", "Set a resource password through an exact registered project/environment/resource binding. Does not echo the password.", scope.merging(["resourceID": "string", "password": "string"]) { _, n in n }, ["projectID", "environmentID", "resourceID", "password"]),
            tool("binding_save", "Create/update a resource association for this project and environment.", scope.merging(["resourceID": "string", "purpose": "string"]) { _, n in n }, ["projectID", "environmentID", "resourceID"]),
            tool("binding_delete", "Remove this exact project/environment/resource association.", scope.merging(["resourceID": "string"]) { _, n in n }, ["projectID", "environmentID", "resourceID"]),
            tool("settings_get", "Get login startup and global shortcut. Never returns the encryption key."),
            tool("settings_set", "Set login startup, global shortcut (optionY/controlOptionY/commandOptionY), or encryptionKey. Never echoes the encryption key.", ["loginStartup": "boolean", "shortcut": "string", "encryptionKey": "string"])
        ]
    }()

    private struct ToolError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
        init(_ message: String) { self.message = message }
    }

    private func send(_ value: [String: Any]) {
        do {
            var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
            data.append(10)
            try output.write(contentsOf: data)
        } catch {
            FileHandle.standardError.write(Data("MCP response write failed.\n".utf8))
        }
    }

    private func receive(_ line: String) async {
        let request: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "Invalid Request"]]); return
            }
            request = parsed
        } catch {
            send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]]); return
        }
        let id = request["id"]
        guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String,
              id == nil || id is NSNull || id is String || (id is NSNumber && CFGetTypeID(id as! NSNumber) != CFBooleanGetTypeID()) else {
            send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "Invalid Request"]]); return
        }
        // JSON-RPC notifications must never produce a response, including errors.
        guard let id else {
            if method == "notifications/initialized", initialized { ready = true }
            return
        }
        func result(_ value: [String: Any]) { send(["jsonrpc": "2.0", "id": id, "result": value]) }
        func failure(_ code: Int, _ message: String) { send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]) }
        if method == "initialize" {
            guard let params = request["params"] as? [String: Any], params["protocolVersion"] is String,
                  params["clientInfo"] is [String: Any], params["capabilities"] is [String: Any] else {
                failure(-32602, "initialize requires protocolVersion, clientInfo and capabilities"); return
            }
            initialized = true
            ready = false
            result(["protocolVersion": "2025-11-25", "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": "peanut-service-manager", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"],
                    "instructions": "Local macOS service manager. Use stable UUID IDs from workspace_list and the complete project/environment scope. Passwords require an explicit binding and resource_password_get. Stops are graceful only."])
            return
        }
        if method == "ping" { result([:]); return }
        guard initialized && ready else { failure(-32000, "Initialize and send notifications/initialized first"); return }
        if method == "tools/list" {
            result(["tools": Self.tools.map { ["name": $0.name, "description": $0.description, "inputSchema": $0.schema] as [String: Any] }]); return
        }
        guard method == "tools/call" else { failure(-32601, "Method not found"); return }
        guard let params = request["params"] as? [String: Any], let name = params["name"] as? String else {
            failure(-32602, "tools/call requires a tool name"); return
        }
        do {
            guard let definition = Self.tools.first(where: { $0.name == name }) else { throw ToolError("Unknown tool: \(name)") }
            let arguments: [String: Any]
            if let supplied = params["arguments"] {
                guard let object = supplied as? [String: Any] else { throw ToolError("arguments must be an object") }
                arguments = object
            } else { arguments = [:] }
            try validate(arguments, tool: definition)
            try model.refreshWorkspaceConfiguration()
            let value = try await call(name, arguments)
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
            result(["content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]], "isError": false])
        } catch {
            result(["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
        }
    }

    private func validate(_ arguments: [String: Any], tool: Tool) throws {
        for key in tool.required where arguments[key] == nil { throw ToolError("Missing required argument: \(key)") }
        for (key, value) in arguments {
            guard let type = tool.fields[key] else { throw ToolError("Unknown argument: \(key)") }
            let valid: Bool
            switch type {
            case "string": valid = value is String
            case "boolean": valid = (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            case "integer": valid = (value as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite && $0.doubleValue.rounded() == $0.doubleValue && abs($0.doubleValue) <= 9_007_199_254_740_991 } ?? false
            case "array": valid = value is [String]
            case "object": valid = value is [String: String]
            default: valid = false
            }
            guard valid else { throw ToolError("\(key) must be \(type)") }
            if key.hasSuffix("ID"), key != "containerID", let string = value as? String, !(key == "runtimeResourceID" && string.isEmpty), UUID(uuidString: string) == nil { throw ToolError("\(key) must be a UUID from the listing tools") }
            if key == "name", (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { throw ToolError("name must not be empty") }
            if key == "port", let port = value as? Int, !(0...65535).contains(port) { throw ToolError("port must be between 0 and 65535") }
            if key == "afterSequence", let sequence = value as? Int, sequence < 0 { throw ToolError("afterSequence must be nonnegative") }
        }
    }

    private func uuid(_ args: [String: Any], _ key: String) throws -> UUID {
        guard let value = args[key] as? String, let id = UUID(uuidString: value) else { throw ToolError("\(key) must be an explicit UUID") }
        return id
    }
    private func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
    private func save(_ change: (inout Workspace) -> Void) throws {
        let baseline = model.workspace
        var conflict = false
        model.update { workspace in
            guard workspace == baseline else { conflict = true; return }
            change(&workspace)
        }
        if let error = model.errorMessage { throw ToolError(error) }
        if conflict { throw ToolError("Workspace changed in another client. Read the target again before retrying.") }
    }
    private func projectIndex(_ id: UUID) throws -> Int {
        guard let index = model.workspace.projects.firstIndex(where: { $0.id == id }) else { throw ToolError("Unknown projectID: \(id)") }
        return index
    }
    private func scope(_ args: [String: Any]) throws -> (Int, Int) {
        let p = try projectIndex(uuid(args, "projectID"))
        let id = try uuid(args, "environmentID")
        guard let e = model.workspace.projects[p].environments.firstIndex(where: { $0.id == id }) else { throw ToolError("Environment \(id) is not associated with project \(model.workspace.projects[p].id)") }
        return (p, e)
    }
    private func serviceScope(_ args: [String: Any]) throws -> (Int, Int, Int) {
        let (p, e) = try scope(args)
        let id = try uuid(args, "serviceID")
        guard let s = model.workspace.projects[p].environments[e].services.firstIndex(where: { $0.id == id }) else { throw ToolError("serviceID \(id) is not in the supplied project/environment") }
        return (p, e, s)
    }
    private func resourceIndex(_ args: [String: Any]) throws -> Int {
        let id = try uuid(args, "resourceID")
        guard let r = model.workspace.resources.firstIndex(where: { $0.id == id }) else { throw ToolError("Unknown resourceID: \(id)") }
        return r
    }
    private func boundResource(_ args: [String: Any]) throws -> (ResourceRecord, ProjectEnvironmentBinding, String) {
        let (p, e) = try scope(args)
        let resource = model.workspace.resources[try resourceIndex(args)]
        let project = model.workspace.projects[p]
        let environment = project.environments[e]
        guard let binding = model.workspace.bindings.first(where: { $0.projectID == project.id && $0.environmentID == environment.id && $0.resourceID == resource.id }) else { throw ToolError("Resource is not bound to this project/environment") }
        return (resource, binding, path(p, e) + "/resource:\(resource.name) [\(resource.id)]")
    }
    private func path(_ p: Int, _ e: Int? = nil, _ s: Int? = nil) -> String {
        let project = model.workspace.projects[p]
        var text = "\(project.name) [\(project.id)]"
        if let e {
            let environment = project.environments[e]
            text += "/\(environment.name) [\(environment.id)]"
            if let s { let service = environment.services[s]; text += "/\(service.name) [\(service.id)]" }
        }
        return text
    }
    private func safeResource(_ resource: ResourceRecord) throws -> [String: Any] {
        var value = try object(resource) as! [String: Any]
        value.removeValue(forKey: "credentialReference")
        value["hasCredential"] = resource.credentialReference != nil
        return value
    }
    private func safeService(_ service: Service, path: String) throws -> [String: Any] {
        var value = try object(service) as! [String: Any]
        value["environment"] = service.environment.mapValues { _ in "[redacted]" }
        value["path"] = path
        return value
    }

    private func supervisor(_ action: SupervisorAction) async throws -> SupervisorResult {
        if client == nil { client = try SupervisorClient() }
        guard let client else { throw ToolError("Supervisor unavailable") }
        return try await withCheckedThrowingContinuation { continuation in
            // XPC error and reply callbacks can race. Resolve a continuation once.
            let gate = MCPReplyGate(continuation)
            client.request(action) { gate.resolve($0.mapError { $0 as Error }) }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20) {
                gate.resolve(.failure(ToolError("Supervisor request timed out; check service_status before retrying a mutation")))
            }
        }
    }
    private func snapshots() async throws -> [SupervisorServiceSnapshot] {
        let result = try await supervisor(.list)
        switch result {
        case .services(let values):
            model.processSnapshots = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
            return values
        case .failure(_, let message): throw ToolError(message)
        default: throw ToolError("Unexpected supervisor status reply")
        }
    }
    private func inactive(_ ids: Set<UUID>) async throws {
        let active = try await snapshots().filter { ids.contains($0.id) && [.running, .starting, .stopping].contains($0.state) }
        guard active.isEmpty else { throw ToolError("Stop active services before deleting configuration: \(active.map { $0.id.uuidString }.joined(separator: ", "))") }
    }
    private func launch(_ service: Service, projectID: UUID, environmentID: UUID) throws -> ServiceLaunchRequest {
        guard !service.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolError("Service command is empty") }
        var environment = service.environment
        if let id = service.runtimeResourceID {
            guard let runtime = model.workspace.resources.first(where: { $0.id == id }), [.php, .node].contains(runtime.type),
                  model.workspace.bindings.contains(where: { $0.projectID == projectID && $0.environmentID == environmentID && $0.resourceID == id }),
                  let executable = runtime.executablePath, FileManager.default.isExecutableFile(atPath: executable) else { throw ToolError("Runtime must be an executable PHP/Node resource bound to this project/environment") }
            environment["PATH"] = URL(fileURLWithPath: executable).deletingLastPathComponent().path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        }
        return ServiceLaunchRequest(serviceID: service.id, projectID: projectID, environmentID: environmentID, name: service.name, workingDirectory: service.workingDirectory, command: service.command, arguments: service.arguments, environment: environment)
    }
    private func acknowledge(_ action: SupervisorAction) async throws -> Any {
        switch try await supervisor(action) {
        case .accepted(let value): model.processSnapshots[value.id] = value; return try object(value)
        case .failure(_, let message): throw ToolError(message)
        default: throw ToolError("Unexpected supervisor acknowledgement")
        }
    }

    private func call(_ name: String, _ args: [String: Any]) async throws -> Any {
        switch name {
        case "workspace_list", "target_search":
            let query = (args["query"] as? String ?? "").lowercased()
            var projects: [[String: Any]] = []
            var candidates: [[String: Any]] = []
            for (p, project) in model.workspace.projects.enumerated() {
                if name == "target_search", project.name.lowercased().contains(query) {
                    candidates.append(["kind": "project", "projectID": project.id.uuidString, "path": path(p)])
                }
                var environments: [[String: Any]] = []
                for (e, environment) in project.environments.enumerated() {
                    let services = try environment.services.enumerated().map { try safeService($0.element, path: path(p, e, $0.offset)) }
                    if name == "target_search" {
                        if environment.name.lowercased().contains(query) { candidates.append(["kind": "environment", "projectID": project.id.uuidString, "environmentID": environment.id.uuidString, "path": path(p, e)]) }
                        for (s, service) in environment.services.enumerated() where service.name.lowercased().contains(query) {
                            candidates.append(["kind": "service", "projectID": project.id.uuidString, "environmentID": environment.id.uuidString, "serviceID": service.id.uuidString, "path": path(p, e, s)])
                        }
                    }
                    if name == "target_search" {
                        for group in environment.groups where group.name.lowercased().contains(query) {
                            candidates.append(["kind": "group", "projectID": project.id.uuidString, "environmentID": environment.id.uuidString, "groupID": group.id.uuidString, "path": path(p, e) + "/group:\(group.name) [\(group.id)]"])
                        }
                    }
                    let groups: [[String: Any]] = environment.groups.map { group in
                        ["id": group.id.uuidString, "name": group.name, "serviceIDs": group.serviceIDs.map(\.uuidString).sorted(), "path": path(p, e) + "/group:\(group.name) [\(group.id)]"]
                    }
                    let bindings = try model.workspace.bindings.filter { $0.projectID == project.id && $0.environmentID == environment.id }.map { binding -> [String: Any] in
                        var item = try object(binding) as! [String: Any]
                        if let resource = model.workspace.resources.first(where: { $0.id == binding.resourceID }) {
                            item["resource"] = try safeResource(resource)
                            item["path"] = path(p, e) + "/resource:\(resource.name) [\(resource.id)]"
                        }
                        return item
                    }
                    environments.append(["id": environment.id.uuidString, "name": environment.name, "path": path(p, e), "services": services, "groups": groups, "bindings": bindings])
                }
                projects.append(["id": project.id.uuidString, "name": project.name, "path": path(p), "environments": environments])
            }
            if name == "target_search" {
                for environment in model.workspace.environments where environment.name.lowercased().contains(query) && !model.workspace.projects.contains(where: { $0.environments.contains(where: { $0.id == environment.id }) }) {
                    candidates.append(["kind": "sharedEnvironment", "environmentID": environment.id.uuidString, "path": "shared-environment:\(environment.name) [\(environment.id)]"])
                }
                for resource in model.workspace.resources where resource.name.lowercased().contains(query) { candidates.append(["kind": "resource", "resourceID": resource.id.uuidString, "path": "resource:\(resource.name) [\(resource.id)]"]) }
                return ["candidates": candidates, "requiresExplicitIDs": true]
            }
            return ["projects": projects, "sharedEnvironments": try object(model.workspace.environments), "resources": try model.workspace.resources.map(safeResource)]
        case "project_save":
            if args["projectID"] != nil {
                let p = try projectIndex(uuid(args, "projectID"))
                try save { $0.projects[p].name = args["name"] as! String }
                return ["projectID": model.workspace.projects[p].id.uuidString, "path": path(p)]
            }
            let project = Project(name: args["name"] as! String)
            try save { $0.projects.append(project) }
            return ["projectID": project.id.uuidString, "path": path(model.workspace.projects.count - 1)]
        case "project_delete":
            let id = try uuid(args, "projectID")
            let p = try projectIndex(id)
            let target = path(p)
            try await inactive(Set(model.workspace.projects[p].environments.flatMap(\.services).map(\.id)))
            try save { workspace in
                workspace.projects.removeAll { $0.id == id }
                workspace.bindings.removeAll { $0.projectID == id }
            }
            return ["deleted": true, "path": target]
        case "environment_save":
            if args["environmentID"] != nil {
                let id = try uuid(args, "environmentID")
                guard model.workspace.environments.contains(where: { $0.id == id }) else { throw ToolError("Unknown shared environmentID") }
                try save { workspace in
                    for e in workspace.environments.indices where workspace.environments[e].id == id { workspace.environments[e].name = args["name"] as! String }
                    for p in workspace.projects.indices {
                        for e in workspace.projects[p].environments.indices where workspace.projects[p].environments[e].id == id { workspace.projects[p].environments[e].name = args["name"] as! String }
                    }
                }
                return ["environmentID": id.uuidString, "name": args["name"]!]
            }
            let environment = WorkspaceEnvironment(name: args["name"] as! String)
            try save { $0.environments.append(environment) }
            return try object(environment)
        case "environment_attach":
            let p = try projectIndex(uuid(args, "projectID"))
            let id = try uuid(args, "environmentID")
            guard let environment = model.workspace.environments.first(where: { $0.id == id }) else { throw ToolError("Unknown shared environmentID") }
            if !model.workspace.projects[p].environments.contains(where: { $0.id == id }) {
                try save { $0.projects[p].environments.append(ProjectEnvironment(id: id, name: environment.name)) }
            }
            let (_, e) = try scope(args)
            return ["path": path(p, e)]
        case "environment_detach":
            let (p, e) = try scope(args)
            let project = model.workspace.projects[p]
            let environment = project.environments[e]
            let target = path(p, e)
            try await inactive(Set(environment.services.map(\.id)))
            try save { workspace in
                workspace.projects[p].environments.removeAll { $0.id == environment.id }
                workspace.bindings.removeAll { $0.projectID == project.id && $0.environmentID == environment.id }
            }
            return ["detached": true, "path": target]
        case "environment_delete":
            let id = try uuid(args, "environmentID")
            guard model.workspace.environments.contains(where: { $0.id == id }) else { throw ToolError("Unknown shared environmentID") }
            guard !model.workspace.projects.contains(where: { $0.environments.contains(where: { $0.id == id }) }) else { throw ToolError("Detach all project associations before deleting this shared environment") }
            try save { $0.environments.removeAll { $0.id == id } }
            return ["deleted": true, "environmentID": id.uuidString]
        case "group_save", "group_delete":
            let (p, e) = try scope(args)
            let environment = model.workspace.projects[p].environments[e]
            let existingID = try args["groupID"].map { _ in try uuid(args, "groupID") }
            let existing = existingID.flatMap { id in environment.groups.first(where: { $0.id == id }) }
            if existingID != nil && existing == nil { throw ToolError("groupID is not in the supplied project/environment") }
            if name == "group_delete" {
                guard let existing else { throw ToolError("groupID is required") }
                try save { $0.projects[p].environments[e].groups.removeAll { $0.id == existing.id } }
                return ["deleted": true, "path": path(p, e) + "/group:\(existing.name) [\(existing.id)]"]
            }
            var group = existing ?? ServiceGroup(name: args["name"] as! String)
            group.name = args["name"] as! String
            if let ids = args["serviceIDs"] as? [String] {
                let uuids = try ids.map { string -> UUID in
                    guard let id = UUID(uuidString: string), environment.services.contains(where: { $0.id == id }) else { throw ToolError("Each serviceIDs entry must identify a service in this exact project/environment") }
                    return id
                }
                group.serviceIDs = Set(uuids)
            }
            try save { workspace in
                workspace.projects[p].environments[e].groups.removeAll { $0.id == group.id }
                workspace.projects[p].environments[e].groups.append(group)
            }
            return ["groupID": group.id.uuidString, "path": path(p, e) + "/group:\(group.name) [\(group.id)]"]
        case "service_save":
            let (p, e) = try scope(args)
            var service: Service
            if args["serviceID"] != nil {
                let (_, _, s) = try serviceScope(args)
                service = model.workspace.projects[p].environments[e].services[s]
            } else {
                guard let directory = args["workingDirectory"] as? String, let command = args["command"] as? String else { throw ToolError("New services require workingDirectory and command") }
                service = Service(name: args["name"] as! String, workingDirectory: directory, command: command)
            }
            service.name = args["name"] as! String
            if let value = args["description"] as? String { service.description = value }
            if let value = args["workingDirectory"] as? String { service.workingDirectory = value }
            if let value = args["command"] as? String { service.command = value }
            if let value = args["arguments"] as? [String] { service.arguments = value }
            if let value = args["environment"] as? [String: String] { service.environment = value }
            if let value = args["startsWithManager"] as? Bool { service.startsWithManager = value }
            if let value = args["host"] as? String { service.host = AccessAddress.nonempty(value) }
            if let value = args["domains"] as? [String] { service.domains = AccessAddress.normalizedDomains(value) }
            if let value = args["port"] as? Int { service.port = value == 0 ? nil : value }
            guard service.hasValidBindingHost else { throw ToolError("Service host must be a valid IPv4 or IPv6 binding address") }
            guard service.hasValidAccessDomains else { throw ToolError("Every service domain must be a valid HTTP(S) access address without credentials") }
            if let value = args["runtimeResourceID"] as? String {
                service.runtimeResourceID = value.isEmpty ? nil : UUID(uuidString: value)
                if let id = service.runtimeResourceID {
                    guard model.workspace.resources.contains(where: { $0.id == id && [.php, .node].contains($0.type) }),
                          model.workspace.bindings.contains(where: { $0.projectID == model.workspace.projects[p].id && $0.environmentID == model.workspace.projects[p].environments[e].id && $0.resourceID == id }) else { throw ToolError("runtimeResourceID must be a PHP/Node resource bound to this project/environment") }
                }
            }
            try save { workspace in
                if let s = workspace.projects[p].environments[e].services.firstIndex(where: { $0.id == service.id }) { workspace.projects[p].environments[e].services[s] = service }
                else { workspace.projects[p].environments[e].services.append(service) }
            }
            let s = model.workspace.projects[p].environments[e].services.firstIndex(where: { $0.id == service.id })!
            return try safeService(service, path: path(p, e, s))
        case "service_delete":
            let (p, e, s) = try serviceScope(args)
            let service = model.workspace.projects[p].environments[e].services[s]
            let target = path(p, e, s)
            try await inactive([service.id])
            try save { workspace in
                workspace.projects[p].environments[e].services.removeAll { $0.id == service.id }
                for g in workspace.projects[p].environments[e].groups.indices {
                    workspace.projects[p].environments[e].groups[g].serviceIDs.remove(service.id)
                }
            }
            return ["deleted": true, "path": target]
        case "service_start", "service_stop", "service_restart", "service_status", "service_logs":
            let (p, e, s) = try serviceScope(args)
            let project = model.workspace.projects[p]
            let environment = project.environments[e]
            let service = environment.services[s]
            let target = path(p, e, s)
            if name == "service_status" {
                let values = try await snapshots()
                if let value = values.first(where: { $0.id == service.id }) { return ["path": target, "status": try object(value)] }
                return ["path": target, "state": "stopped", "trackedBySupervisor": false]
            }
            if name == "service_logs" {
                switch try await supervisor(.logs(serviceID: service.id, afterSequence: UInt64(args["afterSequence"] as? Int ?? 0))) {
                case .logs(let entries, let next): return ["path": target, "entries": try object(entries), "nextSequence": next]
                case .failure(_, let message): throw ToolError(message)
                default: throw ToolError("Unexpected supervisor logs reply")
                }
            }
            if name == "service_stop" { return ["path": target, "status": try await acknowledge(.stop(serviceID: service.id, force: false))] }
            let request = try launch(service, projectID: project.id, environmentID: environment.id)
            if name == "service_restart" {
                let current = try await snapshots().first(where: { $0.id == service.id })
                if let current, [.running, .starting, .stopping].contains(current.state) {
                    _ = try await acknowledge(.stop(serviceID: service.id, force: false))
                    let deadline = Date().addingTimeInterval(10)
                    while true {
                        let state = try await snapshots().first(where: { $0.id == service.id })?.state
                        if state == .exited || state == .failed || state == nil { break }
                        guard Date() < deadline else { throw ToolError("\(target) has not stopped gracefully; restart was not performed. No force-stop was sent.") }
                        try await Task.sleep(nanoseconds: 250_000_000)
                    }
                }
            }
            return ["path": target, "status": try await acknowledge(.start(request))]
        case "resource_list": return ["resources": try model.workspace.resources.map(safeResource)]
        case "resource_save":
            var resource: ResourceRecord
            if args["resourceID"] != nil { resource = model.workspace.resources[try resourceIndex(args)] }
            else { resource = ResourceRecord(name: args["name"] as! String, type: .other) }
            var values = try object(resource) as! [String: Any]
            for (key, value) in args where key != "resourceID" {
                if key == "type", ResourceType(rawValue: value as! String) == nil { throw ToolError("type must be mysql, redis, php, node, other or dockerContainer") }
                if let string = value as? String, string.isEmpty, key != "name", key != "type" { values.removeValue(forKey: key) }
                else if key == "port", value as? Int == 0 { values.removeValue(forKey: key) }
                else { values[key] = value }
            }
            resource = try JSONDecoder().decode(ResourceRecord.self, from: JSONSerialization.data(withJSONObject: values))
            try save { workspace in
                if let r = workspace.resources.firstIndex(where: { $0.id == resource.id }) { workspace.resources[r] = resource }
                else { workspace.resources.append(resource) }
            }
            return try safeResource(resource)
        case "resource_delete":
            let resource = model.workspace.resources[try resourceIndex(args)]
            let runtimeConsumers = Set(model.workspace.projects.flatMap(\.environments).flatMap(\.services).filter { $0.runtimeResourceID == resource.id }.map(\.id))
            if !runtimeConsumers.isEmpty { try await inactive(runtimeConsumers) }
            // Persist metadata before removing the now-unreferenced secret. If deletion
            // fails, the secret remains recoverable and the error is explicit.
            try save { workspace in
                workspace.resources.removeAll { $0.id == resource.id }
                workspace.bindings.removeAll { $0.resourceID == resource.id }
                for p in workspace.projects.indices {
                    for e in workspace.projects[p].environments.indices {
                        for s in workspace.projects[p].environments[e].services.indices where workspace.projects[p].environments[e].services[s].runtimeResourceID == resource.id {
                            workspace.projects[p].environments[e].services[s].runtimeResourceID = nil
                        }
                    }
                }
            }
            if resource.credentialReference != nil { try CredentialVault().delete(for: resource) }
            return ["deleted": true, "resourceID": resource.id.uuidString, "path": "resource:\(resource.name) [\(resource.id)]"]
        case "binding_save", "binding_delete":
            let (p, e) = try scope(args)
            let resource = model.workspace.resources[try resourceIndex(args)]
            let project = model.workspace.projects[p]
            let environment = project.environments[e]
            let existing = model.workspace.bindings.first { $0.projectID == project.id && $0.environmentID == environment.id && $0.resourceID == resource.id }
            if name == "binding_delete", existing == nil { throw ToolError("Binding does not exist") }
            if name == "binding_delete", environment.services.contains(where: { $0.runtimeResourceID == resource.id }) { throw ToolError("Clear service runtimeResourceID references before removing this binding") }
            try save { workspace in
                workspace.bindings.removeAll { $0.projectID == project.id && $0.environmentID == environment.id && $0.resourceID == resource.id }
                if name == "binding_save" { workspace.bindings.append(ProjectEnvironmentBinding(projectID: project.id, environmentID: environment.id, resourceID: resource.id, purpose: args["purpose"] as? String ?? existing?.purpose)) }
            }
            return ["path": path(p, e) + "/resource:\(resource.name) [\(resource.id)]", "bound": name == "binding_save"]
        case "resource_password_get", "resource_password_set", "resource_status":
            var (resource, binding, target) = try boundResource(args)
            if name == "resource_password_get" {
                let password = try CredentialVault().read(for: resource, binding: binding, projectID: binding.projectID, environmentID: binding.environmentID)
                return ["path": target, "password": password.map { String(decoding: $0, as: UTF8.self) } as Any? ?? NSNull()]
            }
            if name == "resource_password_set" {
                let previous = resource
                if resource.credentialReference == nil { resource.credentialReference = "resource-\(resource.id.uuidString)" }
                try CredentialVault().update(Data((args["password"] as! String).utf8), for: resource)
                if previous.credentialReference == nil {
                    do { try save { workspace in if let r = workspace.resources.firstIndex(where: { $0.id == resource.id }) { workspace.resources[r] = resource } } }
                    catch { try? CredentialVault().delete(for: resource); throw error }
                }
                return ["path": target, "hasCredential": true]
            }
            if resource.type == .dockerContainer {
                let status = try await Task.detached { try DockerStatusProbe.check(resource) }.value
                return ["path": target, "check": "docker inspect", "status": status]
            }
            if let host = resource.host, !host.isEmpty, let port = resource.port, port > 0 {
                let reachable = try await tcpCheck(host: host, port: port)
                return ["path": target, "check": "tcp", "host": host, "port": port, "reachable": reachable, "note": "TCP reachability does not validate database authentication."]
            }
            if let executable = resource.executablePath {
                return ["path": target, "check": "executable", "executablePath": executable, "available": FileManager.default.isExecutableFile(atPath: executable)]
            }
            throw ToolError("Resource has no registered host/port, executable path or Docker identity to check")
        case "settings_get": return settings()
        case "settings_set":
            if let shortcut = args["shortcut"] as? String, !["optionY", "controlOptionY", "commandOptionY"].contains(shortcut) { throw ToolError("shortcut must be optionY, controlOptionY or commandOptionY") }
            if let key = args["encryptionKey"] as? String, key.isEmpty { throw ToolError("encryptionKey must not be empty") }
            if let enabled = args["loginStartup"] as? Bool { try LoginItemManager().setEnabled(enabled) }
            if let shortcut = args["shortcut"] as? String {
                UserDefaults.standard.set(shortcut, forKey: "peanutServiceManager.globalShortcut")
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name("PeanutServiceManagerGlobalShortcutChanged"), object: nil, deliverImmediately: true
                )
            }
            if let key = args["encryptionKey"] as? String { try CredentialVault().setEncryptionKey(key) }
            return settings()
        default: throw ToolError("Unknown tool")
        }
    }

    private func settings() -> [String: Any] {
        ["loginStartup": LoginItemManager().isEnabled,
         "shortcut": UserDefaults.standard.string(forKey: "peanutServiceManager.globalShortcut") ?? "optionY",
         "shortcutStatus": UserDefaults.standard.string(forKey: "peanutServiceManager.globalShortcutStatus") ?? "UI not running",
         "encryptionKey": "[redacted]"]
    }

    private func tcpCheck(host: String, port: Int) async throws -> Bool {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else { throw ToolError("Invalid registered port") }
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "org.peanutopensource.PeanutServiceManager.mcp-tcp")
            let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
            let gate = MCPTCPGate(connection: connection, continuation: continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: gate.finish(true)
                case .failed, .cancelled: gate.finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 5) { gate.finish(false) }
        }
    }
}

private final class MCPReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SupervisorResult, Error>?
    init(_ continuation: CheckedContinuation<SupervisorResult, Error>) { self.continuation = continuation }
    func resolve(_ result: Result<SupervisorResult, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

private final class MCPTCPGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private let connection: NWConnection
    init(connection: NWConnection, continuation: CheckedContinuation<Bool, Never>) {
        self.connection = connection
        self.continuation = continuation
    }
    func finish(_ reachable: Bool) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }
        connection.stateUpdateHandler = nil
        connection.cancel()
        pending.resume(returning: reachable)
    }
}
