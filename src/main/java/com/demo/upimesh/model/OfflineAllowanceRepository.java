package com.demo.upimesh.model;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface OfflineAllowanceRepository extends JpaRepository<OfflineAllowance, String> {

    /**
     * Finds the currently active allowance for the specified account, if one exists.
     */
    Optional<OfflineAllowance> findByActiveAccountId(String activeAccountId);

    /**
     * Checks whether an active allowance currently exists for the specified account.
     */
    boolean existsByActiveAccountId(String activeAccountId);

    /**
     * Retrieves all historical and active allowances for an account.
     */
    List<OfflineAllowance> findByAccountIdOrderByIssuedAtDesc(String accountId);
}
