import Foundation

enum DockerStatusProbe {
    static func check(_ resource: ResourceRecord) throws -> String {
        guard resource.type == .dockerContainer else { throw ProbeError.invalidTarget }
        guard let context = resource.dockerContext?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty else {
            throw ProbeError.missingContext
        }
        guard let identity = resource.containerID ?? resource.containerName,
              !identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProbeError.missingIdentity
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["docker", "--context", context, "inspect", "--format", "{{.State.Status}}", identity]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do { try process.run() }
        catch { throw ProbeError.dockerUnavailable }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()

        let response = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            if response.localizedCaseInsensitiveContains("cannot connect") || response.localizedCaseInsensitiveContains("is the docker daemon running") {
                throw ProbeError.contextUnavailable
            }
            if response.localizedCaseInsensitiveContains("no such object") || response.localizedCaseInsensitiveContains("not found") {
                throw ProbeError.containerNotFound
            }
            throw ProbeError.checkFailed
        }
        guard !response.isEmpty else { throw ProbeError.emptyStatus }
        return response
    }
}

private enum ProbeError: LocalizedError {
    case invalidTarget, missingContext, missingIdentity, dockerUnavailable
    case contextUnavailable, containerNotFound, checkFailed, emptyStatus

    var errorDescription: String? {
        switch self {
        case .invalidTarget: return "此检查只适用于 Docker 容器资源。"
        case .missingContext: return "请先填写 Docker context。"
        case .missingIdentity: return "请填写容器 ID 或名称。"
        case .dockerUnavailable: return "无法运行 Docker CLI。请确认 Docker 已安装且命令可用。"
        case .contextUnavailable: return "Docker context 不可连接。"
        case .containerNotFound: return "所选 Docker context 中不存在该容器。"
        case .checkFailed: return "Docker 返回检查失败；请核对 context 和容器身份。"
        case .emptyStatus: return "Docker 未返回容器状态。"
        }
    }
}
