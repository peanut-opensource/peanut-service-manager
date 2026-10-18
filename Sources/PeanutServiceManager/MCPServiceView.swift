import SwiftUI
import AppKit

struct MCPServiceView: View {
    @ObservedObject var model: AppModel
    @State private var copyFeedback: String?

    var body: some View {
        VStack(spacing: 0) {
            ManagerPageHeader(title: "MCP 服务", subtitle: "连接 AI 客户端，管理本机项目、环境、服务与资源", icon: "network")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    readiness
                    section("接入步骤", subtitle: "一次配置，由客户端按需启动", icon: "list.number") {
                        step("1", title: "确认应用已安装", detail: "配置使用下方真实程序路径。临时构建路径在清理或重新构建后可能失效。")
                        Divider().opacity(0.4)
                        step("2", title: "合并客户端配置", detail: "将下方配置加入客户端，并保留已有服务。Codex 使用 ~/.codex/config.toml，其他客户端可使用通用 JSON。")
                        Divider().opacity(0.4)
                        step("3", title: "重新连接并检查", detail: "保存后在客户端重新连接，先用 workspace_list 读取目标。连接状态请在客户端查看。")
                    }
                    configurationCard("Codex", subtitle: "合并到 ~/.codex/config.toml", configuration: codexConfiguration)
                    configurationCard("通用 JSON", subtitle: "用于支持本机 STDIO 的 MCP 客户端", configuration: jsonConfiguration)
                    if let copyFeedback {
                        Label(copyFeedback, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(ManagerStyle.success)
                            .padding(.horizontal, 4)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        section("工具能力", subtitle: "与桌面应用共享本机配置和运行状态", icon: "wrench.and.screwdriver") {
                            capability("项目与环境", detail: "查找稳定 ID，登记项目与环境，维护分组及关联。")
                            capability("服务操作", detail: "登记服务，读取状态和近期日志，启动、优雅停止与重启。")
                            capability("资源与绑定", detail: "登记资源、检查状态，维护项目和环境绑定。Docker 仅登记和检查状态。")
                            capability("应用设置", detail: "读取和更新设置；配置导入、导出在系统设置中完成。")
                        }
                        section("凭据与操作边界", subtitle: "明确目标后再执行操作", icon: "lock.shield") {
                            capability("目标必须明确", detail: "先使用 workspace_list 或 target_search，操作时使用稳定 UUID，并指定完整项目 / 环境 / 服务路径。")
                            capability("密码按需读取", detail: "资源列表隐藏密码和凭据引用。只有 resource_password_get 在明确资源及项目环境绑定后返回明文密码。")
                            capability("加密 key 不回显", detail: "设置读取不返回加密 key；更新 key 后也不会在结果中回显。请仅向可信客户端开放工具权限。")
                            capability("本页操作", detail: "复制仅写入剪贴板，不修改客户端配置，不连接客户端，也不启动或停止已登记服务。")
                        }
                    }
                }
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(24)
            }
        }
        .background(ManagerStyle.canvas)
    }

    private var readiness: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ManagerIconBadge(icon: "network", color: ManagerStyle.purple, size: 44, iconSize: 20, cornerRadius: 8.5)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(executableAvailable ? "MCP 服务程序已就绪" : "MCP 服务程序不可用")
                            .font(.system(size: 16, weight: .semibold))
                        ManagerStatusDot(color: executableAvailable ? ManagerStyle.success : ManagerStyle.warning, size: 7.5)
                    }
                    Text(executableAvailable ? "由客户端按需启动独立进程，连接状态请在客户端中查看。" : "当前路径不存在或不可执行，请检查应用安装后重新打开。")
                        .font(.callout).foregroundColor(ManagerStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("本机 STDIO").font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(ManagerStyle.canvas).clipShape(RoundedRectangle(cornerRadius: ManagerStyle.badgeRadius, style: .continuous)).foregroundColor(ManagerStyle.muted)
                    .overlay(RoundedRectangle(cornerRadius: ManagerStyle.badgeRadius, style: .continuous).strokeBorder(ManagerStyle.fieldBorder, lineWidth: 0.8))
            }
            Divider().opacity(0.4)
            HStack(alignment: .top, spacing: 16) {
                Text("程序路径").font(.callout).foregroundColor(ManagerStyle.muted).frame(width: 70, alignment: .leading)
                ScrollView(.horizontal) {
                    Text(executablePath).font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                        .padding(.vertical, 7).padding(.horizontal, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ManagerStyle.field)
                .overlay(RoundedRectangle(cornerRadius: ManagerStyle.radius).strokeBorder(ManagerStyle.fieldBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: ManagerStyle.radius, style: .continuous))
                Button { copy(executablePath, label: "程序路径") } label: {
                    Label("复制路径", systemImage: "doc.on.doc")
                }.buttonStyle(ManagerButtonStyle(.secondary))
            }
            Text("不开放网络监听端口。每个客户端独立启动 MCP 进程，与本应用共用本机配置及服务运行状态。")
                .font(.caption).foregroundColor(ManagerStyle.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .managerTableSurface()
    }

    private func section<Content: View>(_ title: String, subtitle: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 10) {
                ManagerIconBadge(icon: icon, color: ManagerStyle.purple, size: 32, iconSize: 15, cornerRadius: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(.caption).foregroundColor(ManagerStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .managerTableSurface()
    }

    private func step(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundColor(ManagerStyle.purple).frame(width: 24, height: 24)
                .background(ManagerStyle.purple.opacity(0.12)).clipShape(Circle())
            capability(title, detail: detail)
        }
    }

    private func capability(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.callout).foregroundColor(ManagerStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func configurationCard(_ title: String, subtitle: String, configuration: String) -> some View {
        section(title, subtitle: subtitle, icon: "chevron.left.forwardslash.chevron.right") {
            HStack {
                Label("客户端配置", systemImage: "text.alignleft")
                    .font(.caption.weight(.medium)).foregroundColor(ManagerStyle.muted)
                Spacer()
                Button { copy(configuration, label: "\(title) 配置") } label: {
                    Label("复制配置", systemImage: "doc.on.doc")
                }.buttonStyle(ManagerButtonStyle(.primary))
            }
            ScrollView(.horizontal) {
                Text(configuration).font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ManagerStyle.field)
            .overlay(RoundedRectangle(cornerRadius: ManagerStyle.radius, style: .continuous).strokeBorder(ManagerStyle.fieldBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: ManagerStyle.radius, style: .continuous))
            Text("command 指向上方程序路径").font(.caption).foregroundColor(ManagerStyle.muted)
        }
    }

    private var executablePath: String {
        Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? ""
    }

    private var executableAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executablePath)
    }

    private var codexConfiguration: String {
        let quotedPath = executablePath.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return """
        [mcp_servers.peanut_service_manager]
        command = "\(quotedPath)"
        args = ["--mcp-server"]
        enabled = true
        """
    }

    private var jsonConfiguration: String {
        let configuration: [String: Any] = ["mcpServers": ["peanut-service-manager": [
            "command": executablePath, "args": ["--mcp-server"]
        ]]]
        guard let data = try? JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "无法生成 MCP 客户端配置。" }
        return text
    }

    private func copy(_ value: String, label: String) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(value, forType: .string) {
            copyFeedback = "\(label)已复制，请在客户端中完成配置。"
        } else {
            model.errorMessage = "无法写入剪贴板，请重试。"
        }
    }
}
