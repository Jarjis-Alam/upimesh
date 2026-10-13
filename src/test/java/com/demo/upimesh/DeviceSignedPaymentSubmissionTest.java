package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.DeviceAuthorizationRequest;
import com.demo.upimesh.model.KeyRegistrationRequest;
import com.demo.upimesh.model.MeshPaymentResult;
import com.demo.upimesh.model.PaymentInstruction;
import com.demo.upimesh.model.SignedPaymentRequest;
import com.demo.upimesh.model.TransactionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.annotation.DirtiesContext;

import java.math.BigDecimal;
import java.security.KeyPair;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
@DirtiesContext(classMode = DirtiesContext.ClassMode.BEFORE_EACH_TEST_METHOD)
class DeviceSignedPaymentSubmissionTest {

    @Autowired
    private ApiController apiController;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private TransactionRepository transactionRepository;

    @Autowired
    private CryptoService cryptoService;

    @Autowired
    private SenderKeyRegistry senderKeyRegistry;

    @Autowired
    private DeviceAuthorizationRegistry deviceAuthorizationRegistry;

    private KeyPair aliceDeviceKeyPair;
    private final String aliceDeviceId = "alice-iphone-14-pro";

    private KeyPair attackerDeviceKeyPair;
    private final String attackerDeviceId = "rogue-device-uuid-999";

    @BeforeEach
    void setUp() throws Exception {
        accountRepository.deleteAll();
        transactionRepository.deleteAll();
        senderKeyRegistry.clearForTesting();
        deviceAuthorizationRegistry.clearForTesting();

        // Seed initial test accounts
        accountRepository.save(new Account("alice", new BigDecimal("5000.00")));
        accountRepository.save(new Account("bob", new BigDecimal("1000.00")));
        accountRepository.save(new Account("carol", new BigDecimal("2000.00")));

        // Generate RSA-2048 keypairs for tests
        aliceDeviceKeyPair = cryptoService.generateRsaKeyPair();
        attackerDeviceKeyPair = cryptoService.generateRsaKeyPair();

        // Register Alice's device public key
        String alicePubKeyBase64 = Base64.getEncoder().encodeToString(aliceDeviceKeyPair.getPublic().getEncoded());
        apiController.registerSenderKey(new KeyRegistrationRequest(aliceDeviceId, alicePubKeyBase64), null, null);

        // Authorize Alice's device for account "alice"
        apiController.authorizeDevice(new DeviceAuthorizationRequest(aliceDeviceId, "alice"));
    }

