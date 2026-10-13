import Foundation
import Security
import CryptoKit

/// Represents the cryptographic device identity stored securely in the iOS Keychain.
public struct DeviceIdentity: Sendable, Codable, Equatable {
    /// Stable, persistent installation identifier for this device.
    public let deviceId: String
    
    /// The digital signature algorithm implemented by this identity ("RSASSA-PSS-SHA256").
    public let algorithm: String
    
    /// The asymmetric key specification ("RSA-2048").
    public let keyType: String
    
    /// The public key exported in standard Base64-encoded X.509 SubjectPublicKeyInfo DER format.
    /// This format is directly parsable by Java's `KeyFactory.generatePublic(X509EncodedKeySpec)`.
    public let publicKeyBase64X509: String
    
    /// SHA-256 fingerprint of the X.509 public key in hexadecimal format.
    public let publicKeyFingerprint: String
    
    /// Timestamp when this identity was initialized on the device.
    public let createdAt: Date
    
    /// Indicates whether the active key is stored in the hardware Secure Enclave.
    /// Note: Secure Enclave exclusively supports NIST P-256 elliptic curves and does not support RSA.
    /// Therefore, for RSA-PSS compatibility with the UPI Offline Mesh backend, this is `false`.
    public let isSecureEnclaveBacked: Bool
    
    public init(
        deviceId: String,
        algorithm: String = "RSASSA-PSS-SHA256",
        keyType: String = "RSA-2048",
        publicKeyBase64X509: String,
        publicKeyFingerprint: String,
        createdAt: Date = Date(),
        isSecureEnclaveBacked: Bool = false
    ) {
        self.deviceId = deviceId
        self.algorithm = algorithm
        self.keyType = keyType
        self.publicKeyBase64X509 = publicKeyBase64X509
        self.publicKeyFingerprint = publicKeyFingerprint
        self.createdAt = createdAt
        self.isSecureEnclaveBacked = isSecureEnclaveBacked
    }
}

/// Errors thrown by `DeviceIdentityManager`.
public enum DeviceIdentityError: LocalizedError, Equatable {
    case keyGenerationFailed(String)
    case keyNotFound
    case keyCorrupted
    case signingFailed(String)
    case verificationFailed(String)
    case exportFailed(String)
    case secureEnclaveUnavailable
    case keychainError(OSStatus, String)
    
    public var errorDescription: String? {
        switch self {
        case .keyGenerationFailed(let message):
            return "Failed to generate device signing key: \(message)"
        case .keyNotFound:
            return "No device signing key found in Keychain."
        case .keyCorrupted:
            return "Device signing key in Keychain is invalid or corrupted."
        case .signingFailed(let message):
            return "Cryptographic digital signing failed: \(message)"
        case .verificationFailed(let message):
            return "Signature verification failed: \(message)"
        case .exportFailed(let message):
            return "Failed to export public key: \(message)"
        case .secureEnclaveUnavailable:
            return "Apple Secure Enclave hardware is not available on this device."
        case .keychainError(let status, let message):
            return "Keychain operation failed (status \(status)): \(message)"
        }
    }
}

/// Provides detailed security profile information regarding device hardware and cryptographic support.
public struct SecurityHardwareProfile: Sendable, Codable, Equatable {
    public let isSecureEnclaveAvailable: Bool
    public let activeAlgorithm: String
    public let activeKeyStorage: String
    public let protocolCompatibilityNote: String
}

/// Manages per-installation cryptographic device identity and secure key storage using iOS Keychain Services.
///
/// ### Architectural Notice on Cryptographic Interoperability:
/// The Spring Boot backend (`CryptoService.java` & `ApiController.java`) strictly requires:
/// - Signature Algorithm: `RSASSA-PSS` with `SHA-256`, `MGF1-SHA-256`, and a 32-byte salt.
/// - Key Type: RSA 2048-bit (minimum).
/// - Public Key Format: Base64-encoded X.509 `SubjectPublicKeyInfo`.
///
/// **Apple Platform Capability & Secure Enclave Constraints:**
/// 1. Apple's Secure Enclave hardware processor physically only supports NIST P-256 (and Curve25519 on newer chips)
///    elliptic curves. It possesses NO RSA cryptographic engine.
/// 2. Apple's `CryptoKit` framework does not support RSA key generation or RSA-PSS digital signatures.
/// 3. In contrast, iOS `Security.framework` (Keychain Services) natively supports hardware-protected RSA-2048
///    key generation and standard `SecKeyAlgorithm.rsaSignatureMessagePSSSHA256` signatures.
///
/// To ensure mathematical interoperability with the existing Spring Boot backend without modifying the backend's
/// cryptographic protocol, `DeviceIdentityManager` uses Keychain Services with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// for RSA-2048 signing keys. Private keys are never exported as raw bytes, logged, or saved to UserDefaults.
public final class DeviceIdentityManager: @unchecked Sendable {
    
