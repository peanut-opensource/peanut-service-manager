import Foundation
import Darwin
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LoginItemManager {
    private let label = "org.peanutopensource.PeanutServiceManager.login"

    var isEnabled: Bool {
        guard let dictionary = readPlist() else { return false }
        return dictionary["Label"] as? String == label && dictionary["ProgramArguments"] as? [String] == [Self.executablePath]
    }

    func setEnabled(_ enabled: Bool) throws {
        let url = plistURL
        if enabled {
            if FileManager.default.fileExists(atPath: url.path) {
                guard isEnabled else { throw LoginItemError.configurationConflict }
                return
            }
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [Self.executablePath],
                "RunAtLoad": true,
                "LimitLoadToSessionType": "Aqua"
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try createWithoutReplacing(data, at: url)
        } else {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            guard isEnabled else { throw LoginItemError.configurationConflict }
            try FileManager.default.removeItem(at: url)
        }
    }

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    private func readPlist() -> [String: Any]? {
        guard let data = try? Data(contentsOf: plistURL),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = value as? [String: Any] else { return nil }
        return dictionary
    }

    private func createWithoutReplacing(_ data: Data, at url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            if errno == EEXIST { throw LoginItemError.configurationConflict }
            throw LoginItemError.configurationWriteFailed
        }
        defer { close(descriptor) }
        do {
            try data.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                var offset = 0
                while offset < bytes.count {
                    let count = write(descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
                    guard count > 0 else { throw LoginItemError.configurationWriteFailed }
                    offset += count
                }
            }
        } catch {
            _ = unlink(url.path)
            throw error
        }
    }

    private static var executablePath: String {
        Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    }

}

private enum LoginItemError: LocalizedError {
    case configurationConflict
    case configurationWriteFailed