    @Test
    @DisplayName("1. Genuine device-signed PaymentInstruction settles successfully on ledger")
    void submit_genuineSignature_settlesPaymentSuccessfully() throws Exception {
        String paymentId = "pay-" + UUID.randomUUID();
        String nonce = "nonce-" + UUID.randomUUID();
        BigDecimal amount = new BigDecimal("350.00");

        PaymentInstruction unsigned = new PaymentInstruction(
                paymentId,
                "alice",
                "bob",
                amount,
                Instant.now(),
                nonce,
                null
        );

        // Sign canonical bytes with Alice's device private key (RSASSA-PSS SHA-256)
        String signature = cryptoService.signBase64(unsigned.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());
        PaymentInstruction signedInstruction = unsigned.withSignature(signature);

        SignedPaymentRequest request = new SignedPaymentRequest(aliceDeviceId, signedInstruction);
        ResponseEntity<MeshPaymentResult> response = apiController.submitSignedMeshPayment(request);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertNotNull(response.getBody());
        MeshPaymentResult result = response.getBody();
        assertTrue(result.success());
        assertEquals("SETTLED", result.status());
        assertEquals("alice", result.fromAccount());
        assertEquals("bob", result.toAccount());
        assertEquals(amount, result.amount());
        assertEquals(paymentId, result.paymentId());

        // Verify balances in database ledger
        assertEquals(new BigDecimal("4650.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1350.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
    }

    @Test
    @DisplayName("2. Altered amount is rejected without altering database balances")
    void submit_alteredAmount_rejectedWithoutAlteringBalances() throws Exception {
        PaymentInstruction unsigned = new PaymentInstruction(
                "pay-tamper-1",
                "alice",
                "bob",
                new BigDecimal("100.00"),
                Instant.now(),
                "nonce-tamper-1",
                null
        );

        // Sign for 100.00
        String signature = cryptoService.signBase64(unsigned.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());

        // Tamper instruction amount to 1000.00 while attaching original signature
        PaymentInstruction tampered = new PaymentInstruction(
                "pay-tamper-1",
                "alice",
                "bob",
                new BigDecimal("1000.00"),
                unsigned.createdAt(),
                "nonce-tamper-1",
                signature
        );

        SignedPaymentRequest request = new SignedPaymentRequest(aliceDeviceId, tampered);
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.submitSignedMeshPayment(request)
        );
        assertTrue(ex.getMessage().contains("Invalid digital signature for device: " + aliceDeviceId));

        // Balances must remain completely unchanged
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("3. Altered recipient is rejected without altering database balances")
    void submit_alteredRecipient_rejectedWithoutAlteringBalances() throws Exception {
        PaymentInstruction unsigned = new PaymentInstruction(
                "pay-tamper-2",
                "alice",
                "bob",
                new BigDecimal("50.00"),
                Instant.now(),
                "nonce-tamper-2",
                null
        );

        // Sign for Bob
        String signature = cryptoService.signBase64(unsigned.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());

        // Tamper recipient to Carol
        PaymentInstruction tampered = new PaymentInstruction(
                "pay-tamper-2",
                "alice",
                "carol",
                new BigDecimal("50.00"),
                unsigned.createdAt(),
                "nonce-tamper-2",
                signature
        );

        SignedPaymentRequest request = new SignedPaymentRequest(aliceDeviceId, tampered);
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.submitSignedMeshPayment(request)
        );
        assertTrue(ex.getMessage().contains("Invalid digital signature for device: " + aliceDeviceId));

        // Balances unaltered
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(new BigDecimal("2000.00"), accountRepository.findById("carol").orElseThrow().getBalance());
    }

    @Test
    @DisplayName("4. Unknown device is rejected without altering database balances")
    void submit_unknownDevice_rejectedWithoutAlteringBalances() throws Exception {
        PaymentInstruction unsigned = new PaymentInstruction(
                "pay-unknown-1",
                "alice",
                "bob",
                new BigDecimal("100.00"),
                Instant.now(),
                "nonce-unknown-1",
                null
        );
        String signature = cryptoService.signBase64(unsigned.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());
        PaymentInstruction signed = unsigned.withSignature(signature);

        String unknownDeviceId = "completely-unknown-device-id";
        SignedPaymentRequest request = new SignedPaymentRequest(unknownDeviceId, signed);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.submitSignedMeshPayment(request)
        );
        assertTrue(ex.getMessage().contains("Unknown or unregistered device: " + unknownDeviceId));

        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
    }

    @Test
    @DisplayName("5. Unauthorized account/device pair is rejected even with valid signature")
    void submit_unauthorizedAccountDevicePair_rejectedWithoutAlteringBalances() throws Exception {
        // Register attacker device key in registry
        String attackerPubKeyBase64 = Base64.getEncoder().encodeToString(attackerDeviceKeyPair.getPublic().getEncoded());
        apiController.registerSenderKey(new KeyRegistrationRequest(attackerDeviceId, attackerPubKeyBase64), null, null);

        // Attacker creates instruction claiming to debit "alice"
        PaymentInstruction unsigned = new PaymentInstruction(
                "pay-unauthorized-1",
                "alice",
                "carol",
                new BigDecimal("500.00"),
                Instant.now(),
                "nonce-unauth-1",
                null
        );

        // Attacker signs with their OWN private key (mathematically valid for attackerDeviceId)
        String signature = cryptoService.signBase64(unsigned.toCanonicalBytes(), attackerDeviceKeyPair.getPrivate());
        PaymentInstruction signed = unsigned.withSignature(signature);

        SignedPaymentRequest request = new SignedPaymentRequest(attackerDeviceId, signed);
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.submitSignedMeshPayment(request)
        );
        assertTrue(ex.getMessage().contains("is not authorized to debit account 'alice'"));

