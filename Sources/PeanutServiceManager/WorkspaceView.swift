import AppKit
import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @State private var selectedServiceIDs: Set<UUID> = []
    @State private var selectedGroupFilter: ServiceGroupFilter = .all
    @State private var editor: WorkspaceEditorPresentation?
    @State private var activeTab = 0
    @State private var perspective: WorkspacePerspective = .project
    @State private var pendingEnvironmentRemoval: EnvironmentRemovalTarget?

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
        .frame(minWidth: 1100, minHeight: 640)
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
            if perspective == .project {
                projectColumn.frame(minWidth: 130, idealWidth: 155, maxWidth: 180)
                environmentColumn.frame(minWidth: 140, idealWidth: 170, maxWidth: 195)
            } else {
                sharedEnvironmentColumn.frame(minWidth: 150, idealWidth: 180, maxWidth: 205)
                environmentProjectsColumn.frame(minWidth: 150, idealWidth: 185, maxWidth: 215)
            }
            if let environment {
                serviceWorkspace(environment)
                    .frame(minWidth: 600, idealWidth: 850, maxWidth: .infinity)
            } else {
                emptyMessage("先选择一个环境")
                    .frame(minWidth: 600, maxWidth: .infinity)
            }
        }
        }
        .background(ManagerStyle.canvas)
        .confirmationDialog(pendingEnvironmentRemoval == nil ? "服务仍在运行" : "从项目移除环境？", isPresented: Binding(
            get: { model.forceStopPromptID != nil || pendingEnvironmentRemoval != nil },
            set: { if !$0 { model.forceStopPromptID = nil; pendingEnvironmentRemoval = nil } }
        ), titleVisibility: .visible) {
            if let target = pendingEnvironmentRemoval {
                Button("移除当前项目中的关联", role: .destructive) {
                    model.removeEnvironment(projectID: target.projectID, environmentID: target.environmentID)
                    pendingEnvironmentRemoval = nil
                }
                Button("取消", role: .cancel) { pendingEnvironmentRemoval = nil }
            } else {
                Button("强制结束服务进程组", role: .destructive) {
                    if let serviceID = model.forceStopPromptID { model.forceStopAndContinueRestart(serviceID) }
                    model.forceStopPromptID = nil
                }
                Button("继续等待", role: .cancel) { model.forceStopPromptID = nil }
            }
        } message: {
            if pendingEnvironmentRemoval != nil {
                Text("只移除此项目与环境的关联，并移除此项目在该环境下的服务配置。其他项目仍可使用此环境及其各自的服务配置。")
            } else {
                Text("服务在 10 秒内没有退出。强制结束会向本管理器启动的整个服务进程组发送终止信号。")
            }
        }
        .onAppear {
            model.observeWorkspace()
            model.observeService(model.selectedServiceID)
        }
        .onChange(of: model.selectedServiceID) { model.observeService($0) }
        .onDisappear { model.stopObservingWorkspace() }
    }

    private var workspaceHeader: some View {
        ManagerPageHeader(title: "工作区", subtitle: "按项目、环境和服务浏览本机配置", icon: "square.grid.2x2.fill") {
            Picker("浏览视角", selection: $perspective) {
                Text("项目视角").tag(WorkspacePerspective.project)
                Text("环境视角").tag(WorkspacePerspective.environment)
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
            MetricPill(title: "项目", value: model.workspace.projects.count, icon: "folder.fill")
            MetricPill(title: "服务", value: allServices.count, icon: "gearshape.2.fill")
        }
    }

    private var sharedEnvironmentColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("环境", count: model.workspace.environments.count) {
                guard let project = project ?? uniqueProjects.first else { return }
                editor = .environment(project.id, ProjectEnvironment(name: "开发"), isNew: true)
            }
            List {
                ForEach(model.workspace.environments.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { item in
                    let linkedProjects = uniqueProjects.filter { project in project.environments.contains { $0.id == item.id } }
                    Button {
                        selectSharedEnvironment(item.id)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundColor(model.selectedEnvironmentID == item.id ? ManagerStyle.accent : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).font(.system(.body, design: .rounded).weight(.semibold)).lineLimit(1)
                                Text("关联 \(linkedProjects.count) 个项目")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 5).padding(.horizontal, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(model.selectedEnvironmentID == item.id ? ManagerStyle.selection : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .listRowBackground(Color.clear)
                }
            }
            .overlay { if model.workspace.environments.isEmpty { emptyMessage("先创建一个项目环境") } }
        }
        .background(ManagerStyle.canvas)
    }

    private var environmentProjectsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("使用项目").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.secondary)
                Text("\(projectsForSelectedEnvironment.count)").font(.caption2.weight(.semibold)).foregroundColor(.secondary)
                Spacer()
            }.padding(.horizontal, 14).padding(.vertical, 11)
            List {
                ForEach(projectsForSelectedEnvironment) { item in
                    let target = item.environments.first { $0.id == model.selectedEnvironmentID }
                    Button {
                        guard let target else { return }
                        model.selectedProjectID = item.id
                        model.selectedEnvironmentID = target.id
                        model.selectedServiceID = nil
                        selectedServiceIDs.removeAll()
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(model.selectedProjectID == item.id ? ManagerStyle.accent : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).font(.system(.body, design: .rounded).weight(.semibold)).lineLimit(1)
                                Text("\(target?.services.count ?? 0) 個服務 · \(target?.groups.count ?? 0) 個分組")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 5).padding(.horizontal, 6).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(model.selectedProjectID == item.id ? ManagerStyle.selection : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .listRowBackground(Color.clear)
                }
            }
            .overlay { if model.selectedEnvironmentID == nil { emptyMessage("先选择一个环境") } else if projectsForSelectedEnvironment.isEmpty { emptyMessage("没有关联该环境的项目") } }
        }
        .background(ManagerStyle.canvas)
    }

    private var projectsForSelectedEnvironment: [Project] {
        guard let id = model.selectedEnvironmentID else { return [] }
        return uniqueProjects.filter { $0.environments.contains { $0.id == id } }
    }

    private func selectSharedEnvironment(_ id: UUID) {
        model.selectedEnvironmentID = id
        if !projectsForSelectedEnvironment.contains(where: { $0.id == model.selectedProjectID }),
           let project = projectsForSelectedEnvironment.first {
            model.selectedProjectID = project.id
        }
        model.selectedServiceID = nil
        selectedServiceIDs.removeAll()
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
            HStack(spacing: 8) {
                Text("环境").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.secondary)
                Text("\(project?.environments.count ?? 0)").font(.caption2.weight(.semibold)).foregroundColor(.secondary)
                Spacer()
                Button { if let project { editor = .associateEnvironments(project.id) } } label: {
                    Image(systemName: "link").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.borderless).disabled(project == nil).help("关联已有环境")
                .frame(width: 25, height: 25).background(ManagerStyle.selection).clipShape(Circle())
                Button {
                    guard let project else { return }
                    editor = .environment(project.id, ProjectEnvironment(name: "开发"), isNew: true)
                } label: { Image(systemName: "plus").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(.borderless).disabled(project == nil).help("新建环境")
                    .frame(width: 25, height: 25).background(ManagerStyle.selection).clipShape(Circle())
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
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
                            Button("从当前项目移除环境", role: .destructive) {
                                pendingEnvironmentRemoval = EnvironmentRemovalTarget(projectID: project.id, environmentID: item.id)
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

    private func serviceWorkspace(_ environment: ProjectEnvironment) -> some View {
        VStack(spacing: 0) {
            groupFilterBar(environment)
            Divider()
            HStack(spacing: 0) {
                serviceListPane(environment)
                    .frame(minWidth: 235, idealWidth: 295, maxWidth: 360)
                Divider()
                serviceDetailPane(environment)
                    .frame(minWidth: 340, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ManagerStyle.canvas)
    }

    private func groupFilterBar(_ environment: ProjectEnvironment) -> some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    groupFilterButton("全部（\(uniqueServices(environment.services).count)）", filter: .all, environment: environment)
                    groupFilterButton("未分组（\(ungroupedServices(environment).count)）", filter: .ungrouped, environment: environment)
                    ForEach(uniqueGroups(environment.groups)) { group in
                        groupFilterButton("\(group.name)（\(services(in: group, environment: environment).count)）", filter: .group(group.id), environment: environment)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
            Button {
                guard let project else { return }
                editor = .groups(project.id, environment)
            } label: {
                Label("管理分组", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.trailing, 14)
        }
        .background(ManagerStyle.card)
    }

    private func groupFilterButton(_ title: String, filter: ServiceGroupFilter, environment: ProjectEnvironment) -> some View {
        let isSelected = selectedGroupFilter == filter
        return Button {
            selectedGroupFilter = filter
            if let selectedID = model.selectedServiceID,
               !filteredServices(in: environment, filter: filter).contains(where: { $0.id == selectedID }) {
                model.selectedServiceID = nil
            }
        } label: {
            Text(title)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundColor(isSelected ? .white : ManagerStyle.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(isSelected ? ManagerStyle.accent : ManagerStyle.canvas)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func serviceListPane(_ environment: ProjectEnvironment) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("服务")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Text("\(visibleServices(environment).count)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(selectedInEnvironment(environment).count) 项已选")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(visibleServices(environment)) { item in
                        if let project {
                            serviceRow(item, projectID: project.id, environmentID: environment.id)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if visibleServices(environment).isEmpty {
                    emptyMessage(environment.services.isEmpty ? "此环境还没有服务" : "此分组下还没有服务")
                }
            }

            serviceListFooter(environment)
        }
        .background(ManagerStyle.canvas)
    }

    private func serviceListFooter(_ environment: ProjectEnvironment) -> some View {
        HStack(spacing: 8) {
            Menu {
                Button("全选当前列表") { selectedServiceIDs.formUnion(visibleServiceIDs(environment)) }
                    .disabled(visibleServices(environment).isEmpty)
                Button("清除选择") { selectedServiceIDs = [] }
                    .disabled(selectedInEnvironment(environment).isEmpty)
                Divider()
                Button("启动所选") { runBatch(.start, environment: environment) }
                    .disabled(selectedInEnvironment(environment).isEmpty)
                Button("停止所选") { runBatch(.stop, environment: environment) }
                    .disabled(selectedInEnvironment(environment).isEmpty)
                Button("重启所选") { runBatch(.restart, environment: environment) }
                    .disabled(selectedInEnvironment(environment).isEmpty)
            } label: {
                Label("批量操作", systemImage: "checklist")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer(minLength: 2)
            Button {
                guard let project else { return }
                editor = .service(project.id, environment.id, Service(name: "新服务", workingDirectory: NSHomeDirectory(), command: ""), isNew: true)
            } label: { Label("添加服务", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
                .tint(ManagerStyle.accent)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 62)
        .background(ManagerStyle.card)
        .overlay(alignment: .top) { Rectangle().fill(ManagerStyle.cardBorder).frame(height: 1) }
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
        .contextMenu {
            Button("编辑服务") { editor = .service(projectID, environmentID, item, isNew: false) }
            Button("删除服务", role: .destructive) { model.removeService(projectID: projectID, environmentID: environmentID, serviceID: item.id) }
                .disabled(isActive(item))
        }
    }

    private func serviceDetailPane(_ environment: ProjectEnvironment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            detailHeader
            if let service {
                serviceDetailContent(service, environment: environment)
            } else {
                emptyMessage("从左侧选择服务，查看状态、配置和运行输出")
            }
            serviceDetailFooter(environment)
        }
        .background(ManagerStyle.canvas)
    }

    private var detailHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "gearshape.2.fill")
                .foregroundColor(ManagerStyle.accent)
                .frame(width: 34, height: 34)
                .background(ManagerStyle.selection)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("服务详情").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                Text(service?.name ?? "未选择服务")
                    .font(.system(.headline, design: .rounded).weight(.bold)).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let service { stateBadge(service) }
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(ManagerStyle.card)
    }

    @ViewBuilder
    private func serviceDetailContent(_ service: Service, environment: ProjectEnvironment) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    detailMetric("进程", value: model.processSnapshots[service.id]?.pid.map(String.init) ?? "未启动", icon: "number")
                    if let code = model.processSnapshots[service.id]?.exitCode {
                        detailMetric("退出码", value: String(code), icon: "arrow.turn.down.right")
                    }
                    if service.startsWithManager {
                        detailMetric("启动方式", value: "随应用启动", icon: "power")
                    }
                }
                if let domain = service.domain, !domain.isEmpty {
                    detailCard("访问入口", icon: "globe") {
                        Text(service.port.map { "\(domain):\($0)" } ?? domain)
                            .font(.system(.body, design: .monospaced).weight(.medium))
                            .textSelection(.enabled)
                    }
                }
                detailCard("启动配置", icon: "terminal") {
                    VStack(alignment: .leading, spacing: 9) {
                        detailValue("工作目录", service.workingDirectory, monospaced: true)
                        detailValue("启动命令", service.command.isEmpty ? "尚未填写" : service.command, monospaced: true)
                        if !service.arguments.isEmpty {
                            detailValue("启动参数", service.arguments.joined(separator: " "), monospaced: true)
                        }
                        if let runtimeID = service.runtimeResourceID,
                           let runtime = model.workspace.resources.first(where: { $0.id == runtimeID }) {
                            detailValue("本机运行时", runtime.name)
                        }
                    }
                }
                if !service.environment.isEmpty {
                    detailCard("环境变量", icon: "curlybraces") {
                        Text(service.environment.keys.sorted().joined(separator: " · "))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
                if !service.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailCard("服务说明", icon: "text.quote") {
                        Text(service.description).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let message = model.serviceErrors[service.id] ?? model.processSnapshots[service.id]?.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                detailLogPanel(service)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func serviceDetailFooter(_ environment: ProjectEnvironment) -> some View {
        Group {
            if let service, let project {
                HStack(spacing: 8) {
                    Button {
                        editor = .service(project.id, environment.id, service, isNew: false)
                    } label: { Label("编辑", systemImage: "pencil") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button {
                        ServiceOutputWindowPresenter.show(model: model, service: service)
                    } label: { Label("独立输出", systemImage: "macwindow") }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Spacer(minLength: 4)
                    Button {
                        model.stopService(serviceID: service.id)
                    } label: { Label("停用", systemImage: "stop.fill") }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!isActive(service))
                    Button {
                        model.restartService(projectID: project.id, environmentID: environment.id, serviceID: service.id)
                    } label: { Label("重启", systemImage: "arrow.clockwise") }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!isActive(service))
                    Button {
                        model.startService(projectID: project.id, environmentID: environment.id, serviceID: service.id)
                    } label: { Label("启用", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                        .tint(ManagerStyle.accent)
                        .controlSize(.small)
                        .disabled(service.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isActive(service))
                }
            } else {
                HStack { Text("选择服务后可执行操作").font(.caption).foregroundColor(.secondary); Spacer() }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 62)
        .background(ManagerStyle.card)
        .overlay(alignment: .top) { Rectangle().fill(ManagerStyle.cardBorder).frame(height: 1) }
    }

    private func detailMetric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(.callout, design: .rounded).weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ManagerStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundColor(ManagerStyle.ink)
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ManagerStyle.card)
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(ManagerStyle.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func detailValue(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundColor(.secondary)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailLogPanel(_ service: Service) -> some View {
        detailCard("运行输出", icon: "terminal") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("本窗口显示服务的近期输出")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("清空") { model.clearServiceLogs(service.id) }
                        .font(.caption).disabled((model.processLogs[service.id] ?? "").isEmpty)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(logText(service))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor((model.processLogs[service.id] ?? "").isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                            .textSelection(.enabled)
                            .padding(10)
                            .id("log-bottom")
                    }
                    .frame(height: 150)
                    .onAppear { proxy.scrollTo("log-bottom", anchor: .bottom) }
                    .onChange(of: model.processLogs[service.id] ?? "") { _ in proxy.scrollTo("log-bottom", anchor: .bottom) }
                }
                .background(ManagerStyle.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
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
            EnvironmentEditor(environment: environment, isNew: isNew) {
                saveEnvironment($0, projectID: projectID)
            }
        case .groups(let projectID, let environment):
            GroupsEditor(environment: environment) { saveGroups($0, projectID: projectID) }
        case .service(let projectID, let environmentID, let service, let isNew):
            let groups = project?.environments.first(where: { $0.id == environmentID })?.groups ?? []
            ServiceEditor(service: service, groups: groups, runtimeResources: boundRuntimeResources(projectID: projectID, environmentID: environmentID), isNew: isNew) { edited, groupIDs in
                saveService(edited, groupIDs: groupIDs, projectID: projectID, environmentID: environmentID)
            }
        case .associateEnvironments(let projectID):
            EnvironmentAssociationEditor(
                projectName: model.workspace.projects.first(where: { $0.id == projectID })?.name ?? "项目",
                catalog: model.workspace.environments,
                associatedIDs: Set(model.workspace.projects.first(where: { $0.id == projectID })?.environments.map(\.id) ?? [])
            ) { selectedIDs in
                associateEnvironments(selectedIDs, projectID: projectID)
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
                if let catalogIndex = workspace.environments.firstIndex(where: { $0.id == edited.id }) {
                    workspace.environments[catalogIndex].name = edited.name
                }
                for projectIndex in workspace.projects.indices {
                    for environmentIndex in workspace.projects[projectIndex].environments.indices where workspace.projects[projectIndex].environments[environmentIndex].id == edited.id {
                        workspace.projects[projectIndex].environments[environmentIndex].name = edited.name
                    }
                }
            } else {
                workspace.projects[projectIndex].environments.append(edited)
                if !workspace.environments.contains(where: { $0.id == edited.id }) {
                    workspace.environments.append(WorkspaceEnvironment(id: edited.id, name: edited.name))
                }
            }
        }
        guard model.errorMessage == nil else { return }
        model.selectedProjectID = projectID
        model.selectedEnvironmentID = edited.id
        model.selectedServiceID = nil
        editor = nil
    }

    private func associateEnvironments(_ ids: Set<UUID>, projectID: UUID) {
        model.update { workspace in
            guard let projectIndex = workspace.projects.firstIndex(where: { $0.id == projectID }) else { return }
            let existing = Set(workspace.projects[projectIndex].environments.map(\.id))
            for environment in workspace.environments where ids.contains(environment.id) && !existing.contains(environment.id) {
                workspace.projects[projectIndex].environments.append(ProjectEnvironment(id: environment.id, name: environment.name))
            }
        }
        guard model.errorMessage == nil else { return }
        editor = nil
    }

    private func saveGroups(_ edited: ProjectEnvironment, projectID: UUID) {
        model.update { workspace in
            guard let projectIndex = workspace.projects.firstIndex(where: { $0.id == projectID }),
                  let environmentIndex = workspace.projects[projectIndex].environments.firstIndex(where: { $0.id == edited.id }) else { return }
            workspace.projects[projectIndex].environments[environmentIndex].groups = edited.groups
        }
        guard model.errorMessage == nil else { return }
        if case .group(let groupID) = selectedGroupFilter,
           !edited.groups.contains(where: { $0.id == groupID }) {
            selectedGroupFilter = .all
        }
        editor = nil
    }

    private func saveService(_ edited: Service, groupIDs: Set<UUID>, projectID: UUID, environmentID: UUID) {
        model.update { workspace in
            guard let projectIndex = workspace.projects.firstIndex(where: { $0.id == projectID }),
                  let environmentIndex = workspace.projects[projectIndex].environments.firstIndex(where: { $0.id == environmentID }) else { return }
            if let index = workspace.projects[projectIndex].environments[environmentIndex].services.firstIndex(where: { $0.id == edited.id }) {
                workspace.projects[projectIndex].environments[environmentIndex].services[index] = edited
            } else {
                workspace.projects[projectIndex].environments[environmentIndex].services.append(edited)
            }
            for index in workspace.projects[projectIndex].environments[environmentIndex].groups.indices {
                if groupIDs.contains(workspace.projects[projectIndex].environments[environmentIndex].groups[index].id) {
                    workspace.projects[projectIndex].environments[environmentIndex].groups[index].serviceIDs.insert(edited.id)
                } else {
                    workspace.projects[projectIndex].environments[environmentIndex].groups[index].serviceIDs.remove(edited.id)
                }
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
        selectedGroupFilter = .all
    }

    private func selectEnvironment(_ id: UUID) {
        model.selectedEnvironmentID = id
        model.selectedServiceID = nil
        selectedServiceIDs = []
        selectedGroupFilter = .all
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

    private func visibleServices(_ environment: ProjectEnvironment) -> [Service] {
        filteredServices(in: environment, filter: selectedGroupFilter)
    }

    private func filteredServices(in environment: ProjectEnvironment, filter: ServiceGroupFilter) -> [Service] {
        let uniqueList = uniqueServices(environment.services)
        switch filter {
        case .all:
            return uniqueList
        case .ungrouped:
            let groupedIDs = Set(environment.groups.flatMap(\.serviceIDs))
            return uniqueList.filter { !groupedIDs.contains($0.id) }
        case .group(let id):
            guard let group = environment.groups.first(where: { $0.id == id }) else { return [] }
            return services(in: group, environment: environment)
        }
    }

    private func services(in group: ServiceGroup, environment: ProjectEnvironment) -> [Service] {
        let memberIDs = group.serviceIDs.intersection(Set(environment.services.map(\.id)))
        return uniqueServices(environment.services).filter { memberIDs.contains($0.id) }
    }

    private func ungroupedServices(_ environment: ProjectEnvironment) -> [Service] {
        filteredServices(in: environment, filter: .ungrouped)
    }

    private func visibleServiceIDs(_ environment: ProjectEnvironment) -> Set<UUID> {
        Set(visibleServices(environment).map(\.id))
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

private enum WorkspacePerspective: Hashable {
    case project
    case environment
}

private enum ServiceGroupFilter: Hashable {
    case all
    case ungrouped
    case group(UUID)
}

private struct EnvironmentRemovalTarget {
    let projectID: UUID
    let environmentID: UUID
}

private enum WorkspaceEditorPresentation: Identifiable {
    case project(Project, isNew: Bool)
    case environment(UUID, ProjectEnvironment, isNew: Bool)
    case groups(UUID, ProjectEnvironment)
    case service(UUID, UUID, Service, isNew: Bool)
    case associateEnvironments(UUID)

    var id: UUID {
        switch self {
        case .project(let project, _): return project.id
        case .environment(_, let environment, _): return environment.id
        case .groups(_, let environment): return environment.id
        case .service(_, _, let service, _): return service.id
        case .associateEnvironments(let projectID): return projectID
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
            ManagerEditorHeader(
                title: isNew ? "新建项目" : "编辑项目",
                subtitle: "为服务配置归属项目",
                icon: "folder.fill"
            )
            ScrollView {
                ManagerFormCard("项目信息", subtitle: "项目名称会显示在工作区和服务列表中。", icon: "folder") {
                    ManagerTextField(title: "项目名称", placeholder: "例如 Peanut Admin", text: $draft.name)
                }
                .padding(20)
            }
            .background(ManagerStyle.canvas)
            editorButtons(cancel: { presentationMode.wrappedValue.dismiss() }, canSave: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { onSave(draft) }
        }
        .frame(width: 500, height: 270)
        .background(ManagerStyle.canvas)
    }
}

private struct GroupsEditor: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var draft: ProjectEnvironment
    @State private var newGroupName = ""
    @State private var editingGroupID: UUID?
    let onSave: (ProjectEnvironment) -> Void

    init(environment: ProjectEnvironment, onSave: @escaping (ProjectEnvironment) -> Void) {
        _draft = State(initialValue: environment)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            ManagerEditorHeader(
                title: "管理分组",
                subtitle: "\(draft.name) · 分组只属于当前环境，可把服务加入多个分组",
                icon: "tag.fill"
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ManagerFormCard("添加分组", subtitle: "分组只属于当前环境，一个服务可以加入多个分组。", icon: "tag") {
                        HStack(alignment: .bottom, spacing: 10) {
                            ManagerTextField(title: "分组名称", placeholder: "例如 后端服务", text: $newGroupName)
                            Button {
                                let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                draft.groups.append(ServiceGroup(name: name))
                                newGroupName = ""
                            } label: { Label("添加", systemImage: "plus") }
                                .buttonStyle(.borderedProminent).tint(ManagerStyle.accent)
                                .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    ManagerFormCard("分组列表", subtitle: "编辑分组名称和成员；删除分组不会删除服务。", icon: "list.bullet") {
                        if draft.groups.isEmpty {
                            Text("还没有分组。请使用上方输入框添加。")
                                .font(.callout).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(draft.groups.enumerated()), id: \.element.id) { index, group in
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(spacing: 10) {
                                            Image(systemName: "tag.fill").foregroundColor(ManagerStyle.accent)
                                            if editingGroupID == group.id {
                                                ManagerTextField(title: "分组名称", placeholder: "分组名称", text: groupName(group.id))
                                            } else {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(group.name).font(.system(.body, design: .rounded).weight(.semibold)).foregroundColor(ManagerStyle.ink)
                                                    Text("\(group.serviceIDs.intersection(Set(draft.services.map(\.id))).count) 个服务")
                                                        .font(.caption).foregroundColor(.secondary)
                                                }
                                            }
                                            Spacer(minLength: 8)
                                            Button(editingGroupID == group.id ? "完成编辑" : "编辑") {
                                                editingGroupID = editingGroupID == group.id ? nil : group.id
                                            }.buttonStyle(.bordered)
                                            Button(role: .destructive) { draft.groups.removeAll { $0.id == group.id } } label: {
                                                Image(systemName: "trash")
                                            }.buttonStyle(.bordered).help("删除分组")
                                        }
                                        if editingGroupID == group.id {
                                            if uniqueServices(draft.services).isEmpty {
                                                Text("当前环境还没有服务。添加服务后可在服务编辑页选择所属分组。")
                                                    .font(.caption).foregroundColor(.secondary)
                                            } else {
                                                VStack(alignment: .leading, spacing: 0) {
                                                    ForEach(uniqueServices(draft.services)) { service in
                                                        Toggle(isOn: membership(groupID: group.id, serviceID: service.id)) {
                                                            VStack(alignment: .leading, spacing: 2) {
                                                                Text(service.name).font(.system(.callout, design: .rounded).weight(.semibold))
                                                                Text(service.command.isEmpty ? "未设置启动命令" : service.command).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                                            }
                                                        }
                                                        .toggleStyle(.checkbox).padding(.vertical, 7)
                                                    }
                                                }
                                                .padding(.horizontal, 11).background(ManagerStyle.canvas)
                                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 12)
                                    if index < draft.groups.count - 1 { Divider() }
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(ManagerStyle.canvas)
            editorButtons(cancel: { presentationMode.wrappedValue.dismiss() }) { onSave(draft) }
        }
        .frame(width: 660, height: editorHeight)
        .background(ManagerStyle.canvas)
    }

    private var editorHeight: CGFloat {
        max(480, min(720, (NSScreen.main?.visibleFrame.height ?? 820) - 100))
    }

    private func groupName(_ id: UUID) -> Binding<String> {
        Binding(get: { draft.groups.first(where: { $0.id == id })?.name ?? "" }, set: { name in
            guard let index = draft.groups.firstIndex(where: { $0.id == id }) else { return }
            draft.groups[index].name = name
        })
    }

    private func membership(groupID: UUID, serviceID: UUID) -> Binding<Bool> {
        Binding(get: { draft.groups.first(where: { $0.id == groupID })?.serviceIDs.contains(serviceID) ?? false }, set: { included in
            guard let index = draft.groups.firstIndex(where: { $0.id == groupID }) else { return }
            if included { draft.groups[index].serviceIDs.insert(serviceID) }
            else { draft.groups[index].serviceIDs.remove(serviceID) }
        })
    }

    private func uniqueServices(_ services: [Service]) -> [Service] {
        var seen = Set<UUID>()
        return services.filter { seen.insert($0.id).inserted }
    }
}

private struct EnvironmentEditor: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var draft: ProjectEnvironment
    let isNew: Bool
    let onSave: (ProjectEnvironment) -> Void

    init(environment: ProjectEnvironment, isNew: Bool, onSave: @escaping (ProjectEnvironment) -> Void) {
        _draft = State(initialValue: environment)
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            ManagerEditorHeader(
                title: isNew ? "新建环境" : "编辑环境",
                subtitle: "环境可关联多个项目；各项目中的服务配置分别保存",
                icon: "square.stack.3d.up.fill"
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ManagerFormCard("环境信息", subtitle: "环境属于当前项目。", icon: "square.stack.3d.up") {
                        ManagerTextField(title: "环境名称", placeholder: "例如 开发环境", text: $draft.name)
                    }

                }
                .padding(18)
            }
            .background(ManagerStyle.canvas)
            editorButtons(cancel: { presentationMode.wrappedValue.dismiss() }, canSave: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { onSave(draft) }
        }
        .frame(width: 620, height: editorHeight)
        .background(ManagerStyle.canvas)
    }

    private var editorHeight: CGFloat {
        max(420, min(500, (NSScreen.main?.visibleFrame.height ?? 720) - 80))
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

private struct EnvironmentAssociationEditor: View {
    @Environment(\.presentationMode) private var presentationMode
    let projectName: String
    let catalog: [WorkspaceEnvironment]
    let associatedIDs: Set<UUID>
    let onSave: (Set<UUID>) -> Void
    @State private var selectedIDs: Set<UUID> = []

    private var available: [WorkspaceEnvironment] {
        catalog.filter { !associatedIDs.contains($0.id) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            ManagerEditorHeader(title: "关联已有环境", subtitle: "将共享环境关联到 (projectName)；各项目的服务配置仍各自独立。", icon: "link")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ManagerFormCard("可关联环境", subtitle: "可一次选择多个环境。已关联的环境不会重复显示。", icon: "square.stack.3d.up") {
                        if available.isEmpty {
                            Text(catalog.isEmpty ? "还没有可复用的环境。请先新建一个环境。" : "此项目已关联全部环境。")
                                .font(.callout).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(available.enumerated()), id: \.element.id) { index, environment in
                                    Toggle(isOn: Binding(
                                        get: { selectedIDs.contains(environment.id) },
                                        set: { selected in
                                            if selected { selectedIDs.insert(environment.id) }
                                            else { selectedIDs.remove(environment.id) }
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(environment.name).font(.system(.callout, design: .rounded).weight(.semibold))
                                            Text("共享环境 · ID (environment.id.uuidString.prefix(8))")
                                                .font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    .toggleStyle(.checkbox).padding(.vertical, 9)
                                    if index < available.count - 1 { Divider() }
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(ManagerStyle.canvas)
            editorButtons(cancel: { presentationMode.wrappedValue.dismiss() }, canSave: !selectedIDs.isEmpty) {
                onSave(selectedIDs)
            }
        }
        .frame(width: 560, height: 480)
        .background(ManagerStyle.canvas)
    }
}

private struct ServiceEditor: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var draft: Service
    @State private var argumentsText: String
    @State private var environmentText: String
    @State private var domainText: String
    @State private var portText: String
    @State private var selectedGroupIDs: Set<UUID>
    let isNew: Bool
    let groups: [ServiceGroup]
    let runtimeResources: [ResourceRecord]
    let onSave: (Service, Set<UUID>) -> Void

    init(service: Service, groups: [ServiceGroup], runtimeResources: [ResourceRecord], isNew: Bool, onSave: @escaping (Service, Set<UUID>) -> Void) {
        _draft = State(initialValue: service)
        _argumentsText = State(initialValue: service.arguments.joined(separator: "\n"))
        _environmentText = State(initialValue: service.environment.keys.sorted().map { "\($0)=\(service.environment[$0] ?? "")" }.joined(separator: "\n"))
        _domainText = State(initialValue: service.domain ?? "")
        _portText = State(initialValue: service.port.map(String.init) ?? "")
        _selectedGroupIDs = State(initialValue: Set(groups.filter { $0.serviceIDs.contains(service.id) }.map(\.id)))
        self.groups = groups
        self.runtimeResources = runtimeResources
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            ManagerEditorHeader(
                title: isNew ? "新建服务" : "编辑服务",
                subtitle: "配置启动方式、访问入口和运行环境",
                icon: "gearshape.2.fill"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ManagerFormCard("启动配置", subtitle: "管理器会进入工作目录，再按下方命令启动服务。", icon: "terminal.fill") {
                        VStack(alignment: .leading, spacing: 13) {
                            ManagerTextField(title: "服务名称", placeholder: "例如 API 服务", text: $draft.name)
                            ManagerTextField(title: "工作目录", placeholder: "/项目/所在目录", hint: "服务启动前切换到此目录。", text: $draft.workingDirectory)
                            ManagerTextField(title: "启动命令", placeholder: "例如 php artisan serve", hint: "只填写命令本身；后续参数放到“启动参数”栏。", text: $draft.command)
                            Picker("本机运行时", selection: $draft.runtimeResourceID) {
                                Text("使用当前环境").tag(Optional<UUID>.none)
                                ForEach(runtimeResources) { resource in
                                    Text("\(resource.name) · \(resource.version ?? resource.type.displayName)").tag(Optional(resource.id))
                                }
                            }
                            .help("仅显示已绑定到当前项目环境的 PHP 与 Node.js 运行时")
                            Toggle(isOn: $draft.startsWithManager) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("随管理器启动").font(.system(.callout, design: .rounded).weight(.semibold))
                                    Text("打开花生服务管理器时自动启动此服务。")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                        }
                    }

                    ManagerFormCard("访问入口", subtitle: "仅作为本机备注展示，不会配置 DNS、代理或端口转发。", icon: "globe") {
                        HStack(spacing: 10) {
                            ManagerTextField(title: "域名或主机名", placeholder: "api.example.test", text: $domainText)
                            ManagerTextField(title: "端口", placeholder: "8080", hint: "可选", text: $portText)
                                .frame(width: 120)
                                .onChange(of: portText) { value in portText = String(value.filter(\.isNumber).prefix(5)) }
                        }
                        if !validPort { Text("端口范围为 1–65535。").font(.caption).foregroundColor(.red) }
                    }

                    ManagerFormCard("启动参数（可选）", subtitle: "每行填写一个参数项；选项和值分别占一行，管理器会按顺序组合后传给启动命令。", icon: "text.alignleft") {
                        HStack(alignment: .top, spacing: 12) {
                            LabeledTextEditor(
                                title: "命令参数",
                                hint: "一行一项；例如 --port 与 8000 分别占一行。",
                                placeholder: "--host\n0.0.0.0\n--port\n8000",
                                text: $argumentsText,
                                height: 142
                            )
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 9) {
                                Label("填写示例", systemImage: "lightbulb")
                                    .font(.system(.callout, design: .rounded).weight(.semibold))
                                    .foregroundColor(ManagerStyle.accent)
                                Text("启动命令")
                                    .font(.caption).foregroundColor(.secondary)
                                Text("php artisan serve")
                                    .font(.system(.caption, design: .monospaced).weight(.medium))
                                    .textSelection(.enabled)
                                Divider()
                                Text("每行是一个参数项：")
                                    .font(.caption).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("1  --host")
                                    Text("2  0.0.0.0")
                                    Text("3  --port")
                                    Text("4  8000")
                                }
                                .font(.system(.caption, design: .monospaced).weight(.medium)).textSelection(.enabled)
                                Text("第 3、4 项合起来表示 --port 8000。")
                                    .font(.caption2).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                                Divider()
                                Text("组合后的完整启动命令")
                                    .font(.caption).foregroundColor(.secondary)
                                Text("php artisan serve --host 0.0.0.0 --port 8000")
                                    .font(.system(.caption, design: .monospaced).weight(.medium))
                                    .textSelection(.enabled)
                            }
                            .frame(width: 190, alignment: .leading)
                            .padding(12)
                            .background(ManagerStyle.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    ManagerFormCard("服务说明", subtitle: "仅供你和协作者阅读，不会传给服务进程。", icon: "text.quote") {
                        LabeledTextEditor(title: "用途或备注", hint: "例如：本地 API；需先启动数据库。", placeholder: "记录服务用途、启动注意事项或其他说明…", text: $draft.description, height: 82)
                    }

                    ManagerFormCard("所属分组", subtitle: "分组仅作用于当前环境，可选择多个。", icon: "tag") {
                        if groups.isEmpty {
                            Text("当前环境还没有分组。请先在工作区点击“管理分组”创建分组。")
                                .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                                    Toggle(group.name, isOn: Binding(
                                        get: { selectedGroupIDs.contains(group.id) },
                                        set: { included in
                                            if included { selectedGroupIDs.insert(group.id) }
                                            else { selectedGroupIDs.remove(group.id) }
                                        }
                                    ))
                                    .toggleStyle(.checkbox).padding(.vertical, 8)
                                    if index < groups.count - 1 { Divider() }
                                }
                            }
                        }
                    }

                    ManagerFormCard("环境变量（可选）", subtitle: "仅影响此服务及其子进程；每行一项，格式为 KEY=VALUE。", icon: "curlybraces") {
                        LabeledTextEditor(title: "变量列表", hint: "例如开发环境可设 APP_ENV=development。", placeholder: "APP_ENV=development\nPORT=8080", text: $environmentText, height: 116)
                    }
                }
                .padding(18)
            }
            .frame(maxHeight: .infinity)
            .background(ManagerStyle.canvas)

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
                onSave(draft, selectedGroupIDs)
            }
        }
        .frame(width: 760, height: editorHeight)
        .background(ManagerStyle.canvas)
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
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(ManagerStyle.fieldBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

@ViewBuilder
private func editorButtons(cancel: @escaping () -> Void, canSave: Bool = true, action: @escaping () -> Void) -> some View {
    HStack {
        Spacer()
        Button("取消", action: cancel)
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.bordered)
        Button("保存", action: action)
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(ManagerStyle.accent)
            .disabled(!canSave)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 13)
    .background(ManagerStyle.card)
    .overlay(alignment: .top) { Rectangle().fill(ManagerStyle.cardBorder).frame(height: 1) }
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
