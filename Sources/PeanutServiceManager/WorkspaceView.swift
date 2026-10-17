import AppKit
import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var model: AppModel

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
        HStack(spacing: 0) {
            projectColumn
                .frame(minWidth: 190, idealWidth: 220)
            Divider()
            environmentColumn
                .frame(minWidth: 190, idealWidth: 220)
            Divider()
            serviceColumn
                .frame(minWidth: 210, idealWidth: 250)
            Divider()
            detailColumn
                .frame(minWidth: 330, maxWidth: .infinity)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .alert(item: errorBinding) { message in
            Alert(title: Text("无法保存配置"), message: Text(message.message), dismissButton: .default(Text("好")))
        }
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
                            Image(systemName: "folder")
                            Text(item.name).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.vertical, 3)
                    .background(model.selectedProjectID == item.id ? Color.accentColor.opacity(0.14) : Color.clear)
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
                                Image(systemName: "square.stack.3d.up")
                                Text(item.name).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 3)
                        .background(model.selectedEnvironmentID == item.id ? Color.accentColor.opacity(0.14) : Color.clear)
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
                List {
                    ForEach(uniqueServices(environment.services)) { item in
                        Button(action: { model.selectedServiceID = item.id }) {
                            HStack {
                                Image(systemName: "gearshape")
                                Text(item.name).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 3)
                        .background(model.selectedServiceID == item.id ? Color.accentColor.opacity(0.14) : Color.clear)
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
        .padding(20)
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
            Section(header: Text("服务配置")) {
                TextField("服务名称", text: serviceBinding(service.id, keyPath: \.name))
                TextField("工作目录", text: serviceBinding(service.id, keyPath: \.workingDirectory))
                TextField("启动命令", text: serviceBinding(service.id, keyPath: \.command))
                VStack(alignment: .leading, spacing: 4) {
                    Text("参数（每行一个）").font(.caption).foregroundColor(.secondary)
                    TextEditor(text: argumentsBinding(service.id)).frame(minHeight: 70)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("说明").font(.caption).foregroundColor(.secondary)
                    TextEditor(text: serviceBinding(service.id, keyPath: \.description)).frame(minHeight: 55)
                }
                Toggle("随管理器启动", isOn: serviceBinding(service.id, keyPath: \.startsWithManager))
            }
            Section(header: Text("环境变量"), footer: Text("每行填写 KEY=VALUE；修改后立即保存。")) {
                TextEditor(text: environmentVariablesBinding(service.id))
                    .frame(minHeight: 100)
            }
            if let environment {
                groupEditor(environment)
            }
            Section(footer: Text("删除服务只允许用于当前未运行的实例。当前版本尚不管理进程状态，请先确认此服务未运行。")) {
                Button("删除服务", role: .destructive) { removeService(service.id) }
            }
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
            Text(title).font(.headline)
            Spacer()
            Button(action: action) { Image(systemName: "plus") }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(!enabled)
                .help("添加\(title)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func emptyMessage(_ text: String) -> some View {
        VStack { Text(text).foregroundColor(.secondary) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var uniqueProjects: [Project] { unique(model.workspace.projects) }
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

private struct ErrorAlert: Identifiable {
    let id = UUID()
    let message: String

    init(_ message: String) { self.message = message }
}
