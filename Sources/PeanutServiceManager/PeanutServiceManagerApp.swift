import SwiftUI
import AppKit

@main
struct PeanutServiceManagerApp: App {
    @NSApplicationDelegateAdaptor(ManagerAppDelegate.self) private var appDelegate
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
            .background(WindowLifecycleView())
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

final class ManagerAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let iconURL = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: iconURL) {
            image.isTemplate = true
            item.button?.image = image
        }
        item.button?.image?.accessibilityDescription = "花生服务管理器"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示花生服务管理器", action: #selector(showMainWindow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

private struct WindowLifecycleView: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowLifecycleNSView { WindowLifecycleNSView() }
    func updateNSView(_ nsView: WindowLifecycleNSView, context: Context) { }
}

private final class WindowLifecycleNSView: NSView, NSWindowDelegate {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
