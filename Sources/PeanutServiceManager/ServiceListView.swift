import SwiftUI
import PeanutServiceIPC

private struct ServiceListEntry: Identifiable {
    let project: Project
    let environment: ProjectEnvironment
    let service: Service
    let groups: [ServiceGroup]

    var id: UUID { service.id }
    var path: String { "\(environment.name) / \(project.name)" }
}
private struct ServiceGroupOption: Identifiable {
    let group: ServiceGroup
    let path: String
    var id: UUID { group.id }
    var label: String { "\(group.name) · \(path)" }
}

enum ServicePresentation {
    case table
    case cards
}

struct ServiceListView: View {
    @ObservedObject var model: AppModel
    let presentation: ServicePresentation
    let onEdit: (UUID, UUID, Service) -> Void
    let onSelect: (UUID, UUID, UUID) -> Void

    @State private var searchText = ""
    @State private var selectedGroupID: UUID?
    @FocusState private var isSearchFocused: Bool

    private var entries: [ServiceListEntry] {
        model.workspace.projects.flatMap { project in
            project.environments.flatMap { environment in
                environment.services.map { service in
                    ServiceListEntry(
                        project: project,
                        environment: environment,
                        service: service,
                        groups: environment.groups.filter { $0.serviceIDs.contains(service.id) }
                    )
                }
            }
        }
    }

    private var groupOptions: [ServiceGroupOption] {
        model.workspace.projects.flatMap { project in
            project.environments.flatMap { environment in
                environment.groups.map { ServiceGroupOption(group: $0, path: "\(environment.name) / \(project.name)") }
            }
        }
    }

