import Foundation
import Security
import CryptoKit

/// Represents the cryptographic device identity generated specifically for the macOS Companion.
public struct MacDeviceIdentity: Sendable, Codable, Equatable {
    public let deviceId: String
    public let algorithm: String
    public let keyType: String
    public let publicKeyBase64X509: String
    public let publicKeyFingerprint: String
    public let createdAt: Date

    public init(
        deviceId: String,
        algorithm: String = "RSASSA-PSS-SHA256",
        keyType: String = "RSA-2048",
        publicKeyBase64X509: String,
        publicKeyFingerprint: String,
        createdAt: Date = Date()
    ) {
        self.deviceId = deviceId
        self.algorithm = algorithm
        self.keyType = keyType
        self.publicKeyBase64X509 = publicKeyBase64X509
        self.publicKeyFingerprint = publicKeyFingerprint
        self.createdAt = createdAt
    }
}

/// Manages an isolated cryptographic device identity for the macOS Companion.
///
/// CRITICAL ISOLATION RULES:
/// - Stored independently in `~/Library/Application Support/UPIMeshCompanion/`.
/// - Never shares, copies, or queries the physical iPhone's Keychain or keys.
/// - Generates its own unique `deviceId` (`mac-companion-<UUID>`).
public final class MacDeviceIdentityManager: @unchecked Sendable {

    public static let shared = MacDeviceIdentityManager()

    private let lock = NSLock()
    private var cachedPrivateKey: SecKey?

