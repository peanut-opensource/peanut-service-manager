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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(ManagerStyle.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("设置").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("管理器启动与本机行为").font(.callout).foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 4)

            GroupBox("登录启动") {
                Toggle("登录 macOS 后自动打开花生服务管理器", isOn: $loginEnabled)
                    .onChange(of: loginEnabled) { enabled in
                        do { try LoginItemManager().setEnabled(enabled) }
                        catch {
                            loginEnabled = !enabled
                            model.errorMessage = error.localizedDescription
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }

            GroupBox("兼容性") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("最低支持 macOS 12", systemImage: "checkmark.circle.fill")
                    Label("应用包含 Intel 与 Apple Silicon 通用二进制", systemImage: "cpu")
                }
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }

            GroupBox("本机密码加密") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("资源密码使用 AES-GCM 加密（不是简单混淆）；读取密码时，应用再用本机 key 解密。默认 key 为 123456，以明文保存在本机，可查看、复制和自行设置。")
                        .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    TextField("本机密码加密 key", text: $credentialKey)
                    Button("保存并重新加密密码", action: saveCredentialKey)
                        .disabled(credentialKey.isEmpty)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }

            GroupBox("配置文件") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("导出或导入一份 JSON 配置文件。项目和资源登记信息按原格式保存；资源密码以 AES-GCM 加密，明文 key 会一并保存在文件中。导入时会校验文件结构和密码密文，再直接替换当前配置。")
                        .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("导出配置文件…", action: exportConfiguration)
                    Button("导入并替换配置文件…", action: chooseImportFile)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }
            Spacer()
        }
        .padding(28)
        .background(ManagerStyle.panel)
        .onAppear(perform: loadCredentialKey)
    }

    private func loadCredentialKey() {
        do { credentialKey = try CredentialVault().encryptionKey() }
        catch { model.errorMessage = error.localizedDescription }
    }

    private func saveCredentialKey() {
        do {
            try CredentialVault().setEncryptionKey(credentialKey)
            model.errorMessage = nil
            model.errorMessage = "已保存；本机已登记密码已用新 key 重新加密。"
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
        } catch { model.errorMessage = error.localizedDescription }
    }
}