    private var filteredEntries: [ServiceListEntry] {
        entries.filter { entry in
            let matchesGroup = selectedGroupID == nil || entry.groups.contains { $0.id == selectedGroupID }
            guard matchesGroup else { return false }
            guard !searchText.isEmpty else { return true }
            let service = entry.service
            let searchable = [
                service.name, service.description, service.command, service.workingDirectory,
                service.host ?? "", (service.domains ?? []).joined(separator: " "), service.port.map(String.init) ?? "", entry.path,
                service.arguments.joined(separator: " "), service.environment.keys.sorted().joined(separator: " ")
            ].joined(separator: " ")
            return searchable.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var runningCount: Int {
        entries.filter { model.processSnapshots[$0.id]?.state == .running }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("搜索服务、地址、项目或启动命令", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundColor(.secondary).help("清除搜索")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(ManagerStyle.field)
                .overlay(RoundedRectangle(cornerRadius: ManagerStyle.radius).stroke(isSearchFocused ? ManagerStyle.accent.opacity(0.72) : ManagerStyle.fieldBorder, lineWidth: isSearchFocused ? 1.5 : 1))
                .clipShape(RoundedRectangle(cornerRadius: ManagerStyle.radius, style: .continuous))

                Picker("服务分组", selection: $selectedGroupID) {
                    Text("全部分组").tag(Optional<UUID>.none)
                    ForEach(groupOptions) { option in
                        Text(option.label).tag(Optional(option.id))
                    }
                }
                .frame(width: 190)
                .help("分组是环境内的服务集合，可用于筛选和批量操作")

                Button { model.refreshServiceStates() } label: {
                    Label("刷新状态", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ManagerButtonStyle(.secondary))
                .help("只更新运行状态，不停止或重启服务")

                Menu("批量操作") {
                    Button("启动当前结果") { startFilteredServices() }
                    Button("停止当前结果") { model.stopServices(filteredEntries.map(\.service.id)) }
                    Button("重启当前结果") { restartFilteredServices() }
                }
                .frame(width: 106)
                .disabled(filteredEntries.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            if filteredEntries.isEmpty {
                ScrollView { emptyState }
            } else if presentation == .table {
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        serviceTable
                            .frame(width: max(geometry.size.width, 1100), height: geometry.size.height)
                            .managerTableSurface()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 350), spacing: 16, alignment: .top)], spacing: 16) {
                        ForEach(filteredEntries) { entry in
                            ServiceOverviewCard(
                                entry: entry,
                                model: model,
                                onEdit: { onEdit(entry.project.id, entry.environment.id, entry.service) },
                                onSelect: { onSelect(entry.project.id, entry.environment.id, entry.service.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(ManagerStyle.canvas)
        .onAppear { model.observeWorkspace() }
        .onDisappear { model.stopObservingWorkspace() }
    }

    private var serviceTable: some View {
        Table(filteredEntries) {
            TableColumn("环境") { entry in
                Text(entry.environment.name).lineLimit(1).help(entry.environment.name)
            }
            .width(min: 145, ideal: 155)
            TableColumn("项目") { entry in
                Text(entry.project.name).lineLimit(1).help(entry.project.name)
            }
            .width(min: 100, ideal: 110)
            TableColumn("服务名称") { entry in
                Button { onSelect(entry.project.id, entry.environment.id, entry.service.id) } label: {
                    Text(model.serviceDisplayName(entry.service))
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .help(model.serviceDisplayName(entry.service))
                }
                .buttonStyle(.plain)
            }
            .width(min: 170, ideal: 220)
            TableColumn("分组") { entry in
                let names = entry.groups.map(\.name).joined(separator: "、")
                Text(names.isEmpty ? "未分组" : names)
                    .foregroundColor(.secondary).lineLimit(2).help(names.isEmpty ? "未分组" : names)
            }
            .width(min: 85, ideal: 100)
            TableColumn("运行状态") { entry in
                ServiceTableStatus(entry: entry, model: model)
            }
            .width(110)
            TableColumn("PID") { entry in
                Text(model.processSnapshots[entry.id]?.pid.map(String.init) ?? "—")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(68)
            TableColumn("访问入口") { entry in
                ServiceAccessLinks(service: entry.service, compact: true)
                    .font(.system(.caption, design: .monospaced))
            }
            .width(min: 145, ideal: 170)
            TableColumn("操作") { entry in
                ServiceEntryActions(
                    entry: entry, model: model, compact: true,
                    onEdit: { onEdit(entry.project.id, entry.environment.id, entry.service) },
                    onSelect: { onSelect(entry.project.id, entry.environment.id, entry.service.id) }
                )
            }
            .width(150)
        }
    }

    private var header: some View {
        ManagerPageHeader(title: presentation == .table ? "服务列表" : "服务卡片", subtitle: "按服务查看运行状态、访问入口和启动配置", icon: presentation == .table ? "list.bullet.rectangle" : "square.grid.2x2.fill") {
            ManagerMetricPill(title: "服务", value: entries.count, icon: "server.rack", color: ManagerStyle.accent)
            ManagerMetricPill(title: "运行中", value: runningCount, icon: "checkmark.circle.fill", color: ManagerStyle.success)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: entries.isEmpty ? "server.rack" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 30)).foregroundColor(ManagerStyle.accent.opacity(0.7))
            Text(entries.isEmpty ? "还没有登记服务" : "没有匹配的服务")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text(entries.isEmpty ? "在服务管理中选择项目和环境后添加服务。" : "调整搜索内容或分组筛选条件。")
                .font(.callout).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func startFilteredServices() {
        model.startServices(filteredEntries.map {
            ServiceTarget(projectID: $0.project.id, environmentID: $0.environment.id, serviceID: $0.service.id)
        })
    }

    private func restartFilteredServices() {
        for entry in filteredEntries {
            model.restartService(projectID: entry.project.id, environmentID: entry.environment.id, serviceID: entry.service.id)
        }
    }
}

@MainActor
private struct ServiceEntryState {
    let entry: ServiceListEntry
    let model: AppModel
    private var service: Service { entry.service }
    var snapshot: SupervisorServiceSnapshot? { model.processSnapshots[service.id] }
    var isActive: Bool { snapshot?.state == .starting || snapshot?.state == .running || snapshot?.state == .stopping }
    var state: (String, Color, String) {
        if model.serviceErrors[service.id] != nil || snapshot?.state == .failed {
            return ("启动失败", ManagerStyle.danger, "exclamationmark.triangle.fill")
        }
        switch snapshot?.state {
        case .starting: return ("启动中", ManagerStyle.warning, "arrow.triangle.2.circlepath")
        case .running: return ("运行中", ManagerStyle.success, "checkmark.circle.fill")
        case .stopping: return ("停止中", ManagerStyle.warning, "stop.circle.fill")
        case .exited: return ("已退出", ManagerStyle.muted, "minus.circle")
        case .failed: return ("启动失败", ManagerStyle.danger, "exclamationmark.triangle.fill")
        case .unknown: return ("状态未知", ManagerStyle.muted, "questionmark.circle")
        case nil: return ("未启动", ManagerStyle.muted, "circle")
        }
    }

}

private struct ServiceOverviewCard: View {
    let entry: ServiceListEntry
    @ObservedObject var model: AppModel
    let onEdit: () -> Void
    let onSelect: () -> Void

    private var service: Service { entry.service }
    private var visibleArguments: [String] { service.arguments.filter { !$0.isEmpty } }
    private var status: ServiceEntryState { ServiceEntryState(entry: entry, model: model) }
    private var snapshot: SupervisorServiceSnapshot? { status.snapshot }
    private var state: (String, Color, String) { status.state }
    private var serviceDescription: String { service.description.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 11) {
                ManagerIconBadge(icon: "server.rack", color: ManagerStyle.accent, size: 36, iconSize: 16, cornerRadius: 7)
                VStack(alignment: .leading, spacing: 3) {
                    Button(action: onSelect) {
                        Text(model.serviceDisplayName(service))
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .lineLimit(2)
                            .help(model.serviceDisplayName(service))
                    }
                    .buttonStyle(.plain)
                    Text(entry.path)
                        .font(.system(size: 11))
                        .foregroundColor(ManagerStyle.muted)
                        .lineLimit(1)
                        .help(entry.path)
                }
                Spacer(minLength: 4)
                ManagerStatusBadge(title: state.0, icon: state.2, color: state.1)
            }
            .frame(minHeight: 44)

            if !serviceDescription.isEmpty {
                Text(serviceDescription)
                    .font(.system(size: 12))
                    .foregroundColor(ManagerStyle.muted)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ManagerStyle.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("访问入口")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ManagerStyle.muted)
                    ServiceAccessLinks(service: service)
                        .font(.system(size: 12, design: .monospaced).weight(.medium))
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(ManagerStyle.selection)
            .clipShape(RoundedRectangle(cornerRadius: ManagerStyle.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ManagerStyle.radius, style: .continuous)
                    .strokeBorder(ManagerStyle.accent.opacity(0.18), lineWidth: 0.8)
            )

            if snapshot?.pid != nil || snapshot?.exitCode != nil {
                HStack(spacing: 12) {
                    if let pid = snapshot?.pid {
                        Text("PID \(pid)")
                    }
                    if let code = snapshot?.exitCode {
                        Text("退出码 \(code)")
                            .foregroundColor(status.snapshot?.state == .failed ? ManagerStyle.danger : ManagerStyle.muted)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ManagerStyle.muted)
            }

            detailLine(title: "启动命令", value: service.command.isEmpty ? "未设置" : service.command, icon: "terminal", monospaced: true)
            if !visibleArguments.isEmpty {
                detailLine(title: "启动参数", value: visibleArguments.joined(separator: "  "), icon: "text.alignleft", monospaced: true)
            }
            detailLine(title: "工作目录", value: service.workingDirectory, icon: "folder", monospaced: true)

            VStack(alignment: .leading, spacing: 6) {
                if service.startsWithManager { metadataChip("随管理器启动", icon: "power") }
                if !service.environment.isEmpty { metadataChip("\(service.environment.count) 个环境变量", icon: "slider.horizontal.3") }
                if let runtimeID = service.runtimeResourceID,
                   let runtime = model.workspace.resources.first(where: { $0.id == runtimeID }) {
                    metadataChip(runtime.name, icon: "shippingbox")
                }
            }

            Divider().opacity(0.4)
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 10))
                    .foregroundColor(ManagerStyle.muted)
                if entry.groups.isEmpty {
                    Text("未分组").font(.caption).foregroundColor(ManagerStyle.muted)
                } else {
                    Text(entry.groups.map(\.name).joined(separator: "、"))
                        .font(.caption).foregroundColor(ManagerStyle.muted).lineLimit(2)
                        .help(entry.groups.map(\.name).joined(separator: "、"))
                }
                Spacer(minLength: 2)
            }

            ServiceEntryActions(entry: entry, model: model, onEdit: onEdit, onSelect: onSelect)
        }
        .padding(16)
        .background(ManagerStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: ManagerStyle.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ManagerStyle.cardRadius, style: .continuous)
                .strokeBorder(ManagerStyle.cardBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.035), radius: 6, x: 0, y: 2)
    }

    private func detailLine(title: String, value: String, icon: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(ManagerStyle.muted)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 10)).foregroundColor(ManagerStyle.muted)
                Text(value)
                    .font(monospaced ? .system(size: 11, design: .monospaced) : .system(size: 11))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    private func metadataChip(_ title: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 8.5, weight: .semibold))
            Text(title).font(.system(size: 9.5, weight: .medium, design: .monospaced))
        }
        .foregroundColor(ManagerStyle.ink)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(ManagerStyle.canvas)
        .clipShape(RoundedRectangle(cornerRadius: ManagerStyle.badgeRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ManagerStyle.badgeRadius, style: .continuous).strokeBorder(ManagerStyle.fieldBorder, lineWidth: 0.8))
        .lineLimit(1)
    }
}

