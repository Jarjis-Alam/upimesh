package com.demo.upimesh.model;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.File;
import java.io.InputStream;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class CrossLanguageCanonicalizationTest {

    private record Fixture(
            String paymentId,
            String fromAccount,
            String toAccount,
            BigDecimal amount,
            String amountInput,
            String isoTimestamp,
            String nonce
    ) {}

    private static final Fixture[] FIXTURES = new Fixture[]{
            new Fixture(
                    "pay-uuid-whole-001",
                    "Alice",
                    "Bob",
                    new BigDecimal("1250.75"),
                    "1250.75",
                    "2026-10-12T18:30:00Z",
                    "nonce-whole-111"
            ),
            new Fixture(
                    "pay-uuid-millis-002",
                    "CAROL",
                    "Alice",
                    new BigDecimal("500"),
                    "500",
                    "2026-10-12T09:15:30.500Z",
                    "nonce-millis-222"
            ),
            new Fixture(
                    "pay-uuid-micros-003",
                    "bob",
                    "carol",
                    new BigDecimal("99.99900"),
                    "99.99900",
                    "2026-10-12T14:22:11.123450Z",
                    "nonce-micros-333"
            ),
            new Fixture(
                    "pay-uuid-nanos-004",
                    "Alice",
                    "CAROL",
                    new BigDecimal("0.05"),
                    "0.05",
                    "2026-10-12T23:59:59.123456789Z",
                    "nonce-nanos-444"
            )
    };

    @Test
    @DisplayName("Swift and Java produce byte-for-byte identical canonical payloads for the same fixtures")
    void testCrossLanguageCanonicalPayloadEquality() throws Exception {
        File swiftSource = new File("ios/UPIMesh/UPIMesh/PaymentInstruction.swift");
        assertTrue(swiftSource.exists(), "PaymentInstruction.swift must exist at " + swiftSource.getAbsolutePath());

        MessageDigest sha256 = MessageDigest.getInstance("SHA-256");

        for (Fixture f : FIXTURES) {
            // 1. Generate canonical bytes in Java
            PaymentInstruction javaInstruction = new PaymentInstruction(
                    f.paymentId(),
                    f.fromAccount(),
                    f.toAccount(),
                    f.amount(),
                    Instant.parse(f.isoTimestamp()),
                    f.nonce(),
                    null
            );
            byte[] javaBytes = javaInstruction.toCanonicalBytes();
            String javaCanonicalString = new String(javaBytes, StandardCharsets.UTF_8);
            String javaSha256Hex = bytesToHex(sha256.digest(javaBytes));

            // 2. Execute Swift CLI to construct identical PaymentInstruction and dump canonical bytes
            byte[] swiftBytes = runSwiftCanonicalization(
                    f.paymentId(),
                    f.fromAccount(),
                    f.toAccount(),
                    f.amountInput(),
                    f.isoTimestamp(),
                    f.nonce()
            );
            assertNotNull(swiftBytes, "Swift output must not be null for fixture: " + f.paymentId());
            String swiftCanonicalString = new String(swiftBytes, StandardCharsets.UTF_8);
            String swiftSha256Hex = bytesToHex(sha256.digest(swiftBytes));

            // 3. Assert exact byte-for-byte equality and SHA-256 digest match
            assertEquals(javaCanonicalString, swiftCanonicalString, "Canonical string mismatch for fixture " + f.paymentId());
            assertArrayEquals(javaBytes, swiftBytes, "Canonical byte mismatch for fixture " + f.paymentId());
            assertEquals(javaSha256Hex, swiftSha256Hex, "SHA-256 digest mismatch for fixture " + f.paymentId());
        }
    }

    private byte[] runSwiftCanonicalization(
            String paymentId,
            String fromAccount,
            String toAccount,
            String amount,
            String isoTimestamp,
            String nonce
    ) throws Exception {
        String swiftScript = """
                import Foundation
                
                let paymentId = "%s"
                let from = "%s"
                let to = "%s"
                let amountDec = Decimal(string: "%s")!
                let instant = try! PaymentInstant.parse("%s")
                let nonce = "%s"
                
                let inst = try! PaymentInstruction(
                    paymentId: paymentId,
                    fromAccount: from,
                    toAccount: to,
                    amount: amountDec,
                    createdAt: instant,
                    nonce: nonce
                )
                let data = inst.toCanonicalBytes()
                FileHandle.standardOutput.write(data)
                """.formatted(paymentId, fromAccount, toAccount, amount, isoTimestamp, nonce);

        String paymentInstructionSource = java.nio.file.Files.readString(java.nio.file.Path.of("ios/UPIMesh/UPIMesh/PaymentInstruction.swift"));
        String combinedScript = paymentInstructionSource + "\n" + swiftScript;

        ProcessBuilder pb = new ProcessBuilder("swift", "-");
        pb.redirectError(ProcessBuilder.Redirect.INHERIT);
        Process process = pb.start();

        process.getOutputStream().write(combinedScript.getBytes(StandardCharsets.UTF_8));
        process.getOutputStream().close();

        byte[] outputBytes;
        try (InputStream is = process.getInputStream()) {
            outputBytes = is.readAllBytes();
        }

        int exitCode = process.waitFor();
        if (exitCode != 0) {
            throw new IllegalStateException("Swift process exited with code " + exitCode);
        }

        return outputBytes;
    }

    private static String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }
}
