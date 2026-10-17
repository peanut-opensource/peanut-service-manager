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
        fileURL = directory.appendingPathComponent("workspace.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if fileManager.fileExists(atPath: fileURL.path) {
            workspace = try decoder.decode(Workspace.self, from: Data(contentsOf: fileURL))
        } else {
            workspace = Workspace()
        }
    }

    func update(_ change: (inout Workspace) -> Void) throws {
        var next = workspace
        change(&next)
        let data = try encoder.encode(next)
        try data.write(to: fileURL, options: .atomic)
        workspace = next
    }
}
