import Combine
import Foundation
import PeanutServiceIPC

private enum ConfigurationImportError: LocalizedError {
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .rollbackFailed: return "配置导入失败，且无法恢复原密码文件；请保留当前本机数据并检查磁盘空间。"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var workspace: Workspace
    @Published var selectedProjectID: UUID?
    @Published var selectedEnvironmentID: UUID?
    @Published var selectedServiceID: UUID?
    @Published var selectedResourceID: UUID?
    @Published var errorMessage: String?
    @Published var processSnapshots: [UUID: SupervisorServiceSnapshot] = [:]
    @Published var processLogs: [UUID: String] = [:]
    @Published var serviceErrors: [UUID: String] = [:]
    @Published var forceStopPromptID: UUID?
    private var pendingRestarts: [UUID: ServiceTarget] = [:]
    private var restartChecksRemaining: [UUID: Int] = [:]

    private let store: WorkspaceStore
    private var supervisor: SupervisorClient?
    private var observationTimer: Timer?
    private var observedServiceID: UUID?
    private var outputWindowServiceIDs: Set<UUID> = []
    private var logSequences: [UUID: UInt64] = [:]
    private var didCheckStartupServices = false

    init(store: WorkspaceStore) {
        self.store = store
        workspace = store.workspace
    }

    func serviceDisplayName(_ service: Service) -> String {
        for project in workspace.projects {
            if let environment = project.environments.first(where: { $0.services.contains(where: { $0.id == service.id }) }) {
                let prefix = environment.groups
                    .filter { $0.serviceIDs.contains(service.id) }
                    .map { "【\($0.name)】" }
                    .joined()
                return prefix + service.name
            }
        }
        return service.name
    }

