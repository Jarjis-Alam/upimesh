package com.demo.upimesh;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class IdempotencyServiceTest {

    private IdempotencyService idempotencyService;

    @BeforeEach
    void setUp() {
        idempotencyService = new IdempotencyService();
    }

    @Test
    @DisplayName("computeHash() produces consistent 64-character SHA-256 hex string")
    void computeHashProducesDeterministicHex() {
        EncryptedPacket packet1 = new EncryptedPacket(new byte[]{1, 2}, new byte[]{3, 4}, new byte[]{5, 6});
        EncryptedPacket packet2 = new EncryptedPacket(new byte[]{1, 2}, new byte[]{3, 4}, new byte[]{5, 6});
        EncryptedPacket packet3 = new EncryptedPacket(new byte[]{9, 9}, new byte[]{3, 4}, new byte[]{5, 6});

        String hash1 = idempotencyService.computeHash(packet1);
        String hash2 = idempotencyService.computeHash(packet2);
        String hash3 = idempotencyService.computeHash(packet3);

        assertNotNull(hash1);
        assertEquals(64, hash1.length(), "SHA-256 hex string must be 64 characters long");
        assertEquals(hash1, hash2, "Identical packets must produce identical hash");
        assertNotEquals(hash1, hash3, "Different packets must produce different hash");
    }

    @Test
    @DisplayName("First claim succeeds; repeat claim fails")
    void firstClaimSucceedsRepeatFails() {
        String hash = "hash-12345";

        assertTrue(idempotencyService.tryClaim(hash), "First claim must succeed");
        assertFalse(idempotencyService.tryClaim(hash), "Immediate repeat claim must fail");

        idempotencyService.markSettled(hash);
        assertTrue(idempotencyService.isSettled(hash));
        assertFalse(idempotencyService.tryClaim(hash), "Claim after settlement must fail");
    }

    @Test
    @DisplayName("Different hashes can be claimed independently")
    void differentHashesClaimedIndependently() {
        String hashA = "hash-A";
        String hashB = "hash-B";

        assertTrue(idempotencyService.tryClaim(hashA));
        assertTrue(idempotencyService.tryClaim(hashB));

        idempotencyService.markSettled(hashA);
        assertTrue(idempotencyService.isSettled(hashA));
        assertFalse(idempotencyService.isSettled(hashB));
    }

    @Test
    @DisplayName("Releasing an in-flight claim allows subsequent retry")
    void releasingClaimAllowsRetry() {
        String hash = "hash-retry-1";

        assertTrue(idempotencyService.tryClaim(hash));
        assertFalse(idempotencyService.tryClaim(hash));

        // Release because processing encountered an error
        idempotencyService.releaseClaim(hash);
        assertFalse(idempotencyService.isSettled(hash));

        // Retry must now succeed
        assertTrue(idempotencyService.tryClaim(hash));
    }

    @Test
    @DisplayName("Multiple concurrent threads attempting to claim same hash yield exactly one winner")
    void concurrentClaimsYieldExactlyOneWinner() throws InterruptedException, ExecutionException {
        String hash = "hash-concurrent-test";
        int threadCount = 20;
        ExecutorService executor = Executors.newFixedThreadPool(threadCount);
        CountDownLatch startLatch = new CountDownLatch(1);
        List<Future<Boolean>> futures = new ArrayList<>();

        for (int i = 0; i < threadCount; i++) {
            futures.add(executor.submit(() -> {
                startLatch.await(); // ensure all threads launch concurrently
                return idempotencyService.tryClaim(hash);
            }));
        }

        startLatch.countDown(); // fire all threads simultaneously

        int successfulClaims = 0;
        for (Future<Boolean> future : futures) {
            if (future.get()) {
                successfulClaims++;
            }
        }

        executor.shutdown();
        assertEquals(1, successfulClaims, "Exactly one thread must succeed in claiming the packet");
    }
}
