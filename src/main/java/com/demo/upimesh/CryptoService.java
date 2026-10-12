package com.demo.upimesh;

import org.springframework.stereotype.Service;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.OAEPParameterSpec;
import javax.crypto.spec.PSource;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.security.Signature;
import java.security.spec.MGF1ParameterSpec;
import java.security.spec.PSSParameterSpec;
import java.util.Base64;

@Service
public class CryptoService {

    private static final String RSA_TRANSFORMATION = "RSA/ECB/OAEPWithSHA-256AndMGF1Padding";
    private static final String AES_TRANSFORMATION = "AES/GCM/NoPadding";
    public static final String SIGNATURE_ALGORITHM = "RSASSA-PSS";

    private static final int RSA_KEY_SIZE = 2048;
    private static final int AES_KEY_SIZE = 256; // 32 bytes
    private static final int GCM_IV_LENGTH_BYTES = 12; // 96 bits
    private static final int GCM_TAG_LENGTH_BITS = 128; // 16 bytes authentication tag

    /**
     * Standard RSASSA-PSS parameter specification using SHA-256 and MGF1 with SHA-256 and 32-byte salt.
     */
    private static final PSSParameterSpec PSS_PARAM_SPEC = new PSSParameterSpec(
            "SHA-256",
            "MGF1",
            MGF1ParameterSpec.SHA256,
            32,
            1
    );

    private final SecureRandom secureRandom = new SecureRandom();

    /**
     * Generates a new RSA-2048 key pair.
     */
    public KeyPair generateRsaKeyPair() throws GeneralSecurityException {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(RSA_KEY_SIZE, secureRandom);
        return generator.generateKeyPair();
    }

