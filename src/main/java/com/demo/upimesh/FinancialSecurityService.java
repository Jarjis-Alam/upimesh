package com.demo.upimesh;

import com.demo.upimesh.model.AccountPrincipal;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Service managing authentication and scoped access control for financial read endpoints.
 * <p>
 * Controls access to:
 * - GET /api/accounts
 * - GET /api/transactions
 * - GET /api/reconciliation
 * <p>
 * PROTOTYPE SECURITY POLICY:
 * 1. Unauthenticated requests are rejected (HTTP 401 Unauthorized).
 * 2. Authenticated users are scoped strictly to their own identity (cross-account queries rejected with HTTP 403 Forbidden).
 * 3. Reconciliation report access strictly requires administrative role (ROLE_ADMIN).
 * 4. Development simulator demo authentication is supported ONLY in non-production environments when explicitly enabled.
 * 5. Production environment strictly disables demo credentials fail-closed and enforces strong admin tokens on startup.
 */
@Service
public class FinancialSecurityService {

    private static final Logger log = LoggerFactory.getLogger(FinancialSecurityService.class);

    private static final Set<String> REJECTED_INSECURE_TOKENS = Set.of(
            "true", "false", "token", "dev-test-token", "admin", "password", "secret", "123456"
    );

    private Environment environment;

    @Value("${upimesh.demo-auth-enabled:false}")
    private boolean demoAuthEnabled = false;

    @Value("${upimesh.admin-token:${UPI_MESH_ADMIN_TOKEN:${UPIMESH_ADMIN_TOKEN:}}}")
    private String configuredAdminToken;
    private final Map<String, String> configuredUserTokens = new ConcurrentHashMap<>();

    @Autowired
    public FinancialSecurityService(@Autowired(required = false) Environment environment) {
        this.environment = environment;
    }

    public void setEnvironment(Environment environment) {
        this.environment = environment;
    }

    @PostConstruct
    public void validateSecurityConfigurationOnStartup() {
        if (isProductionEnvironment()) {
            if (isDemoAuthEnabled()) {
                throw new IllegalStateException("Production startup failed: Demo authentication cannot be enabled in production profile.");
            }
            String adminToken = getEffectiveAdminToken();
            if (adminToken == null || adminToken.isBlank()) {
                throw new IllegalStateException("Production startup failed: An explicitly configured administrative token (UPI_MESH_ADMIN_TOKEN or upimesh.admin-token) is required in production profile.");
            }
            if (REJECTED_INSECURE_TOKENS.contains(adminToken.toLowerCase()) || "demo-token-admin".equalsIgnoreCase(adminToken)) {
                throw new IllegalStateException("Production startup failed: Configured administrator token is insecure/trivial: " + adminToken);
            }
            if (adminToken.length() < 16) {
                throw new IllegalStateException("Production startup failed: Administrator token must be at least 16 characters long in production profile.");
            }
        }
    }

    public static boolean isProduction(Environment environment) {
        if (environment != null) {
            for (String profile : environment.getActiveProfiles()) {
                if ("prod".equalsIgnoreCase(profile) || "production".equalsIgnoreCase(profile)) {
                    return true;
                }
            }
        }
        String envProfile = System.getenv("SPRING_PROFILES_ACTIVE");
        if (envProfile != null) {
            for (String p : envProfile.split(",")) {
                if ("prod".equalsIgnoreCase(p.trim()) || "production".equalsIgnoreCase(p.trim())) {
                    return true;
                }
            }
        }
        return false;
    }

    public boolean isProductionEnvironment() {
        return isProduction(this.environment);
    }

    public void setDemoAuthEnabled(boolean enabled) {
        if (enabled && isProductionEnvironment()) {
            log.error("CRITICAL: Attempted to enable demo authentication in production environment! Forcing disabled.");
            this.demoAuthEnabled = false;
            return;
        }
        this.demoAuthEnabled = enabled;
    }

    public boolean isDemoAuthEnabled() {
        if (isProductionEnvironment()) {
            return false;
        }
        return this.demoAuthEnabled;
    }

    public void setConfiguredAdminToken(String token) {
        this.configuredAdminToken = token;
    }

    public void setConfiguredUserToken(String accountId, String token) {
        if (accountId != null && token != null) {
            this.configuredUserTokens.put(accountId.trim().toLowerCase(), token.trim());
        }
    }

