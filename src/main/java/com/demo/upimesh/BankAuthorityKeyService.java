package com.demo.upimesh;

import com.demo.upimesh.model.BankAuthorityCredential;
import com.demo.upimesh.model.BankAuthorityCredentialRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Service;

import javax.crypto.Cipher;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.time.Instant;
import java.util.Base64;
import java.util.Optional;

/**
 * Service managing the authoritative central bank's dedicated cryptographic keypair
 * used to sign offline allowance vouchers.
 * <p>
 * Persistence, Security & Restart Invariants:
 * 1. The bank's keypair is persisted to the database via BankAuthorityCredentialRepository,
 *    allowing it to survive application restarts so that previously issued vouchers remain valid.
 * 2. Authenticated Encryption at Rest (AES-256-GCM):
 *    When configured with an external secret (UPI_MESH_KEY_ENCRYPTION_KEY or upimesh.bank-authority.encryption-key),
 *    the bank's private key is stored encrypted with AES-256-GCM using a 12-byte IV and 128-bit authentication tag.
 * 3. The encryption key is NEVER stored in the database alongside the private key.
 * 4. Fail-Closed Decryption:
 *    If decryption fails or the encryption key is missing, the service FAILS CLOSED and does NOT
 *    automatically regenerate a key, preventing silent voucher invalidation.
 * 5. Production Profile Enforcement:
 *    In production profile, authenticated encryption at rest is mandatory; unencrypted keys fail startup.
 * 6. All voucher signatures use RSASSA-PSS with SHA-256 and standard MGF1 parameters.
 */
@Service
public class BankAuthorityKeyService {

    private static final Logger log = LoggerFactory.getLogger(BankAuthorityKeyService.class);
    public static final String DEFAULT_MASTER_KEY_ID = "bank-authority-master";
    public static final String ENCRYPTED_PREFIX = "ENC:AES-GCM:";
    private static final int GCM_IV_LENGTH_BYTES = 12;
    private static final int GCM_TAG_LENGTH_BITS = 128;

    private final CryptoService cryptoService;
    private final BankAuthorityCredentialRepository credentialRepository;
    private final Environment environment;
    private final SecureRandom secureRandom = new SecureRandom();

    @Value("${upimesh.bank-authority.encryption-key:${UPI_MESH_KEY_ENCRYPTION_KEY:${UPIMESH_KEY_ENCRYPTION_KEY:}}}")
    private String configuredEncryptionKey;

    @Value("${upimesh.bank-authority.auto-migrate-encryption:false}")
    private boolean autoMigrateEncryption = false;

    private final KeyPair bankAuthorityKeyPair;

    @Autowired
    public BankAuthorityKeyService(
            CryptoService cryptoService,
            @Autowired(required = false) BankAuthorityCredentialRepository credentialRepository,
            @Autowired(required = false) Environment environment
    ) {
        this.cryptoService = cryptoService;
        this.credentialRepository = credentialRepository;
        this.environment = environment;
        this.bankAuthorityKeyPair = initializeOrLoadKeyPair();
    }

    public BankAuthorityKeyService(
            CryptoService cryptoService,
            BankAuthorityCredentialRepository credentialRepository
    ) {
        this(cryptoService, credentialRepository, (Environment) null);
    }

    public BankAuthorityKeyService(
            CryptoService cryptoService,
            BankAuthorityCredentialRepository credentialRepository,
            String explicitEncryptionKey
    ) {
        this.cryptoService = cryptoService;
        this.credentialRepository = credentialRepository;
        this.environment = null;
        this.configuredEncryptionKey = explicitEncryptionKey;
        this.bankAuthorityKeyPair = initializeOrLoadKeyPair();
    }

    public BankAuthorityKeyService(CryptoService cryptoService, KeyPair keyPair) {
        this.cryptoService = cryptoService;
        this.credentialRepository = null;
        this.environment = null;
        if (keyPair == null) {
            throw new IllegalArgumentException("Bank KeyPair must not be null");
        }
        this.bankAuthorityKeyPair = keyPair;
    }

    public void setConfiguredEncryptionKey(String configuredEncryptionKey) {
        this.configuredEncryptionKey = configuredEncryptionKey;
    }

