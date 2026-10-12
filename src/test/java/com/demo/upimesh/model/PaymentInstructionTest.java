package com.demo.upimesh.model;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

class PaymentInstructionTest {

    @Test
    @DisplayName("Factory method create() sets valid non-null fields")
    void factoryMethodCreatesValidInstruction() {
        PaymentInstruction instruction = PaymentInstruction.create("alice", "bob", new BigDecimal("250.00"));

        assertNotNull(instruction.paymentId());
        assertNotNull(UUID.fromString(instruction.paymentId()));
        assertEquals("alice", instruction.fromAccount());
        assertEquals("bob", instruction.toAccount());
        assertEquals(new BigDecimal("250.00"), instruction.amount());
        assertNotNull(instruction.createdAt());
        assertNotNull(instruction.nonce());
        assertNotNull(UUID.fromString(instruction.nonce()));
    }

    @Test
    @DisplayName("Canonical constructor succeeds with valid fields")
    void canonicalConstructorSucceeds() {
        String paymentId = UUID.randomUUID().toString();
        Instant now = Instant.now();
        String nonce = UUID.randomUUID().toString();

        PaymentInstruction instruction = new PaymentInstruction(
                paymentId,
                "alice",
                "carol",
                new BigDecimal("100"),
                now,
                nonce
        );

        assertEquals(paymentId, instruction.paymentId());
        assertEquals("alice", instruction.fromAccount());
        assertEquals("carol", instruction.toAccount());
        assertEquals(new BigDecimal("100"), instruction.amount());
        assertEquals(now, instruction.createdAt());
        assertEquals(nonce, instruction.nonce());
    }

    @Test
    @DisplayName("Rejects null or non-positive amount")
    void rejectsInvalidAmount() {
        assertThrows(IllegalArgumentException.class, () ->
                PaymentInstruction.create("alice", "bob", null)
        );

        assertThrows(IllegalArgumentException.class, () ->
                PaymentInstruction.create("alice", "bob", BigDecimal.ZERO)
        );

        assertThrows(IllegalArgumentException.class, () ->
                PaymentInstruction.create("alice", "bob", new BigDecimal("-50"))
        );
    }

    @Test
    @DisplayName("Rejects same sender and receiver")
    void rejectsSameSenderAndReceiver() {
        assertThrows(IllegalArgumentException.class, () ->
                PaymentInstruction.create("alice", "alice", new BigDecimal("100"))
        );
    }

    @Test
    @DisplayName("Rejects blank or null accounts")
    void rejectsBlankOrNullAccounts() {
        assertThrows(IllegalArgumentException.class, () ->
                PaymentInstruction.create(null, "bob", new BigDecimal("100"))
        );

        assertThrows(IllegalArgumentException.class, () ->
                PaymentInstruction.create("  ", "bob", new BigDecimal("100"))
        );

        assertThrows(IllegalArgumentException.class, () ->
                PaymentInstruction.create("alice", null, new BigDecimal("100"))
        );

        assertThrows(IllegalArgumentException.class, () ->
                PaymentInstruction.create("alice", "  ", new BigDecimal("100"))
        );
    }

    @Test
    @DisplayName("Canonical constructor rejects null paymentId, createdAt, or nonce")
    void rejectsNullMetadata() {
        Instant now = Instant.now();
        String nonce = UUID.randomUUID().toString();
        String id = UUID.randomUUID().toString();

        assertThrows(IllegalArgumentException.class, () ->
                new PaymentInstruction(null, "alice", "bob", new BigDecimal("10"), now, nonce)
        );

        assertThrows(IllegalArgumentException.class, () ->
                new PaymentInstruction(id, "alice", "bob", new BigDecimal("10"), null, nonce)
        );

        assertThrows(IllegalArgumentException.class, () ->
                new PaymentInstruction(id, "alice", "bob", new BigDecimal("10"), now, null)
        );
    }

    @Test
    @DisplayName("Canonical byte representation is deterministic and stable")
    void canonicalBytesIsDeterministic() {
        Instant now = Instant.parse("2026-10-12T12:00:00Z");
        PaymentInstruction instruction1 = new PaymentInstruction(
                "pay-123",
                "alice",
                "bob",
                new BigDecimal("100.00"),
                now,
                "nonce-456",
                null
        );
        PaymentInstruction instruction2 = new PaymentInstruction(
                "pay-123",
                "ALICE",
                "BOB",
                new BigDecimal("100.00"),
                now,
                "nonce-456",
                "some-sig"
        );

        // Same fields must yield exact same canonical bytes regardless of case or signature field
        assertEquals(new String(instruction1.toCanonicalBytes()), new String(instruction2.toCanonicalBytes()));
    }

    @Test
    @DisplayName("withSignature copies instruction and retains all fields")
    void withSignatureRetainsAllFields() {
        PaymentInstruction unsigned = PaymentInstruction.create("alice", "bob", new BigDecimal("50.00"));
        PaymentInstruction signed = unsigned.withSignature("test-signature");

        assertEquals(unsigned.paymentId(), signed.paymentId());
        assertEquals(unsigned.fromAccount(), signed.fromAccount());
        assertEquals(unsigned.toAccount(), signed.toAccount());
        assertEquals(unsigned.amount(), signed.amount());
        assertEquals(unsigned.createdAt(), signed.createdAt());
        assertEquals(unsigned.nonce(), signed.nonce());
        assertEquals("test-signature", signed.signature());
    }
}