    /// Default shared singleton instance for app-wide use.
    public static let shared = DeviceIdentityManager()
    
    // Keychain tag and service identifiers
    private let keyTag: String
    private let serviceName: String
    private let deviceIdAccount: String
    
    // Thread safety synchronization lock
    private let lock = NSLock()
    
    // Cached private key reference
    private var cachedPrivateKey: SecKey?
    
    /// Initializes a `DeviceIdentityManager` instance.
    /// Allows custom identifiers for test isolation.
    public init(
        keyTag: String = "com.upimesh.identity.signingkey",
        serviceName: String = "com.upimesh.identity",
        deviceIdAccount: String = "deviceId"
    ) {
        self.keyTag = keyTag
        self.serviceName = serviceName
        self.deviceIdAccount = deviceIdAccount
    }
    
    // MARK: - Identity Management
    
    /// Retrieves the existing device identity from the Keychain, or securely generates a new one.
    @discardableResult
    public func getOrCreateIdentity() throws -> DeviceIdentity {
        lock.lock()
        defer { lock.unlock() }
        
        if let existing = try loadIdentityInternal() {
            return existing
        }
        
        return try generateNewIdentityInternal()
    }
    
    /// Loads the device identity if one already exists in Keychain without creating a new one.
    public func loadIdentity() throws -> DeviceIdentity? {
        lock.lock()
        defer { lock.unlock() }
        return try loadIdentityInternal()
    }
    
    /// Forcefully regenerates the device signing key and identity, replacing any existing key in the Keychain.
    /// By default, preserves the stable `deviceId` unless `keepDeviceId` is explicitly false.
    @discardableResult
    public func regenerateIdentity(keepDeviceId: Bool = true) throws -> DeviceIdentity {
        lock.lock()
        defer { lock.unlock() }
        
        try deleteIdentityInternal(deleteDeviceId: !keepDeviceId)
        return try generateNewIdentityInternal()
    }
    
    /// Securely deletes the device signing key and device ID from Keychain.
    public func deleteIdentity() throws {
        lock.lock()
        defer { lock.unlock() }
        try deleteIdentityInternal(deleteDeviceId: true)
    }
    
    // MARK: - Digital Signing & Verification
    
