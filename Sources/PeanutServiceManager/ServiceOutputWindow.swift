import AppKit
import SwiftUI

@MainActor
enum ServiceOutputWindowPresenter {
    private static var windows: [UUID: NSWindow] = [:]
    private static var models: [UUID: AppModel] = [:]
    private static var delegates: [UUID: ServiceOutputWindowDelegate] = [:]

    static func show(model: AppModel, service: Service) {
        if let window = windows[service.id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(model.serviceDisplayName(service)) · 运行输出"
        window.minSize = NSSize(width: 520, height: 320)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ServiceOutputWindowView(model: model, service: service))
        let delegate = ServiceOutputWindowDelegate(serviceID: service.id)
        window.delegate = delegate
        windows[service.id] = window
        models[service.id] = model
        delegates[service.id] = delegate
        model.setOutputWindowOpen(true, serviceID: service.id)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    fileprivate static func close(serviceID: UUID) {
        models[serviceID]?.setOutputWindowOpen(false, serviceID: serviceID)
        models[serviceID] = nil
        delegates[serviceID] = nil
        windows[serviceID] = nil
    }
}

@MainActor
private final class ServiceOutputWindowDelegate: NSObject, NSWindowDelegate {
    private let serviceID: UUID

    init(serviceID: UUID) { self.serviceID = serviceID }

    func windowWillClose(_ notification: Notification) {
        ServiceOutputWindowPresenter.close(serviceID: serviceID)
    }
}

@MainActor
private struct ServiceOutputWindowView: View {
    @ObservedObject var model: AppModel
    let service: Service

    private var output: String { model.processLogs[service.id] ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.serviceDisplayName(service)).font(.title2.weight(.semibold))
                    Text("标准输出与错误输出 · 仅显示当前运行期间内容")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("清空") { model.clearServiceLogs(service.id) }
                    .disabled(output.isEmpty)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(output.isEmpty ? "服务启动后，执行输出会显示在这里。" : output)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(output.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
                        .textSelection(.enabled)
                        .padding(16)
                        .id("output-bottom")
                }
                .onAppear { proxy.scrollTo("output-bottom", anchor: .bottom) }
                .onChange(of: output) { _ in proxy.scrollTo("output-bottom", anchor: .bottom) }
            }
            .background(Color(NSColor.textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 320)
        .background(ManagerStyle.canvas)
    }
}
