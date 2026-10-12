package com.demo.upimesh;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class CryptoServiceTest {

    private CryptoService cryptoService;
    private KeyPair keyPair;

    @BeforeEach
    void setUp() throws GeneralSecurityException {
        cryptoService = new CryptoService();
        keyPair = cryptoService.generateRsaKeyPair();
    }

    @Test
    @DisplayName("Encryption followed by decryption returns the original plaintext")
    void encryptAndDecryptReturnsOriginalPlaintext() throws GeneralSecurityException {
        String originalMessage = "upi://pay?pa=alice@mesh&am=500.00&tx=txn_1001&note=Mesh Settlement 🚀";

        EncryptedPacket packet = cryptoService.encrypt(originalMessage, keyPair.getPublic());

        assertNotNull(packet);
        assertNotNull(packet.encryptedAesKey());
        assertNotNull(packet.iv());
        assertNotNull(packet.ciphertext());

        // RSA-2048 produces a 256-byte ciphertext
        assertEquals(256, packet.encryptedAesKey().length);
        // AES-GCM standard IV is 12 bytes
        assertEquals(12, packet.iv().length);

        String decryptedMessage = cryptoService.decrypt(packet, keyPair.getPrivate());
        assertEquals(originalMessage, decryptedMessage);
    }

    @Test
    @DisplayName("Different encryption calls use different IVs")
    void differentEncryptionCallsUseDifferentIVs() throws GeneralSecurityException {
        String message = "constant message for testing IV freshness";

        EncryptedPacket packet1 = cryptoService.encrypt(message, keyPair.getPublic());
        EncryptedPacket packet2 = cryptoService.encrypt(message, keyPair.getPublic());

        assertFalse(Arrays.equals(packet1.iv(), packet2.iv()), "Consecutive encryptions must use unique IVs");
        assertFalse(Arrays.equals(packet1.ciphertext(), packet2.ciphertext()), "Ciphertexts must differ due to unique IV and key");
    }

    @Test
    @DisplayName("Tampered ciphertext is rejected by AES-GCM authentication tag verification")
    void tamperedCiphertextIsRejected() throws GeneralSecurityException {
        String message = "transfer 100 from alice to bob";
        EncryptedPacket packet = cryptoService.encrypt(message, keyPair.getPublic());

        // Tamper with one byte of the ciphertext
        byte[] tamperedCiphertext = packet.ciphertext().clone();
        tamperedCiphertext[0] ^= 0x01;

        EncryptedPacket tamperedPacket = new EncryptedPacket(
                packet.encryptedAesKey(),
                packet.iv(),
                tamperedCiphertext
        );

        assertThrows(GeneralSecurityException.class, () ->
                cryptoService.decrypt(tamperedPacket, keyPair.getPrivate())
        );
    }

    @Test
    @DisplayName("Tampered IV is rejected by AES-GCM authentication")
    void tamperedIvIsRejected() throws GeneralSecurityException {
        String message = "transfer 100 from alice to bob";
        EncryptedPacket packet = cryptoService.encrypt(message, keyPair.getPublic());

        // Tamper with one byte of the IV
        byte[] tamperedIv = packet.iv().clone();
        tamperedIv[0] ^= 0x01;

        EncryptedPacket tamperedPacket = new EncryptedPacket(
                packet.encryptedAesKey(),
                tamperedIv,
                packet.ciphertext()
        );

        assertThrows(GeneralSecurityException.class, () ->
                cryptoService.decrypt(tamperedPacket, keyPair.getPrivate())
        );
    }

    @Test
    @DisplayName("An incorrect private key cannot decrypt the packet successfully")
    void incorrectPrivateKeyFailsDecryption() throws GeneralSecurityException {
        String message = "secret payload";
        EncryptedPacket packet = cryptoService.encrypt(message, keyPair.getPublic());

        // Generate an entirely different key pair
        KeyPair wrongKeyPair = cryptoService.generateRsaKeyPair();

        assertThrows(GeneralSecurityException.class, () ->
                cryptoService.decrypt(packet, wrongKeyPair.getPrivate())
        );
    }

    @Test
    @DisplayName("RSA-PSS signing generates valid verifiable signature")
    void rsaPssSigningAndVerificationSucceeds() throws GeneralSecurityException {
        byte[] payload = "CANONICAL_PAYMENT_INSTRUCTION_DATA".getBytes();
        byte[] signature = cryptoService.sign(payload, keyPair.getPrivate());

        assertNotNull(signature);
        assertEquals(256, signature.length, "RSA-2048 PSS signature is 256 bytes");

        boolean verified = cryptoService.verifySignature(payload, signature, keyPair.getPublic());
        assertTrue(verified, "Signature must verify against corresponding public key");
    }

    @Test
    @DisplayName("Tampered payload fails RSA-PSS signature verification")
    void tamperedPayloadFailsVerification() throws GeneralSecurityException {
        byte[] payload = "AMOUNT=100.00".getBytes();
        byte[] signature = cryptoService.sign(payload, keyPair.getPrivate());

        byte[] tamperedPayload = "AMOUNT=999.00".getBytes();
        boolean verified = cryptoService.verifySignature(tamperedPayload, signature, keyPair.getPublic());
        assertFalse(verified, "Tampered payload must fail signature verification");
    }

    @Test
    @DisplayName("Signature verification fails when checked against wrong public key")
    void wrongPublicKeyFailsVerification() throws GeneralSecurityException {
        byte[] payload = "CANONICAL_DATA".getBytes();
        byte[] signature = cryptoService.sign(payload, keyPair.getPrivate());

        KeyPair differentKeyPair = cryptoService.generateRsaKeyPair();
        boolean verified = cryptoService.verifySignature(payload, signature, differentKeyPair.getPublic());
        assertFalse(verified, "Verification against different public key must return false");
    }

    @Test
    @DisplayName("Base64 signature convenience methods handle signing and invalid Base64 safely")
    void base64ConvenienceMethodsWorkSafely() throws GeneralSecurityException {
        byte[] payload = "TEST_BASE64_DATA".getBytes();
        String sigBase64 = cryptoService.signBase64(payload, keyPair.getPrivate());
        assertNotNull(sigBase64);

        assertTrue(cryptoService.verifySignatureBase64(payload, sigBase64, keyPair.getPublic()));
        assertFalse(cryptoService.verifySignatureBase64(payload, "invalid-base-64-!!!", keyPair.getPublic()));
        assertFalse(cryptoService.verifySignatureBase64(payload, null, keyPair.getPublic()));
        assertFalse(cryptoService.verifySignatureBase64(null, sigBase64, keyPair.getPublic()));
    }
}
