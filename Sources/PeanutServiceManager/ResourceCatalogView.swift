import SwiftUI

enum ResourcePresentation {
    case list
    case management
}

struct ResourceCatalogView: View {
    @ObservedObject var model: AppModel
    var presentation: ResourcePresentation = .management
    var onManage: ((UUID) -> Void)? = nil
    @State private var editingResource: ResourceRecord?
    @State private var searchText = ""
    @State private var isCreatingResource = false
    @State private var bindingProjectID: UUID?
    @State private var bindingEnvironmentID: UUID?
    @State private var pendingDeletion: ResourceRecord?
    @State private var isCheckingDocker = false
    @State private var probeMessage: String?
    @State private var probeSucceeded = false
    @FocusState private var isSearchFocused: Bool

    private var selectedResource: ResourceRecord? {
        model.workspace.resources.first { $0.id == model.selectedResourceID }
    }

    private var bindingTargets: [(project: Project, environment: ProjectEnvironment)] {
        model.workspace.projects.flatMap { project in
            project.environments.map { (project: project, environment: $0) }
        }
    }

    private var targetBindings: [ProjectEnvironmentBinding] {
        guard let projectID = bindingProjectID, let environmentID = bindingEnvironmentID else { return [] }
        return model.workspace.bindings.filter { $0.projectID == projectID && $0.environmentID == environmentID }
    }

    var body: some View {
        Group {
            if presentation == .list {
                resourceList
            } else {
                management
            }
        }
        .background(ManagerStyle.canvas)
        .sheet(isPresented: $isCreatingResource) {
            ResourceEditor(resource: nil) { save($0) }
        }
        .sheet(item: $editingResource) { resource in
            ResourceEditor(resource: resource) { save($0) }
        }
        .alert(item: errorBinding) { message in
            Alert(title: Text("无法保存配置"), message: Text(message.message), dismissButton: .default(Text("好")))
        }
        .confirmationDialog("删除资源？", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
            Button("删除资源及其环境绑定", role: .destructive) { confirmDelete() }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("资源配置、项目环境绑定及该资源已加密保存的密码将被删除。此操作无法撤销。")
        }
        .onAppear(perform: chooseInitialTarget)
        .onChange(of: model.selectedResourceID) { _ in probeMessage = nil }
    }