    private var appSupportDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("UPIMeshCompanion", isDirectory: true)
    }

    private var identityFileURL: URL {
        appSupportDir.appendingPathComponent("companion_identity.json")
    }

    private var keyFileURL: URL {
        appSupportDir.appendingPathComponent("companion_key.pkcs1")
    }

    public init() {}

    /// Retrieves or generates a dedicated macOS companion cryptographic identity.
    public func getOrCreateIdentity() throws -> MacDeviceIdentity {
        lock.lock()
        defer { lock.unlock() }

        if let existingKey = try? getOrLoadPrivateKeyInternal() {
            let deviceId = loadDeviceIdInternal() ?? "mac-companion-\(UUID().uuidString.lowercased())"
            return try assembleIdentity(privateKey: existingKey, deviceId: deviceId)
        }

        return try generateNewIdentityInternal()
    }

    /// Digitally signs canonical data bytes using the Mac companion's private RSA key.
    public func sign(message: Data) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        let privateKey = try getOrLoadPrivateKeyInternal()
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, .rsaSignatureMessagePSSSHA256) else {
            throw NSError(domain: "MacDeviceIdentity", code: 1, userInfo: [NSLocalizedDescriptionKey: "Algorithm not supported"])
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePSSSHA256,
            message as CFData,
            &error
        ) as Data? else {
            let desc = error?.takeRetainedValue().localizedDescription ?? "Signing failed"
            throw NSError(domain: "MacDeviceIdentity", code: 2, userInfo: [NSLocalizedDescriptionKey: desc])
        }

        return signature
    }

    /// Returns Base64-encoded RSASSA-PSS signature.
    public func signBase64(message: Data) throws -> String {
        let sigData = try sign(message: message)
        return sigData.base64EncodedString()
    }

    /// Exports the Mac companion public key as Base64 X.509 SubjectPublicKeyInfo.
    public func exportPublicKeyBase64X509() throws -> String {
        let identity = try getOrCreateIdentity()
        return identity.publicKeyBase64X509
    }

    // MARK: - Mathematical Signature Verification

    /// Verifies an RSASSA-PSS SHA-256 digital signature against an external X.509 public key.
    ///
    /// NOTE: Mathematical validity verifies only that the bytes were signed by the holder of the private key
    /// corresponding to `publicKeyBase64X509`. It does NOT authenticate that the public key is authorized
    /// to debit the claimed account on the bank ledger. Identity authorization requires backend bridge settlement.
    public static func verifyRemoteRSASSA_PSS(
        publicKeyBase64X509: String,
        message: Data,
        signatureBase64: String
    ) -> (isValid: Bool, errorDescription: String?) {
        let trimmedKey = publicKeyBase64X509.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let keyData = Data(base64Encoded: trimmedKey) else {
            return (false, "Public key is not valid Base64.")
        }
        let trimmedSig = signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sigData = Data(base64Encoded: trimmedSig) else {
            return (false, "Signature is not valid Base64.")
        }

        let importAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic
        ]

        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(keyData as CFData, importAttrs as CFDictionary, &error) else {
            let desc = error?.takeRetainedValue().localizedDescription ?? "Key import failed"
            return (false, "Failed to import RSA public key: \(desc)")
        }

        guard SecKeyIsAlgorithmSupported(publicKey, .verify, .rsaSignatureMessagePSSSHA256) else {
            return (false, "Algorithm RSASSA-PSS SHA-256 is not supported by imported key.")
        }

        var verifyError: Unmanaged<CFError>?
        let verified = SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePSSSHA256,
            message as CFData,
            sigData as CFData,
            &verifyError
        )

        if verified {
            return (true, nil)
        } else {
            let desc = verifyError?.takeRetainedValue().localizedDescription ?? "Verification failed"
            return (false, desc)
        }
    }

    // MARK: - Internal Key Management

    private func getOrLoadPrivateKeyInternal() throws -> SecKey {
        if let cached = cachedPrivateKey {
            return cached
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: keyFileURL.path) else {
            throw NSError(domain: "MacDeviceIdentity", code: 3, userInfo: [NSLocalizedDescriptionKey: "Key file not found"])
        }

        let privData = try Data(contentsOf: keyFileURL)
        let importAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(privData as CFData, importAttrs as CFDictionary, &error) else {
            let desc = error?.takeRetainedValue().localizedDescription ?? "Key import failed"
            throw NSError(domain: "MacDeviceIdentity", code: 4, userInfo: [NSLocalizedDescriptionKey: desc])
        }

        cachedPrivateKey = key
        return key
    }

    private func generateNewIdentityInternal() throws -> MacDeviceIdentity {
        let fm = FileManager.default
        if !fm.fileExists(atPath: appSupportDir.path) {
            try fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        }

        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, &error) else {
            let desc = error?.takeRetainedValue().localizedDescription ?? "SecKeyCreateRandomKey failed"
            throw NSError(domain: "MacDeviceIdentity", code: 5, userInfo: [NSLocalizedDescriptionKey: desc])
        }

        cachedPrivateKey = privateKey

        // Export PKCS#1 DER representation and save with 0600 permissions
        guard let pkcs1Data = SecKeyCopyExternalRepresentation(privateKey, &error) as Data? else {
            let desc = error?.takeRetainedValue().localizedDescription ?? "PKCS#1 export failed"
            throw NSError(domain: "MacDeviceIdentity", code: 6, userInfo: [NSLocalizedDescriptionKey: desc])
        }

        try pkcs1Data.write(to: keyFileURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFileURL.path)

        var deviceId = loadDeviceIdInternal()
        if deviceId == nil {
            let freshId = "mac-companion-\(UUID().uuidString.lowercased())"
            saveDeviceIdInternal(freshId)
            deviceId = freshId
        }

        return try assembleIdentity(privateKey: privateKey, deviceId: deviceId!)
    }

    private func assembleIdentity(privateKey: SecKey, deviceId: String) throws -> MacDeviceIdentity {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw NSError(domain: "MacDeviceIdentity", code: 7, userInfo: [NSLocalizedDescriptionKey: "Unable to copy public key"])
        }

        var error: Unmanaged<CFError>?
        guard let pkcs1Data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            let desc = error?.takeRetainedValue().localizedDescription ?? "Failed to export public key"
            throw NSError(domain: "MacDeviceIdentity", code: 8, userInfo: [NSLocalizedDescriptionKey: desc])
        }

        let x509Data = Self.exportX509SubjectPublicKeyInfo(from: pkcs1Data)
        let base64X509 = x509Data.base64EncodedString()
        let digest = SHA256.hash(data: x509Data)
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined(separator: ":")

        let identity = MacDeviceIdentity(
            deviceId: deviceId,
            publicKeyBase64X509: base64X509,
            publicKeyFingerprint: fingerprint,
            createdAt: Date()
        )

        // Save metadata
        let data = try JSONEncoder().encode(identity)
        try data.write(to: identityFileURL, options: .atomic)

        return identity
    }

    private func loadDeviceIdInternal() -> String? {
        guard let data = try? Data(contentsOf: identityFileURL),
              let identity = try? JSONDecoder().decode(MacDeviceIdentity.self, from: data) else {
            return nil
        }
        return identity.deviceId
    }

    private func saveDeviceIdInternal(_ deviceId: String) {
        // Handled in assembleIdentity
    }

    // MARK: - ASN.1 DER Encoding Helpers

    public static func exportX509SubjectPublicKeyInfo(from pkcs1: Data) -> Data {
        let algorithmIdentifier: [UInt8] = [
            0x30, 0x0D,
            0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,
            0x05, 0x00
        ]
        let bitStringContentLength = pkcs1.count + 1
        var bitString = Data([0x03])
        bitString.append(encodeDERLength(bitStringContentLength))
        bitString.append(0x00)
        bitString.append(pkcs1)

        var sequenceContent = Data(algorithmIdentifier)
        sequenceContent.append(bitString)

        var outerSequence = Data([0x30])
        outerSequence.append(encodeDERLength(sequenceContent.count))
        outerSequence.append(sequenceContent)
        return outerSequence
    }

    private static func encodeDERLength(_ length: Int) -> Data {
        if length < 128 {
            return Data([UInt8(length)])
        } else if length < 256 {
            return Data([0x81, UInt8(length)])
        } else {
            let high = UInt8((length >> 8) & 0xFF)
            let low = UInt8(length & 0xFF)
            return Data([0x82, high, low])
        }
    }
}
