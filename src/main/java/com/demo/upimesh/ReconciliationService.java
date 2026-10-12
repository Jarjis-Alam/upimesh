package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.ReconciliationReport;
import com.demo.upimesh.model.ReconciliationReport.AccountReconciliationEntry;
import com.demo.upimesh.model.ReconciliationReport.AccountStatus;
import com.demo.upimesh.model.ReconciliationReport.BalanceStatus;
import com.demo.upimesh.model.ReconciliationReport.StructuralStatus;
import com.demo.upimesh.model.Transaction;
import com.demo.upimesh.model.TransactionRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Service providing read-only ledger reconciliation and balance integrity audits.
 * <p>
 * Architectural Principles & Mathematical Model:
 * 1. Structural Ledger Check (Double-Entry Invariant):
 *    Every valid transfer between internal accounts debits a sender and credits a receiver by equal amounts.
 *    Total ledger debits must strictly equal total ledger credits (sum(debits) == sum(credits)).
 *    IMPORTANT: Double-entry conservation validates ONLY that the recorded journal entries are internally balanced.
 *    It is NOT proof that individual account balances are correct or that accounts have not been manipulated outside the ledger.
 * 2. Account Balance Reconciliation:
 *    For an account with a documented authoritative opening balance:
 *        Expected closing balance = Opening balance + Credits − Debits
 *        Discrepancy = Actual balance − Expected closing balance
 *    An account is reconciled if and only if discrepancy == 0.
 * 3. Handling Missing/Unknown Opening Balances:
 *    If an account lacks an authoritative opening balance, it CANNOT be verified or fully reconciled.
 *    We do NOT treat (actualBalance - netMovement >= 0) as proof of reconciliation.
 *    Unverified accounts are explicitly classified as UNVERIFIABLE and listed in the report.
 * 4. Read-Only Safety:
 *    This service never silently alters or repairs account balances or ledger history.
 *    Discrepancies and unverifiable states are strictly audited and reported.
 */
@Service
public class ReconciliationService {

    public static final Map<String, BigDecimal> DEFAULT_SEED_OPENING_BALANCES = Map.of(
            "alice", new BigDecimal("5000.00"),
            "bob", new BigDecimal("1000.00"),
            "carol", new BigDecimal("2000.00")
    );

    private final AccountRepository accountRepository;
    private final TransactionRepository transactionRepository;

    @Autowired
    public ReconciliationService(AccountRepository accountRepository, TransactionRepository transactionRepository) {
        this.accountRepository = accountRepository;
        this.transactionRepository = transactionRepository;
    }

    /**
     * Reconciles all accounts using the documented seed baseline as the opening balance source of truth.
     */
    @Transactional(readOnly = true)
    public ReconciliationReport reconcile() {
        return reconcile(DEFAULT_SEED_OPENING_BALANCES);
    }

    /**
     * Reconciles all accounts against provided opening balances and recorded ledger movements.
     * Decouples structural ledger invariants from account balance verification.
     *
     * @param openingBalances map of account ID to authoritative opening balance
     * @return comprehensive ReconciliationReport with distinct structural and balance statuses
     */
    @Transactional(readOnly = true)
    public ReconciliationReport reconcile(Map<String, BigDecimal> openingBalances) {
        Map<String, BigDecimal> baseline = openingBalances != null ? openingBalances : Collections.emptyMap();
        List<Account> accounts = accountRepository.findAll();
        List<Transaction> transactions = transactionRepository != null
                ? transactionRepository.findAll()
                : Collections.emptyList();

        List<String> discrepancies = new ArrayList<>();
        List<String> unverifiableAccounts = new ArrayList<>();
        BigDecimal totalLedgerDebits = BigDecimal.ZERO;
        BigDecimal totalLedgerCredits = BigDecimal.ZERO;
        int checkedCount = 0;
        boolean invalidTxFound = false;

        // Tally credits and debits per account from settled transactions
        Map<String, BigDecimal> debitsPerAccount = new HashMap<>();
        Map<String, BigDecimal> creditsPerAccount = new HashMap<>();

        for (Transaction tx : transactions) {
            if ("SETTLED".equalsIgnoreCase(tx.getStatus())) {
                checkedCount++;
                BigDecimal amount = tx.getAmount();

                if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
                    discrepancies.add("Transaction " + tx.getId() + " has invalid non-positive amount: " + amount);
                    invalidTxFound = true;
                    continue;
                }

                String from = tx.getFromAccount() != null ? tx.getFromAccount().trim().toLowerCase() : "";
                String to = tx.getToAccount() != null ? tx.getToAccount().trim().toLowerCase() : "";

                if (from.isBlank() || to.isBlank() || from.equalsIgnoreCase(to)) {
                    discrepancies.add("Transaction " + tx.getId() + " has invalid account references: from=" + from + ", to=" + to);
                    invalidTxFound = true;
                }

                totalLedgerDebits = totalLedgerDebits.add(amount);
                totalLedgerCredits = totalLedgerCredits.add(amount);

                debitsPerAccount.put(from, debitsPerAccount.getOrDefault(from, BigDecimal.ZERO).add(amount));
                creditsPerAccount.put(to, creditsPerAccount.getOrDefault(to, BigDecimal.ZERO).add(amount));
            }
        }

