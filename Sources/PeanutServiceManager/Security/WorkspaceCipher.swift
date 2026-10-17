import CryptoKit
import Foundation
import Darwin

enum WorkspaceCipher {
    private static let credentialMagic = Data("PSMCRD01".utf8)

    static func writeSecurely(_ data: Data, to url: URL) throws {
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporaryURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CipherError.secureWriteFailed
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let handle = try FileHandle(forWritingTo: temporaryURL)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        let status = temporaryURL.path.withCString { source in
            url.path.withCString { destination in Darwin.rename(source, destination) }
        }
        guard status == 0 else { throw CipherError.secureWriteFailed }
    }

    static func encryptCredential(_ plaintext: Data, key: String) throws -> Data {
        guard !key.isEmpty else { throw CipherError.invalidCredentialKey }
        let derivedKey = Data(SHA256.hash(data: Data(key.utf8)))
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: derivedKey))
        guard let combined = box.combined else { throw CipherError.encryptionFailed }
        return credentialMagic + combined
    }

    static func decryptCredential(_ ciphertext: Data, key: String) throws -> Data {
        guard !key.isEmpty else { throw CipherError.invalidCredentialKey }
        guard ciphertext.starts(with: credentialMagic) else { throw CipherError.invalidCredentialFile }
        let sealed = ciphertext.dropFirst(credentialMagic.count)
        do {
            let box = try AES.GCM.SealedBox(combined: Data(sealed))
            let derivedKey = Data(SHA256.hash(data: Data(key.utf8)))
            return try AES.GCM.open(box, using: SymmetricKey(data: derivedKey))
        } catch {
            throw CipherError.wrongCredentialKeyOrDamagedFile
        }
    }

}
enum CipherError: LocalizedError {
    case encryptionFailed, invalidCredentialFile
    case wrongCredentialKeyOrDamagedFile, invalidCredentialKey
    case secureWriteFailed

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "无法加密资源密码。"
        case .invalidCredentialFile: return "本机密码文件格式无效或版本不受支持。"
        case .wrongCredentialKeyOrDamagedFile: return "本机加密 key 不正确或密码文件已损坏。"
        case .invalidCredentialKey: return "加密 key 不能为空。"
        case .secureWriteFailed: return "无法安全写入本机文件。"
        }
    }
}