    private var resourceList: some View {
        VStack(spacing: 0) {
            ManagerPageHeader(title: "资源列表", subtitle: "查看资源版本、连接地址及项目环境用途", icon: "list.bullet.rectangle") {
                ManagerMetricPill(title: "登记资源", value: model.workspace.resources.count, icon: "externaldrive.fill", color: ManagerStyle.cyan)
            }
            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundColor(ManagerStyle.muted)
                    TextField("搜索名称、类型、版本、地址、用途或项目环境", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundColor(ManagerStyle.muted)
                            .help("清除搜索").accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(ManagerStyle.field)
                .overlay(RoundedRectangle(cornerRadius: ManagerStyle.radius).stroke(isSearchFocused ? ManagerStyle.accent.opacity(0.72) : ManagerStyle.fieldBorder, lineWidth: isSearchFocused ? 1.5 : 1))
                .clipShape(RoundedRectangle(cornerRadius: ManagerStyle.radius, style: .continuous))
                Button { isCreatingResource = true } label: { Label("登记资源", systemImage: "plus") }
                    .buttonStyle(ManagerButtonStyle(.primary))
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            if listedResources.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: searchText.isEmpty ? "externaldrive" : "magnifyingglass")
                        .font(.system(size: 32)).foregroundColor(ManagerStyle.accent)
                    Text(searchText.isEmpty ? "尚未登记资源" : "没有匹配的资源")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text(searchText.isEmpty ? "登记资源后，可在这里查看资源信息及项目环境绑定。" : "尝试其他名称、地址或项目环境。")
                        .foregroundColor(ManagerStyle.muted)
                    if searchText.isEmpty {
                        Button("登记资源") { isCreatingResource = true }
                            .buttonStyle(ManagerButtonStyle(.primary))
                    } else {
                        Button("清除搜索") { searchText = "" }
                            .buttonStyle(ManagerButtonStyle(.secondary))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                ScrollView(.horizontal) {
                Table(listedResources) {
                    TableColumn("名称") { resource in
                        HStack(spacing: 7) {
                            Image(systemName: resourceIcon(resource.type))
                                .foregroundColor(resourceColor(resource.type))
                            Text(resource.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                        }.help(resource.name)
                    }.width(min: 130, ideal: 160)
                    TableColumn("类型") { resource in Text(resource.type.displayName).lineLimit(1) }
                        .width(min: 65, ideal: 85, max: 100)
                    TableColumn("版本") { resource in listCell(resource.version ?? "—") }
                        .width(min: 50, ideal: 65, max: 90)
                    TableColumn("Host / Port") { resource in listCell(listAddress(resource)) }
                        .width(min: 110, ideal: 140)
                    TableColumn("用途") { resource in listCell(resource.purpose ?? "—") }
                        .width(min: 100, ideal: 130)
                    TableColumn("绑定项目 / 环境") { resource in listCell(bindingSummary(resource)) }
                        .width(min: 150, ideal: 220)
                    TableColumn("操作") { resource in
                        HStack(spacing: 6) {
                            Button("编辑") { editingResource = resource }
                                .buttonStyle(ManagerButtonStyle(.secondary))
                            Button("管理") { openManagement(resource) }
                                .buttonStyle(ManagerButtonStyle(.accent))
                        }.controlSize(.small)
                    }.width(144)
                }
                .frame(width: max(geometry.size.width, 950), height: geometry.size.height)
                .managerTableSurface()
                }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }

    private var listedResources: [ResourceRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.workspace.resources.filter { resource in
            query.isEmpty || [resource.name, resource.type.displayName, resource.version ?? "", listAddress(resource), resource.purpose ?? "", bindingSummary(resource)]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func listCell(_ value: String) -> some View {
        Text(value).lineLimit(1).truncationMode(.middle).help(value)
    }

    private func listAddress(_ resource: ResourceRecord) -> String {
        switch (resource.host, resource.port) {
        case let (host?, port?): return "\(host):\(port)"
        case let (host?, nil): return host
        case let (nil, port?): return "端口 \(port)"
        case (nil, nil): return "—"
        }
    }

    private func bindingSummary(_ resource: ResourceRecord) -> String {
        let names = model.workspace.bindings.filter { $0.resourceID == resource.id }.map { binding in
            let project = model.workspace.projects.first { $0.id == binding.projectID }
            let environment = project?.environments.first { $0.id == binding.environmentID }
            return "\(project?.name ?? "未知项目") / \(environment?.name ?? "未知环境")"
        }.sorted()
        return names.isEmpty ? "未绑定" : names.joined(separator: "；")
    }

    private func openManagement(_ resource: ResourceRecord) {
        model.selectedResourceID = resource.id
        onManage?(resource.id)
    }

    private var management: some View {
        VStack(spacing: 0) {
            ManagerPageHeader(title: "资源管理", subtitle: "登记并关联项目环境所需的本地资源", icon: "externaldrive.fill") {
                ManagerMetricPill(title: "资源总数", value: model.workspace.resources.count, icon: "externaldrive.fill", color: ManagerStyle.cyan)
            }
            HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("资源目录").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(ManagerStyle.muted)
                        Text("\(model.workspace.resources.count) 项资源").font(.caption2).foregroundColor(ManagerStyle.muted)
                    }
                    Spacer()
                    Button { isCreatingResource = true } label: { Label("登记资源", systemImage: "plus") }
                        .buttonStyle(ManagerButtonStyle(.primary)).controlSize(.small)
                }
                .padding()
                List {
                    ForEach(model.workspace.resources.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { resource in
                        Button { model.selectedResourceID = resource.id } label: {
                            HStack(spacing: 10) {
                                Image(systemName: resourceIcon(resource.type))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(resourceColor(resource.type))
                                    .frame(width: 30, height: 30)
                                    .background(resourceColor(resource.type).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: ManagerStyle.radius, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(resource.name).font(.system(.body, design: .rounded).weight(.semibold)).lineLimit(1)
                                    Text(resourceSummary(resource)).font(.caption).foregroundColor(ManagerStyle.muted).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 5).padding(.horizontal, 6)
                            .background(model.selectedResourceID == resource.id ? ManagerStyle.selection : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: ManagerStyle.radius, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button("编辑") { editingResource = resource }
                            Button("删除资源", role: .destructive) { delete(resource) }
                        }
                    }
                }
            }
            .frame(minWidth: 240, idealWidth: 270, maxWidth: 320)
            .background(ManagerStyle.canvas)
            detail
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                .padding(18)
                .background(ManagerStyle.panel)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let resource = selectedResource {
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    HStack(spacing: 13) {
                        ManagerIconBadge(icon: resourceIcon(resource.type), color: resourceColor(resource.type), size: 44, iconSize: 20, cornerRadius: 10)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(resource.name).font(.system(size: 21, weight: .bold, design: .rounded))
                                .lineLimit(2).help(resource.name)
                            Text(resource.type.displayName).font(.callout).foregroundColor(ManagerStyle.muted)
                        }
                    }
                    Spacer()
                    Button("编辑") { editingResource = resource }
                        .buttonStyle(ManagerButtonStyle(.secondary))
                    Button("删除", role: .destructive) { delete(resource) }
                        .buttonStyle(ManagerButtonStyle(.danger))
                }
                ManagerFormCard("资源信息", subtitle: "版本、来源、路径与连接方式", icon: resourceIcon(resource.type)) {
                    VStack(alignment: .leading, spacing: 7) {
                        detailRow("版本", resource.version)
                        detailRow("来源", resource.source)
                        detailRow("用途", resource.purpose)
                        detailRow("说明", resource.notes)
                        detailRow("本机路径", resource.executablePath)
                        detailRow("连接信息", connectionDescription(resource))
                        detailRow("容器信息", dockerDescription(resource))
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }
                if resource.type == .dockerContainer {
                    ManagerFormCard("容器状态", subtitle: "读取当前容器运行状态", icon: "shippingbox") {
                        VStack(alignment: .leading, spacing: 9) {
                            Button {
                                checkDockerStatus(resource)
                            } label: {
                                Label(isCheckingDocker ? "正在检查…" : "检查容器状态", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(ManagerButtonStyle(.secondary))
                            .disabled(isCheckingDocker)
                            if let probeMessage {
                                Label(probeMessage, systemImage: probeSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.callout)
                                    .foregroundColor(probeSucceeded ? ManagerStyle.success : ManagerStyle.warning)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                }
                ManagerFormCard("项目与环境绑定", subtitle: "一个资源可以关联多个项目环境", icon: "link") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Picker("项目 / 环境", selection: bindingTarget) {
                                Text("选择项目和环境").tag(Optional<String>.none)
                                ForEach(bindingTargets, id: \.environment.id) { target in
                                    Text("\(target.project.name) / \(target.environment.name)")
                                        .tag(Optional(target.project.id.uuidString + ":" + target.environment.id.uuidString))
                                }
                            }
                            Button("绑定") { bind(resource) }
                                .buttonStyle(ManagerButtonStyle(.primary))
                                .disabled(bindingProjectID == nil || bindingEnvironmentID == nil || targetBindings.contains { $0.resourceID == resource.id })
                        }
                        if targetBindings.contains(where: { $0.resourceID == resource.id }) {
                            Label("已绑定到所选环境", systemImage: "checkmark.circle.fill").foregroundColor(.secondary)
                                .font(.callout)
                            Button("解除此环境绑定", role: .destructive) { unbind(resource) }
                                .buttonStyle(ManagerButtonStyle(.danger))
                        } else {
                            Text("选择一个项目和环境后绑定。一个资源可以绑定到多个环境。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }
            }
            .frame(maxWidth: 850, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "externaldrive.fill").font(.system(size: 34)).foregroundColor(ManagerStyle.accent.opacity(0.65))
                Text("准备好整理你的本地资源了吗？").font(.system(.title3, design: .rounded).weight(.semibold))
                Text("选择一项资源查看详情，或登记新资源并关联项目环境。")
                    .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
                Button("登记资源") { isCreatingResource = true }
                    .buttonStyle(ManagerButtonStyle(.primary))
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var bindingTarget: Binding<String?> {
        Binding(get: {
            guard let projectID = bindingProjectID, let environmentID = bindingEnvironmentID else { return nil }
            return projectID.uuidString + ":" + environmentID.uuidString
        }, set: { value in
            guard let value = value else { bindingProjectID = nil; bindingEnvironmentID = nil; return }
            let parts = value.split(separator: ":")
            guard parts.count == 2, let projectID = UUID(uuidString: String(parts[0])), let environmentID = UUID(uuidString: String(parts[1])) else { return }
            bindingProjectID = projectID
            bindingEnvironmentID = environmentID
        })
    }

    private var errorBinding: Binding<IdentifiableMessage?> {
        Binding(get: { model.errorMessage.map(IdentifiableMessage.init) }, set: { if $0 == nil { model.errorMessage = nil } })
    }

    private func save(_ resource: ResourceRecord) -> Bool {
        model.update { workspace in
            if let index = workspace.resources.firstIndex(where: { $0.id == resource.id }) { workspace.resources[index] = resource }
            else { workspace.resources.append(resource) }
        }
        guard model.errorMessage == nil else { return false }
        model.selectedResourceID = resource.id
        isCreatingResource = false
        editingResource = nil
        return true
    }

    private func delete(_ resource: ResourceRecord) {
        pendingDeletion = resource
    }

    private func confirmDelete() {
        guard let resource = pendingDeletion else { return }
        pendingDeletion = nil
        model.removeResource(resource.id)
        guard model.errorMessage == nil else { return }
        do {
            if resource.credentialReference != nil { try CredentialVault().delete(for: resource) }
        } catch { model.errorMessage = error.localizedDescription }
        if model.selectedResourceID == resource.id { model.selectedResourceID = nil }
    }

    private func bind(_ resource: ResourceRecord) {
        guard let projectID = bindingProjectID, let environmentID = bindingEnvironmentID else { return }
        model.update { workspace in
            guard !workspace.bindings.contains(where: { $0.projectID == projectID && $0.environmentID == environmentID && $0.resourceID == resource.id }) else { return }
            workspace.bindings.append(ProjectEnvironmentBinding(projectID: projectID, environmentID: environmentID, resourceID: resource.id))
        }
    }

    private func unbind(_ resource: ResourceRecord) {
        guard let projectID = bindingProjectID, let environmentID = bindingEnvironmentID else { return }
        model.update { $0.bindings.removeAll { $0.projectID == projectID && $0.environmentID == environmentID && $0.resourceID == resource.id } }
    }

    private func chooseInitialTarget() {
        if let projectID = model.selectedProjectID,
           let project = model.workspace.projects.first(where: { $0.id == projectID }),
           let environmentID = model.selectedEnvironmentID,
           project.environments.contains(where: { $0.id == environmentID }) {
            bindingProjectID = projectID
            bindingEnvironmentID = environmentID
        } else if let target = bindingTargets.first {
            bindingProjectID = target.project.id
            bindingEnvironmentID = target.environment.id
        }
    }

    private func checkDockerStatus(_ resource: ResourceRecord) {
        isCheckingDocker = true
        probeMessage = nil
        Task {
            do {
                let status = try await Task.detached(priority: .utility) { try DockerStatusProbe.check(resource) }.value
                probeSucceeded = true
                probeMessage = "容器状态：\(status)"
            } catch {
                probeSucceeded = false
                probeMessage = error.localizedDescription
            }
            isCheckingDocker = false
        }
    }

    private func resourceSummary(_ resource: ResourceRecord) -> String {
        [resource.type.displayName, resource.version, resource.host.map { host in resource.port.map { "\(host):\($0)" } ?? host }, resource.containerName].compactMap { $0 }.joined(separator: " · ")
    }

    private func connectionDescription(_ resource: ResourceRecord) -> String? {
        guard resource.host != nil || resource.port != nil || resource.database != nil || resource.username != nil else { return nil }
        return [resource.host, resource.port.map(String.init), resource.database, resource.username].compactMap { $0 }.joined(separator: " · ")
    }

    private func dockerDescription(_ resource: ResourceRecord) -> String? {
        let value = [resource.dockerContext, resource.containerName, resource.containerID].compactMap { $0 }.joined(separator: " · ")
        return value.isEmpty ? nil : value
    }

    private func detailRow(_ title: String, _ value: String?) -> some View {
        Group { if let value = value, !value.isEmpty { HStack(alignment: .firstTextBaseline) { Text(title).foregroundColor(.secondary).frame(width: 86, alignment: .leading); Text(value).textSelection(.enabled) } } }
    }

    private func resourceIcon(_ type: ResourceType) -> String {
        switch type {
        case .mysql: return "cylinder.split.1x2.fill"
        case .redis: return "bolt.horizontal.circle.fill"
        case .php, .node: return "terminal.fill"
        case .dockerContainer: return "shippingbox.fill"
        case .other: return "shippingbox"
        }
    }

    private func resourceColor(_ type: ResourceType) -> Color {
        switch type {
        case .mysql: return ManagerStyle.warning
        case .redis: return ManagerStyle.danger
        case .php: return ManagerStyle.purple
        case .node: return ManagerStyle.success
        case .dockerContainer: return ManagerStyle.cyan
        case .other: return ManagerStyle.accent
        }
    }
}

private struct ResourceEditor: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var draft: ResourceRecord
    @State private var secret = ""
    @State private var credentialError: String?
    private let isNew: Bool
    let onSave: (ResourceRecord) -> Bool

    init(resource: ResourceRecord?, onSave: @escaping (ResourceRecord) -> Bool) {
        _draft = State(initialValue: resource ?? ResourceRecord(name: "", type: .mysql))
        isNew = resource == nil
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            ManagerEditorHeader(
                title: isNew ? "登记新资源" : "编辑资源",
                subtitle: "填写资源信息；字段会根据资源类型显示",
                icon: "externaldrive.fill"
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ManagerFormCard("基本信息", subtitle: "名称和类型用于识别资源及其适用范围。", icon: "tag") {
                        VStack(alignment: .leading, spacing: 13) {
                            ManagerTextField(title: "资源名称", placeholder: "例如 本机 \(draft.type.displayName)", text: $draft.name)
                            Picker("资源类型", selection: $draft.type) {
                                ForEach(ResourceType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.menu)
                            HStack(spacing: 12) {
                                optionalField("版本", value: $draft.version, placeholder: draft.type == .node ? "例如 22.x" : "例如 8.4")
                                optionalField("来源", value: $draft.source, placeholder: "例如 Homebrew")
                            }
                            HStack(spacing: 12) {
                                optionalField("用途", value: $draft.purpose, placeholder: "例如 本机开发")
                                optionalField("说明", value: optionalText($draft.notes), placeholder: "可选备注")
                            }
                        }
                    }

                    if draft.type == .php || draft.type == .node || draft.type == .other {
                        ManagerFormCard("本机运行时", subtitle: "使用可执行文件的完整路径，便于准确选择版本。", icon: "terminal") {
                            optionalField("可执行文件路径", value: $draft.executablePath, placeholder: draft.type == .node ? "/opt/homebrew/bin/node" : "/opt/homebrew/bin/php")
                        }
                    }

                    if draft.type == .mysql || draft.type == .redis || draft.type == .dockerContainer || draft.type == .other {
                        ManagerFormCard("连接信息", subtitle: "填写应用实际可访问的地址；不会自动更改资源配置。", icon: "network") {
                            VStack(alignment: .leading, spacing: 13) {
                                HStack(spacing: 12) {
                                    optionalField("主机地址", value: $draft.host, placeholder: "127.0.0.1")
                                    ManagerTextField(
                                        title: "端口",
                                        placeholder: draft.type == .redis ? "6379" : "3306",
                                        text: Binding(get: { draft.port.map(String.init) ?? "" }, set: { draft.port = Int($0.filter(\.isNumber)) })
                                    )
                                    .frame(width: 120)
                                }
                                optionalField(draft.type == .redis ? "数据库索引" : "数据库名称", value: $draft.database, placeholder: draft.type == .redis ? "0" : "可选")
                                optionalField("用户名", value: $draft.username, placeholder: "可选")
                                ManagerSecureField(
                                    title: "资源密码（可选）",
                                    placeholder: draft.credentialReference == nil ? "输入资源密码" : "留空以保留当前密码",
                                    text: $secret
                                )
                                if draft.credentialReference != nil {
                                    Label("已有密码已在本机加密保存", systemImage: "lock.fill")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    if draft.type == .dockerContainer {
                        ManagerFormCard("容器标识", subtitle: "只登记现有容器信息；应用不会管理容器启停。", icon: "shippingbox") {
                            VStack(alignment: .leading, spacing: 13) {
                                optionalField("Docker 上下文", value: $draft.dockerContext, placeholder: "default")
                                optionalField("容器 ID", value: $draft.containerID, placeholder: "可选")
                                optionalField("容器名称", value: $draft.containerName, placeholder: "例如 local-mysql")
                            }
                        }
                    }

                    if let credentialError {
                        Label(credentialError, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundColor(ManagerStyle.danger)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ManagerStyle.danger.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                }
                .padding(18)
            }
            .background(ManagerStyle.canvas)
            editorButtonsForResource
        }
        .frame(width: 660, height: editorHeight)
        .background(ManagerStyle.canvas)
    }

    private var editorHeight: CGFloat {
        max(440, min(660, (NSScreen.main?.visibleFrame.height ?? 760) - 110))
    }

    private func save() {
        var resource = normalized(draft)
        let isNewCredential = !secret.isEmpty && resource.credentialReference == nil
        do {
            if !secret.isEmpty {
                let vault = CredentialVault()
                if resource.credentialReference == nil {
                    resource.credentialReference = UUID().uuidString
                    try vault.add(Data(secret.utf8), for: resource)
                } else {
                    try vault.update(Data(secret.utf8), for: resource)
                }
            }
            guard onSave(resource) else {
                if isNewCredential { try? CredentialVault().delete(for: resource) }
                credentialError = "无法保存资源配置。请检查上方提示后重试。"
                return
            }
            secret = ""
            presentationMode.wrappedValue.dismiss()
        } catch {
            credentialError = error.localizedDescription
        }
    }

    private var editorButtonsForResource: some View {
        HStack {
            Spacer()
            Button("取消") { presentationMode.wrappedValue.dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(ManagerButtonStyle(.secondary))
            Button("保存") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(ManagerButtonStyle(.primary))
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(ManagerStyle.card)
        .overlay(alignment: .top) { Rectangle().fill(ManagerStyle.cardBorder).frame(height: 1) }
    }

    private func optionalField(_ title: String, value: Binding<String?>, placeholder: String = "") -> some View {
        ManagerTextField(
            title: title,
            placeholder: placeholder.isEmpty ? title : placeholder,
            text: Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
        )
    }

    private func optionalField(_ title: String, value: Binding<String>, placeholder: String) -> some View {
        ManagerTextField(title: title, placeholder: placeholder, text: value)
    }

    private func optionalText(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func normalized(_ resource: ResourceRecord) -> ResourceRecord {
        var result = resource
        result.name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.version = cleaned(result.version)
        result.source = cleaned(result.source)
        result.purpose = cleaned(result.purpose)
        result.notes = cleaned(result.notes)
        result.executablePath = cleaned(result.executablePath)
        result.host = cleaned(result.host)
        result.database = cleaned(result.database)
        result.username = cleaned(result.username)
        result.dockerContext = cleaned(result.dockerContext)
        result.containerID = cleaned(result.containerID)
        result.containerName = cleaned(result.containerName)
        return result
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

private struct IdentifiableMessage: Identifiable {
    let id = UUID()
    let message: String
    init(_ message: String) { self.message = message }
}


