import SwiftUI
import PeanutServiceIPC

private struct ServiceListEntry: Identifiable {
    let project: Project
    let environment: ProjectEnvironment
    let service: Service
    let groups: [ServiceGroup]

    var id: UUID { service.id }
    var path: String { "\(project.name) / \(environment.name)" }
}
private struct ServiceGroupOption: Identifiable {
    let group: ServiceGroup
    let path: String
    var id: UUID { group.id }
    var label: String { "\(group.name) · \(path)" }
}

struct ServiceListView: View {
    @ObservedObject var model: AppModel
    let onEdit: (UUID, UUID, Service) -> Void
    let onSelect: (UUID, UUID, UUID) -> Void

    @State private var searchText = ""
    @State private var selectedGroupID: UUID?

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
                environment.groups.map { ServiceGroupOption(group: $0, path: "\(project.name) / \(environment.name)") }
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
                service.domain ?? "", service.port.map(String.init) ?? "", entry.path,
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
                    TextField("搜索服务、域名、项目或启动命令", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(ManagerStyle.card)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.10), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Picker("服务分组", selection: $selectedGroupID) {
                    Text("全部分组").tag(Optional<UUID>.none)
                    ForEach(groupOptions) { option in
                        Text(option.label).tag(Optional(option.id))
                    }
                }
                .frame(maxWidth: 260)
                .help("分组是环境内的服务集合，可用于筛选和批量操作")

                Menu("批量操作") {
                    Button("启动当前结果") { startFilteredServices() }
                    Button("停止当前结果") { model.stopServices(filteredEntries.map(\.service.id)) }
                    Button("重启当前结果") { restartFilteredServices() }
                }
                .disabled(filteredEntries.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            ScrollView {
                if filteredEntries.isEmpty {
                    emptyState
                } else {
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
            .background(ManagerStyle.canvas)
        }
        .background(ManagerStyle.canvas)
        .onAppear { model.observeWorkspace() }
        .onDisappear { model.stopObservingWorkspace() }
    }

    private var header: some View {
        ManagerPageHeader(title: "服务总览", subtitle: "按服务查看运行状态、访问入口和启动配置", icon: "list.bullet.rectangle.portrait.fill") {
            overviewMetric(title: "服务", value: entries.count, icon: "server.rack", color: ManagerStyle.accent)
            overviewMetric(title: "运行中", value: runningCount, icon: "checkmark.circle.fill", color: ManagerStyle.success)
        }
    }

    private func overviewMetric(title: String, value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)").font(.system(.headline, design: .rounded).weight(.bold))
                Text(title).font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: entries.isEmpty ? "server.rack" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 30)).foregroundColor(ManagerStyle.accent.opacity(0.7))
            Text(entries.isEmpty ? "还没有登记服务" : "没有匹配的服务")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text(entries.isEmpty ? "在工作区选择项目和环境后添加服务。" : "调整搜索内容或分组筛选条件。")
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

private struct ServiceOverviewCard: View {
    let entry: ServiceListEntry
    @ObservedObject var model: AppModel
    let onEdit: () -> Void
    let onSelect: () -> Void

    private var service: Service { entry.service }
    private var visibleArguments: [String] { service.arguments.filter { !$0.isEmpty } }
    private var snapshot: SupervisorServiceSnapshot? { model.processSnapshots[service.id] }
    private var isActive: Bool { snapshot?.state == .starting || snapshot?.state == .running || snapshot?.state == .stopping }
    private var serviceDescription: String { service.description.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var state: (String, Color, String) {
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
        case nil: return ("等待状态", ManagerStyle.muted, "circle")
        }
    }

    private var accessAddress: String? {
        let domain = service.domain?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !domain.isEmpty || service.port != nil else { return nil }
        if domain.isEmpty { return service.port.map { "端口 \($0)" } }
        return service.port.map { "\(domain):\($0)" } ?? domain
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 11) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(state.1)
                    .frame(width: 5)
                VStack(alignment: .leading, spacing: 5) {
                    Button(action: onSelect) {
                        Text(service.name).font(.system(.title3, design: .rounded).weight(.bold)).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    Text(entry.path).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 5)
                Label(state.0, systemImage: state.2)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundColor(state.1)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(state.1.opacity(0.10))
                    .clipShape(Capsule())
            }
            .frame(height: 48)