    public void setAutoMigrateEncryption(boolean autoMigrateEncryption) {
        this.autoMigrateEncryption = autoMigrateEncryption;
    }

    public boolean isProductionEnvironment() {
        return FinancialSecurityService.isProduction(this.environment);
    }

    public boolean isAutoMigrateEnabled() {
        if (autoMigrateEncryption) {
            return true;
        }
        if (environment != null) {
            String prop = environment.getProperty("upimesh.bank-authority.auto-migrate-encryption");
            if (prop != null) {
                return Boolean.parseBoolean(prop.trim());
            }
        }
        return false;
    }

    public static boolean isEncryptedFormat(String storedValue) {
        return storedValue != null && storedValue.startsWith(ENCRYPTED_PREFIX);
    }

    public static SecretKey deriveAesKey(String secret) {
        if (secret == null || secret.isBlank()) {
            throw new IllegalArgumentException("Encryption secret must not be blank");
        }
        String clean = secret.trim();
        // 1. If 64 hex characters (32 bytes)
        if (clean.length() == 64 && clean.matches("^[0-9a-fA-F]+$")) {
            byte[] keyBytes = new byte[32];
            for (int i = 0; i < 32; i++) {
                keyBytes[i] = (byte) Integer.parseInt(clean.substring(i * 2, i * 2 + 2), 16);
            }
            return new SecretKeySpec(keyBytes, "AES");
        }
        // 2. If 44 Base64 characters (32 bytes)
        if (clean.length() == 44) {
            try {
                byte[] decoded = Base64.getDecoder().decode(clean);
                if (decoded.length == 32) {
                    return new SecretKeySpec(decoded, "AES");
                }
            } catch (IllegalArgumentException ignored) {}
        }
        // 3. Otherwise derive 256-bit key via SHA-256 with domain separation
        try {
            MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
            sha256.update("upimesh-bank-authority-keystore-v1:".getBytes(StandardCharsets.UTF_8));
            byte[] derived = sha256.digest(clean.getBytes(StandardCharsets.UTF_8));
            return new SecretKeySpec(derived, "AES");
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 algorithm unavailable", e);
        }
    }

