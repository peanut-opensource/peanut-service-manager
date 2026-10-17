import Foundation
import Combine

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

        if fileManager.fileExists(atPath: fileURL.path) {
            workspace = try decoder.decode(Workspace.self, from: Data(contentsOf: fileURL))
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } else {
            workspace = Workspace()
            try persist(workspace)
        }
    }

    func update(_ change: (inout Workspace) -> Void) throws {
        var next = workspace
        change(&next)
        try persist(next)
        workspace = next
    }

    func replace(with next: Workspace) throws {
        try persist(next)
        workspace = next
    }

    private func persist(_ value: Workspace) throws {
        let plaintext = try encoder.encode(value)
        try WorkspaceCipher.writeSecurely(plaintext, to: fileURL)
    }
}