    func update(_ change: (inout Workspace) -> Void) {
        do {
            try store.update(change)
            workspace = store.workspace
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func configurationExport() throws -> Data {
        try LocalConfigurationFile.make(workspace: workspace, vault: CredentialVault()).encoded()
    }

    func importConfiguration(_ data: Data) throws {
        let decoded = try LocalConfigurationFile.decode(data)
        let vault = CredentialVault()
        let snapshot = try vault.exportedConfiguration()
        var importedWorkspace = decoded.workspace
        var secrets: [String: Data] = [:]
        for projectIndex in importedWorkspace.projects.indices {
            for environmentIndex in importedWorkspace.projects[projectIndex].environments.indices {
                for serviceIndex in importedWorkspace.projects[projectIndex].environments[environmentIndex].services.indices {
                    let service = importedWorkspace.projects[projectIndex].environments[environmentIndex].services[serviceIndex]
                    importedWorkspace.projects[projectIndex].environments[environmentIndex].services[serviceIndex].resourceIDs = Array(Set(service.resourceIDs)).sorted { $0.uuidString < $1.uuidString }
                }
            }
        }
        for resourceIndex in importedWorkspace.resources.indices {
            let resourceID = importedWorkspace.resources[resourceIndex].id
            if let password = decoded.passwords[resourceID] {
                let reference = "resource-\(resourceID.uuidString)"
                importedWorkspace.resources[resourceIndex].credentialReference = reference
                secrets[reference] = password
            } else {
                importedWorkspace.resources[resourceIndex].credentialReference = nil
            }
        }
        do {
            try vault.replacePasswords(secrets)
            try store.replace(with: importedWorkspace)
            workspace = store.workspace
            selectedProjectID = nil
            selectedEnvironmentID = nil
            selectedServiceID = nil
            selectedResourceID = nil
            errorMessage = nil
        } catch {
            do { try vault.replaceConfiguration(with: snapshot) }
            catch { throw ConfigurationImportError.rollbackFailed }
            throw error
        }
    }

    func addProject(name: String = "新项目") {
        let project = Project(name: name)
        update { $0.projects.append(project) }
        selectedProjectID = project.id
        selectedEnvironmentID = nil
        selectedServiceID = nil
    }

    func addEnvironment(projectID: UUID, name: String = "开发") {
        let environment = ProjectEnvironment(name: name)
        update { workspace in
            guard let index = workspace.projects.firstIndex(where: { $0.id == projectID }) else { return }
            workspace.environments.append(WorkspaceEnvironment(id: environment.id, name: name))
            workspace.projects[index].environments.append(environment)
        }
        selectedEnvironmentID = environment.id
        selectedServiceID = nil
    }

    func addService(projectID: UUID, environmentID: UUID) {
        let service = Service(name: "新服务", workingDirectory: NSHomeDirectory(), command: "")
        update { workspace in
            guard let projectIndex = workspace.projects.firstIndex(where: { $0.id == projectID }),
                  let environmentIndex = workspace.projects[projectIndex].environments.firstIndex(where: { $0.id == environmentID }) else { return }
            workspace.projects[projectIndex].environments[environmentIndex].services.append(service)
        }
        selectedServiceID = service.id
    }

    func addGroup(projectID: UUID, environmentID: UUID, name: String = "新分组") {
        let group = ServiceGroup(name: name)
        update { workspace in
            guard let projectIndex = workspace.projects.firstIndex(where: { $0.id == projectID }),
                  let environmentIndex = workspace.projects[projectIndex].environments.firstIndex(where: { $0.id == environmentID }) else { return }
            workspace.projects[projectIndex].environments[environmentIndex].groups.append(group)
        }
    }

    func addResource(name: String = "新资源") {
        let resource = ResourceRecord(name: name, type: .other)
        update { $0.resources.append(resource) }
        selectedResourceID = resource.id
    }

    func startServicesMarkedForManagerLaunch() {
        guard !didCheckStartupServices else { return }
        didCheckStartupServices = true
        let targets = workspace.projects.flatMap { project in
            project.environments.flatMap { environment in
                environment.services.filter(\.startsWithManager).map {
                    ServiceTarget(projectID: project.id, environmentID: environment.id, serviceID: $0.id)
                }
            }
        }
        guard !targets.isEmpty else { return }
        do {
            try supervisorClient().request(.list) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    let running: Set<UUID>
                    if case .success(.services(let snapshots)) = result {
                        self.processSnapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
                        running = Set(snapshots.filter { $0.state == .running || $0.state == .starting || $0.state == .stopping }.map(\.id))
                    } else {
                        self.handle(result)
                        return
                    }
                    let pending = targets.filter { !running.contains($0.serviceID) }
                    self.startServices(pending)
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func startService(projectID: UUID, environmentID: UUID, serviceID: UUID) {
        guard let service = workspace.projects.first(where: { $0.id == projectID })?.environments.first(where: { $0.id == environmentID })?.services.first(where: { $0.id == serviceID }) else { return }
        serviceErrors[serviceID] = nil
        processSnapshots[serviceID] = SupervisorServiceSnapshot(id: serviceID, projectID: projectID, environmentID: environmentID, name: service.name, state: .starting)
        var launchEnvironment = service.environment
        if let runtimeID = service.runtimeResourceID {
            guard let resource = workspace.resources.first(where: { $0.id == runtimeID }),
                  workspace.bindings.contains(where: { $0.projectID == projectID && $0.environmentID == environmentID && $0.resourceID == runtimeID }) else {
                reportServiceFailure(serviceID, message: "所选运行时不存在或未绑定到此项目环境。")
                return
            }
            guard let path = resource.executablePath, FileManager.default.isExecutableFile(atPath: path) else {
                reportServiceFailure(serviceID, message: "所选运行时路径不存在或不可执行：\(resource.executablePath ?? "未设置")")
                return
            }
            let applicableTypes: Set<ResourceType> = [.php, .node]
            guard applicableTypes.contains(resource.type) else {
                reportServiceFailure(serviceID, message: "所选资源不是可用于服务启动的 PHP 或 Node.js 运行时。")
                return
            }
            let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            launchEnvironment["PATH"] = URL(fileURLWithPath: path).deletingLastPathComponent().path + ":" + currentPath
        }
        do {
            let client = try supervisorClient()
            let request = ServiceLaunchRequest(serviceID: service.id, projectID: projectID, environmentID: environmentID, name: service.name, workingDirectory: service.workingDirectory, command: service.command, arguments: service.arguments, environment: launchEnvironment)
            client.request(.start(request)) { [weak self] result in
                Task { @MainActor in self?.handle(result, serviceID: serviceID) }
            }
        } catch { reportServiceFailure(serviceID, message: error.localizedDescription) }
    }

    /// Batch operations use stable service IDs and continue independently when one request fails.
    func startServices(_ targets: [ServiceTarget]) {
        var seen = Set<UUID>()
        for target in targets where seen.insert(target.serviceID).inserted {
            startService(projectID: target.projectID, environmentID: target.environmentID, serviceID: target.serviceID)
        }
    }

    func stopServices(_ serviceIDs: [UUID]) {
        for serviceID in Set(serviceIDs) { stopService(serviceID: serviceID) }
    }

    func restartService(projectID: UUID, environmentID: UUID, serviceID: UUID) {
        let state = processSnapshots[serviceID]?.state
        if state == nil || state == .unknown {
            do {
                try supervisorClient().request(.list) { [weak self] result in
                    Task { @MainActor in
                        guard let self else { return }
                        self.handle(result)
                        if let snapshot = self.processSnapshots[serviceID],
                           snapshot.state == .running || snapshot.state == .starting || snapshot.state == .stopping {
                            self.restartService(projectID: projectID, environmentID: environmentID, serviceID: serviceID)
                        } else {
                            self.startService(projectID: projectID, environmentID: environmentID, serviceID: serviceID)
                        }
                    }
                }
            } catch { errorMessage = error.localizedDescription }
            return
        }
        guard state == .running || state == .starting || state == .stopping else {
            startService(projectID: projectID, environmentID: environmentID, serviceID: serviceID)
            return
        }
        pendingRestarts[serviceID] = ServiceTarget(projectID: projectID, environmentID: environmentID, serviceID: serviceID)
        restartChecksRemaining[serviceID] = 40
        do {
            try supervisorClient().request(.stop(serviceID: serviceID, force: false)) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.handle(result)
                    if case .failure = result { self.cancelRestart(serviceID) }
                    else { self.scheduleRestartCheck(serviceID) }
                }
            }
        } catch { pendingRestarts.removeValue(forKey: serviceID); errorMessage = error.localizedDescription }
    }

    func forceStopAndContinueRestart(_ serviceID: UUID) {
        stopService(serviceID: serviceID, force: true)
        restartChecksRemaining[serviceID] = 40
        scheduleRestartCheck(serviceID)
    }

    private func scheduleRestartCheck(_ serviceID: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.pendingRestarts[serviceID] != nil else { return }
            self.refreshServiceStates {
                guard self.pendingRestarts[serviceID] != nil else { return }
                if self.processSnapshots[serviceID]?.state == .exited {
                    self.finishRestart(serviceID)
                } else {
                    let remaining = (self.restartChecksRemaining[serviceID] ?? 0) - 1
                    self.restartChecksRemaining[serviceID] = remaining
                    if remaining <= 0 { self.forceStopPromptID = serviceID }
                    else { self.scheduleRestartCheck(serviceID) }
                }
            }
        }
    }

    private func finishRestart(_ serviceID: UUID) {
        guard let target = pendingRestarts.removeValue(forKey: serviceID) else { return }
        restartChecksRemaining.removeValue(forKey: serviceID)
        startService(projectID: target.projectID, environmentID: target.environmentID, serviceID: target.serviceID)
    }

    private func cancelRestart(_ serviceID: UUID) {
        pendingRestarts.removeValue(forKey: serviceID)
        restartChecksRemaining.removeValue(forKey: serviceID)
    }

    func stopService(serviceID: UUID, force: Bool = false) {
        do {
            try supervisorClient().request(.stop(serviceID: serviceID, force: force)) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.handle(result)
                    guard !force else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                        self?.refreshServiceStates { [weak self] in
                            guard let self,
                                  let state = self.processSnapshots[serviceID]?.state,
                                  state == .running || state == .stopping else { return }
                            self.forceStopPromptID = serviceID
                        }
                    }
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func refreshServiceStates() {
        refreshServiceStates(completion: nil)
    }

    func observeWorkspace() {
        do { try refreshWorkspaceConfiguration() }
        catch { errorMessage = error.localizedDescription }
        refreshServiceStates()
        refreshObservedServiceLogs()
        guard observationTimer == nil else { return }
        observationTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                do { try self.refreshWorkspaceConfiguration() }
                catch { self.errorMessage = error.localizedDescription }
                self.refreshServiceStates()
                self.refreshObservedServiceLogs()
            }
        }
        if let observationTimer { RunLoop.main.add(observationTimer, forMode: .common) }
    }