    public static String encryptPrivateKey(byte[] pkcs8DerBytes, SecretKey aesKey, SecureRandom random) throws GeneralSecurityException {
        if (pkcs8DerBytes == null || aesKey == null) {
            throw new IllegalArgumentException("Private key bytes and AES key must not be null");
        }
        byte[] iv = new byte[GCM_IV_LENGTH_BYTES];
        random.nextBytes(iv);

        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, aesKey, new GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv));
        byte[] ciphertextWithTag = cipher.doFinal(pkcs8DerBytes);

        ByteBuffer buffer = ByteBuffer.allocate(iv.length + ciphertextWithTag.length);
        buffer.put(iv);
        buffer.put(ciphertextWithTag);

        return ENCRYPTED_PREFIX + Base64.getEncoder().encodeToString(buffer.array());
    }

    public static byte[] decryptPrivateKey(String encryptedPayload, SecretKey aesKey) throws GeneralSecurityException {
        if (encryptedPayload == null || !encryptedPayload.startsWith(ENCRYPTED_PREFIX)) {
            throw new IllegalArgumentException("Invalid encrypted payload format; missing " + ENCRYPTED_PREFIX);
        }
        if (aesKey == null) {
            throw new IllegalArgumentException("AES key must not be null for decryption");
        }
        String b64 = encryptedPayload.substring(ENCRYPTED_PREFIX.length()).trim();
        byte[] combined = Base64.getDecoder().decode(b64);
        if (combined.length < GCM_IV_LENGTH_BYTES + (GCM_TAG_LENGTH_BITS / 8)) {
            throw new IllegalArgumentException("Encrypted payload too short to contain IV and authentication tag");
        }
        byte[] iv = new byte[GCM_IV_LENGTH_BYTES];
        System.arraycopy(combined, 0, iv, 0, GCM_IV_LENGTH_BYTES);

        byte[] cipherTextWithTag = new byte[combined.length - GCM_IV_LENGTH_BYTES];
        System.arraycopy(combined, GCM_IV_LENGTH_BYTES, cipherTextWithTag, 0, cipherTextWithTag.length);

        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, aesKey, new GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv));
        return cipher.doFinal(cipherTextWithTag);
    }

    private SecretKey resolveEncryptionKey() {
        String keyStr = null;
        if (configuredEncryptionKey != null && !configuredEncryptionKey.isBlank()) {
            keyStr = configuredEncryptionKey.trim();
        } else {
            String env1 = System.getenv("UPI_MESH_KEY_ENCRYPTION_KEY");
            if (env1 != null && !env1.isBlank()) {
                keyStr = env1.trim();
            } else {
                String env2 = System.getenv("UPIMESH_KEY_ENCRYPTION_KEY");
                if (env2 != null && !env2.isBlank()) {
                    keyStr = env2.trim();
                } else if (environment != null) {
                    String prop = environment.getProperty("upimesh.bank-authority.encryption-key");
                    if (prop != null && !prop.isBlank()) {
                        keyStr = prop.trim();
                    }
                }
            }
        }
        if (keyStr == null || keyStr.isBlank()) {
            return null;
        }
        return deriveAesKey(keyStr);
    }

    private KeyPair initializeOrLoadKeyPair() {
        SecretKey encryptionKey = resolveEncryptionKey();
        boolean isProd = isProductionEnvironment();

        if (isProd && encryptionKey == null) {
            throw new IllegalStateException(
                    "Production startup failed: Bank authority key encryption key (UPI_MESH_KEY_ENCRYPTION_KEY or upimesh.bank-authority.encryption-key) is strictly required."
            );
        }

        if (credentialRepository != null) {
            Optional<BankAuthorityCredential> existing = credentialRepository.findById(DEFAULT_MASTER_KEY_ID);
            if (existing.isPresent()) {
                BankAuthorityCredential cred = existing.get();
                try {
                    KeyFactory keyFactory = KeyFactory.getInstance(cred.getAlgorithm());

                    byte[] pubBytes = Base64.getDecoder().decode(cred.getPublicKeyBase64());
                    PublicKey pubKey = keyFactory.generatePublic(new X509EncodedKeySpec(pubBytes));

                    String privStr = cred.getPrivateKeyBase64();
                    byte[] privBytes;
                    boolean isEncrypted = isEncryptedFormat(privStr);

                    if (isEncrypted) {
                        if (encryptionKey == null) {
                            throw new IllegalStateException(
                                    "Bank authority private key in repository is encrypted, but encryption key (UPI_MESH_KEY_ENCRYPTION_KEY or upimesh.bank-authority.encryption-key) is not configured. Decryption aborted fail-closed without key regeneration."
                            );
                        }
                        try {
                            privBytes = decryptPrivateKey(privStr, encryptionKey);
                        } catch (GeneralSecurityException e) {
                            throw new IllegalStateException(
                                    "Failed to decrypt bank authority private key: AEAD authentication failed (wrong key or corrupted ciphertext). Key regeneration is disabled to prevent voucher invalidation. Startup aborted.", e
                            );
                        }
                    } else {
                        // Unencrypted legacy format
                        if (isProd) {
                            throw new IllegalStateException(
                                    "Production startup failed: Bank authority private key in repository is stored in unencrypted legacy format. Migration to encrypted storage is required."
                            );
                        }
                        log.warn("Bank authority private key loaded from UNENCRYPTED legacy storage ({}). Configure UPI_MESH_KEY_ENCRYPTION_KEY to enable encryption at rest.", DEFAULT_MASTER_KEY_ID);
                        privBytes = Base64.getDecoder().decode(privStr);

                        // If auto-migration is explicitly enabled AND encryptionKey is present:
                        if (encryptionKey != null && isAutoMigrateEnabled()) {
                            log.info("Auto-migrating legacy bank authority private key to AES-GCM encrypted format...");
                            String encPriv = encryptPrivateKey(privBytes, encryptionKey, secureRandom);
                            // Verify decryption roundtrip before writing!
                            byte[] testDec = decryptPrivateKey(encPriv, encryptionKey);
                            if (!MessageDigest.isEqual(privBytes, testDec)) {
                                throw new IllegalStateException("Sanity check failed during key migration: decrypted bytes do not match original!");
                            }
                            BankAuthorityCredential updated = new BankAuthorityCredential(
                                    cred.getId(),
                                    cred.getPublicKeyBase64(),
                                    encPriv,
                                    cred.getAlgorithm(),
                                    cred.getKeySize(),
                                    cred.getCreatedAt()
                            );
                            credentialRepository.save(updated);
                            log.info("Successfully migrated bank authority private key to AES-GCM encrypted format at rest.");
                        }
                    }

                    PrivateKey privKey = keyFactory.generatePrivate(new PKCS8EncodedKeySpec(privBytes));

                    log.info("Loaded existing BankAuthorityKeyService keypair from persistent storage ({}) [encrypted={}]", DEFAULT_MASTER_KEY_ID, isEncrypted);
                    return new KeyPair(pubKey, privKey);
                } catch (IllegalStateException e) {
                    // Do NOT catch and regenerate! Re-throw fail-closed!
                    throw e;
                } catch (Exception e) {
                    // Do NOT regenerate if loading an existing key fails!
                    throw new IllegalStateException("Failed to load existing bank authority key from repository: " + e.getMessage() + ". Key regeneration aborted fail-closed.", e);
                }
            }
        }

        // Generate fresh keypair (only if no key exists in repository)
        try {
            KeyPair freshPair = cryptoService.generateRsaKeyPair();
            if (credentialRepository != null) {
                try {
                    String pubB64 = Base64.getEncoder().encodeToString(freshPair.getPublic().getEncoded());
                    byte[] privDer = freshPair.getPrivate().getEncoded();
                    String storedPriv;
                    if (encryptionKey != null) {
                        storedPriv = encryptPrivateKey(privDer, encryptionKey, secureRandom);
                        log.info("Persisted fresh BankAuthorityKeyService keypair in AES-GCM encrypted format ({})", DEFAULT_MASTER_KEY_ID);
                    } else {
                        if (isProd) {
                            throw new IllegalStateException("Production startup failed: Cannot persist bank authority key in unencrypted format.");
                        }
                        storedPriv = Base64.getEncoder().encodeToString(privDer);
                        log.warn("Persisted fresh BankAuthorityKeyService keypair in UNENCRYPTED format ({})", DEFAULT_MASTER_KEY_ID);
                    }
                    BankAuthorityCredential cred = new BankAuthorityCredential(
                            DEFAULT_MASTER_KEY_ID,
                            pubB64,
                            storedPriv,
                            "RSA",
                            2048,
                            Instant.now()
                    );
                    credentialRepository.save(cred);
                } catch (Exception e) {
                    if (e instanceof IllegalStateException ise) throw ise;
                    log.warn("Could not persist bank authority keypair to repository: {}", e.getMessage());
                }
            }
            return freshPair;
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("Failed to initialize bank authority keypair", e);
        }
    }

    /**
     * Signs canonical voucher bytes using the bank's dedicated private key.
     */
    public String signVoucherBase64(byte[] canonicalVoucherBytes) {
        if (canonicalVoucherBytes == null) {
            throw new IllegalArgumentException("Canonical voucher bytes must not be null");
        }
        try {
            return cryptoService.signBase64(canonicalVoucherBytes, bankAuthorityKeyPair.getPrivate());
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("Failed to generate bank voucher signature", e);
        }
    }

    /**
     * Verifies a voucher's signature against the bank authority's trusted public key.
     */
    public boolean verifyVoucherSignature(byte[] canonicalVoucherBytes, String signatureBase64) {
        if (canonicalVoucherBytes == null || signatureBase64 == null || signatureBase64.isBlank()) {
            return false;
        }
        try {
            return cryptoService.verifySignatureBase64(canonicalVoucherBytes, signatureBase64, bankAuthorityKeyPair.getPublic());
        } catch (GeneralSecurityException e) {
            log.warn("Cryptographic error during voucher signature verification: {}", e.getMessage());
            return false;
        }
    }

    /**
     * Returns the bank authority's public verification key.
     */
    public PublicKey getBankPublicKey() {
        return bankAuthorityKeyPair.getPublic();
    }

    /**
     * Returns the Base64 X.509 DER encoded public key for distribution to clients and verification.
     */
    public String getBankPublicKeyBase64() {
        return Base64.getEncoder().encodeToString(bankAuthorityKeyPair.getPublic().getEncoded());
    }
}
