import CryptoKit
import Foundation
import CommonCrypto
import Darwin

enum WorkspaceCipher {
    private static let credentialMagic = Data("PSMCRD01".utf8)
    private static let exportMagic = Data("PSMEXP01".utf8)
    private static let exportSaltLength = 16
    private static let keyLength = 32
    private static let pbkdf2Rounds: UInt32 = 600_000

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

    static func encryptExport(_ plaintext: Data, passphrase: String) throws -> Data {
        guard passphrase.count >= 10 else { throw CipherError.passphraseTooShort }
        let salt = try randomData(count: exportSaltLength)
        let key = try deriveKey(passphrase: passphrase, salt: salt)
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key))
        guard let combined = box.combined else { throw CipherError.encryptionFailed }
        return exportMagic + salt + combined
    }

    static func decryptExport(_ ciphertext: Data, passphrase: String) throws -> Data {
        guard ciphertext.starts(with: exportMagic), ciphertext.count > exportMagic.count + exportSaltLength else {
            throw CipherError.invalidExportFile
        }
        let saltStart = exportMagic.count
        let saltEnd = saltStart + exportSaltLength
        let salt = Data(ciphertext[saltStart..<saltEnd])
        let combined = Data(ciphertext[saltEnd...])
        let box: AES.GCM.SealedBox
        do { box = try AES.GCM.SealedBox(combined: combined) }
        catch { throw CipherError.wrongPassphraseOrDamagedFile }
        do { return try AES.GCM.open(box, using: SymmetricKey(data: try deriveKey(passphrase: passphrase, salt: salt))) }
        catch { throw CipherError.wrongPassphraseOrDamagedFile }
    }

    private static func deriveKey(passphrase: String, salt: Data) throws -> Data {
        let password = Data(passphrase.utf8)
        var output = Data(count: keyLength)
        let status: Int32 = output.withUnsafeMutableBytes { outputBuffer in
            password.withUnsafeBytes { passwordBuffer in
                salt.withUnsafeBytes { saltBuffer in
                    guard let outputBase = outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                          let passwordBase = passwordBuffer.bindMemory(to: Int8.self).baseAddress,
                          let saltBase = saltBuffer.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2), passwordBase, password.count,
                        saltBase, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        pbkdf2Rounds, outputBase, keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CipherError.keyDerivationFailed }
        return output
    }

    private static func randomData(count: Int) throws -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

enum CipherError: LocalizedError {
    case encryptionFailed, invalidCredentialFile, invalidExportFile
    case passphraseTooShort, wrongPassphraseOrDamagedFile
    case wrongCredentialKeyOrDamagedFile, invalidCredentialKey
    case keyDerivationFailed
    case secureWriteFailed

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "无法加密密码或备份数据。"
        case .invalidCredentialFile: return "本机密码文件格式无效或版本不受支持。"
        case .invalidExportFile: return "导入文件格式无效或版本不受支持。"
        case .passphraseTooShort: return "加密口令至少需要 10 个字符。"
        case .wrongPassphraseOrDamagedFile: return "口令错误或加密文件已损坏。"
        case .wrongCredentialKeyOrDamagedFile: return "本机加密 key 不正确或密码文件已损坏。"
        case .invalidCredentialKey: return "加密 key 不能为空。"
        case .keyDerivationFailed: return "无法从口令生成加密密钥。"
        case .secureWriteFailed: return "无法安全写入本机文件。"
        }
    }
}