    var errorDescription: String? {
        switch self {
        case .configurationConflict:
            return "登录启动配置文件已存在且不属于花生服务管理器，未覆盖该文件。"
        case .configurationWriteFailed:
            return "无法写入登录启动配置文件。"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var loginEnabled = LoginItemManager().isEnabled
    @State private var credentialKey = ""
    @State private var feedback: String?
    @AppStorage("peanutServiceManager.globalShortcut") private var globalShortcut = "optionY"
    @AppStorage("peanutServiceManager.globalShortcutStatus") private var globalShortcutStatus = "正在检查"
    @State private var mcpFeedback: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ManagerPageHeader(title: "设置", subtitle: "应用行为、本机安全与配置文件", icon: "slider.horizontal.3")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 430, maximum: 560), spacing: 16)], alignment: .leading, spacing: 16) {
                    settingsCard("应用启动", subtitle: "登录与系统兼容性", icon: "power", color: ManagerStyle.accent) {
                        Toggle("登录 macOS 后自动打开花生服务管理器", isOn: $loginEnabled)
                            .onChange(of: loginEnabled) { enabled in
                                do { try LoginItemManager().setEnabled(enabled) }
                                catch {
                                    loginEnabled = !enabled
                                    model.errorMessage = error.localizedDescription
                                }
                            }
                        Divider()
                        Label("支持 macOS 12 及更新版本", systemImage: "checkmark.circle.fill")
                        Label("兼容 Intel 与 Apple 芯片", systemImage: "cpu")
                            .font(.callout).foregroundColor(.secondary)
                    }

                    settingsCard("快捷键", subtitle: "在任何应用中快速显示管理器", icon: "command", color: Color(red: 0.34, green: 0.48, blue: 0.77)) {
                        Picker("显示主窗口", selection: $globalShortcut) {
                            Text("Option + Y").tag("optionY")
                            Text("Control + Option + Y").tag("controlOptionY")
                            Text("Command + Option + Y").tag("commandOptionY")
                        }
                        .onChange(of: globalShortcut) { _ in
                            DistributedNotificationCenter.default().postNotificationName(
                                Notification.Name("PeanutServiceManagerGlobalShortcutChanged"), object: nil, deliverImmediately: true
                            )
                        }
                        HStack(spacing: 8) {
                            Circle().fill(globalShortcutStatus == "已启用" ? ManagerStyle.success : ManagerStyle.warning).frame(width: 8, height: 8)
                            Text("状态：\(globalShortcutStatus)").font(.callout).foregroundColor(.secondary)
                        }
                        Text("快捷键由本机全局热键注册。若被其他应用占用，可在此切换组合键。")
                            .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }

                    settingsCard("密码保护", subtitle: "只加密资源密码", icon: "lock.shield", color: Color(red: 0.23, green: 0.61, blue: 0.50)) {
                        Text("资源密码在本机单独加密保存；本机使用时可解密。加密 key 以明文保存在本机配置中。")
                            .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        ManagerTextField(title: "本机加密 key", placeholder: "例如 123456", text: $credentialKey)
                        Button("保存并重新加密已登记密码", action: saveCredentialKey)
                            .buttonStyle(.borderedProminent).tint(ManagerStyle.accent)
                            .disabled(credentialKey.isEmpty)
                    }

                    settingsCard("配置文件", subtitle: "导出备份或替换本机配置", icon: "doc.on.doc", color: Color(red: 0.69, green: 0.48, blue: 0.22)) {
                        Text("导出的 JSON 包含项目、环境、服务、资源和密码密文。导入前会校验格式与关联，成功后替换当前配置。")
                            .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("导出配置…", action: exportConfiguration).buttonStyle(.bordered)
                            Button("导入并替换…", action: chooseImportFile).buttonStyle(.bordered)
                        }
                        if let feedback {
                            Label(feedback, systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundColor(Color(red: 0.23, green: 0.61, blue: 0.50))
                        }
                    }

                    settingsCard("软件信息", subtitle: "版本、项目仓库与开发团队", icon: "info.circle", color: ManagerStyle.accent) {
                        infoRow("版本", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知")
                        Divider()
                        HStack(alignment: .top) {
                            Text("仓库").foregroundColor(.secondary)
                            Spacer(minLength: 12)
                            Link("github.com/peanut-opensource/peanut-service-manager", destination: URL(string: "https://github.com/peanut-opensource/peanut-service-manager")!)
                                .lineLimit(1).textSelection(.enabled)
                        }.font(.callout)
                        Divider()
                        infoRow("开发团队", "花生科技研发中心")
                    }

                    settingsCard("本地 MCP 服务", subtitle: "让 AI 客户端安全管理本机项目、环境和服务", icon: "network", color: ManagerStyle.accent) {
                        Label(mcpExecutableAvailable ? "服务程序已就绪，客户端按需启动" : "找不到 MCP 服务程序，请重新安装应用",
                              systemImage: mcpExecutableAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundColor(mcpExecutableAvailable ? ManagerStyle.success : ManagerStyle.warning)
                        infoRow("传输方式", "本机 STDIO；不开放网络端口")
                        infoRow("程序路径", mcpExecutablePath)
                        Text("在 Codex 的 ~/.codex/config.toml 中添加下方配置，然后重启或重新连接客户端。每个客户端会独立启动 MCP 进程；服务配置和运行状态与本应用共用。")
                            .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("复制 Codex 配置") { copyMCPConfiguration(for: .codex) }
                                .buttonStyle(.borderedProminent).tint(ManagerStyle.accent)
                            Button("复制通用 JSON 配置") { copyMCPConfiguration(for: .json) }
                                .buttonStyle(.bordered)
                        }
                        if let mcpFeedback {
                            Label(mcpFeedback, systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundColor(ManagerStyle.success)
                        }
                    }
                }
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(26)
        }
        .background(ManagerStyle.canvas)
        .frame(minWidth: 1100, minHeight: 640)
        .onAppear(perform: loadCredentialKey)
    }

    private func settingsCard<Content: View>(_ title: String, subtitle: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundColor(color)
                    .frame(width: 34, height: 34).background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.body, design: .rounded).weight(.bold))
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(ManagerStyle.card)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ManagerStyle.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value).foregroundColor(ManagerStyle.ink).textSelection(.enabled)
        }.font(.callout)
    }

    private var mcpExecutablePath: String {
        Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? ""
    }

    private var mcpExecutableAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: mcpExecutablePath)
    }

    private enum MCPConfigurationFormat { case codex, json }

    private func copyMCPConfiguration(for format: MCPConfigurationFormat) {
        let configuration: String
        switch format {
        case .codex:
            let quotedPath = mcpExecutablePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            configuration = """
            [mcp_servers.peanut_service_manager]
            command = "\(quotedPath)"
            args = ["--mcp-server"]
            enabled = true
            """
        case .json:
            let value: [String: Any] = ["mcpServers": ["peanut-service-manager": ["command": mcpExecutablePath, "args": ["--mcp-server"]]]]
            guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else {
                model.errorMessage = "无法生成 MCP 客户端配置。"
                return
            }
            configuration = text
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configuration, forType: .string)
        mcpFeedback = "配置已复制。"
    }

    private func loadCredentialKey() {
        do { credentialKey = try CredentialVault().encryptionKey() }
        catch { model.errorMessage = error.localizedDescription }
    }

    private func saveCredentialKey() {
        do {
            try CredentialVault().setEncryptionKey(credentialKey)
            model.errorMessage = nil
            feedback = "已保存，新 key 已用于重新加密已登记密码。"
        } catch { model.errorMessage = error.localizedDescription }
    }

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Peanut-Service-Manager.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try model.configurationExport()
            try WorkspaceCipher.writeSecurely(data, to: url)
            model.errorMessage = nil
            feedback = "配置文件已导出。"
        } catch { model.errorMessage = error.localizedDescription }
    }

    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return }
        guard let url = panel.url else { return }
        do {
            try model.importConfiguration(Data(contentsOf: url))
            credentialKey = try CredentialVault().encryptionKey()
            feedback = "配置已导入并替换本机数据。"
        } catch { model.errorMessage = error.localizedDescription }
    }
}