private struct ServiceTableStatus: View {
    let entry: ServiceListEntry
    @ObservedObject var model: AppModel

    var body: some View {
        let status = ServiceEntryState(entry: entry, model: model)
        VStack(alignment: .leading, spacing: 3) {
            ManagerStatusBadge(
                title: status.state.0,
                icon: status.state.2,
                color: status.state.1,
                compact: true
            )
            if let code = status.snapshot?.exitCode {
                Text("退出码 \(code)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(status.snapshot?.state == .failed ? ManagerStyle.danger : ManagerStyle.muted)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ServiceEntryActions: View {
    let entry: ServiceListEntry
    @ObservedObject var model: AppModel
    var compact = false
    let onEdit: () -> Void
    let onSelect: () -> Void

    var body: some View {
        let status = ServiceEntryState(entry: entry, model: model)
        HStack(spacing: 6) {
            Button {
                model.startService(projectID: entry.project.id, environmentID: entry.environment.id, serviceID: entry.service.id)
            } label: { actionLabel("启动", icon: "play.fill") }
                .buttonStyle(ManagerButtonStyle(.start, iconOnly: compact))
                .help("启动服务").accessibilityLabel("启动服务")
                .disabled(status.isActive || entry.service.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button { model.stopService(serviceID: entry.service.id) } label: { actionLabel("停止", icon: "stop.fill") }
                .buttonStyle(ManagerButtonStyle(.danger, iconOnly: compact))
                .help("停止服务").accessibilityLabel("停止服务")
                .disabled(!status.isActive)
            Button {
                model.restartService(projectID: entry.project.id, environmentID: entry.environment.id, serviceID: entry.service.id)
            } label: { actionLabel("重启", icon: "arrow.triangle.2.circlepath") }
                .buttonStyle(ManagerButtonStyle(.secondary, iconOnly: compact))
                .help("重启服务：先停止，再重新启动").accessibilityLabel("重启服务")
                .disabled(!status.isActive)
            Menu {
                Button("编辑服务", action: onEdit)
                Button("查看详情", action: onSelect)
                Button("查看实时输出") {
                    model.selectedProjectID = entry.project.id
                    model.selectedEnvironmentID = entry.environment.id
                    model.selectedServiceID = entry.service.id
                    ServiceOutputWindowPresenter.show(model: model, service: entry.service)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ManagerStyle.ink)
                    .frame(width: 28, height: 28)
            }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28, height: 28)
                .fixedSize()
                .managerIconSurface()
                .help("编辑、详情与实时输出").accessibilityLabel("服务更多操作")
        }
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private func actionLabel(_ title: String, icon: String) -> some View {
        if compact { Image(systemName: icon).frame(width: 12, height: 14) }
        else { Label(title, systemImage: icon) }
    }
}
