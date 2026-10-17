import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var workspace: Workspace
    @Published var selectedProjectID: UUID?
    @Published var selectedEnvironmentID: UUID?
    @Published var selectedServiceID: UUID?
    @Published var selectedResourceID: UUID?
    @Published var errorMessage: String?

    private let store: WorkspaceStore

    init(store: WorkspaceStore) {
        self.store = store
        workspace = store.workspace
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

    func removeResource(_ resourceID: UUID) {
        update { workspace in
            workspace.resources.removeAll { $0.id == resourceID }
            workspace.bindings.removeAll { $0.resourceID == resourceID }
            for projectIndex in workspace.projects.indices {
                for environmentIndex in workspace.projects[projectIndex].environments.indices {
                    for serviceIndex in workspace.projects[projectIndex].environments[environmentIndex].services.indices where
                        workspace.projects[projectIndex].environments[environmentIndex].services[serviceIndex].runtimeResourceID == resourceID {
                        workspace.projects[projectIndex].environments[environmentIndex].services[serviceIndex].runtimeResourceID = nil
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
        update { workspace in
            let environmentIDs = Set(workspace.projects.first(where: { $0.id == projectID })?.environments.map(\.id) ?? [])
            workspace.projects.removeAll { $0.id == projectID }
            workspace.bindings.removeAll { $0.projectID == projectID || environmentIDs.contains($0.environmentID) }
        }
        if selectedProjectID == projectID {
            selectedProjectID = nil
            selectedEnvironmentID = nil
            selectedServiceID = nil
        }
    }

    func removeEnvironment(projectID: UUID, environmentID: UUID) {
        update { workspace in
            guard let index = workspace.projects.firstIndex(where: { $0.id == projectID }) else { return }
            workspace.projects[index].environments.removeAll { $0.id == environmentID }
            workspace.bindings.removeAll { $0.projectID == projectID && $0.environmentID == environmentID }
        }
        if selectedEnvironmentID == environmentID {
            selectedEnvironmentID = nil
            selectedServiceID = nil
        }
    }

    func removeService(projectID: UUID, environmentID: UUID, serviceID: UUID) {
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
}