        // 1. Structural Ledger Check
        boolean systemZeroSumMaintained = totalLedgerDebits.compareTo(totalLedgerCredits) == 0;
        StructuralStatus structuralStatus;
        if (!systemZeroSumMaintained) {
            structuralStatus = StructuralStatus.IMBALANCED;
            discrepancies.add(String.format("Global double-entry imbalance: total debits (%s) != total credits (%s)",
                    totalLedgerDebits, totalLedgerCredits));
        } else if (invalidTxFound) {
            structuralStatus = StructuralStatus.INVALID_TRANSACTIONS;
        } else {
            structuralStatus = StructuralStatus.BALANCED;
        }
        boolean isLedgerBalanced = (structuralStatus == StructuralStatus.BALANCED);

        // 2. Account Balance Reconciliation
        List<AccountReconciliationEntry> accountResults = new ArrayList<>();
        boolean hasDiscrepancy = false;
        boolean hasUnverifiable = false;

        for (Account account : accounts) {
            String accountId = account.getId() != null ? account.getId().trim().toLowerCase() : "";
            BigDecimal actualBalance = account.getBalance();
            BigDecimal openingBalance = baseline.get(accountId);

            BigDecimal debits = debitsPerAccount.getOrDefault(accountId, BigDecimal.ZERO);
            BigDecimal credits = creditsPerAccount.getOrDefault(accountId, BigDecimal.ZERO);
            BigDecimal netMovement = credits.subtract(debits);

            BigDecimal expectedBalance;
            BigDecimal discrepancy;
            AccountStatus accountStatus;
            boolean matches;

            if (openingBalance != null) {
                expectedBalance = openingBalance.add(credits).subtract(debits);
                discrepancy = actualBalance.subtract(expectedBalance);

                if (discrepancy.compareTo(BigDecimal.ZERO) == 0) {
                    accountStatus = AccountStatus.RECONCILED;
                    matches = true;
                } else {
                    accountStatus = AccountStatus.DISCREPANCY;
                    matches = false;
                    hasDiscrepancy = true;
                    discrepancies.add(String.format(
                            "Discrepancy for account '%s': actual balance %s does not agree with expected %s (opening %s, credits %s, debits %s, delta %s)",
                            account.getId(), actualBalance, expectedBalance, openingBalance, credits, debits, discrepancy
                    ));
                }
            } else {
                // No authoritative opening balance: account CANNOT be verified or reconciled
                expectedBalance = null;
                discrepancy = null;
                accountStatus = AccountStatus.UNVERIFIABLE;
                matches = false;
                hasUnverifiable = true;
                unverifiableAccounts.add(account.getId());
                discrepancies.add(String.format(
                        "Account '%s' cannot be fully reconciled: missing authoritative opening balance",
                        account.getId()
                ));
            }

            accountResults.add(new AccountReconciliationEntry(
                    account.getId(),
                    openingBalance,
                    credits,
                    debits,
                    netMovement,
                    expectedBalance,
                    actualBalance,
                    discrepancy,
                    accountStatus,
                    matches
            ));
        }

        // Determine balance reconciliation status
        BalanceStatus balanceStatus;
        if (hasDiscrepancy) {
            balanceStatus = BalanceStatus.DISCREPANCY;
        } else if (hasUnverifiable || accounts.isEmpty()) {
            balanceStatus = BalanceStatus.UNVERIFIABLE;
        } else {
            balanceStatus = BalanceStatus.RECONCILED;
        }
        boolean isBalancesReconciled = (balanceStatus == BalanceStatus.RECONCILED);

        // Overall reconciliation passes only if BOTH structural check is balanced AND all balances reconciled
        boolean isReconciled = isLedgerBalanced && isBalancesReconciled && discrepancies.isEmpty();

        return new ReconciliationReport(
                isReconciled,
                isLedgerBalanced,
                isBalancesReconciled,
                structuralStatus,
                balanceStatus,
                Instant.now(),
                checkedCount,
                totalLedgerDebits,
                totalLedgerCredits,
                systemZeroSumMaintained,
                accountResults,
                discrepancies,
                unverifiableAccounts
        );
    }

    /**
     * Performs a read-only structural ledger check without assuming opening balances.
     * Evaluates double-entry conservation and transaction validity, but explicitly reports
     * that account balances cannot be verified without authoritative opening balances.
     */
    @Transactional(readOnly = true)
    public ReconciliationReport reconcileConsistencyOnly() {
        return reconcile(Collections.emptyMap());
    }

    /**
     * Alias for {@link #reconcileConsistencyOnly()}.
     */
    @Transactional(readOnly = true)
    public ReconciliationReport checkLedgerStructure() {
        return reconcileConsistencyOnly();
    }
}