    /// Digitally signs canonical data bytes using RSASSA-PSS SHA-256 with MGF1 and 32-byte salt.
    /// - Parameter message: The canonical byte payload to sign (e.g. from `PaymentInstruction.toCanonicalBytes()`).
    /// - Returns: Raw 256-byte signature data.
    public func sign(message: Data) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        
        let privateKey = try getOrLoadPrivateKeyInternal()
        
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, .rsaSignatureMessagePSSSHA256) else {
            throw DeviceIdentityError.signingFailed("Algorithm rsaSignatureMessagePSSSHA256 is not supported by this key.")
        }
        
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePSSSHA256,
            message as CFData,
            &error
        ) as Data? else {
            let errDesc = error?.takeRetainedValue().localizedDescription ?? "Unknown signing error"
            throw DeviceIdentityError.signingFailed(errDesc)
        }
        
        return signature
    }
    
    /// Digitally signs canonical data bytes and returns the signature formatted as a Base64 string.
    public func signBase64(message: Data) throws -> String {
        let signatureData = try sign(message: message)
        return signatureData.base64EncodedString()
    }
    
    /// Verifies an RSASSA-PSS SHA-256 digital signature against the device's public key.
    /// - Parameters:
    ///   - signature: The signature bytes to verify.
    ///   - message: The expected message payload bytes.
    /// - Returns: `true` if mathematically valid, `false` otherwise.
    public func verify(signature: Data, for message: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            let privateKey = try getOrLoadPrivateKeyInternal()
            guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
                return false
            }
            
            guard SecKeyIsAlgorithmSupported(publicKey, .verify, .rsaSignatureMessagePSSSHA256) else {
                return false
            }
            
            var error: Unmanaged<CFError>?
            let isValid = SecKeyVerifySignature(
                publicKey,
                .rsaSignatureMessagePSSSHA256,
                message as CFData,
                signature as CFData,
                &error
            )
            return isValid
        } catch {
            return false
        }
    }
    
    /// Verifies a Base64-encoded RSASSA-PSS SHA-256 signature.
    public func verifyBase64(signatureBase64: String, for message: Data) -> Bool {
        guard let sigData = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return verify(signature: sigData, for: message)
    }
    
    // MARK: - Public Key Export
    
    /// Exports the device public key formatted as Base64-encoded X.509 SubjectPublicKeyInfo.
    public func exportPublicKeyBase64X509() throws -> String {
        let identity = try getOrCreateIdentity()
        return identity.publicKeyBase64X509
    }
    
    /// Exports the device public key formatted as raw X.509 SubjectPublicKeyInfo DER Data.
    public func exportPublicKeyX509() throws -> Data {
        let identity = try getOrCreateIdentity()
        guard let data = Data(base64Encoded: identity.publicKeyBase64X509) else {
            throw DeviceIdentityError.exportFailed("Malformed Base64 in exported public key.")
        }
        return data
    }
    
    // MARK: - Hardware Profile & Security Evaluation
    
    /// Returns the active security profile and hardware capabilities.
    public func hardwareProfile() -> SecurityHardwareProfile {
        let seAvailable = SecureEnclave.isAvailable
        let note = "Spring Boot backend requires RSASSA-PSS (SHA-256, 32-byte salt) and RSA-2048 keys. " +
                   "Apple Secure Enclave only supports NIST P-256 elliptic curves and has no RSA hardware engine. " +
                   "Keys are securely stored in the iOS Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly."
        
        return SecurityHardwareProfile(
            isSecureEnclaveAvailable: seAvailable,
            activeAlgorithm: "RSASSA-PSS-SHA256",
            activeKeyStorage: "iOS Keychain (SecKey RSA-2048, Device-Locked)",
            protocolCompatibilityNote: note
        )
    }
    
    // MARK: - Internal Implementation
    
    private func getOrLoadPrivateKeyInternal() throws -> SecKey {
        if let cached = cachedPrivateKey {
            return cached
        }
        
        let tagData = keyTag.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess, let keyRef = item else {
            if status == errSecItemNotFound {
                throw DeviceIdentityError.keyNotFound
            }
            throw DeviceIdentityError.keychainError(status, "SecItemCopyMatching failed to locate private key.")
        }
        
        // CFTypeRef to SecKey cast
        let privateKey = keyRef as! SecKey
        cachedPrivateKey = privateKey
        return privateKey
    }
    
    private func loadIdentityInternal() throws -> DeviceIdentity? {
        // 1. Check if private key exists in Keychain
        let tagData = keyTag.data(using: .utf8)!
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: true
        ]
        
        var keyItem: CFTypeRef?
        let keyStatus = SecItemCopyMatching(keyQuery as CFDictionary, &keyItem)
        if keyStatus == errSecItemNotFound {
            return nil
        }
        guard keyStatus == errSecSuccess, let keyRef = keyItem else {
            throw DeviceIdentityError.keychainError(keyStatus, "Failed to inspect existing key.")
        }
        
        let privateKey = keyRef as! SecKey
        cachedPrivateKey = privateKey
        
        // 2. Load deviceId
        guard let deviceId = try loadDeviceIdInternal() else {
            // If key exists but deviceId was lost, regenerate deviceId
            let freshId = UUID().uuidString
            try saveDeviceIdInternal(freshId)
            return try assembleIdentity(privateKey: privateKey, deviceId: freshId)
        }
        
        return try assembleIdentity(privateKey: privateKey, deviceId: deviceId)
    }
    
    private func generateNewIdentityInternal() throws -> DeviceIdentity {
        let tagData = keyTag.data(using: .utf8)!
        
        // Delete any stale key with this tag before generating
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        cachedPrivateKey = nil
        
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecAttrApplicationTag as String: tagData,
            kSecAttrIsPermanent as String: true,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tagData,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, &error) else {
            let desc = error?.takeRetainedValue().localizedDescription ?? "SecKeyCreateRandomKey failed"
            throw DeviceIdentityError.keyGenerationFailed(desc)
        }
        
        cachedPrivateKey = privateKey
        
        // Obtain or generate stable deviceId
        var deviceId = try loadDeviceIdInternal()
        if deviceId == nil {
            let freshId = UUID().uuidString
            try saveDeviceIdInternal(freshId)
            deviceId = freshId
        }
        
        return try assembleIdentity(privateKey: privateKey, deviceId: deviceId!)
    }
    
    private func assembleIdentity(privateKey: SecKey, deviceId: String) throws -> DeviceIdentity {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw DeviceIdentityError.exportFailed("Unable to derive public key from private key.")
        }
        
        var error: Unmanaged<CFError>?
        guard let pkcs1Data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            let desc = error?.takeRetainedValue().localizedDescription ?? "SecKeyCopyExternalRepresentation failed"
            throw DeviceIdentityError.exportFailed(desc)
        }
        
        // Wrap PKCS#1 into X.509 SubjectPublicKeyInfo DER
        let x509Data = Self.exportX509SubjectPublicKeyInfo(from: pkcs1Data)
        let base64X509 = x509Data.base64EncodedString()
        let fingerprint = Self.computeFingerprint(for: x509Data)
        
        return DeviceIdentity(
            deviceId: deviceId,
            algorithm: "RSASSA-PSS-SHA256",
            keyType: "RSA-2048",
            publicKeyBase64X509: base64X509,
            publicKeyFingerprint: fingerprint,
            createdAt: Date(),
            isSecureEnclaveBacked: false
        )
    }
    
    private func deleteIdentityInternal(deleteDeviceId: Bool = true) throws {
        cachedPrivateKey = nil
        
        // Delete both private and public keys associated with this tag
        let tagData = keyTag.data(using: .utf8)!
        SecItemDelete([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ] as CFDictionary)
        SecItemDelete([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic
        ] as CFDictionary)
        SecItemDelete([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData
        ] as CFDictionary)
        
        if deleteDeviceId {
            // Delete deviceId
            let idQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: deviceIdAccount
            ]
            SecItemDelete(idQuery as CFDictionary)
        }
    }
    
    private func loadDeviceIdInternal() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: deviceIdAccount,
            kSecReturnData as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw DeviceIdentityError.keychainError(status, "Failed to read deviceId from Keychain.")
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    private func saveDeviceIdInternal(_ deviceId: String) throws {
        let data = deviceId.data(using: .utf8)!
        
        // Delete existing item if any
        let delQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: deviceIdAccount
        ]
        SecItemDelete(delQuery as CFDictionary)
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: deviceIdAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DeviceIdentityError.keychainError(status, "Failed to save deviceId to Keychain.")
        }
    }
    
    // MARK: - ASN.1 DER Encoding Helpers
    
    /// Wraps a PKCS#1 RSA public key DER (`SEQUENCE { INTEGER modulus, INTEGER exponent }`)
    /// into standard X.509 `SubjectPublicKeyInfo` format:
    ///
    /// ```asn1
    /// SubjectPublicKeyInfo ::= SEQUENCE {
    ///     algorithm         AlgorithmIdentifier, -- rsaEncryption (1.2.840.113549.1.1.1)
    ///     subjectPublicKey  BIT STRING          -- wraps PKCS#1 RSAPublicKey DER
    /// }
    /// ```
    public static func exportX509SubjectPublicKeyInfo(from pkcs1: Data) -> Data {
        // AlgorithmIdentifier: rsaEncryption (1.2.840.113549.1.1.1) with NULL parameters (15 bytes)
        let algorithmIdentifier: [UInt8] = [
            0x30, 0x0D,
            0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,
            0x05, 0x00
        ]
        
        // BIT STRING header: 0x03 + length + 0x00 (0 unused bits)
        let bitStringContentLength = pkcs1.count + 1
        var bitString = Data([0x03])
        bitString.append(encodeDERLength(bitStringContentLength))
        bitString.append(0x00) // 0 unused bits
        bitString.append(pkcs1)
        
        // Inner SEQUENCE content = AlgorithmIdentifier + BIT STRING
        var sequenceContent = Data(algorithmIdentifier)
        sequenceContent.append(bitString)
        
        // Outer SEQUENCE header
        var outerSequence = Data([0x30])
        outerSequence.append(encodeDERLength(sequenceContent.count))
        outerSequence.append(sequenceContent)
        
        return outerSequence
    }
    
    /// Encodes length according to ASN.1 DER rules.
    public static func encodeDERLength(_ length: Int) -> Data {
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
    
    /// Computes the SHA-256 fingerprint of the X.509 public key in colon-separated hex format.
    public static func computeFingerprint(for x509Data: Data) -> String {
        let digest = SHA256.hash(data: x509Data)
        return digest.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    /// Verifies an RSASSA-PSS SHA-256 digital signature against an external X.509 SubjectPublicKeyInfo public key.
    ///
    /// NOTE: Mathematical validity verifies only that the canonical bytes were signed by the holder of the
    /// private key corresponding to `publicKeyBase64X509`. It does NOT authenticate that the public key is
    /// authorized to debit the claimed account on the bank ledger. Identity and balance authorization
    /// remain strictly enforced by the backend bridge upon settlement.
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
            let desc = error?.takeRetainedValue().localizedDescription ?? "Unknown key import error"
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
            let desc = verifyError?.takeRetainedValue().localizedDescription ?? "Mathematical verification failed"
            return (false, desc)
        }
    }
}
