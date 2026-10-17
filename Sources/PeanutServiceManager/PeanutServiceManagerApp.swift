import SwiftUI
import AppKit
import Carbon.HIToolbox

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
            .frame(minWidth: 820, minHeight: 560)
            .background(WindowLifecycleView())
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

final class ManagerAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(globalShortcutConfigurationChanged),
            name: Notification.Name("PeanutServiceManagerGlobalShortcutChanged"),
            object: nil
        )
        registerGlobalShortcut()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let hotKeyHandlerRef { RemoveEventHandler(hotKeyHandlerRef) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    @objc fileprivate func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    private func registerGlobalShortcut() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
            self.hotKeyHandlerRef = nil
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                Unmanaged<ManagerAppDelegate>.fromOpaque(userData).takeUnretainedValue().showMainWindow()
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &hotKeyHandlerRef
        )
        guard installStatus == noErr else {
            UserDefaults.standard.set("注册失败", forKey: "peanutServiceManager.globalShortcutStatus")
            return
        }
        let shortcutID = EventHotKeyID(signature: OSType(0x50534D31), id: 1)
        let preset = UserDefaults.standard.string(forKey: "peanutServiceManager.globalShortcut") ?? "optionY"
        let modifiers: UInt32
        switch preset {
        case "controlOptionY": modifiers = UInt32(optionKey | controlKey)
        case "commandOptionY": modifiers = UInt32(optionKey | cmdKey)
        default: modifiers = UInt32(optionKey)
        }
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_Y),
            modifiers,
            shortcutID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            UserDefaults.standard.set("注册失败：快捷键可能已被占用", forKey: "peanutServiceManager.globalShortcutStatus")
            if let hotKeyHandlerRef {
                RemoveEventHandler(hotKeyHandlerRef)
                self.hotKeyHandlerRef = nil
            }
        } else {
            UserDefaults.standard.set("已启用", forKey: "peanutServiceManager.globalShortcutStatus")
        }
    }

    @objc private func globalShortcutConfigurationChanged() { registerGlobalShortcut() }

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
        fitWindowToVisibleScreen()
    }

    private func fitWindowToVisibleScreen() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true, animate: false)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
