import AppKit
import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @State private var selectedServiceIDs: Set<UUID> = []
    @State private var selectedGroupID: UUID?
    @State private var editor: WorkspaceEditorPresentation?
    @State private var activeTab = 0

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
        TabView(selection: $activeTab) {
            configurationView
                .tabItem { Label("工作区", systemImage: "square.grid.2x2.fill") }
                .tag(0)
            ServiceListView(
                model: model,
                onEdit: { projectID, environmentID, service in
                    editor = .service(projectID, environmentID, service, isNew: false)
                },
                onSelect: { projectID, environmentID, serviceID in
                    model.selectedProjectID = projectID
                    model.selectedEnvironmentID = environmentID
                    model.selectedServiceID = serviceID
                    activeTab = 0
                }
            )
            .tabItem { Label("服务列表", systemImage: "list.bullet.rectangle.portrait") }
            .tag(1)
            ResourceCatalogView(model: model)
                .tabItem { Label("资源", systemImage: "externaldrive.fill") }
                .tag(2)
            SettingsView(model: model)
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
                .tag(3)
        }
        .accentColor(ManagerStyle.accent)
        .frame(minWidth: 820, minHeight: 560)
        .sheet(item: $editor) { presentation in editorSheet(presentation) }
        .alert(item: errorBinding) { message in
            Alert(title: Text("无法执行操作"), message: Text(message.message), dismissButton: .default(Text("好")))
        }
        .onAppear {
            model.startServicesMarkedForManagerLaunch()
        }
    }

    private var configurationView: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Divider().opacity(0.55)
        HSplitView {
            projectColumn.frame(minWidth: 130, idealWidth: 155, maxWidth: 180)
            environmentColumn.frame(minWidth: 140, idealWidth: 160, maxWidth: 185)
            serviceColumn.frame(minWidth: 195, idealWidth: 205, maxWidth: 205)
            serviceManagementColumn.frame(minWidth: 280, idealWidth: 360, maxWidth: .infinity)
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
        .onAppear {
            model.observeWorkspace()
            model.observeService(model.selectedServiceID)
        }
        .onChange(of: model.selectedServiceID) { model.observeService($0) }
        .onDisappear { model.stopObservingWorkspace() }
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
                editor = .project(Project(name: ""), isNew: true)
            }
            List {
                ForEach(uniqueProjects) { item in
                    HStack(spacing: 4) {
                        Button { selectProject(item.id) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(model.selectedProjectID == item.id ? ManagerStyle.accent : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).font(.system(.body, design: .rounded).weight(.semibold)).lineLimit(1).minimumScaleFactor(0.78)
                                    Text("\(item.environments.count) 个环境")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { editor = .project(item, isNew: false) } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                            .help("编辑项目")
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .background(model.selectedProjectID == item.id ? ManagerStyle.selection : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .listRowBackground(Color.clear)
                    .contextMenu {
                        Button("编辑项目") { editor = .project(item, isNew: false) }
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
                editor = .environment(project.id, ProjectEnvironment(name: "开发"), isNew: true)
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
                                        Text(item.name).font(.system(.body, design: .rounded).weight(.semibold)).lineLimit(1).minimumScaleFactor(0.78)
                                        Text("\(item.services.count) 个服务 · \(item.groups.count) 个分组")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button { editor = .environment(project.id, item, isNew: false) } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless)
                                .help("编辑环境")
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 6)
                        .background(model.selectedEnvironmentID == item.id ? ManagerStyle.selection : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button("编辑环境") { editor = .environment(project.id, item, isNew: false) }
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
                editor = .service(project.id, environment.id, Service(name: "新服务", workingDirectory: NSHomeDirectory(), command: ""), isNew: true)
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
            } else {
                emptyMessage("先选择一个环境")
            }
        }
        .background(ManagerStyle.card)
    }

    private func serviceToolbar(_ environment: ProjectEnvironment) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("已选 \(selectedInEnvironment(environment).count)")
                    .font(.caption).foregroundColor(.secondary)
                Spacer(minLength: 2)
                Picker("分组", selection: $selectedGroupID) {
                    Text("选择分组").tag(Optional<UUID>.none)
                    ForEach(uniqueGroups(environment.groups)) { group in Text(group.name).tag(Optional(group.id)) }
                }
                .labelsHidden()
                .frame(maxWidth: 115)
                Button {
                    guard let group = environment.groups.first(where: { $0.id == selectedGroupID }) else { return }
                    selectedServiceIDs.formUnion(group.serviceIDs.intersection(Set(environment.services.map(\.id))))
                } label: { Image(systemName: "person.2.badge.plus") }
                    .help("把该分组中的服务加入批量选择，不会修改分组成员")
                    .disabled(selectedGroupID == nil)
            }
            HStack {
                Button("管理分组") {
                    guard let project else { return }
                    editor = .environment(project.id, environment, isNew: false)
                }
                .help("分组属于当前环境；可将服务加入多个分组，方便筛选和批量操作")
                Spacer()
                Menu("批量操作") {
                    Button("全选") { selectedServiceIDs = Set(uniqueServices(environment.services).map(\.id)) }
                    Divider()
                    Button("启动所选") { runBatch(.start, environment: environment) }
                        .disabled(selectedInEnvironment(environment).isEmpty)
                    Button("停止所选") { runBatch(.stop, environment: environment) }
                        .disabled(selectedInEnvironment(environment).isEmpty)
                    Button("重启所选") { runBatch(.restart, environment: environment) }
                        .disabled(selectedInEnvironment(environment).isEmpty)
                }
                .disabled(environment.services.isEmpty)
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(ManagerStyle.accent.opacity(0.055))
        .overlay(alignment: .bottom) { Rectangle().fill(ManagerStyle.accent.opacity(0.12)).frame(height: 1) }
    }

    private func serviceRow(_ item: Service, projectID: UUID, environmentID: UUID) -> some View {
        HStack(spacing: 8) {
            Button { model.selectedServiceID = item.id } label: {
                HStack(spacing: 10) {
                    Image(systemName: processStateIcon(item))
                        .foregroundColor(processStateColor(item))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
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
            Button { editor = .service(projectID, environmentID, item, isNew: false) } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help("编辑服务配置")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(model.selectedServiceID == item.id ? ManagerStyle.accent.opacity(0.10) : Color(NSColor.textBackgroundColor).opacity(0.58))
        .overlay(alignment: .leading) {
            Capsule().fill(model.selectedServiceID == item.id ? ManagerStyle.accent : Color.clear).frame(width: 3).padding(.vertical, 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .listRowBackground(Color.clear)
        .contextMenu {
            Button("编辑服务") { editor = .service(projectID, environmentID, item, isNew: false) }
            Button("删除服务", role: .destructive) { model.removeService(projectID: projectID, environmentID: environmentID, serviceID: item.id) }
                .disabled(isActive(item))
        }
    }

    private var serviceManagementColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("服务面板").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.secondary)
                    Text(service?.name ?? "选择一项服务")
                        .font(.system(.title3, design: .rounded).weight(.bold)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let service { stateBadge(service) }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 16)
            .background(ManagerStyle.accent.opacity(0.045))
            Divider().opacity(0.4)
            if let service, let environment {
                serviceManagementContent(service, environment: environment)
            } else {
                emptyMessage("选择服务后查看状态、操作和运行输出")
            }
        }
        .background(ManagerStyle.card)
    }

    private func serviceManagementContent(_ service: Service, environment: ProjectEnvironment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("进程", systemImage: "number").font(.caption).foregroundColor(.secondary)
                Text(model.processSnapshots[service.id]?.pid.map(String.init) ?? "未启动")
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                Spacer(minLength: 4)
                if let code = model.processSnapshots[service.id]?.exitCode {
                    Text("退出码 \(code)").font(.caption.weight(.medium)).foregroundColor(code == 0 ? .secondary : .red)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("工作目录", systemImage: "folder").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                Text(service.workingDirectory).font(.system(.caption, design: .monospaced)).lineLimit(2).textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("启动命令", systemImage: "chevron.left.forwardslash.chevron.right").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                Text(service.command.isEmpty ? "尚未填写启动命令" : service.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(service.command.isEmpty ? .secondary : .primary)
                    .lineLimit(2).textSelection(.enabled)
            }

            if let domain = service.domain, !domain.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                    Text(service.port.map { "\(domain):\($0)" } ?? domain)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Button { guard let project else { return }; model.startService(projectID: project.id, environmentID: environment.id, serviceID: service.id) } label: {
                        Label("启动", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent).tint(ManagerStyle.accent)
                    .disabled(service.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isActive(service))
                    Button { model.stopService(serviceID: service.id) } label: { Label("停止", systemImage: "stop.fill") }
                        .disabled(!isActive(service))
                    Button {
                        guard let project else { return }
                        model.restartService(projectID: project.id, environmentID: environment.id, serviceID: service.id)
                    } label: { Label("重启", systemImage: "arrow.clockwise") }
                        .disabled(!isActive(service))
                }
                .controlSize(.small)
                HStack(spacing: 8) {
                    Button {
                        guard let project else { return }
                        editor = .service(project.id, environment.id, service, isNew: false)
                    } label: { Label("编辑配置", systemImage: "pencil") }
                    Button { ServiceOutputWindowPresenter.show(model: model, service: service) } label: {
                        Label("独立输出", systemImage: "macwindow")
                    }
                    .help("在单独窗口查看此服务的实时输出")
                }
                .controlSize(.small)
            }

            if let message = model.serviceErrors[service.id] ?? model.processSnapshots[service.id]?.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("运行输出", systemImage: "terminal").font(.system(.callout, design: .rounded).weight(.semibold))
                    Spacer()
                    Button("清空") { model.clearServiceLogs(service.id) }
                        .font(.caption).disabled((model.processLogs[service.id] ?? "").isEmpty)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(logText(service))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor((model.processLogs[service.id] ?? "").isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
                            .textSelection(.enabled)
                            .padding(12)
                            .id("log-bottom")
                    }
                    .onAppear { proxy.scrollTo("log-bottom", anchor: .bottom) }
                    .onChange(of: model.processLogs[service.id] ?? "") { _ in proxy.scrollTo("log-bottom", anchor: .bottom) }
                }
                .frame(maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.10), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
    }

    private func stateBadge(_ service: Service) -> some View {
        Label(processStateLabel(service), systemImage: processStateIcon(service))
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundColor(processStateColor(service))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(processStateColor(service).opacity(0.1))
            .clipShape(Capsule())
    }

    private func logText(_ service: Service) -> String {
        let output = model.processLogs[service.id] ?? ""
        return output.isEmpty ? "服务启动后，标准输出和错误输出会显示在这里。\n本窗口不另开终端，也不会保存历史日志。" : output
    }

    @ViewBuilder private func editorSheet(_ presentation: WorkspaceEditorPresentation) -> some View {
        switch presentation {
        case .project(let project, let isNew):
            ProjectEditor(project: project, isNew: isNew) { saveProject($0) }
        case .environment(let projectID, let environment, let isNew):
            EnvironmentEditor(environment: environment, services: project?.environments.first(where: { $0.id == environment.id })?.services ?? [], isNew: isNew) {
                saveEnvironment($0, projectID: projectID)
            }
        case .service(let projectID, let environmentID, let service, let isNew):
            ServiceEditor(service: service, runtimeResources: boundRuntimeResources(projectID: projectID, environmentID: environmentID), isNew: isNew) {
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
        if model.serviceErrors[service.id] != nil { return "启动失败" }
        guard let snapshot = model.processSnapshots[service.id] else { return "状态未知" }
        switch snapshot.state {
        case .starting: return "启动中"
        case .running: return "运行中"
        case .stopping: return "停止中"
        case .exited: return "已退出"
        case .failed:
            if let code = snapshot.exitCode { return "执行失败 · 退出码 \(code)" }
            return "启动或运行失败"
        case .unknown: return "状态未知"
        }
    }

    private func processStateIcon(_ service: Service) -> String {
        if model.serviceErrors[service.id] != nil { return "exclamationmark.circle.fill" }
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
        if model.serviceErrors[service.id] != nil { return Color(red: 0.78, green: 0.31, blue: 0.33) }
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
    case project(Project, isNew: Bool)
    case environment(UUID, ProjectEnvironment, isNew: Bool)
    case service(UUID, UUID, Service, isNew: Bool)

    var id: UUID {
        switch self {
        case .project(let project, _): return project.id
        case .environment(_, let environment, _): return environment.id
        case .service(_, _, let service, _): return service.id
        }
    }
}

private struct ProjectEditor: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var draft: Project
    let isNew: Bool
    let onSave: (Project) -> Void

    init(project: Project, isNew: Bool, onSave: @escaping (Project) -> Void) {
        _draft = State(initialValue: project)
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? "新建项目" : "编辑项目").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding()
            Form { TextField("项目名称", text: $draft.name).textFieldStyle(.roundedBorder) }
                .padding(.horizontal, 14)
            editorButtons(cancel: { presentationMode.wrappedValue.dismiss() }, canSave: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { onSave(draft) }
        }
        .frame(width: 420, height: 190)
    }
}

private struct EnvironmentEditor: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var draft: ProjectEnvironment
    let isNew: Bool
    let services: [Service]
    let onSave: (ProjectEnvironment) -> Void

    init(environment: ProjectEnvironment, services: [Service], isNew: Bool, onSave: @escaping (ProjectEnvironment) -> Void) {
        _draft = State(initialValue: environment)
        self.services = services
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? "新建环境" : "编辑环境").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding()
            Form {
                Section("环境") { TextField("环境名称", text: $draft.name) }
                Section {
                    Text("分组只把当前环境中的服务组成集合，用于服务列表筛选和批量启停；不会复制服务或改变项目、环境归属。一个服务可以加入多个分组。")
                        .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
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
            editorButtons(cancel: { presentationMode.wrappedValue.dismiss() }, canSave: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { onSave(draft) }
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
    @State private var domainText: String
    @State private var portText: String
    let isNew: Bool
    let runtimeResources: [ResourceRecord]
    let onSave: (Service) -> Void

    init(service: Service, runtimeResources: [ResourceRecord], isNew: Bool, onSave: @escaping (Service) -> Void) {
        _draft = State(initialValue: service)
        _argumentsText = State(initialValue: service.arguments.joined(separator: "\n"))
        _environmentText = State(initialValue: service.environment.keys.sorted().map { "\($0)=\(service.environment[$0] ?? "")" }.joined(separator: "\n"))
        _domainText = State(initialValue: service.domain ?? "")
        _portText = State(initialValue: service.port.map(String.init) ?? "")
        self.runtimeResources = runtimeResources
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isNew ? "新建服务" : "编辑服务").font(.system(.title3, design: .rounded).weight(.bold))
                    Text("配置运行方式、访问入口和服务分组信息").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(ManagerStyle.card)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ServiceEditorSection("启动配置", subtitle: "设置服务启动时执行的命令和本机运行环境。") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("服务名称", text: $draft.name).textFieldStyle(.roundedBorder)
                            TextField("工作目录", text: $draft.workingDirectory).textFieldStyle(.roundedBorder)
                            TextField("启动命令", text: $draft.command).textFieldStyle(.roundedBorder)
                            Picker("本机运行时", selection: $draft.runtimeResourceID) {
                                Text("使用当前环境").tag(Optional<UUID>.none)
                                ForEach(runtimeResources) { resource in
                                    Text("\(resource.name) · \(resource.version ?? resource.type.displayName)").tag(Optional(resource.id))
                                }
                            }
                            .help("仅显示已绑定到当前项目环境的 PHP 与 Node.js 运行时")
                            Toggle("随管理器启动", isOn: $draft.startsWithManager)
                        }
                    }

                    ServiceEditorSection("访问入口", subtitle: "用于列表展示和快速识别，不会自动配置 DNS、代理或修改启动命令。") {
                        HStack(spacing: 10) {
                            TextField("域名或主机名", text: $domainText).textFieldStyle(.roundedBorder)
                            TextField("端口", text: $portText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .onChange(of: portText) { value in portText = String(value.filter(\.isNumber).prefix(5)) }
                        }
                        if !validPort { Text("端口范围为 1–65535。").font(.caption).foregroundColor(.red) }
                    }

                    ServiceEditorSection("启动参数与说明", subtitle: "参数逐行输入；说明仅用于记录，不会传给服务进程。") {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledTextEditor(title: "启动参数", hint: "每行填写一个参数，空行会忽略。", placeholder: "例如：--port\n8080", text: $argumentsText, height: 90)
                            LabeledTextEditor(title: "服务说明", hint: "记录此服务的用途或启动注意事项。", placeholder: "输入服务说明…", text: $draft.description, height: 72)
                        }
                    }

                    ServiceEditorSection("环境变量", subtitle: "仅影响此服务及其子进程；每行一项，格式为 KEY=VALUE。") {
                        LabeledTextEditor(title: "环境变量", hint: "只在保存配置后应用。", placeholder: "例如：APP_ENV=development\nPORT=8080", text: $environmentText, height: 110)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: .infinity)
            .background(ManagerStyle.canvas)

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            editorButtons(cancel: { presentationMode.wrappedValue.dismiss() }, canSave: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validPort) {
                draft.arguments = argumentsText.split(separator: "\n").map(String.init)
                let domain = domainText.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.domain = domain.isEmpty ? nil : domain
                draft.port = Int(portText).flatMap { (1...65535).contains($0) ? $0 : nil }
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
        .frame(width: 680, height: editorHeight)
    }

    private var editorHeight: CGFloat {
        max(420, min(650, (NSScreen.main?.visibleFrame.height ?? 760) - 110))
    }

    private var validPort: Bool {
        let value = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return true }
        guard let port = Int(value) else { return false }
        return (1...65535).contains(port)
    }
}

private struct LabeledTextEditor: View {
    let title: String
    let hint: String
    let placeholder: String
    @Binding var text: String
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(.callout, design: .rounded).weight(.semibold))
            Text(hint).font(.caption).foregroundColor(.secondary)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(NSColor.textBackgroundColor))
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .padding(5)
                    .background(Color.clear)
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.75))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: height)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct ServiceEditorSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(.headline, design: .rounded))
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            content
        }
        .padding(14)
        .background(ManagerStyle.card)
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

@ViewBuilder
private func editorButtons(cancel: @escaping () -> Void, canSave: Bool = true, action: @escaping () -> Void) -> some View {
    HStack {
        Spacer()
        Button("取消", action: cancel)
            .keyboardShortcut(.cancelAction)
        Button("保存", action: action)
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(ManagerStyle.accent)
            .disabled(!canSave)
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
