package com.demo.upimesh.model;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.nio.charset.StandardCharsets;

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

    @Test
    @DisplayName("Canonical byte representation across whole and fractional seconds, amounts, and account normalization")
    void canonicalBytesAcrossWholeAndFractionalSeconds() {
        // Whole seconds
        PaymentInstruction whole = new PaymentInstruction(
                "p-whole",
                "Alice",
                "Bob",
                new BigDecimal("100"),
                Instant.parse("2026-10-12T12:00:00Z"),
                "n-1",
                null
        );
        String expectedWhole = "UPI-MESH-INSTRUCTION-V1\n" +
                "paymentId:7:p-whole\n" +
                "fromAccount:5:alice\n" +
                "toAccount:3:bob\n" +
                "amount:6:100.00\n" +
                "createdAt:20:2026-10-12T12:00:00Z\n" +
                "nonce:3:n-1\n";
        assertEquals(expectedWhole, new String(whole.toCanonicalBytes(), StandardCharsets.UTF_8));

        // Milliseconds (3 digits)
        PaymentInstruction millis = new PaymentInstruction(
                "p-millis",
                "ALICE",
                "CAROL",
                new BigDecimal("250.5"),
                Instant.parse("2026-10-12T15:30:45.500Z"),
                "n-2",
                null
        );
        String expectedMillis = "UPI-MESH-INSTRUCTION-V1\n" +
                "paymentId:8:p-millis\n" +
                "fromAccount:5:alice\n" +
                "toAccount:5:carol\n" +
                "amount:6:250.50\n" +
                "createdAt:24:2026-10-12T15:30:45.500Z\n" +
                "nonce:3:n-2\n";
        assertEquals(expectedMillis, new String(millis.toCanonicalBytes(), StandardCharsets.UTF_8));

        // Microseconds (6 digits)
        PaymentInstruction micros = new PaymentInstruction(
                "p-micros",
                "alice",
                "bob",
                new BigDecimal("99.99900"),
                Instant.parse("2026-10-12T08:15:30.123450Z"),
                "n-3",
                null
        );
        String expectedMicros = "UPI-MESH-INSTRUCTION-V1\n" +
                "paymentId:8:p-micros\n" +
                "fromAccount:5:alice\n" +
                "toAccount:3:bob\n" +
                "amount:6:99.999\n" +
                "createdAt:27:2026-10-12T08:15:30.123450Z\n" +
                "nonce:3:n-3\n";
        assertEquals(expectedMicros, new String(micros.toCanonicalBytes(), StandardCharsets.UTF_8));

        // Nanoseconds (9 digits)
        PaymentInstruction nanos = new PaymentInstruction(
                "p-nanos",
                "alice",
                "bob",
                new BigDecimal("0.05"),
                Instant.parse("2026-10-12T23:59:59.123456789Z"),
                "n-4",
                null
        );
        String expectedNanos = "UPI-MESH-INSTRUCTION-V1\n" +
                "paymentId:7:p-nanos\n" +
                "fromAccount:5:alice\n" +
                "toAccount:3:bob\n" +
                "amount:4:0.05\n" +
                "createdAt:30:2026-10-12T23:59:59.123456789Z\n" +
                "nonce:3:n-4\n";
        assertEquals(expectedNanos, new String(nanos.toCanonicalBytes(), StandardCharsets.UTF_8));
    }
}

