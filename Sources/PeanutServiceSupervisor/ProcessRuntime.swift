import Darwin
import Foundation
import PeanutServiceIPC

/// Owns only process groups created by this supervisor instance.
final class ProcessRuntime {
    private let lock = NSRecursiveLock()
    private var records: [UUID: Record] = [:]
    private let logCapacity = 256 * 1024

    private final class Record {
        let request: ServiceLaunchRequest
        let pid: pid_t
        let group: pid_t
        var state: SupervisorProcessState = .starting
        var exitCode: Int32?
        var message: String?
        var entries: [SupervisorLogEntry] = []
        var nextSequence: UInt64 = 1
        var logBytes = 0
        var groupGone = false
        var requestedStop = false

        init(request: ServiceLaunchRequest, pid: pid_t) {
            self.request = request
            self.pid = pid
            self.group = pid
        }
    }

    func start(_ request: ServiceLaunchRequest) throws -> SupervisorServiceSnapshot {
        lock.lock(); defer { lock.unlock() }
        if let existing = records[request.serviceID] {
            refresh(existing)
            if !existing.groupGone { return snapshot(existing) }
            records.removeValue(forKey: request.serviceID)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: request.workingDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RuntimeError("工作目录不存在或不是目录。")
        }
        guard !request.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuntimeError("启动命令为空。")
        }

