import AppKit
import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @State private var selectedServiceIDs: Set<UUID> = []
    @State private var selectedGroupID: UUID?
    @State private var editor: WorkspaceEditorPresentation?

    private var project: Project? {
        model.workspace.projects.first { $0.id == model.selectedProjectID }
    }

    private var environment: ProjectEnvironment? {
        project?.environments.first { $0.id == model.selectedEnvironmentID }
    }

    private var service: Service? {
        environment?.services.first { $0.id == model.selectedServiceID }
    }

    var body: some View {
        TabView {
            configurationView
                .tabItem { Label("工作区", systemImage: "square.grid.2x2.fill") }
            ResourceCatalogView(model: model)
                .tabItem { Label("资源", systemImage: "externaldrive.fill") }
            SettingsView(model: model)
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
        .accentColor(ManagerStyle.accent)
        .frame(minWidth: 1000, minHeight: 640)
        .alert(item: errorBinding) { message in
            Alert(title: Text("无法执行操作"), message: Text(message.message), dismissButton: .default(Text("好")))
        }
        .onAppear {
            model.refreshServiceStates()
            model.startServicesMarkedForManagerLaunch()
        }
    }

    private var configurationView: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Divider().opacity(0.55)
            HStack(spacing: 0) {
                projectColumn.frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
                Divider()
                environmentColumn.frame(minWidth: 205, idealWidth: 225, maxWidth: 270)
                Divider()
                serviceColumn.frame(minWidth: 470, maxWidth: .infinity)
            }
        }
        .background(ManagerStyle.canvas)
        .sheet(item: $editor) { presentation in
            editorSheet(presentation)
        }
        .confirmationDialog("服务仍在运行", isPresented: Binding(get: { model.forceStopPromptID != nil }, set: { if !$0 { model.forceStopPromptID = nil } }), titleVisibility: .visible) {
            Button("强制结束服务进程组", role: .destructive) {
                if let serviceID = model.forceStopPromptID { model.forceStopAndContinueRestart(serviceID) }
                model.forceStopPromptID = nil
            }
            Button("继续等待", role: .cancel) { model.forceStopPromptID = nil }
        } message: {
            Text("服务在 10 秒内没有退出。强制结束会向本管理器启动的整个服务进程组发送终止信号。")
        }
        .onChange(of: model.selectedServiceID) { model.observeService($0) }
        .onDisappear { model.observeService(nil) }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(LinearGradient(colors: [ManagerStyle.accent, ManagerStyle.accent.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("工作区").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("按项目、环境和服务浏览本机配置").font(.callout).foregroundColor(.secondary)
            }
            Spacer()
            MetricPill(title: "项目", value: model.workspace.projects.count, icon: "folder.fill")
            MetricPill(title: "服务", value: allServices.count, icon: "gearshape.2.fill")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(ManagerStyle.canvas)
    }

    private var projectColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("项目", count: uniqueProjects.count) {
                editor = .project(Project(name: ""))
            }
            List {
                ForEach(uniqueProjects) { item in
                    HStack(spacing: 4) {
                        Button { selectProject(item.id) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(model.selectedProjectID == item.id ? ManagerStyle.accent : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).font(.system(.body, design: .rounded).weight(.semibold)).lineLimit(1)
                                    Text("\(item.environments.count) 个环境")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { editor = .project(item) } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                            .help("编辑项目")
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .background(model.selectedProjectID == item.id ? ManagerStyle.selection : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .listRowBackground(Color.clear)
                    .contextMenu {
                        Button("编辑项目") { editor = .project(item) }
                        Button("删除项目", role: .destructive) { model.removeProject(item.id) }
                    }
                }
            }
            .overlay {
                if uniqueProjects.isEmpty { emptyMessage("添加一个项目开始使用") }
            }
        }
        .background(ManagerStyle.canvas)
    }

    private var environmentColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("环境", count: project?.environments.count ?? 0, enabled: project != nil) {
                guard let project else { return }
                editor = .environment(project.id, ProjectEnvironment(name: "开发"))
            }
            if let project {
                List {
                    ForEach(uniqueEnvironments(project.environments)) { item in
                        HStack(spacing: 4) {
                            Button { selectEnvironment(item.id) } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "square.stack.3d.up.fill")
                                        .foregroundColor(model.selectedEnvironmentID == item.id ? ManagerStyle.accent : .secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name).font(.system(.body, design: .rounded).weight(.semibold)).lineLimit(1)
                                        Text("\(item.services.count) 个服务 · \(item.groups.count) 个分组")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button { editor = .environment(project.id, item) } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless)
                                .help("编辑环境")
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 6)
                        .background(model.selectedEnvironmentID == item.id ? ManagerStyle.selection : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button("编辑环境") { editor = .environment(project.id, item) }
                            Button("删除环境", role: .destructive) {
                                model.removeEnvironment(projectID: project.id, environmentID: item.id)
                            }
                        }
                    }
                }
                .overlay {
                    if project.environments.isEmpty { emptyMessage("添加一个环境") }
                }
            } else {
                emptyMessage("先选择一个项目")
            }
        }
        .background(ManagerStyle.canvas)
    }

    private var serviceColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("服务", count: environment?.services.count ?? 0, enabled: environment != nil) {
                guard let project, let environment else { return }
                editor = .service(project.id, environment.id, Service(name: "新服务", workingDirectory: NSHomeDirectory(), command: ""))
            }
            if let environment {
                serviceToolbar(environment)
                List {
                ForEach(uniqueServices(environment.services)) { item in
                        if let project {
                            serviceRow(item, projectID: project.id, environmentID: environment.id)
                        }
                    }
                }
                .overlay {
                    if environment.services.isEmpty { emptyMessage("此环境还没有服务") }
                }
                if let service { selectedServicePanel(service, environment: environment) }
            } else {
                emptyMessage("先选择一个环境")
            }
        }
        .background(ManagerStyle.panel)
    }

    private func serviceToolbar(_ environment: ProjectEnvironment) -> some View {
        HStack(spacing: 8) {
            Text("已选 \(selectedInEnvironment(environment).count)")
                .font(.caption).foregroundColor(.secondary)
            Picker("分组", selection: $selectedGroupID) {
                Text("选择分组").tag(Optional<UUID>.none)
                ForEach(uniqueGroups(environment.groups)) { group in Text(group.name).tag(Optional(group.id)) }
            }
            .frame(maxWidth: 145)
            Button("加入") {
                guard let group = environment.groups.first(where: { $0.id == selectedGroupID }) else { return }
                selectedServiceIDs.formUnion(group.serviceIDs.intersection(Set(environment.services.map(\.id))))
            }
            .disabled(selectedGroupID == nil)
            Spacer()
            Button("全选") { selectedServiceIDs = Set(uniqueServices(environment.services).map(\.id)) }
            Button("启动") { runBatch(.start, environment: environment) }.disabled(selectedInEnvironment(environment).isEmpty)
            Button("停止") { runBatch(.stop, environment: environment) }.disabled(selectedInEnvironment(environment).isEmpty)
            Button("重启") { runBatch(.restart, environment: environment) }.disabled(selectedInEnvironment(environment).isEmpty)
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func serviceRow(_ item: Service, projectID: UUID, environmentID: UUID) -> some View {
        HStack(spacing: 8) {
            Button { model.selectedServiceID = item.id } label: {
                HStack(spacing: 10) {
                    Image(systemName: processStateIcon(item))
                        .foregroundColor(processStateColor(item))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(.system(.body, design: .rounded).weight(.semibold)).lineLimit(1)
                        Text(item.command.isEmpty ? "未设置启动命令" : item.command)
                            .font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("批量选择", isOn: serviceSelection(item.id))
                .labelsHidden()
                .toggleStyle(.checkbox)
            Button { editor = .service(projectID, environmentID, item) } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help("编辑服务配置")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 7)
        .background(model.selectedServiceID == item.id ? ManagerStyle.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .listRowBackground(Color.clear)
        .contextMenu {
            Button("编辑服务") { editor = .service(projectID, environmentID, item) }
            Button("删除服务", role: .destructive) { model.removeService(projectID: projectID, environmentID: environmentID, serviceID: item.id) }
                .disabled(isActive(item))
        }
    }

    private func selectedServicePanel(_ service: Service, environment: ProjectEnvironment) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Label(processStateLabel(service), systemImage: processStateIcon(service))
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundColor(processStateColor(service))
                if let pid = model.processSnapshots[service.id]?.pid {
                    Text("PID \(pid)").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("编辑配置") {
                    guard let project else { return }
                    editor = .service(project.id, environment.id, service)
                }
            }
            HStack(spacing: 16) {
                Label(service.name, systemImage: "gearshape.fill").font(.system(.body, design: .rounded).weight(.bold))
                Text(service.workingDirectory).font(.caption).foregroundColor(.secondary).lineLimit(1).textSelection(.enabled)
            }
            Text(service.command.isEmpty ? "尚未填写启动命令" : service.command)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(service.command.isEmpty ? .secondary : .primary)
                .lineLimit(2)
            HStack {
                Button("启动") {
                    guard let project else { return }
                    model.startService(projectID: project.id, environmentID: environment.id, serviceID: service.id)
                }
                .buttonStyle(.borderedProminent)
                .tint(ManagerStyle.accent)
                .disabled(service.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isActive(service))
                Button("停止") { model.stopService(serviceID: service.id) }
                    .disabled(!isActive(service))
                Button("重启") {
                    guard let project else { return }
                    model.restartService(projectID: project.id, environmentID: environment.id, serviceID: service.id)
                }
                .disabled(!isActive(service))
                Spacer()
            }
            if let message = model.processSnapshots[service.id]?.message {
                Text(message).font(.caption).foregroundColor(.secondary).lineLimit(2)
            }
            if let output = model.processLogs[service.id], !output.isEmpty {
                Text(output.split(separator: "\n").suffix(2).joined(separator: "\n"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(15)
        .background(ManagerStyle.card)
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
    }

    @ViewBuilder private func editorSheet(_ presentation: WorkspaceEditorPresentation) -> some View {
        switch presentation {
        case .project(let project):
            ProjectEditor(project: project) { saveProject($0) }
        case .environment(let projectID, let environment):
            EnvironmentEditor(environment: environment, services: project?.environments.first(where: { $0.id == environment.id })?.services ?? []) {
                saveEnvironment($0, projectID: projectID)
            }
        case .service(let projectID, let environmentID, let service):
            ServiceEditor(service: service, runtimeResources: boundRuntimeResources(projectID: projectID, environmentID: environmentID)) {
                saveService($0, projectID: projectID, environmentID: environmentID)
            }
        }
    }

    private func saveProject(_ edited: Project) {
        model.update { workspace in
            if let index = workspace.projects.firstIndex(where: { $0.id == edited.id }) { workspace.projects[index] = edited }
            else { workspace.projects.append(edited) }
        }
        guard model.errorMessage == nil else { return }
        model.selectedProjectID = edited.id
        model.selectedEnvironmentID = nil
        model.selectedServiceID = nil
        editor = nil
    }

    private func saveEnvironment(_ edited: ProjectEnvironment, projectID: UUID) {
        model.update { workspace in
            guard let projectIndex = workspace.projects.firstIndex(where: { $0.id == projectID }) else { return }
            if let index = workspace.projects[projectIndex].environments.firstIndex(where: { $0.id == edited.id }) {
                workspace.projects[projectIndex].environments[index] = edited
            } else {
                workspace.projects[projectIndex].environments.append(edited)
            }
        }
        guard model.errorMessage == nil else { return }
        model.selectedProjectID = projectID
        model.selectedEnvironmentID = edited.id
        model.selectedServiceID = nil
        editor = nil
    }

    private func saveService(_ edited: Service, projectID: UUID, environmentID: UUID) {
        model.update { workspace in
            guard let projectIndex = workspace.projects.firstIndex(where: { $0.id == projectID }),
                  let environmentIndex = workspace.projects[projectIndex].environments.firstIndex(where: { $0.id == environmentID }) else { return }
            if let index = workspace.projects[projectIndex].environments[environmentIndex].services.firstIndex(where: { $0.id == edited.id }) {
                workspace.projects[projectIndex].environments[environmentIndex].services[index] = edited
            } else {
                workspace.projects[projectIndex].environments[environmentIndex].services.append(edited)
            }
        }
        guard model.errorMessage == nil else { return }
        model.selectedProjectID = projectID
        model.selectedEnvironmentID = environmentID
        model.selectedServiceID = edited.id
        editor = nil
    }

    private func columnHeader(_ title: String, count: Int, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.secondary)
            Text("\(count)").font(.caption2.weight(.semibold)).foregroundColor(.secondary)
            Spacer()
            Button(action: action) { Image(systemName: "plus").font(.system(size: 11, weight: .bold)) }
                .buttonStyle(.borderless)
                .disabled(!enabled)
                .help("添加\(title)")
                .frame(width: 25, height: 25)
                .background(ManagerStyle.selection)
                .clipShape(Circle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func emptyMessage(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up").font(.title2).foregroundColor(ManagerStyle.accent.opacity(0.72))
            Text(text).font(.callout).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var uniqueProjects: [Project] { unique(model.workspace.projects) }
    private var allServices: [Service] { model.workspace.projects.flatMap(\.environments).flatMap(\.services) }
    private func boundRuntimeResources(projectID: UUID, environmentID: UUID) -> [ResourceRecord] {
        let boundIDs = Set(model.workspace.bindings.filter { $0.projectID == projectID && $0.environmentID == environmentID }.map(\.resourceID))
        return model.workspace.resources.filter { boundIDs.contains($0.id) && ($0.type == .php || $0.type == .node) }
    }

    private func uniqueEnvironments(_ values: [ProjectEnvironment]) -> [ProjectEnvironment] { unique(values) }
    private func uniqueServices(_ values: [Service]) -> [Service] { unique(values) }
    private func uniqueGroups(_ values: [ServiceGroup]) -> [ServiceGroup] { unique(values) }

    private func unique<T: Identifiable>(_ values: [T]) -> [T] where T.ID: Hashable {
        var seen = Set<T.ID>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private func selectProject(_ id: UUID) {
        model.selectedProjectID = id
        model.selectedEnvironmentID = nil
        model.selectedServiceID = nil
        selectedServiceIDs = []
        selectedGroupID = nil
    }

    private func selectEnvironment(_ id: UUID) {
        model.selectedEnvironmentID = id
        model.selectedServiceID = nil
        selectedServiceIDs = []
        selectedGroupID = nil
    }

    private func serviceSelection(_ id: UUID) -> Binding<Bool> {
        Binding(get: { selectedServiceIDs.contains(id) }, set: { selected in
            if selected { selectedServiceIDs.insert(id) }
            else { selectedServiceIDs.remove(id) }
        })
    }

    private func selectedInEnvironment(_ environment: ProjectEnvironment) -> Set<UUID> {
        selectedServiceIDs.intersection(Set(environment.services.map(\.id)))
    }

    private func isActive(_ service: Service) -> Bool {
        guard let state = model.processSnapshots[service.id]?.state else { return false }
        return state == .starting || state == .running || state == .stopping
    }

    private func processStateLabel(_ service: Service) -> String {
        guard let snapshot = model.processSnapshots[service.id] else { return "状态未知" }
        switch snapshot.state {
        case .starting: return "启动中"
        case .running: return "运行中"
        case .stopping: return "停止中"
        case .exited: return "已退出"
        case .failed: return "启动或运行失败"
        case .unknown: return "状态未知"
        }
    }

    private func processStateIcon(_ service: Service) -> String {
        guard let state = model.processSnapshots[service.id]?.state else { return "questionmark.circle" }
        switch state {
        case .starting, .running: return "play.circle.fill"
        case .stopping: return "stop.circle"
        case .exited: return "checkmark.circle"
        case .failed: return "exclamationmark.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    private func processStateColor(_ service: Service) -> Color {
        guard let state = model.processSnapshots[service.id]?.state else { return .secondary }
        switch state {
        case .starting, .running: return Color(red: 0.20, green: 0.59, blue: 0.46)
        case .stopping: return Color(red: 0.79, green: 0.52, blue: 0.19)
        case .exited, .unknown: return .secondary
        case .failed: return Color(red: 0.78, green: 0.31, blue: 0.33)
        }
    }

    private enum BatchAction { case start, stop, restart }

    private func runBatch(_ action: BatchAction, environment: ProjectEnvironment) {
        guard let projectID = model.selectedProjectID else { return }
        let ids = selectedInEnvironment(environment)
        switch action {
        case .start:
            model.startServices(ids.map { ServiceTarget(projectID: projectID, environmentID: environment.id, serviceID: $0) })
        case .stop:
            model.stopServices(Array(ids))
        case .restart:
            for serviceID in ids {
                model.restartService(projectID: projectID, environmentID: environment.id, serviceID: serviceID)
            }
        }
    }

    private var errorBinding: Binding<ErrorAlert?> {
        Binding(get: { model.errorMessage.map(ErrorAlert.init) }, set: { _ in model.errorMessage = nil })
    }
}

private enum WorkspaceEditorPresentation: Identifiable {
    case project(Project)
    case environment(UUID, ProjectEnvironment)
    case service(UUID, UUID, Service)

    var id: UUID {
        switch self {
        case .project(let project): return project.id
        case .environment(_, let environment): return environment.id
        case .service(_, _, let service): return service.id
        }
    }
}

private struct ProjectEditor: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var draft: Project
    let onSave: (Project) -> Void

    init(project: Project, onSave: @escaping (Project) -> Void) {
        _draft = State(initialValue: project)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(draft.name.isEmpty ? "新建项目" : "编辑项目").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding()
            Form { TextField("项目名称", text: $draft.name) }
                .padding(.horizontal, 14)
            editorButtons(cancel: { presentationMode.wrappedValue.dismiss() }) { onSave(draft) }
        }
        .frame(width: 420, height: 190)
    }
}

private struct EnvironmentEditor: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var draft: ProjectEnvironment
    let services: [Service]
    let onSave: (ProjectEnvironment) -> Void

    init(environment: ProjectEnvironment, services: [Service], onSave: @escaping (ProjectEnvironment) -> Void) {
        _draft = State(initialValue: environment)
        self.services = services
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("环境设置").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding()
            Form {
                Section("环境") { TextField("环境名称", text: $draft.name) }
                Section {
                    ForEach(draft.groups) { group in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                TextField("分组名称", text: groupName(group.id))
                                Button(role: .destructive) { draft.groups.removeAll { $0.id == group.id } } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            ForEach(services) { service in
                                Toggle(service.name, isOn: groupMembership(groupID: group.id, serviceID: service.id))
                                    .toggleStyle(.checkbox)
                            }
                            if services.isEmpty { Text("保存环境后添加服务，即可管理分组成员。").font(.caption).foregroundColor(.secondary) }
                        }
                        .padding(.vertical, 3)
                    }
                    Button("添加分组") { draft.groups.append(ServiceGroup(name: "新分组")) }
                } header: { Text("服务分组") }
            }
            .padding(.horizontal, 14)
            editorButtons(cancel: { presentationMode.wrappedValue.dismiss() }) { onSave(draft) }
        }
        .frame(minWidth: 520, minHeight: 430)
    }

    private func groupName(_ id: UUID) -> Binding<String> {
        Binding(get: { draft.groups.first(where: { $0.id == id })?.name ?? "" }, set: { name in
            guard let index = draft.groups.firstIndex(where: { $0.id == id }) else { return }
            draft.groups[index].name = name
        })
    }

    private func groupMembership(groupID: UUID, serviceID: UUID) -> Binding<Bool> {
        Binding(get: { draft.groups.first(where: { $0.id == groupID })?.serviceIDs.contains(serviceID) ?? false }, set: { included in
            guard let index = draft.groups.firstIndex(where: { $0.id == groupID }) else { return }
            if included { draft.groups[index].serviceIDs.insert(serviceID) }
            else { draft.groups[index].serviceIDs.remove(serviceID) }
        })
    }
}

private struct ServiceEditor: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var draft: Service
    @State private var argumentsText: String
    @State private var environmentText: String
    let runtimeResources: [ResourceRecord]
    let onSave: (Service) -> Void

    init(service: Service, runtimeResources: [ResourceRecord], onSave: @escaping (Service) -> Void) {
        _draft = State(initialValue: service)
        _argumentsText = State(initialValue: service.arguments.joined(separator: "\n"))
        _environmentText = State(initialValue: service.environment.keys.sorted().map { "\($0)=\(service.environment[$0] ?? "")" }.joined(separator: "\n"))
        self.runtimeResources = runtimeResources
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("服务设置").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding()
            Form {
                Section("启动配置") {
                    TextField("服务名称", text: $draft.name)
                    TextField("工作目录", text: $draft.workingDirectory)
                    TextField("启动命令", text: $draft.command)
                    Picker("本机运行时", selection: $draft.runtimeResourceID) {
                        Text("使用当前环境").tag(Optional<UUID>.none)
                        ForEach(runtimeResources) { resource in
                            Text("\(resource.name) · \(resource.version ?? resource.type.displayName)").tag(Optional(resource.id))
                        }
                    }
                    .help("仅显示已绑定到当前项目环境的 PHP 与 Node.js 运行时")
                    Toggle("随管理器启动", isOn: $draft.startsWithManager)
                }
                Section("参数与说明") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("参数（每行一个）").font(.caption).foregroundColor(.secondary)
                        TextEditor(text: $argumentsText).frame(height: 68)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("说明").font(.caption).foregroundColor(.secondary)
                        TextEditor(text: $draft.description).frame(height: 55)
                    }
                }
                Section("环境变量") {
                    Text("每行填写 KEY=VALUE；只在保存时更新。")
                        .font(.caption).foregroundColor(.secondary)
                    TextEditor(text: $environmentText).frame(height: 90)
                }
            }
            .padding(.horizontal, 14)
            editorButtons(cancel: { presentationMode.wrappedValue.dismiss() }) {
                draft.arguments = argumentsText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                var values: [String: String] = [:]
                for line in environmentText.split(separator: "\n") {
                    guard let separator = line.firstIndex(of: "=") else { continue }
                    let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                    let value = String(line[line.index(after: separator)...])
                    if !key.isEmpty { values[key] = value }
                }
                draft.environment = values
                onSave(draft)
            }
        }
        .frame(minWidth: 650, minHeight: 560)
    }
}

@ViewBuilder
private func editorButtons(cancel: @escaping () -> Void, action: @escaping () -> Void) -> some View {
    HStack {
        Spacer()
        Button("取消", action: cancel)
            .keyboardShortcut(.cancelAction)
        Button("保存", action: action)
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(ManagerStyle.accent)
    }
    .padding(14)
}

enum ManagerStyle {
    static let accent = Color(red: 0.31, green: 0.43, blue: 0.82)
    static let canvas = Color(NSColor.controlBackgroundColor)
    static let panel = Color(NSColor.windowBackgroundColor)
    static let selection = accent.opacity(0.12)
    static let card = Color(NSColor.textBackgroundColor)
}

private struct MetricPill: View {
    let title: String
    let value: Int
    let icon: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundColor(ManagerStyle.accent)
            Text("\(value)").font(.system(.callout, design: .rounded).weight(.bold))
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(ManagerStyle.card.opacity(0.86))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

private struct ErrorAlert: Identifiable {
    let id = UUID()
    let message: String
    init(_ message: String) { self.message = message }
}
