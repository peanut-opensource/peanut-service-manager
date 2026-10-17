import SwiftUI

@main
struct PeanutServiceManagerApp: App {
    @StateObject private var model: AppModel

    init() {
        let store = try! WorkspaceStore()
        _model = StateObject(wrappedValue: AppModel(store: store))
    }

    var body: some Scene {
        WindowGroup("花生服务管理器") {
            WorkspaceView(model: model)
                .frame(minWidth: 900, minHeight: 580)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var workspace: Workspace
    @Published var selection: UUID?

    let store: WorkspaceStore

    init(store: WorkspaceStore) {
        self.store = store
        workspace = store.workspace
    }

    func addProject() {
        do {
            try store.update { $0.projects.append(Project(name: "新项目")) }
            workspace = store.workspace
        } catch {
            NSLog("Failed to save workspace: %@", error.localizedDescription)
        }
    }
}

struct WorkspaceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: model.addProject) {
                        Label("添加项目", systemImage: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .help("添加项目")
                }
                .padding(8)

                List(selection: $model.selection) {
                    ForEach(model.workspace.projects) { project in
                        Label(project.name, systemImage: "folder")
                            .tag(project.id)
                    }
                }
            }
            .frame(minWidth: 220)

            Group {
                if model.selection == nil {
                    VStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("选择或添加项目")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("项目配置")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