        var outputPipe: [Int32] = [0, 0]
        guard pipe(&outputPipe) == 0 else { throw RuntimeError("无法创建服务输出管道（errno \(errno)）。") }
        _ = fcntl(outputPipe[0], F_SETFL, fcntl(outputPipe[0], F_GETFL) | O_NONBLOCK)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0,
              posix_spawnattr_init(&attributes) == 0 else {
            close(outputPipe[0]); close(outputPipe[1])
            throw RuntimeError("无法初始化进程启动配置。")
        }
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, outputPipe[0])
        posix_spawn_file_actions_addclose(&actions, outputPipe[1])
        let directoryResult = posix_spawn_file_actions_addchdir_np(&actions, request.workingDirectory)
        guard directoryResult == 0 else {
            close(outputPipe[0]); close(outputPipe[1])
            throw RuntimeError("无法设置服务工作目录（errno \(directoryResult)）。")
        }
        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        sigaddset(&defaultSignals, SIGTERM)
        sigaddset(&defaultSignals, SIGINT)
        sigaddset(&defaultSignals, SIGHUP)
        sigaddset(&defaultSignals, SIGPIPE)
        var signalMask = sigset_t()
        sigemptyset(&signalMask)
        guard posix_spawnattr_setsigdefault(&attributes, &defaultSignals) == 0,
              posix_spawnattr_setsigmask(&attributes, &signalMask) == 0,
              posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0 else {
            close(outputPipe[0]); close(outputPipe[1])
            throw RuntimeError("无法设置服务进程组及其信号行为。")
        }

        // Keep the configured arguments on the command invocation. A separate
        // shell line would execute each argument as another command.
        let argumentSuffix = request.arguments.filter { !$0.isEmpty }.map(Self.shellQuote).joined(separator: " ")
        let command = request.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let script = argumentSuffix.isEmpty ? command : "\(command) \(argumentSuffix)"
        let argvStrings = ["/bin/sh", "-c", script, request.name]
        let argv = argvStrings.map { strdup($0) } + [nil]
        defer { argv.forEach { if let item = $0 { free(item) } } }

        var environment = ProcessInfo.processInfo.environment
        request.environment.forEach { environment[$0.key] = $0.value }
        let envValues: [String] = environment.keys.sorted().map { "\($0)=\(environment[$0]!)" }
        let envStrings: [UnsafeMutablePointer<CChar>?] = envValues.map { strdup($0) } + [nil]
        defer { envStrings.forEach { if let item = $0 { free(item) } } }

        var child: pid_t = 0
        let result = posix_spawn(&child, "/bin/sh", &actions, &attributes, argv, envStrings)
        close(outputPipe[1])
        guard result == 0 else {
            close(outputPipe[0])
            throw RuntimeError("服务启动失败（errno \(result)）。")
        }
        let record = Record(request: request, pid: child)
        record.state = .running
        records[request.serviceID] = record
        DispatchQueue.global(qos: .utility).async { [weak self, weak record] in
            guard let self, let record else { close(outputPipe[0]); return }
            self.readOutput(fd: outputPipe[0], record: record)
        }
        DispatchQueue.global(qos: .utility).async { [weak self, weak record] in
            guard let self, let record else { return }
            var status: Int32 = 0
            while waitpid(record.pid, &status, 0) < 0 && errno == EINTR { }
            self.lock.lock()
            let termination = status & 0x7f
            if termination == 0 { record.exitCode = (status >> 8) & 0xff }
            else if termination != 0x7f { record.exitCode = 128 + termination }
            self.refresh(record)
            self.lock.unlock()
        }
        return snapshot(record)
    }

    func stop(serviceID: UUID, force: Bool) throws -> SupervisorServiceSnapshot {
        lock.lock(); defer { lock.unlock() }
        guard let record = records[serviceID] else { throw RuntimeError("未找到由当前管理器启动的服务实例。") }
        refresh(record)
        guard !record.groupGone else { return snapshot(record) }
        let signal = force ? SIGKILL : SIGTERM
        guard kill(-record.group, signal) == 0 || errno == ESRCH else {
            throw RuntimeError("无法向已登记的服务进程组发送停止信号（errno \(errno)）。")
        }
        record.requestedStop = true
        record.state = .stopping
        record.message = force ? "已向服务进程组发送强制停止信号。" : "已向服务进程组发送正常停止信号。"
        return snapshot(record)
    }

    func snapshots() -> [SupervisorServiceSnapshot] {
        lock.lock(); defer { lock.unlock() }
        return records.values.map { refresh($0); return snapshot($0) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func logs(serviceID: UUID, afterSequence: UInt64) -> (entries: [SupervisorLogEntry], nextSequence: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard let record = records[serviceID] else { return ([], 1) }
        return (record.entries.filter { $0.sequence > afterSequence }, record.nextSequence)
    }

    private func refresh(_ record: Record) {
        guard !record.groupGone else { return }
        if kill(-record.group, 0) == 0 || errno == EPERM {
            record.state = record.state == .stopping ? .stopping : .running
            if record.exitCode != nil { record.message = "启动包装进程已退出，进程组仍有进程运行。" }
            return
        }
        guard errno == ESRCH else { return }
        record.groupGone = true
        record.state = record.requestedStop || record.exitCode == 0 || record.exitCode == nil ? .exited : .failed
        record.message = record.state == .failed ? "服务进程已异常退出。" : nil
    }

    private func readOutput(fd: Int32, record: Record) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                let text = String(decoding: buffer[..<count], as: UTF8.self)
                lock.lock()
                let bytes = text.utf8.count
                record.entries.append(makeLog(sequence: record.nextSequence, stream: "combined", text: text))
                record.nextSequence &+= 1
                record.logBytes += bytes
                while record.logBytes > logCapacity, !record.entries.isEmpty {
                    record.logBytes -= record.entries.removeFirst().text.utf8.count
                }
                lock.unlock()
            } else if count == 0 { break }
            else if errno == EINTR { continue }
            else if errno == EAGAIN || errno == EWOULDBLOCK { usleep(20_000) }
            else { break }
        }
        close(fd)
    }

    private func snapshot(_ record: Record) -> SupervisorServiceSnapshot {
        makeSnapshot(["id": record.request.serviceID.uuidString, "projectID": record.request.projectID.uuidString,
                      "environmentID": record.request.environmentID.uuidString, "name": record.request.name,
                      "state": record.state.rawValue, "pid": Int(record.pid), "exitCode": record.exitCode as Any? ?? NSNull(),
                      "message": record.message as Any? ?? NSNull(), "nextLogSequence": record.nextSequence])
    }

    private func makeSnapshot(_ object: [String: Any]) -> SupervisorServiceSnapshot {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return try! JSONDecoder().decode(SupervisorServiceSnapshot.self, from: data)
    }

    private func makeLog(sequence: UInt64, stream: String, text: String) -> SupervisorLogEntry {
        let data = try! JSONSerialization.data(withJSONObject: ["sequence": sequence, "stream": stream, "text": text])
        return try! JSONDecoder().decode(SupervisorLogEntry.self, from: data)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct RuntimeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
