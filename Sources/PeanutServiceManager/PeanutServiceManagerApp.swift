import SwiftUI

@main
struct PeanutServiceManagerApp: App {
    @State private var model: AppModel?
    @State private var startupError: String?

    init() {
        do {
            _model = State(initialValue: AppModel(store: try WorkspaceStore()))
            _startupError = State(initialValue: nil)
        } catch {
            _model = State(initialValue: nil)
            _startupError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup("花生服务管理器") {
            Group {
                if let model {
                    WorkspaceView(model: model)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                        Text("无法读取本地配置")
                            .font(.headline)
                        Text(startupError ?? "未知错误")
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                }
            }
            .frame(minWidth: 900, minHeight: 580)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
