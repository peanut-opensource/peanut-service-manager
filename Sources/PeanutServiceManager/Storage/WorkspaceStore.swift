import Foundation
import Combine
import Darwin

private enum WorkspaceStoreError: LocalizedError {
    case concurrentModification

    var errorDescription: String? {
        "本机配置已在另一客户端中修改。请刷新页面后重试，避免覆盖新数据。"
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var workspace: Workspace

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("PeanutServiceManager", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        fileURL = directory.appendingPathComponent("workspace.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        workspace = Workspace()
        workspace = try withExclusiveFileLock {
            if fileManager.fileExists(atPath: fileURL.path) {
                let value = try decoder.decode(Workspace.self, from: Data(contentsOf: fileURL))
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
                return value
            }
            let value = Workspace()
            try persist(value)
            return value
        }
    }

    func update(_ change: (inout Workspace) -> Void) throws {
        let expected = workspace
        workspace = try withExclusiveFileLock {
            var next = try loadLatestWorkspace()
            guard next == expected else { throw WorkspaceStoreError.concurrentModification }
            change(&next)
            try persist(next)
            return next
        }
    }

    func replace(with next: Workspace) throws {
        workspace = try withExclusiveFileLock {
            try persist(next)
            return next
        }
    }

    func refreshFromDisk() throws -> Bool {
        let latest = try withExclusiveFileLock { try loadLatestWorkspace() }
        guard latest != workspace else { return false }
        workspace = latest
        return true
    }

    private func loadLatestWorkspace() throws -> Workspace {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Workspace() }
        return try decoder.decode(Workspace.self, from: Data(contentsOf: fileURL))
    }

    private func persist(_ value: Workspace) throws {
        let plaintext = try encoder.encode(value)
        try WorkspaceCipher.writeSecurely(plaintext, to: fileURL)
    }

    private func withExclusiveFileLock<T>(_ body: () throws -> T) throws -> T {
        let lockURL = fileURL.deletingLastPathComponent().appendingPathComponent("workspace.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileLocking) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            throw CocoaError(.fileLocking)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }
}