    func refreshWorkspaceConfiguration() throws {
        guard try store.refreshFromDisk() else { return }
        workspace = store.workspace
        if let selectedProjectID, !workspace.projects.contains(where: { $0.id == selectedProjectID }) {
            self.selectedProjectID = nil
            selectedEnvironmentID = nil
            selectedServiceID = nil
        } else if let selectedProjectID, let selectedEnvironmentID,
                  let project = workspace.projects.first(where: { $0.id == selectedProjectID }),
                  !project.environments.contains(where: { $0.id == selectedEnvironmentID }) {
            self.selectedEnvironmentID = nil
            selectedServiceID = nil
        }
    }

    func stopObservingWorkspace() {
        observedServiceID = nil
        stopObservationTimerIfUnused()
    }

    private func refreshServiceStates(completion: (() -> Void)?) {
        do {
            try supervisorClient().request(.list) { [weak self] result in
                Task { @MainActor in
                    if case .success(.services(let snapshots)) = result {
                        self?.processSnapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
                    }
                    completion?()
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func observeService(_ serviceID: UUID?) {
        observedServiceID = serviceID
        guard let serviceID else { return }
        do { _ = try supervisorClient() }
        catch { errorMessage = error.localizedDescription; return }
        refreshServiceLogs(serviceID: serviceID)
    }

    func setOutputWindowOpen(_ isOpen: Bool, serviceID: UUID) {
        if isOpen {
            outputWindowServiceIDs.insert(serviceID)
            observeWorkspace()
        } else {
            outputWindowServiceIDs.remove(serviceID)
            stopObservationTimerIfUnused()
        }
    }

    private func refreshObservedServiceLogs() {
        var serviceIDs = outputWindowServiceIDs
        if let observedServiceID { serviceIDs.insert(observedServiceID) }
        serviceIDs.forEach(refreshServiceLogs(serviceID:))
    }

    private func stopObservationTimerIfUnused() {
        guard observedServiceID == nil, outputWindowServiceIDs.isEmpty else { return }
        observationTimer?.invalidate()
        observationTimer = nil
    }

    func refreshServiceLogs(serviceID: UUID) {
        do {
            try supervisorClient().request(.logs(serviceID: serviceID, afterSequence: logSequences[serviceID] ?? 0)) { [weak self] result in
                guard case .success(.logs(let entries, let nextSequence)) = result else { return }
                Task { @MainActor in
                    guard let self else { return }
                    self.logSequences[serviceID] = max(self.logSequences[serviceID] ?? 0, nextSequence > 0 ? nextSequence - 1 : 0)
                    guard !entries.isEmpty else { return }
                    let addition = entries.map(\.text).joined()
                    var text = (self.processLogs[serviceID] ?? "") + addition
                    if text.utf8.count > 65_536 { text = String(text.suffix(50_000)) }
                    self.processLogs[serviceID] = text
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func clearServiceLogs(_ serviceID: UUID) {
        processLogs[serviceID] = ""
    }

    private func supervisorClient() throws -> SupervisorClient {
        if let supervisor { return supervisor }
        let client = try SupervisorClient()
        supervisor = client
        return client
    }

    private func handle(_ result: Result<SupervisorResult, SupervisorClientError>, serviceID: UUID? = nil) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
            if let serviceID { reportServiceFailure(serviceID, message: error.localizedDescription, showAlert: false) }
        case .success(.accepted(let snapshot)):
            processSnapshots[snapshot.id] = snapshot
            serviceErrors[snapshot.id] = nil
        case .success(.failure(_, let message)):
            errorMessage = message
            if let serviceID { reportServiceFailure(serviceID, message: message, showAlert: false) }
        case .success(.services(let snapshots)): processSnapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        case .success(.logs): break
        }
    }

    private func reportServiceFailure(_ serviceID: UUID, message: String, showAlert: Bool = true) {
        serviceErrors[serviceID] = message
        if showAlert { errorMessage = message }
        for project in workspace.projects {
            for environment in project.environments {
                guard let service = environment.services.first(where: { $0.id == serviceID }) else { continue }
                processSnapshots[serviceID] = SupervisorServiceSnapshot(
                    id: serviceID,
                    projectID: project.id,
                    environmentID: environment.id,
                    name: service.name,
                    state: .failed,
                    message: message
                )
                return
            }
        }
    }

    func removeResource(_ resourceID: UUID) {
        update { workspace in
            workspace.resources.removeAll { $0.id == resourceID }
            workspace.bindings.removeAll { $0.resourceID == resourceID }
            for projectIndex in workspace.projects.indices {
                for environmentIndex in workspace.projects[projectIndex].environments.indices {
                    for serviceIndex in workspace.projects[projectIndex].environments[environmentIndex].services.indices where
                        workspace.projects[projectIndex].environments[environmentIndex].services[serviceIndex].runtimeResourceID == resourceID ||
                        workspace.projects[projectIndex].environments[environmentIndex].services[serviceIndex].resourceIDs.contains(resourceID) {
                        if workspace.projects[projectIndex].environments[environmentIndex].services[serviceIndex].runtimeResourceID == resourceID {
                            workspace.projects[projectIndex].environments[environmentIndex].services[serviceIndex].runtimeResourceID = nil
                        }
                        workspace.projects[projectIndex].environments[environmentIndex].services[serviceIndex].resourceIDs.removeAll { $0 == resourceID }
                    }
                }
            }
        }
        if selectedResourceID == resourceID { selectedResourceID = nil }
    }

    func setResourceBinding(_ binding: ProjectEnvironmentBinding, enabled: Bool) {
        update { workspace in
            if enabled {
                guard !workspace.bindings.contains(where: { $0.id == binding.id }) else { return }
                workspace.bindings.append(binding)
            } else {
                workspace.bindings.removeAll { $0.id == binding.id }
            }
        }
    }

    func removeProject(_ projectID: UUID) {
        let serviceIDs = workspace.projects.first(where: { $0.id == projectID })?.environments.flatMap(\.services).map(\.id) ?? []
        guard !containsActiveService(serviceIDs) else {
            errorMessage = "此项目仍有运行中的服务。请先停止这些服务，再删除项目。"
            return
        }
        update { workspace in
            let environmentIDs = Set(workspace.projects.first(where: { $0.id == projectID })?.environments.map(\.id) ?? [])
            workspace.projects.removeAll { $0.id == projectID }
            workspace.bindings.removeAll { $0.projectID == projectID }
            let stillUsed = Set(workspace.projects.flatMap(\.environments).map(\.id))
            workspace.environments.removeAll { environmentIDs.contains($0.id) && !stillUsed.contains($0.id) }
        }
        if selectedProjectID == projectID {
            selectedProjectID = nil
            selectedEnvironmentID = nil
            selectedServiceID = nil
        }
    }

    func removeEnvironment(projectID: UUID, environmentID: UUID) {
        let serviceIDs = workspace.projects.first(where: { $0.id == projectID })?.environments.first(where: { $0.id == environmentID })?.services.map(\.id) ?? []
        guard !containsActiveService(serviceIDs) else {
            errorMessage = "此环境仍有运行中的服务。请先停止这些服务，再删除环境。"
            return
        }
        update { workspace in
            guard let index = workspace.projects.firstIndex(where: { $0.id == projectID }) else { return }
            workspace.projects[index].environments.removeAll { $0.id == environmentID }
            workspace.bindings.removeAll { $0.projectID == projectID && $0.environmentID == environmentID }
            let stillUsed = workspace.projects.contains { project in project.environments.contains { $0.id == environmentID } }
            if !stillUsed { workspace.environments.removeAll { $0.id == environmentID } }
        }
        if selectedEnvironmentID == environmentID {
            selectedEnvironmentID = nil
            selectedServiceID = nil
        }
    }

    func removeService(projectID: UUID, environmentID: UUID, serviceID: UUID) {
        guard !containsActiveService([serviceID]) else {
            errorMessage = "此服务仍在运行。请先停止服务，再删除配置。"
            return
        }
        update { workspace in
            guard let projectIndex = workspace.projects.firstIndex(where: { $0.id == projectID }),
                  let environmentIndex = workspace.projects[projectIndex].environments.firstIndex(where: { $0.id == environmentID }) else { return }
            var environment = workspace.projects[projectIndex].environments[environmentIndex]
            environment.services.removeAll { $0.id == serviceID }
            for index in environment.groups.indices {
                environment.groups[index].serviceIDs.remove(serviceID)
            }
            workspace.projects[projectIndex].environments[environmentIndex] = environment
        }
        if selectedServiceID == serviceID { selectedServiceID = nil }
    }

    func removeGroup(projectID: UUID, environmentID: UUID, groupID: UUID) {
        update { workspace in
            guard let projectIndex = workspace.projects.firstIndex(where: { $0.id == projectID }),
                  let environmentIndex = workspace.projects[projectIndex].environments.firstIndex(where: { $0.id == environmentID }) else { return }
            workspace.projects[projectIndex].environments[environmentIndex].groups.removeAll { $0.id == groupID }
        }
    }

    private func containsActiveService(_ ids: [UUID]) -> Bool {
        ids.contains { id in
            guard let state = processSnapshots[id]?.state else { return false }
            return state == .starting || state == .running || state == .stopping
        }
    }
}