            if !serviceDescription.isEmpty {
                Text(serviceDescription).font(.callout).foregroundColor(.secondary).lineLimit(2)
            }

            HStack(spacing: 10) {
                Image(systemName: "globe.americas.fill").foregroundColor(ManagerStyle.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("访问入口").font(.caption2).foregroundColor(.secondary)
                    Text(accessAddress ?? "未登记域名和端口")
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                        .foregroundColor(accessAddress == nil ? .secondary : .primary)
                        .lineLimit(1).textSelection(.enabled)
                }
                Spacer()
                if let pid = snapshot?.pid { Text("PID \(pid)").font(.system(.caption2, design: .monospaced)).foregroundColor(.secondary) }
                if let code = snapshot?.exitCode { Text("退出码 \(code)").font(.system(.caption2, design: .monospaced)).foregroundColor(code == 0 ? .secondary : ManagerStyle.danger) }
            }
            .padding(11)
            .background(ManagerStyle.accent.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            detailLine(title: "启动命令", value: service.command.isEmpty ? "未设置" : service.command, icon: "chevron.left.forwardslash.chevron.right", monospaced: true)
            if !visibleArguments.isEmpty {
                detailLine(title: "启动参数", value: visibleArguments.joined(separator: "  "), icon: "text.alignleft", monospaced: true)
            }
            detailLine(title: "工作目录", value: service.workingDirectory, icon: "folder", monospaced: true)
            HStack(spacing: 7) {
                if service.startsWithManager { metadataChip("随管理器启动", icon: "power") }
                if !service.environment.isEmpty { metadataChip("\(service.environment.count) 个环境变量", icon: "slider.horizontal.3") }
                if let runtimeID = service.runtimeResourceID,
                   let runtime = model.workspace.resources.first(where: { $0.id == runtimeID }) {
                    metadataChip(runtime.name, icon: "shippingbox")
                }
            }

            Divider().opacity(0.6)
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "person.3").foregroundColor(.secondary)
                if entry.groups.isEmpty {
                    Text("未分组").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(entry.groups) { group in metadataChip(group.name, icon: "tag.fill") }
                }
                Spacer(minLength: 2)
                Button("编辑") { onEdit() }
                    .controlSize(.small)
            }

            HStack(spacing: 8) {
                Button {
                    model.startService(projectID: entry.project.id, environmentID: entry.environment.id, serviceID: service.id)
                } label: { Label("启动", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).tint(ManagerStyle.accent)
                    .disabled(isActive || service.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button { model.stopService(serviceID: service.id) } label: { Label("停止", systemImage: "stop.fill") }
                    .disabled(!isActive)
                Button {
                    model.restartService(projectID: entry.project.id, environmentID: entry.environment.id, serviceID: service.id)
                } label: { Label("重启", systemImage: "arrow.clockwise") }
                    .disabled(!isActive)
                Spacer()
                Button {
                    model.selectedProjectID = entry.project.id
                    model.selectedEnvironmentID = entry.environment.id
                    model.selectedServiceID = service.id
                    ServiceOutputWindowPresenter.show(model: model, service: service)
                } label: { Image(systemName: "terminal") }
                    .help("查看实时输出")
            }
            .controlSize(.small)
        }
        .padding(16)
        .background(ManagerStyle.card)
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: .black.opacity(0.045), radius: 12, x: 0, y: 4)
    }

    private func detailLine(title: String, value: String, icon: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon).foregroundColor(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption2).foregroundColor(.secondary)
                Text(value).font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                    .lineLimit(2).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    private func metadataChip(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundColor(ManagerStyle.ink)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(ManagerStyle.canvas)
            .clipShape(Capsule())
            .lineLimit(1)
    }
}
