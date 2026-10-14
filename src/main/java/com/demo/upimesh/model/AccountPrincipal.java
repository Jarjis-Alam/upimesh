package com.demo.upimesh.model;

import java.util.Collections;
import java.util.Set;

/**
 * Principal representing an authenticated user or administrator session for financial endpoints.
 */
public record AccountPrincipal(
        String name,
        Set<String> roles
) {
    public static final String ROLE_ADMIN = "ROLE_ADMIN";
    public static final String ROLE_USER = "ROLE_USER";

    public AccountPrincipal {
        roles = roles != null ? Collections.unmodifiableSet(roles) : Collections.emptySet();
    }

    public boolean isAdmin() {
        return roles.contains(ROLE_ADMIN);
    }

    public boolean canAccessAccount(String targetAccountId) {
        if (targetAccountId == null || targetAccountId.isBlank()) {
            return false;
        }
        if (isAdmin()) {
            return true;
        }
        return name != null && name.equalsIgnoreCase(targetAccountId.trim());
    }
}
