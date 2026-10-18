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

    var body: some View {
        VStack(spacing: 0) {
            ManagerPageHeader(title: "系统设置", subtitle: "应用行为、本机安全与配置文件", icon: "slider.horizontal.3")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    settingsCard("应用启动", subtitle: "登录与系统兼容性", icon: "power", color: ManagerStyle.accent) {
                        Toggle("登录 macOS 后自动打开花生服务管理器", isOn: $loginEnabled)
                            .toggleStyle(.switch)
                            .onChange(of: loginEnabled) { enabled in
                                do { try LoginItemManager().setEnabled(enabled) }
                                catch {
                                    loginEnabled = !enabled
                                    model.errorMessage = error.localizedDescription
                                }
                            }
                        Divider().opacity(0.4)
                        HStack(spacing: 18) {
                            Label("macOS 12 及更新版本", systemImage: "checkmark.circle")
                            Label("Intel 与 Apple 芯片", systemImage: "cpu")
                        }
                        .font(.caption).foregroundColor(ManagerStyle.muted)
                    }

                    settingsCard("快捷键", subtitle: "在任何应用中快速显示管理器", icon: "command", color: ManagerStyle.cyan) {
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
                            ManagerStatusDot(color: globalShortcutStatus == "已启用" ? ManagerStyle.success : ManagerStyle.warning, size: 7.5)
                            Text("状态：\(globalShortcutStatus)").font(.callout).foregroundColor(ManagerStyle.muted)
                        }
                        Text("若快捷键被其他应用占用，可切换组合键。")
                            .font(.caption).foregroundColor(ManagerStyle.muted).fixedSize(horizontal: false, vertical: true)
                    }

                    settingsCard("密码保护", subtitle: "只加密资源密码", icon: "lock.shield", color: ManagerStyle.success) {
                        Text("资源密码在本机单独加密保存；本机使用时可解密。加密 key 以明文保存在本机配置中。")
                            .font(.callout).foregroundColor(ManagerStyle.muted).fixedSize(horizontal: false, vertical: true)
                        ManagerTextField(title: "本机加密 key", placeholder: "例如 123456", text: $credentialKey)
                        Button("保存并重新加密已登记密码", action: saveCredentialKey)
                            .buttonStyle(ManagerButtonStyle(.primary))
                            .disabled(credentialKey.isEmpty)
                    }

                    settingsCard("配置文件", subtitle: "导出备份或替换本机配置", icon: "doc.on.doc", color: ManagerStyle.warning) {
                        Text("导出的 JSON 包含项目、环境、服务、资源和密码密文。导入前会校验格式与关联，成功后替换当前配置。")
                            .font(.callout).foregroundColor(ManagerStyle.muted).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Button(action: exportConfiguration) {
                                Label("导出配置…", systemImage: "square.and.arrow.up")
                            }.buttonStyle(ManagerButtonStyle(.secondary))
                            Button(action: chooseImportFile) {
                                Label("导入并替换…", systemImage: "square.and.arrow.down")
                            }.buttonStyle(ManagerButtonStyle(.secondary))
                        }
                        if let feedback {
                            Label(feedback, systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundColor(ManagerStyle.success)
                        }
                    }

                    settingsCard("软件信息", subtitle: "版本、项目仓库与开发团队", icon: "info.circle", color: ManagerStyle.purple) {
                        infoRow("版本", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知")
                        Divider().opacity(0.4)
                        HStack(alignment: .top) {
                            Text("仓库").foregroundColor(ManagerStyle.muted)
                            Spacer(minLength: 12)
                            Link("github.com/peanut-opensource/peanut-service-manager", destination: URL(string: "https://github.com/peanut-opensource/peanut-service-manager")!)
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }.font(.callout)
                        Divider().opacity(0.4)
                        infoRow("开发团队", "花生科技研发中心")
                    }

                }
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(24)
            }
        }
        .background(ManagerStyle.canvas)
        .onAppear(perform: loadCredentialKey)
    }

    private func settingsCard<Content: View>(_ title: String, subtitle: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 24) {
            HStack(alignment: .top, spacing: 10) {
                ManagerIconBadge(icon: icon, color: color, size: 34, iconSize: 15, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(ManagerStyle.ink)
                    Text(subtitle).font(.caption).foregroundColor(ManagerStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(width: 210, alignment: .leading)
            VStack(alignment: .leading, spacing: 14) {
                content()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .managerTableSurface()
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundColor(ManagerStyle.muted)
            Spacer()
            Text(value).foregroundColor(ManagerStyle.ink).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }.font(.callout)
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
