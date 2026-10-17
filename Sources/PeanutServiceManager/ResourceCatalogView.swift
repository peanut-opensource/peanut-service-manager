import SwiftUI

struct ResourceCatalogView: View {
    @ObservedObject var model: AppModel
    @State private var editingResource: ResourceRecord?
    @State private var isCreatingResource = false
    @State private var bindingProjectID: UUID?
    @State private var bindingEnvironmentID: UUID?

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
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("资源").font(.headline)
                    Spacer()
                    Button { isCreatingResource = true } label: { Image(systemName: "plus") }
                        .help("登记资源")
                }
                .padding()
                List {
                    ForEach(model.workspace.resources.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { resource in
                        Button { model.selectedResourceID = resource.id } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(resource.name)
                                Text(resourceSummary(resource)).font(.caption).foregroundColor(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .listRowBackground(model.selectedResourceID == resource.id ? Color.accentColor.opacity(0.14) : Color.clear)
                        .contextMenu {
                            Button("编辑") { editingResource = resource }
                            Button("删除资源", role: .destructive) { delete(resource) }
                        }
                    }
                }
            }
            .frame(minWidth: 220, idealWidth: 270)
            Divider()
            detail
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
        }
        .sheet(isPresented: $isCreatingResource) {
            ResourceEditor(resource: nil) { save($0) }
        }
        .sheet(item: $editingResource) { resource in
            ResourceEditor(resource: resource) { save($0) }
        }
        .alert(item: errorBinding) { message in
            Alert(title: Text("无法保存配置"), message: Text(message.message), dismissButton: .default(Text("好")))
        }
        .onAppear(perform: chooseInitialTarget)
    }

    @ViewBuilder private var detail: some View {
        if let resource = selectedResource {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(resource.name).font(.title2).bold()
                        Text(resource.type.displayName).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("编辑") { editingResource = resource }
                    Button("删除", role: .destructive) { delete(resource) }
                }
                GroupBox("资源信息") {
                    VStack(alignment: .leading, spacing: 7) {
                        detailRow("版本", resource.version)
                        detailRow("来源", resource.source)
                        detailRow("用途", resource.purpose)
                        detailRow("说明", resource.notes)
                        detailRow("本机路径", resource.executablePath)
                        detailRow("连接", connectionDescription(resource))
                        detailRow("Docker", dockerDescription(resource))
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                }
                GroupBox("项目与环境绑定") {
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
                                .disabled(bindingProjectID == nil || bindingEnvironmentID == nil || targetBindings.contains { $0.resourceID == resource.id })
                        }
                        if targetBindings.contains(where: { $0.resourceID == resource.id }) {
                            Label("已绑定到所选环境", systemImage: "checkmark.circle.fill").foregroundColor(.secondary)
                                .font(.callout)
                            Button("解除此环境绑定", role: .destructive) { unbind(resource) }
                        } else {
                            Text("选择一个项目和环境后绑定。一个资源可以绑定到多个环境。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                }
                Spacer()
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "externaldrive").font(.largeTitle).foregroundColor(.secondary)
                Text("选择资源或登记新资源").foregroundColor(.secondary)
                Button("登记资源") { isCreatingResource = true }
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

    private func save(_ resource: ResourceRecord) {
        model.update { workspace in
            if let index = workspace.resources.firstIndex(where: { $0.id == resource.id }) { workspace.resources[index] = resource }
            else { workspace.resources.append(resource) }
        }
        model.selectedResourceID = resource.id
        isCreatingResource = false
        editingResource = nil
    }

    private func delete(_ resource: ResourceRecord) {
        model.update { workspace in
            workspace.resources.removeAll { $0.id == resource.id }
            workspace.bindings.removeAll { $0.resourceID == resource.id }
        }
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
}

private struct ResourceEditor: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var draft: ResourceRecord
    let onSave: (ResourceRecord) -> Void

    init(resource: ResourceRecord?, onSave: @escaping (ResourceRecord) -> Void) {
        _draft = State(initialValue: resource ?? ResourceRecord(name: "", type: .mysql))
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("资源登记").font(.headline); Spacer() }
                .padding()
            Form {
                Section(header: Text("基本信息")) {
                    TextField("名称", text: $draft.name)
                    Picker("类型", selection: $draft.type) { ForEach(ResourceType.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                    optionalField("版本", value: $draft.version)
                    optionalField("来源", value: $draft.source)
                    optionalField("用途", value: $draft.purpose)
                    TextField("说明", text: optionalText($draft.notes))
                }
                Section(header: Text("本机运行时")) { optionalField("可执行文件路径", value: $draft.executablePath) }
                Section(header: Text("连接信息")) {
                    optionalField("Host", value: $draft.host)
                    TextField("Port", text: Binding(get: { draft.port.map(String.init) ?? "" }, set: { draft.port = Int($0.filter(\.isNumber)) }))
                    optionalField("Database", value: $draft.database)
                    optionalField("Username", value: $draft.username)
                }
                Section(header: Text("Docker 容器")) {
                    optionalField("Docker context", value: $draft.dockerContext)
                    optionalField("Container ID", value: $draft.containerID)
                    optionalField("Container name", value: $draft.containerName)
                }
                Text("凭据将在后续版本通过钥匙串管理。此处不录入密码。")
                    .font(.caption).foregroundColor(.secondary)
            }
            HStack { Spacer(); Button("取消") { presentationMode.wrappedValue.dismiss() }; Button("保存") { onSave(normalized(draft)); presentationMode.wrappedValue.dismiss() }.keyboardShortcut(.defaultAction).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                .padding()
        }
        .frame(minWidth: 520, minHeight: 580)
    }

    private func optionalField(_ title: String, value: Binding<String?>) -> some View {
        TextField(title, text: Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 }))
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