    /**
     * Encrypts UTF-8 plaintext using hybrid encryption:
     * 1. Generates a fresh random 32-byte AES key (AES-256).
     * 2. Generates a fresh 12-byte cryptographically secure IV.
     * 3. Encrypts plaintext with AES-256-GCM (including 128-bit authentication tag).
     * 4. Encrypts the AES key with RSA-OAEP using SHA-256 and MGF1-SHA-256.
     */
    public EncryptedPacket encrypt(String plaintext, PublicKey rsaPublicKey) throws GeneralSecurityException {
        if (plaintext == null) {
            throw new IllegalArgumentException("Plaintext must not be null");
        }
        if (rsaPublicKey == null) {
            throw new IllegalArgumentException("RSA public key must not be null");
        }

        // 1. Generate 32-byte (256-bit) AES key
        KeyGenerator keyGen = KeyGenerator.getInstance("AES");
        keyGen.init(AES_KEY_SIZE, secureRandom);
        SecretKey aesKey = keyGen.generateKey();

        // 2. Generate 12-byte IV for AES-GCM
        byte[] iv = new byte[GCM_IV_LENGTH_BYTES];
        secureRandom.nextBytes(iv);

        // 3. Encrypt plaintext using AES-256-GCM
        Cipher aesCipher = Cipher.getInstance(AES_TRANSFORMATION);
        GCMParameterSpec gcmSpec = new GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv);
        aesCipher.init(Cipher.ENCRYPT_MODE, aesKey, gcmSpec);
        byte[] ciphertext = aesCipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));

        // 4. Encrypt AES key using RSA-OAEP with SHA-256
        Cipher rsaCipher = Cipher.getInstance(RSA_TRANSFORMATION);
        OAEPParameterSpec oaepSpec = new OAEPParameterSpec(
                "SHA-256",
                "MGF1",
                MGF1ParameterSpec.SHA256,
                PSource.PSpecified.DEFAULT
        );
        rsaCipher.init(Cipher.ENCRYPT_MODE, rsaPublicKey, oaepSpec);
        byte[] encryptedAesKey = rsaCipher.doFinal(aesKey.getEncoded());

        return new EncryptedPacket(encryptedAesKey, iv, ciphertext);
    }

    /**
     * Decrypts an encrypted packet:
     * 1. Decrypts AES key using RSA-OAEP (SHA-256) and the RSA private key.
     * 2. Authenticates and decrypts the ciphertext using AES-256-GCM.
     */
    public String decrypt(EncryptedPacket packet, PrivateKey rsaPrivateKey) throws GeneralSecurityException {
        if (packet == null) {
            throw new IllegalArgumentException("Encrypted packet must not be null");
        }
        if (rsaPrivateKey == null) {
            throw new IllegalArgumentException("RSA private key must not be null");
        }

        // 1. Decrypt AES key with RSA private key
        Cipher rsaCipher = Cipher.getInstance(RSA_TRANSFORMATION);
        OAEPParameterSpec oaepSpec = new OAEPParameterSpec(
                "SHA-256",
                "MGF1",
                MGF1ParameterSpec.SHA256,
                PSource.PSpecified.DEFAULT
        );
        rsaCipher.init(Cipher.DECRYPT_MODE, rsaPrivateKey, oaepSpec);
        byte[] decryptedAesKeyBytes = rsaCipher.doFinal(packet.encryptedAesKey());
        SecretKey aesKey = new SecretKeySpec(decryptedAesKeyBytes, "AES");

        // 2. Authenticate and decrypt AES-GCM ciphertext
        Cipher aesCipher = Cipher.getInstance(AES_TRANSFORMATION);
        GCMParameterSpec gcmSpec = new GCMParameterSpec(GCM_TAG_LENGTH_BITS, packet.iv());
        aesCipher.init(Cipher.DECRYPT_MODE, aesKey, gcmSpec);
        byte[] plaintextBytes = aesCipher.doFinal(packet.ciphertext());

        return new String(plaintextBytes, StandardCharsets.UTF_8);
    }

    /**
     * Cryptographically signs data using RSA-PSS with SHA-256.
     *
     * @param data       the canonical payload bytes to sign
     * @param privateKey the sender's private RSA signing key
     * @return the raw signature bytes
     * @throws GeneralSecurityException if cryptographic signing fails
     */
    public byte[] sign(byte[] data, PrivateKey privateKey) throws GeneralSecurityException {
        if (data == null) {
            throw new IllegalArgumentException("Data to sign must not be null");
        }
        if (privateKey == null) {
            throw new IllegalArgumentException("Private key must not be null");
        }
        Signature signature = Signature.getInstance(SIGNATURE_ALGORITHM);
        signature.setParameter(PSS_PARAM_SPEC);
        signature.initSign(privateKey);
        signature.update(data);
        return signature.sign();
    }

    /**
     * Convenience method returning the Base64-encoded RSA-PSS signature.
     */
    public String signBase64(byte[] data, PrivateKey privateKey) throws GeneralSecurityException {
        return Base64.getEncoder().encodeToString(sign(data, privateKey));
    }

    /**
     * Verifies an RSA-PSS signature against data and the sender's trusted public key.
     *
     * @param data           the expected canonical payload bytes
     * @param signatureBytes the signature bytes to verify
     * @param publicKey      the sender's trusted public verification key
     * @return true if the signature is valid, false otherwise
     * @throws GeneralSecurityException if verification parameters or algorithms are invalid
     */
    public boolean verifySignature(byte[] data, byte[] signatureBytes, PublicKey publicKey) throws GeneralSecurityException {
        if (data == null || signatureBytes == null || publicKey == null) {
            return false;
        }
        Signature verifier = Signature.getInstance(SIGNATURE_ALGORITHM);
        verifier.setParameter(PSS_PARAM_SPEC);
        verifier.initVerify(publicKey);
        verifier.update(data);
        return verifier.verify(signatureBytes);
    }

    /**
     * Verifies a Base64-encoded RSA-PSS signature.
     * Returns false if the signature is null, blank, malformed Base64, or mathematically invalid.
     */
    public boolean verifySignatureBase64(byte[] data, String signatureBase64, PublicKey publicKey) throws GeneralSecurityException {
        if (data == null || signatureBase64 == null || signatureBase64.isBlank() || publicKey == null) {
            return false;
        }
        try {
            byte[] signatureBytes = Base64.getDecoder().decode(signatureBase64);
            return verifySignature(data, signatureBytes, publicKey);
        } catch (IllegalArgumentException e) {
            return false;
        }
    }
}
