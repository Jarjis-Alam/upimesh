package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.ConsumedConsentRepository;
import com.demo.upimesh.model.ProcessedPacketRepository;
import com.demo.upimesh.model.Transaction;
import com.demo.upimesh.model.TransactionRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Stage 8.14: Financial Read Endpoints Access-Control and Scoping Test Suite.
 * <p>
 * Verifies strict account-level security for:
 * - GET /api/accounts
 * - GET /api/transactions
 * - GET /api/reconciliation
 * <p>
 * Tested Security Invariants:
 * 1. Anonymous access is strictly denied (401 Unauthorized).
 * 2. Invalid or placeholder tokens are rejected (401 Unauthorized).
 * 3. Authenticated users only receive data scoped to their own identity.
 * 4. Cross-account reading via parameter tampering is strictly denied (403 Forbidden).
 * 5. Reconciliation reports are restricted to administrators (ROLE_ADMIN); regular users get 403 Forbidden.
 * 6. Unauthorized read attempts do not mutate ledger balances, transactions, or idempotency records.
 * 7. Production configuration fails closed against demo credentials.
 * 8. Mesh and public endpoints have clearly separated, tested access boundaries.
 */
@SpringBootTest
@DirtiesContext(classMode = DirtiesContext.ClassMode.BEFORE_EACH_TEST_METHOD)
public class FinancialReadAccessControlTest {

    @Autowired
    private ApiController apiController;

    @Autowired
    private FinancialSecurityService financialSecurityService;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private TransactionRepository transactionRepository;

    @Autowired
    private ProcessedPacketRepository processedPacketRepository;

    @Autowired
    private ConsumedConsentRepository consumedConsentRepository;

    @Autowired
    private org.springframework.core.env.Environment originalEnvironment;

    @Autowired
    private WebApplicationContext webApplicationContext;

    private MockMvc mockMvc;

    private static final String TEST_ADMIN_TOKEN = "stage814-test-admin-secret-token";
    private static final String ALICE_PROD_TOKEN = "stage814-alice-secret-bearer-token";
    private static final String BOB_PROD_TOKEN = "stage814-bob-secret-bearer-token";

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(webApplicationContext).build();

        accountRepository.deleteAll();
        transactionRepository.deleteAll();
        if (processedPacketRepository != null) {
            processedPacketRepository.deleteAll();
        }
        if (consumedConsentRepository != null) {
            consumedConsentRepository.deleteAll();
        }

        apiController.setEnvironment(originalEnvironment);
        apiController.setConfiguredAdminToken(TEST_ADMIN_TOKEN);
        financialSecurityService.setEnvironment(originalEnvironment);
        financialSecurityService.setConfiguredAdminToken(TEST_ADMIN_TOKEN);
        financialSecurityService.setDemoAuthEnabled(true);
        financialSecurityService.clearConfiguredUserTokens();
        financialSecurityService.setConfiguredUserToken("alice", ALICE_PROD_TOKEN);
        financialSecurityService.setConfiguredUserToken("bob", BOB_PROD_TOKEN);

        // Seed test accounts with reconciled balances matching the 3 transactions:
        // Alice: 5000 - 100 (tx-1) + 25 (tx-3) = 4925.00
        // Bob:   1000 + 100 (tx-1) - 50 (tx-2) = 1050.00
        // Carol: 2000 + 50 (tx-2) - 25 (tx-3)  = 2025.00
        accountRepository.save(new Account("alice", new BigDecimal("4925.00")));
        accountRepository.save(new Account("bob", new BigDecimal("1050.00")));
        accountRepository.save(new Account("carol", new BigDecimal("2025.00")));