    public void clearConfiguredUserTokens() {
        this.configuredUserTokens.clear();
    }

    private String getEffectiveAdminToken() {
        if (configuredAdminToken != null && !configuredAdminToken.isBlank()) {
            return configuredAdminToken.trim();
        }
        String env1 = System.getenv("UPI_MESH_ADMIN_TOKEN");
        if (env1 != null && !env1.isBlank()) {
            return env1.trim();
        }
        String env2 = System.getenv("UPIMESH_ADMIN_TOKEN");
        if (env2 != null && !env2.isBlank()) {
            return env2.trim();
        }
        if (environment != null) {
            String prop = environment.getProperty("upimesh.admin-token");
            if (prop != null && !prop.isBlank()) {
                return prop.trim();
            }
        }
        return null;
    }

    /**
     * Resolves an incoming request into an authenticated AccountPrincipal.
     */
    public Optional<AccountPrincipal> resolvePrincipal(String authHeader, String adminTokenHeader) {
        String token = extractToken(authHeader, adminTokenHeader);
        if (token == null || token.isBlank()) {
            return Optional.empty();
        }

        // 1. Check against administrator pairing token (constant-time)
        String adminToken = getEffectiveAdminToken();
        if (adminToken != null && !adminToken.isBlank() && !REJECTED_INSECURE_TOKENS.contains(adminToken.toLowerCase())) {
            byte[] expected = adminToken.getBytes(StandardCharsets.UTF_8);
            byte[] provided = token.getBytes(StandardCharsets.UTF_8);
            if (MessageDigest.isEqual(expected, provided)) {
                return Optional.of(new AccountPrincipal("admin", Set.of(AccountPrincipal.ROLE_ADMIN)));
            }
        }

        // 2. Check explicitly configured user tokens (constant-time)
        for (Map.Entry<String, String> entry : configuredUserTokens.entrySet()) {
            String acc = entry.getKey();
            String expectedUserToken = entry.getValue();
            if (expectedUserToken != null && !expectedUserToken.isBlank()) {
                byte[] expected = expectedUserToken.getBytes(StandardCharsets.UTF_8);
                byte[] provided = token.getBytes(StandardCharsets.UTF_8);
                if (MessageDigest.isEqual(expected, provided)) {
                    return Optional.of(new AccountPrincipal(acc, Set.of(AccountPrincipal.ROLE_USER)));
                }
            }
        }

        // 3. Controlled Development Simulator Demo Authentication
        if (isDemoAuthEnabled()) {
            Optional<AccountPrincipal> demoPrincipal = resolveDemoToken(token);
            if (demoPrincipal.isPresent()) {
                return demoPrincipal;
            }
        }

        return Optional.empty();
    }

    private Optional<AccountPrincipal> resolveDemoToken(String token) {
        String clean = token.trim();
        if (clean.startsWith("demo-token-")) {
            String target = clean.substring("demo-token-".length()).trim().toLowerCase();
            if ("admin".equalsIgnoreCase(target)) {
                return Optional.of(new AccountPrincipal("admin", Set.of(AccountPrincipal.ROLE_ADMIN)));
            }
            if (!target.isBlank()) {
                return Optional.of(new AccountPrincipal(target, Set.of(AccountPrincipal.ROLE_USER)));
            }
        } else if (clean.startsWith("demo:")) {
            String target = clean.substring("demo:".length()).trim().toLowerCase();
            if ("admin".equalsIgnoreCase(target)) {
                return Optional.of(new AccountPrincipal("admin", Set.of(AccountPrincipal.ROLE_ADMIN)));
            }
            if (!target.isBlank()) {
                return Optional.of(new AccountPrincipal(target, Set.of(AccountPrincipal.ROLE_USER)));
            }
        }
        return Optional.empty();
    }

    private String extractToken(String authHeader, String adminTokenHeader) {
        if (adminTokenHeader != null && !adminTokenHeader.isBlank()) {
            return adminTokenHeader.trim();
        }
        if (authHeader != null && !authHeader.isBlank()) {
            String trimmed = authHeader.trim();
            if (trimmed.regionMatches(true, 0, "Bearer ", 0, 7)) {
                return trimmed.substring(7).trim();
            }
            return trimmed;
        }
        return null;
    }
}
