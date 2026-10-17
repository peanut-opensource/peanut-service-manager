import AppKit
import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @State private var selectedServiceIDs: Set<UUID> = []
    @State private var selectedGroupID: UUID?

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
                projectColumn.frame(minWidth: 160, idealWidth: 190)
                Divider()
                environmentColumn.frame(minWidth: 165, idealWidth: 195)
                Divider()
                serviceColumn.frame(minWidth: 180, idealWidth: 220)
                Divider()
                detailColumn.frame(minWidth: 330, maxWidth: .infinity)
            }
        }
        .background(ManagerStyle.canvas)
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
                Text("管理项目环境与本地服务").font(.callout).foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                MetricPill(title: "项目", value: model.workspace.projects.count, icon: "folder.fill")
                MetricPill(title: "服务", value: model.workspace.projects.flatMap(\.environments).flatMap(\.services).count, icon: "gearshape.2.fill")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(ManagerStyle.canvas)
    }

    private var projectColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("项目") {
                model.addProject()
            }
            List {
                ForEach(uniqueProjects) { item in
                    Button(action: { selectProject(item.id) }) {
                        HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(model.selectedProjectID == item.id ? ManagerStyle.accent : .secondary)
                                    .frame(width: 22)
                            Text(item.name).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .background(model.selectedProjectID == item.id ? ManagerStyle.selection : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contextMenu {
                        Button("删除项目", role: .destructive) { model.removeProject(item.id) }
                    }
                }
            }
        }
    }

    private var environmentColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("环境", enabled: project != nil) {
                guard let projectID = model.selectedProjectID else { return }
                model.addEnvironment(projectID: projectID)
            }
            if let project {
                List {
                    ForEach(uniqueEnvironments(project.environments)) { item in
                        Button(action: { selectEnvironment(item.id) }) {
                            HStack {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .foregroundColor(model.selectedEnvironmentID == item.id ? ManagerStyle.accent : .secondary)
                                    .frame(width: 22)
                                Text(item.name).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 5)
                        .padding(.horizontal, 6)
                        .background(model.selectedEnvironmentID == item.id ? ManagerStyle.selection : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contextMenu {
                            Button("删除环境", role: .destructive) {
                                model.removeEnvironment(projectID: project.id, environmentID: item.id)
                            }
                        }
                    }
                }
            } else {
                emptyMessage("选择项目")
            }
        }
    }

    private var serviceColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("服务", enabled: environment != nil) {
                guard let projectID = model.selectedProjectID,
                      let environmentID = model.selectedEnvironmentID else { return }
                model.addService(projectID: projectID, environmentID: environmentID)
            }
            if let environment {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text("已选 \(selectedServiceIDs.count)").font(.caption).foregroundColor(.secondary)
                        Spacer(minLength: 0)
                        Picker("分组", selection: $selectedGroupID) {
                            Text("选择分组").tag(Optional<UUID>.none)
                            ForEach(uniqueGroups(environment.groups)) { group in Text(group.name).tag(Optional(group.id)) }
                        }
                        .frame(maxWidth: 105)
                        Button("加入") {
                            guard let group = environment.groups.first(where: { $0.id == selectedGroupID }) else { return }
                            selectedServiceIDs.formUnion(group.serviceIDs.intersection(Set(environment.services.map(\.id))))
                        }
                        .disabled(selectedGroupID == nil)
                    }
                    HStack(spacing: 8) {
                        Button("全选") { selectedServiceIDs = Set(uniqueServices(environment.services).map(\.id)) }
                        Spacer(minLength: 0)
                        Button("启动") { runBatch(.start, environment: environment) }.disabled(selectedServiceIDs.isEmpty)
                        Button("停止") { runBatch(.stop, environment: environment) }.disabled(selectedServiceIDs.isEmpty)
                        Button("重启") { runBatch(.restart, environment: environment) }.disabled(selectedServiceIDs.isEmpty)
                    }
                }
                .buttonStyle(.borderless).font(.caption).padding(.horizontal, 12).padding(.bottom, 6)
                List {
                    ForEach(uniqueServices(environment.services)) { item in
                        Button(action: { model.selectedServiceID = item.id }) {
                            HStack {
                                Image(systemName: selectedServiceIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedServiceIDs.contains(item.id) ? ManagerStyle.accent : .secondary)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if selectedServiceIDs.contains(item.id) { selectedServiceIDs.remove(item.id) }
                                        else { selectedServiceIDs.insert(item.id) }
                                    }
                                Image(systemName: "gearshape.fill")
                                    .foregroundColor(model.selectedServiceID == item.id ? ManagerStyle.accent : .secondary)
                                    .frame(width: 22)
                                Text(item.name).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 5)
                        .padding(.horizontal, 6)
                        .background(model.selectedServiceID == item.id ? ManagerStyle.selection : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contextMenu {
                            Button("删除服务", role: .destructive) { removeService(item.id) }
                        }
                    }
                }
            } else {
                emptyMessage("选择环境")
            }
        }
    }

    private var detailColumn: some View {
        Group {
            if let service {
                serviceEditor(service)
            } else if let project {
                projectEditor(project)
            } else if let environment {
                environmentEditor(environment)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3").font(.largeTitle).foregroundColor(.secondary)
                    Text("选择项目、环境或服务以编辑配置")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(24)
        .background(ManagerStyle.panel)
    }

    private func projectEditor(_ project: Project) -> some View {
        Form {
            Section(header: Text("项目配置")) {
                TextField("项目名称", text: projectBinding(project.id, keyPath: \.name))
                Button("删除项目", role: .destructive) { model.removeProject(project.id) }
            }
        }
    }

    private func environmentEditor(_ environment: ProjectEnvironment) -> some View {
        Form {
            Section(header: Text("环境配置")) {
                TextField("环境名称", text: environmentBinding(environment.id, keyPath: \.name))
                Button("删除环境", role: .destructive) {
                    guard let projectID = model.selectedProjectID else { return }
                    model.removeEnvironment(projectID: projectID, environmentID: environment.id)
                }
            }
            groupEditor(environment)
        }
    }

    private func serviceEditor(_ service: Service) -> some View {
        Form {
            Section(header: Text("进程管理")) {
                HStack {
                    Label(processStateLabel(service), systemImage: processStateIcon(service))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundColor(processStateColor(service))
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(processStateColor(service).opacity(0.11))
                        .clipShape(Capsule())
                    Spacer()
                    Button("启动") {
                        guard let projectID = model.selectedProjectID, let environmentID = model.selectedEnvironmentID else { return }
                        model.startService(projectID: projectID, environmentID: environmentID, serviceID: service.id)
                    }
                    .disabled(service.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isActive(service))
                    .buttonStyle(.borderedProminent)
                    .tint(ManagerStyle.accent)
                    Button("停止") { model.stopService(serviceID: service.id) }
                        .disabled(!isActive(service))
                        .buttonStyle(.bordered)
                    Button("重启") {
                        guard let projectID = model.selectedProjectID, let environmentID = model.selectedEnvironmentID else { return }
                        model.restartService(projectID: projectID, environmentID: environmentID, serviceID: service.id)
                    }
                    .disabled(!isActive(service))
                    .buttonStyle(.bordered)
                }
                if let snapshot = model.processSnapshots[service.id], let pid = snapshot.pid {
                    Text("PID \(pid)").font(.caption).foregroundColor(.secondary)
                }
                if let message = model.processSnapshots[service.id]?.message {
                    Text(message).font(.caption).foregroundColor(.secondary)
                }
            }
            Section(header: Text("服务配置")) {
                TextField("服务名称", text: serviceBinding(service.id, keyPath: \.name))
                TextField("工作目录", text: serviceBinding(service.id, keyPath: \.workingDirectory))
                TextField("启动命令", text: serviceBinding(service.id, keyPath: \.command))
                Picker("本机运行时", selection: serviceBinding(service.id, keyPath: \.runtimeResourceID)) {
                    Text("使用当前环境").tag(Optional<UUID>.none)
                    ForEach(boundRuntimeResources) { resource in
                        Text("\(resource.name) · \(resource.version ?? resource.type.displayName)").tag(Optional(resource.id))
                    }
                }
                .help("仅显示已绑定到当前项目环境的 PHP 与 Node.js 运行时")
                VStack(alignment: .leading, spacing: 4) {
                    Text("参数（每行一个）").font(.caption).foregroundColor(.secondary)
                    TextEditor(text: argumentsBinding(service.id)).frame(height: 72)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("说明").font(.caption).foregroundColor(.secondary)
                    TextEditor(text: serviceBinding(service.id, keyPath: \.description)).frame(height: 56)
                }
                Toggle("随管理器启动", isOn: serviceBinding(service.id, keyPath: \.startsWithManager))
            }
            Section(header: Text("环境变量"), footer: Text("每行填写 KEY=VALUE；修改后立即保存。")) {
                TextEditor(text: environmentVariablesBinding(service.id))
                    .frame(height: 100)
            }
            Section(header: HStack {
                Text("近期输出")
                Spacer()
                Button("刷新") { model.refreshServiceLogs(serviceID: service.id) }
                Button("清空视图") { model.clearServiceLogs(service.id) }
            }, footer: Text("仅保留管理器内存中的近期输出；关闭管理器后不会保存日志。")) {
                ScrollView {
                    Text(model.processLogs[service.id].flatMap { $0.isEmpty ? nil : $0 } ?? "服务输出会显示在这里")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(model.processLogs[service.id]?.isEmpty == false ? .primary : .secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 160)
                .background(ManagerStyle.card)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }
            if let environment {
                groupEditor(environment)
            }
            Section(footer: Text("运行中的服务不能删除。停止操作只作用于本管理器启动并登记的进程组。")) {
                Button("删除服务", role: .destructive) { removeService(service.id) }
                    .disabled(isActive(service))
            }
        }
        .onAppear { model.observeService(service.id) }
        .onDisappear { model.observeService(nil) }
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
        case .exited: return .secondary
        case .failed: return Color(red: 0.78, green: 0.31, blue: 0.33)
        case .unknown: return .secondary
        }
    }

    @ViewBuilder
    private func groupEditor(_ environment: ProjectEnvironment) -> some View {
        Section(header: HStack {
            Text("分组")
            Spacer()
            Button("添加分组") {
                guard let projectID = model.selectedProjectID,
                      let environmentID = model.selectedEnvironmentID else { return }
                model.addGroup(projectID: projectID, environmentID: environmentID)
            }
            .disabled(model.selectedEnvironmentID != environment.id)
        }) {
            ForEach(uniqueGroups(environment.groups)) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("分组名称", text: groupBinding(environment.id, groupID: group.id, keyPath: \.name))
                        Button("删除", role: .destructive) { removeGroup(environment.id, groupID: group.id) }
                            .buttonStyle(BorderlessButtonStyle())
                    }
                    if !environment.services.isEmpty {
                        ForEach(uniqueServices(environment.services)) { candidate in
                            Toggle(candidate.name, isOn: membershipBinding(environment.id, groupID: group.id, serviceID: candidate.id))
                                .toggleStyle(CheckboxToggleStyle())
                        }
                    } else {
                        Text("添加服务后可将服务加入多个分组。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func columnHeader(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.secondary)
            Spacer()
            Button(action: action) { Image(systemName: "plus").font(.system(size: 11, weight: .bold)) }
                .buttonStyle(BorderlessButtonStyle())
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
        VStack(spacing: 9) {
            Image(systemName: "arrow.left.circle").font(.title2).foregroundColor(ManagerStyle.accent.opacity(0.72))
            Text(text).font(.callout).foregroundColor(.secondary)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var uniqueProjects: [Project] { unique(model.workspace.projects) }
    private var boundRuntimeResources: [ResourceRecord] {
        guard let projectID = model.selectedProjectID, let environmentID = model.selectedEnvironmentID else { return [] }
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
    }

    private func selectEnvironment(_ id: UUID) {
        model.selectedEnvironmentID = id
        model.selectedServiceID = nil
    }

    private func projectBinding<Value>(_ id: UUID, keyPath: WritableKeyPath<Project, Value>) -> Binding<Value> {
        Binding(get: {
            self.model.workspace.projects.first(where: { $0.id == id })?[keyPath: keyPath] ?? Project(name: "")[keyPath: keyPath]
        }, set: { value in
            self.model.update { workspace in
                guard let index = workspace.projects.firstIndex(where: { $0.id == id }) else { return }
                workspace.projects[index][keyPath: keyPath] = value
            }
        })
    }

    private func environmentBinding<Value>(_ id: UUID, keyPath: WritableKeyPath<ProjectEnvironment, Value>) -> Binding<Value> {
        Binding(get: {
            self.currentEnvironment(id)?[keyPath: keyPath] ?? self.environmentFallback(keyPath)
        }, set: { value in
            self.mutateEnvironment(id) { $0[keyPath: keyPath] = value }
        })
    }

    private func serviceBinding<Value>(_ id: UUID, keyPath: WritableKeyPath<Service, Value>) -> Binding<Value> {
        Binding(get: {
            self.currentService(id)?[keyPath: keyPath] ?? self.serviceFallback(keyPath)
        }, set: { value in
            self.mutateService(id) { $0[keyPath: keyPath] = value }
        })
    }

    private func argumentsBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { self.currentService(id)?.arguments.joined(separator: "\n") ?? "" }, set: { text in
            self.mutateService(id) { $0.arguments = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
        })
    }

    private func environmentVariablesBinding(_ id: UUID) -> Binding<String> {
        Binding(get: {
            (self.currentService(id)?.environment ?? [:]).keys.sorted().map { "\($0)=\(self.currentService(id)?.environment[$0] ?? "")" }.joined(separator: "\n")
        }, set: { text in
            var values: [String: String] = [:]
            for line in text.split(separator: "\n") {
                guard let separator = line.firstIndex(of: "=") else { continue }
                let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: separator)...])
                if !key.isEmpty { values[key] = value }
            }
            self.mutateService(id) { $0.environment = values }
        })
    }

    private func groupBinding<Value>(_ environmentID: UUID, groupID: UUID, keyPath: WritableKeyPath<ServiceGroup, Value>) -> Binding<Value> {
        Binding(get: { self.currentGroup(environmentID, groupID: groupID)?[keyPath: keyPath] ?? self.groupFallback(keyPath) }, set: { value in
            self.mutateEnvironment(environmentID) { environment in
                guard let index = environment.groups.firstIndex(where: { $0.id == groupID }) else { return }
                environment.groups[index][keyPath: keyPath] = value
            }
        })
    }

    private func membershipBinding(_ environmentID: UUID, groupID: UUID, serviceID: UUID) -> Binding<Bool> {
        Binding(get: { self.currentGroup(environmentID, groupID: groupID)?.serviceIDs.contains(serviceID) ?? false }, set: { included in
            self.mutateEnvironment(environmentID) { environment in
                guard let index = environment.groups.firstIndex(where: { $0.id == groupID }) else { return }
                if included { environment.groups[index].serviceIDs.insert(serviceID) }
                else { environment.groups[index].serviceIDs.remove(serviceID) }
            }
        })
    }

    private func currentEnvironment(_ id: UUID) -> ProjectEnvironment? {
        model.workspace.projects.lazy.compactMap { $0.environments.first(where: { $0.id == id }) }.first
    }

    private func currentService(_ id: UUID) -> Service? {
        model.workspace.projects.lazy.flatMap { $0.environments }.compactMap { $0.services.first(where: { $0.id == id }) }.first
    }

    private func currentGroup(_ environmentID: UUID, groupID: UUID) -> ServiceGroup? {
        currentEnvironment(environmentID)?.groups.first { $0.id == groupID }
    }

    private func mutateEnvironment(_ id: UUID, change: (inout ProjectEnvironment) -> Void) {
        model.update { workspace in
            guard let projectIndex = workspace.projects.firstIndex(where: { $0.environments.contains(where: { $0.id == id }) }),
                  let environmentIndex = workspace.projects[projectIndex].environments.firstIndex(where: { $0.id == id }) else { return }
            change(&workspace.projects[projectIndex].environments[environmentIndex])
        }
    }

    private func mutateService(_ id: UUID, change: (inout Service) -> Void) {
        model.update { workspace in
            guard let projectIndex = workspace.projects.firstIndex(where: { $0.environments.contains(where: { $0.services.contains(where: { $0.id == id }) }) }),
                  let environmentIndex = workspace.projects[projectIndex].environments.firstIndex(where: { $0.services.contains(where: { $0.id == id }) }),
                  let serviceIndex = workspace.projects[projectIndex].environments[environmentIndex].services.firstIndex(where: { $0.id == id }) else { return }
            change(&workspace.projects[projectIndex].environments[environmentIndex].services[serviceIndex])
        }
    }

    private func removeService(_ id: UUID) {
        guard let projectID = model.selectedProjectID, let environmentID = model.selectedEnvironmentID else { return }
        model.removeService(projectID: projectID, environmentID: environmentID, serviceID: id)
    }

    private enum BatchAction { case start, stop, restart }

    private func runBatch(_ action: BatchAction, environment: ProjectEnvironment) {
        guard let projectID = model.selectedProjectID else { return }
        let ids = selectedServiceIDs.intersection(Set(environment.services.map(\.id)))
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

    private func removeGroup(_ environmentID: UUID, groupID: UUID) {
        guard let projectID = model.selectedProjectID else { return }
        model.removeGroup(projectID: projectID, environmentID: environmentID, groupID: groupID)
    }

    private var errorBinding: Binding<ErrorAlert?> {
        Binding(get: { self.model.errorMessage.map(ErrorAlert.init) }, set: { _ in self.model.errorMessage = nil })
    }

    private func environmentFallback<Value>(_ keyPath: WritableKeyPath<ProjectEnvironment, Value>) -> Value {
        ProjectEnvironment(name: "")[keyPath: keyPath]
    }

    private func serviceFallback<Value>(_ keyPath: WritableKeyPath<Service, Value>) -> Value {
        Service(name: "", workingDirectory: "", command: "")[keyPath: keyPath]
    }

    private func groupFallback<Value>(_ keyPath: WritableKeyPath<ServiceGroup, Value>) -> Value {
        ServiceGroup(name: "")[keyPath: keyPath]
    }
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