        // Alice's funds remain safe
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("6. Duplicate payment ID is rejected on resubmission")
    void submit_duplicatePaymentId_rejected() throws Exception {
        PaymentInstruction unsigned = new PaymentInstruction(
                "pay-dup-1",
                "alice",
                "bob",
                new BigDecimal("100.00"),
                Instant.now(),
                "nonce-dup-1",
                null
        );
        String signature = cryptoService.signBase64(unsigned.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());
        PaymentInstruction signed = unsigned.withSignature(signature);

        SignedPaymentRequest request = new SignedPaymentRequest(aliceDeviceId, signed);

        // First submission succeeds
        ResponseEntity<MeshPaymentResult> resp1 = apiController.submitSignedMeshPayment(request);
        assertEquals(HttpStatus.OK, resp1.getStatusCode());
        assertEquals(new BigDecimal("4900.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());

        // Resubmitting same instruction must be rejected as duplicate
        DuplicatePacketException ex = assertThrows(DuplicatePacketException.class, () ->
                apiController.submitSignedMeshPayment(request)
        );
        assertTrue(ex.getMessage().contains("already settled"));

        // Balances must not be debited a second time
        assertEquals(new BigDecimal("4900.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
    }

    @Test
    @DisplayName("7. Replayed nonce for same sender is rejected")
    void submit_replayedNonce_rejected() throws Exception {
        PaymentInstruction inst1 = new PaymentInstruction(
                "pay-nonce-1",
                "alice",
                "bob",
                new BigDecimal("100.00"),
                Instant.now(),
                "shared-nonce-123",
                null
        );
        String sig1 = cryptoService.signBase64(inst1.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());
        apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, inst1.withSignature(sig1)));

        // Second instruction with different payment ID but SAME nonce
        PaymentInstruction inst2 = new PaymentInstruction(
                "pay-nonce-2",
                "alice",
                "bob",
                new BigDecimal("50.00"),
                Instant.now(),
                "shared-nonce-123",
                null
        );
        String sig2 = cryptoService.signBase64(inst2.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());

        DuplicatePacketException ex = assertThrows(DuplicatePacketException.class, () ->
                apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, inst2.withSignature(sig2)))
        );
        assertTrue(ex.getMessage().contains("nonce already used for sender alice"));

        assertEquals(new BigDecimal("4900.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
    }

    @Test
    @DisplayName("8. Expired payment instruction is rejected")
    void submit_expiredInstruction_rejected() throws Exception {
        PaymentInstruction expired = new PaymentInstruction(
                "pay-expired-1",
                "alice",
                "bob",
                new BigDecimal("50.00"),
                Instant.now().minus(25, ChronoUnit.HOURS),
                "nonce-exp-1",
                null
        );
        String sig = cryptoService.signBase64(expired.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, expired.withSignature(sig)))
        );
        assertTrue(ex.getMessage().contains("Payment instruction has expired"));

        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("9. Insufficient funds rejected without altering database balances")
    void submit_insufficientFunds_rejected() throws Exception {
        // Alice has 5000.00, attempting to transfer 9000.00
        PaymentInstruction unsigned = new PaymentInstruction(
                "pay-overdraft-1",
                "alice",
                "bob",
                new BigDecimal("9000.00"),
                Instant.now(),
                "nonce-overdraft-1",
                null
        );
        String sig = cryptoService.signBase64(unsigned.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());

        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, unsigned.withSignature(sig)))
        );
        assertTrue(ex.getMessage().contains("Insufficient funds"));

        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
    }
}