        // Seed discrete transactions
        Instant now = Instant.now();
        transactionRepository.save(new Transaction("tx-1", "alice", "bob", new BigDecimal("100.00"), now.minusSeconds(30), "SETTLED"));
        transactionRepository.save(new Transaction("tx-2", "bob", "carol", new BigDecimal("50.00"), now.minusSeconds(20), "SETTLED"));
        transactionRepository.save(new Transaction("tx-3", "carol", "alice", new BigDecimal("25.00"), now.minusSeconds(10), "SETTLED"));
    }

    @AfterEach
    void tearDown() {
        apiController.setEnvironment(originalEnvironment);
        financialSecurityService.setEnvironment(originalEnvironment);
        financialSecurityService.clearConfiguredUserTokens();
    }

    // =========================================================================
    // 1. Anonymous Access Rejection (401 Unauthorized)
    // =========================================================================

    @Test
    @DisplayName("1. Anonymous request to GET /api/accounts is rejected with 401 Unauthorized")
    void testAccounts_anonymousRequest_rejectedWith401() throws Exception {
        mockMvc.perform(get("/api/accounts"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/accounts").param("accountId", "alice"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("2. Anonymous request to GET /api/transactions is rejected with 401 Unauthorized")
    void testTransactions_anonymousRequest_rejectedWith401() throws Exception {
        mockMvc.perform(get("/api/transactions"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/transactions").param("accountId", "alice"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("3. Anonymous request to GET /api/reconciliation is rejected with 401 Unauthorized")
    void testReconciliation_anonymousRequest_rejectedWith401() throws Exception {
        mockMvc.perform(get("/api/reconciliation"))
                .andExpect(status().isUnauthorized());
    }

    // =========================================================================
    // 2. Invalid Token Handling (401 Unauthorized)
    // =========================================================================

    @Test
    @DisplayName("4. Malformed or insecure placeholder tokens are rejected with 401 Unauthorized")
    void testInvalidTokens_rejectedWith401() throws Exception {
        // Unknown token
        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer invalid-token-xyz"))
                .andExpect(status().isUnauthorized());

        // Insecure placeholder tokens
        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer dev-test-token"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/transactions")
                        .header("Authorization", "Bearer admin"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/reconciliation")
                        .header("X-Admin-Token", "password"))
                .andExpect(status().isUnauthorized());
    }

    // =========================================================================
    // 3. User Authentication & Identity Scoping
    // =========================================================================

    @Test
    @DisplayName("5. Authenticated user receives only their own account data")
    void testAccounts_userAuthentication_scopedToOwnAccountOnly() throws Exception {
        // Alice views accounts via Bearer token
        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer " + ALICE_PROD_TOKEN))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].id", is("alice")))
                .andExpect(jsonPath("$[0].balance", is(4925.00)));

        // Alice views accounts via simulator demo auth
        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer demo-token-alice"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].id", is("alice")));

        // Bob views accounts via simulator demo auth
        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer demo-token-bob"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].id", is("bob")))
                .andExpect(jsonPath("$[0].balance", is(1050.00)));
    }

    @Test
    @DisplayName("6. Authenticated user specifying their own accountId query succeeds")
    void testAccounts_ownAccountIdQuery_succeeds() throws Exception {
        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer " + ALICE_PROD_TOKEN)
                        .param("accountId", "alice"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].id", is("alice")));
    }

    // =========================================================================
    // 4. Cross-Account Access Prevention (403 Forbidden)
    // =========================================================================

    @Test
    @DisplayName("7. Cross-account query parameter tampering on /api/accounts is rejected with 403 Forbidden")
    void testAccounts_crossAccountAccess_rejectedWith403() throws Exception {
        // Alice attempts to read Bob's account
        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer demo-token-alice")
                        .param("accountId", "bob"))
                .andExpect(status().isForbidden());

        // Alice attempts to read Carol's account
        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer " + ALICE_PROD_TOKEN)
                        .param("accountId", "carol"))
                .andExpect(status().isForbidden());

        // Bob attempts to read Alice's account
        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer demo-token-bob")
                        .param("accountId", "alice"))
                .andExpect(status().isForbidden());

        // Alice attempts to query nonexistent account
        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer demo-token-alice")
                        .param("accountId", "nonexistent"))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("8. Authenticated user receives only transactions where they are sender or recipient")
    void testTransactions_userAuthentication_scopedToOwnTransactions() throws Exception {
        // In setUp:
        // tx-1: alice -> bob
        // tx-2: bob -> carol
        // tx-3: carol -> alice

        // Alice should see tx-1 and tx-3, but NOT tx-2 (bob -> carol)
        mockMvc.perform(get("/api/transactions")
                        .header("Authorization", "Bearer demo-token-alice"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[0].id", is("tx-3")))
                .andExpect(jsonPath("$[1].id", is("tx-1")));

        // Bob should see tx-1 and tx-2, but NOT tx-3 (carol -> alice)
        mockMvc.perform(get("/api/transactions")
                        .header("Authorization", "Bearer demo-token-bob"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[0].id", is("tx-2")))
                .andExpect(jsonPath("$[1].id", is("tx-1")));
    }

    @Test
    @DisplayName("9. Cross-account query parameter tampering on /api/transactions is rejected with 403 Forbidden")
    void testTransactions_crossAccountAccess_rejectedWith403() throws Exception {
        // Alice attempts to read Bob's transaction history
        mockMvc.perform(get("/api/transactions")
                        .header("Authorization", "Bearer demo-token-alice")
                        .param("accountId", "bob"))
                .andExpect(status().isForbidden());

        // Alice attempts to read Carol's transaction history
        mockMvc.perform(get("/api/transactions")
                        .header("Authorization", "Bearer demo-token-alice")
                        .param("accountId", "carol"))
                .andExpect(status().isForbidden());

        // Bob attempts to read Alice's transaction history
        mockMvc.perform(get("/api/transactions")
                        .header("Authorization", "Bearer demo-token-bob")
                        .param("accountId", "alice"))
                .andExpect(status().isForbidden());
    }

    // =========================================================================
    // 5. Administrator Privileges & Role Segregation
    // =========================================================================

    @Test
    @DisplayName("10. Administrator has full visibility across all accounts and transactions")
    void testAdmin_hasFullAccessToAccountsAndTransactions() throws Exception {
        // Admin via Bearer token
        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer " + TEST_ADMIN_TOKEN))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(3)));

        // Admin via X-Admin-Token
        mockMvc.perform(get("/api/transactions")
                        .header("X-Admin-Token", TEST_ADMIN_TOKEN))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(3)));

        // Admin querying specific account
        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer " + TEST_ADMIN_TOKEN)
                        .param("accountId", "bob"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].id", is("bob")));

        // Admin querying specific account's transactions
        mockMvc.perform(get("/api/transactions")
                        .header("Authorization", "Bearer " + TEST_ADMIN_TOKEN)
                        .param("accountId", "carol"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)));
    }

    @Test
    @DisplayName("11. Non-admin users are rejected with 403 Forbidden on /api/reconciliation")
    void testReconciliation_regularUser_rejectedWith403() throws Exception {
        // Alice is a regular user
        mockMvc.perform(get("/api/reconciliation")
                        .header("Authorization", "Bearer demo-token-alice"))
                .andExpect(status().isForbidden());

        mockMvc.perform(get("/api/reconciliation")
                        .header("Authorization", "Bearer " + ALICE_PROD_TOKEN))
                .andExpect(status().isForbidden());

        // Bob is a regular user
        mockMvc.perform(get("/api/reconciliation")
                        .header("Authorization", "Bearer demo-token-bob"))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("12. Administrator receives full reconciliation report on /api/reconciliation")
    void testReconciliation_admin_returnsReport() throws Exception {
        mockMvc.perform(get("/api/reconciliation")
                        .header("Authorization", "Bearer " + TEST_ADMIN_TOKEN))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.isReconciled", is(true)))
                .andExpect(jsonPath("$.isLedgerBalanced", is(true)));

        mockMvc.perform(get("/api/reconciliation")
                        .header("X-Admin-Token", TEST_ADMIN_TOKEN))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.isReconciled", is(true)));
    }

    // =========================================================================
    // 6. Ledger Integrity & Non-Mutation under Unauthorized Access
    // =========================================================================

    @Test
    @DisplayName("13. Unauthorized read attempts do not mutate balances, transactions, or consent records")
    void testUnauthorizedRequests_doNotMutateLedger() throws Exception {
        BigDecimal aliceInitial = accountRepository.findById("alice").orElseThrow().getBalance();
        BigDecimal bobInitial = accountRepository.findById("bob").orElseThrow().getBalance();
        long txCountBefore = transactionRepository.count();
        long consentCountBefore = consumedConsentRepository != null ? consumedConsentRepository.count() : 0;
        long packetCountBefore = processedPacketRepository != null ? processedPacketRepository.count() : 0;

        // Perform multiple unauthorized / rejected requests
        mockMvc.perform(get("/api/accounts")).andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/accounts").param("accountId", "bob").header("Authorization", "Bearer demo-token-alice"))
                .andExpect(status().isForbidden());
        mockMvc.perform(get("/api/transactions")).andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/transactions").param("accountId", "carol").header("Authorization", "Bearer demo-token-alice"))
                .andExpect(status().isForbidden());
        mockMvc.perform(get("/api/reconciliation")).andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/reconciliation").header("Authorization", "Bearer demo-token-alice"))
                .andExpect(status().isForbidden());

        // Verify all state is strictly unchanged
        BigDecimal aliceAfter = accountRepository.findById("alice").orElseThrow().getBalance();
        BigDecimal bobAfter = accountRepository.findById("bob").orElseThrow().getBalance();
        long txCountAfter = transactionRepository.count();
        long consentCountAfter = consumedConsentRepository != null ? consumedConsentRepository.count() : 0;
        long packetCountAfter = processedPacketRepository != null ? processedPacketRepository.count() : 0;

        assertEquals(0, aliceInitial.compareTo(aliceAfter), "Alice balance must not be modified by unauthorized reads");
        assertEquals(0, bobInitial.compareTo(bobAfter), "Bob balance must not be modified by unauthorized reads");
        assertEquals(txCountBefore, txCountAfter, "Transaction count must not change");
        assertEquals(consentCountBefore, consentCountAfter, "Consent records count must not change");
        assertEquals(packetCountBefore, packetCountAfter, "Processed packets count must not change");
    }

    // =========================================================================
    // 7. Production Environment Fail-Closed Guarantees
    // =========================================================================

    @Test
    @DisplayName("14. Demo authentication fails closed in production profile")
    void testProductionConfiguration_demoAuthFailsClosed() throws Exception {
        MockEnvironment prodEnv = new MockEnvironment();
        prodEnv.setActiveProfiles("prod");
        apiController.setEnvironment(prodEnv);
        financialSecurityService.setEnvironment(prodEnv);

        // Attempting to enable demo auth in production is forced to false
        financialSecurityService.setDemoAuthEnabled(true);
        assertFalse(financialSecurityService.isDemoAuthEnabled(), "Demo auth must remain disabled in production profile");

        // Demo tokens fail in production
        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer demo-token-alice"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer demo-token-admin"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/transactions")
                        .header("Authorization", "Bearer demo-token-alice"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/reconciliation")
                        .header("Authorization", "Bearer demo-token-admin"))
                .andExpect(status().isUnauthorized());

        // Valid production credentials still succeed
        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer " + ALICE_PROD_TOKEN))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].id", is("alice")));

        mockMvc.perform(get("/api/reconciliation")
                        .header("Authorization", "Bearer " + TEST_ADMIN_TOKEN))
                .andExpect(status().isOk());
    }

    // =========================================================================
    // 8. Separate Mesh Endpoint Access Policy
    // =========================================================================

    @Test
    @DisplayName("15. Mesh public key and topology endpoints have independent access boundaries")
    void testMeshEndpoints_separateAccessPolicy() throws Exception {
        // Public bridge encryption key is accessible to mobile clients without bank session
        mockMvc.perform(get("/api/bridge/public-key"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.algorithm", is("RSA")));

        // Mesh topology is accessible to network nodes
        mockMvc.perform(get("/api/mesh/topology"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status", is("ONLINE")));
    }
}
