package com.demo.upimesh.model;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

/**
 * Immutable report representing the outcome of a ledger reconciliation audit.
 * <p>
 * Decouples structural ledger invariants (double-entry sum of debits == sum of credits)
 * from account balance reconciliation (expected closing balance = opening balance + credits - debits).
 *
 * @param isReconciled               true if both structural check passes and all account balances match authoritative opening balances
 * @param isLedgerBalanced           true if total debits equal total credits and all transactions are valid
 * @param isBalancesReconciled       true if every account has an authoritative opening balance and actual balance equals expected balance
 * @param structuralStatus           status of structural ledger check (BALANCED, IMBALANCED, INVALID_TRANSACTIONS)
 * @param balanceStatus              status of account balance reconciliation (RECONCILED, DISCREPANCY, UNVERIFIABLE)
 * @param reconciledAt               timestamp when the reconciliation audit ran
 * @param totalTransactionsChecked   count of settled transactions audited
 * @param totalLedgerDebits          sum of all settled ledger debits across accounts
 * @param totalLedgerCredits         sum of all settled ledger credits across accounts
 * @param systemZeroSumMaintained   true if totalLedgerDebits equals totalLedgerCredits
 * @param accountResults             detailed reconciliation result for each audited account
 * @param discrepancies              list of descriptive discrepancy strings detected
 * @param unverifiableAccounts       list of account IDs that could not be reconciled due to missing authoritative opening balances
 */
public record ReconciliationReport(
        boolean isReconciled,
        boolean isLedgerBalanced,
        boolean isBalancesReconciled,
        StructuralStatus structuralStatus,
        BalanceStatus balanceStatus,
        Instant reconciledAt,
        int totalTransactionsChecked,
        BigDecimal totalLedgerDebits,
        BigDecimal totalLedgerCredits,
        boolean systemZeroSumMaintained,
        List<AccountReconciliationEntry> accountResults,
        List<String> discrepancies,
        List<String> unverifiableAccounts
) {

    public enum StructuralStatus {
        BALANCED,
        IMBALANCED,
        INVALID_TRANSACTIONS
    }

    public enum BalanceStatus {
        RECONCILED,
        DISCREPANCY,
        UNVERIFIABLE
    }

    public enum AccountStatus {
        RECONCILED,
        DISCREPANCY,
        UNVERIFIABLE
    }

    public record AccountReconciliationEntry(
            String accountId,
            BigDecimal openingBalance,
            BigDecimal totalCredits,
            BigDecimal totalDebits,
            BigDecimal netMovement,
            BigDecimal expectedBalance,
            BigDecimal actualBalance,
            BigDecimal discrepancy,
            AccountStatus status,
            boolean matches
    ) {}
}
