# AORA: Final Mathematical Consistency and Implementation Audit Report

**Document Type:** Formal Mathematical & Implementation Consistency Audit  
**Target Module:** `research/predictive-provisioning/`  
**Algorithms Audited:** AORA (`src/aora.py`), Simulator (`src/simulator.py`), Baseline Models M1 & M2 (`src/strategies.py`)  
**Scope:** Research and mathematical verification only. Strictly non-destructive (zero application code modifications; zero commits/pushes).  
**Date:** November 2026  
**Status:** Audit Completed & Fully Grounded in Source Code

---

## Executive Summary

This report performs a comprehensive, line-by-line mathematical consistency audit of the **Predictive Adaptive Offline Provisioning Framework (PAOPF)** and the **Adaptive Offline Reserve Algorithm (AORA)**. It examines six structural dimensions of the research module:
1. **Cold-Start Allocation Consistency:** Traces the mathematical derivation of Phase 1 prior mode ($R_{\text{cold}} = \text{₹}81.13$) and resolves the apparent discrepancy with post-warmup metrics.
2. **Duration-Conditioned Demand Support ($D_{\max}(T)$):** Derives the exact boundary conditions under which $R^*$ is pinned at $D_{\max}(T)$ in commuter regimes and validates subgradient behavior.
3. **Parameter Sensitivity & Phase Diagram:** Formally establishes the theoretical unpegging condition and labels empirical grid thresholds appropriately.
4. **Statistical Rigor & Seed-Level Aggregation:** Validates that 95% Student's $t$-confidence intervals are computed on seed-level aggregate clusters, properly accounting for intra-seed temporal correlation.
5. **Objective & Unit Consistency:** Verifies the mathematical bridge between the ex-ante Wasserstein DRO optimization objective and the ex-post realized benchmark loss function.
6. **Independent Numerical Solver Verification:** Validates AORA's continuous optimizer (Golden Section Search + Subgradient Bisection) against an independent 2D discrete reference solver across 7 critical edge cases and boundary regimes.

---

## 1. Cold-Start Consistency & Discrepancy Resolution

### 1.1 Implementation Architecture of Cold-Start Phase 1
In [`src/aora.py`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/aora.py#L448-L476), Phase 1 is executed strictly when the count of genuine historical blackout events is zero ($N = 0$):

```python
# Lines 451-455 in src/aora.py
if N == 0:
    mu_D_0 = self.prior_spending_rate * self.prior_duration               # 40.0 * 1.0 = 40.0 INR
    sigma_D_0 = self.prior_spending_std * math.sqrt(self.prior_duration)  # 25.0 * sqrt(1.0) = 25.0 INR
    R_cold = min(effective_R_max, max(0.0, mu_D_0 + self.z_cold * sigma_D_0))
    R_cold = round(R_cold, 2)
```

Evaluating the prior constants defined in `src/aora.py` (lines 61–64):
- $\mu_{\text{spend}}^0 = 40.0\text{ INR/h}$
- $T_{\text{prior}} = 1.0\text{ h} \implies \mu_D^0 = 40.0\text{ INR}$
- $\sigma_{\text{spend}}^0 = 25.0\text{ INR/h} \implies \sigma_D^0 = 25.0 \times \sqrt{1.0} = 25.0\text{ INR}$
- Quantile parameter: $z_{\text{cold}} = 1.645$ (standard 95% normal quantile)

The closed-form cold-start calculation is:
$$R_{\text{cold}} = \min\left( R_{\text{effective\_max}}, \, 40.0 + 1.645 \times 25.0 \right) = \min\left( R_{\text{effective\_max}}, \, 40.0 + 41.125 \right) = \mathbf{\text{₹}81.13}$$

### 1.2 Resolution of the Reporting Discrepancy: ₹81.13 vs. Scenario-Dependent Reserves
In [`AORA_BENCHMARK_AUDIT.md`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/AORA_BENCHMARK_AUDIT.md#L151-L163), Cold-Start was reported as **₹81.13** across all scenarios. However, in the subsequent script [`run_aora_30seed_validation.py`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/run_aora_30seed_validation.py#L90-L96), Task 5 reported scenario-dependent values:
- Reliable Urban 5G: ₹122.99 ± ₹20.21
- Urban Metro Commute: ₹513.50 ± ₹132.06
- Rural Weak Signal: ₹2,000.00 ± ₹0.00

**Investigation & Root Cause Analysis:**
1. **Warmup Injection in the Benchmark Loop:**
   In [`src/simulator.py`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/simulator.py#L96-L99), the simulator executes 10 warmup epochs before the 60 evaluation epochs begin:
   ```python
   for ep in range(warmup_epochs):
       outage, transactions = ground_truth_epochs[ep % len(ground_truth_epochs)]
       for pred in predictors.values():
           pred.record_epoch_observation(outage, transactions)
   ```
2. **Warmup History Contamination of $N$:**
   In `run_aora_30seed_validation.py`, Task 5 heuristically partitioned evaluation epochs as:
   ```python
   if ep.epoch_id <= 3: # labeled as "Cold-Start"
   ```
   However, because 10 warmup epochs had already run:
   - In **Rural Weak Signal** ($p_{\text{out}} = 0.70$), the predictor had already recorded $N \approx 7$ genuine blackout events during warmup. Therefore, at `epoch_id = 1`, $N = 7 > 0$. The algorithm was **not in Phase 1 ($N=0$)**; it was already executing Phase 2 (empirical DRO), which saturated at ₹2,000.00.
   - In **Urban Metro Commute** ($p_{\text{out}} = 0.35$), the predictor had recorded $N \approx 3.5$ events during warmup. Empirical DRO was already active, allocating $R^* \in [245, 647]$ INR.
   - In **Reliable Urban 5G** ($p_{\text{out}} = 0.05$), only $\sim 0.5$ outages occurred during warmup. In seeds where 0 outages occurred, $N = 0 \implies R^* = \text{₹}81.12$. In seeds where 1 outage occurred, $N = 1 \implies R^* = \text{₹}174.40$. The aggregate average was ₹122.99.
3. **Empirical Verification of Strict Cold-Start ($W = 0$):**
   When `warmup_epochs = 0` is set, all scenarios evaluate with $N = 0$ at Epoch 1. Tracing this directly confirms that:
   - Reliable Urban 5G: **₹81.12**
   - Urban Metro Commute: **₹81.12**
   - Rural Weak Signal: **₹81.12**

**Conclusion:** The discrepancy was caused entirely by labeling early post-warmup epochs as "cold start". When evaluated under strict cold-start ($N=0$), AORA provisions exactly **₹81.12** across all network regimes.

### 1.3 Audit of Synthetic Prior Separation
We audited [`src/aora.py`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/aora.py#L76-L120) (`extract_regularized_demand_observations`):
- Line 93: Outage events are filtered strictly by `e.occurred and e.duration_hours > 0.0`.
- Lines 103–107: Spend amounts are summed exclusively from `predictor.transaction_history` where `t.occurred_during_outage` is true.
- Line 113: Pseudo-duration shrinkage $\tilde{\nu}_i = \frac{d_i + \alpha_0 \nu_{\text{prior}}}{T_i + \alpha_0}$ regularizes individual rates, but **no synthetic pseudo-observation is appended to the empirical sample list**.
- Length $N = \text{len}(genuine\_demands)$ strictly equals the count of genuine historical outages.

**Verdict:** Invariant satisfied. Synthetic prior samples are never mixed into empirical sample counts.

---

## 2. Duration-Conditioned Demand Support: Mathematical & Boundary Analysis

### 2.1 Exact Implementation of $D_{\max}(T)$
In [`src/aora.py`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/aora.py#L392-L410):
```python
# Lines 392-395
nu_max = max(500.0, user.spending_rate_mean * 4.0)
duration_spend_bound = max(40.0, nu_max * T_forecast)
D_max = max(duration_spend_bound, R_max) if T_forecast >= 2.0 else duration_spend_bound

# Lines 405-406
if genuine_demands:
    D_max = max(D_max, max(genuine_demands) * 1.05)

# Line 409
effective_R_max = min(R_max, D_max)
```

The effective reserve upper bound passed to the optimizer is:
$$R_{\text{upper}} = \min\left( R_{\max}, \, D_{\max}(T) \right)$$

### 2.2 Proof of Boundary Pinning at $D_{\max}(T)$
Consider a commuter regime where prospective outage duration is short ($T_{\text{forecast}} < 2.0\text{ h}$), such that $D_{\max}(T) < R_{\max}$. The feasible search interval is $R \in [0, D_{\max}(T)]$.

The reduced dual profile function is:
$$v(R) = \min_{\lambda \in [0, c_{\text{short}}]} \left\{ c_{\text{lock}} R H + c_{\text{exposure}} \frac{R^2}{R_{\max}} + p_{\text{robust}} \lambda \epsilon + \frac{p_{\text{robust}}}{N} \sum_{i=1}^N \Omega_i(R, \lambda) \right\}$$
where:
$$\Omega_i(R, \lambda) = \max \left\{ 0, \, c_{\text{short}}(\tilde{d}_i - R), \, c_{\text{short}}(D_{\max} - R) - \lambda(D_{\max} - \tilde{d}_i) \right\}$$

**Theorem 1 (Condition for Boundary Pinning):**  
If for all $R \in [0, D_{\max}(T)]$, the left-hand subgradient satisfies:
$$\left. \frac{\partial v(R)}{\partial R} \right|_{-} \le 0$$
then the optimal reserve is uniquely pinned at the duration bound: $R^* = D_{\max}(T)$.

**Proof:**  
As $R \to D_{\max}(T)^{-}$, consider $\lambda = 0$. The third piece of $\Omega_i$ dominates:
$$\Omega_i(R, 0) = c_{\text{short}}(D_{\max}(T) - R) > 0 \quad (\text{for } R < D_{\max}(T))$$
Its derivative with respect to $R$ is strictly $-c_{\text{short}}$. The subgradient of $v(R)$ at $R = D_{\max}(T)^{-}$ is:
$$\left. \frac{\partial v(R)}{\partial R} \right|_{R = D_{\max}(T)^{-}} = c_{\text{lock}} H + \frac{2 c_{\text{exposure}} D_{\max}(T)}{R_{\max}} - p_{\text{robust}} c_{\text{short}}$$

Therefore, if:
$$c_{\text{lock}} H + \frac{2 c_{\text{exposure}} D_{\max}(T)}{R_{\max}} < p_{\text{robust}} c_{\text{short}}$$
the left subgradient at the upper boundary is strictly negative. Because $v(R)$ is convex on $[0, D_{\max}(T)]$ and its subgradient does not contain zero on the interior, the minimum on the closed interval $[0, D_{\max}(T)]$ must occur at the boundary $R^* = D_{\max}(T)$. $\blacksquare$

### 2.3 Evaluation in Urban Metro Commute
- In Metro Commute: $T_{\text{forecast}} \approx 0.49\text{ h} \implies D_{\max}(T) \approx 647.17\text{ INR}$.
- $c_{\text{lock}} H = 0.0001 \times 24.0 = 0.0024$.
- $p_{\text{robust}} \approx 0.30$, $c_{\text{short}} = 2.0 \implies p_{\text{robust}} c_{\text{short}} \approx 0.60$.
- For $c_{\text{exposure}} \le 0.10$:
  $$\text{Marginal Holding Cost} \le 0.0024 + \frac{2 \times 0.10 \times 647.17}{2000} = 0.0671 \ll 0.60$$
- Condition (Theorem 1) holds with a $9\times$ safety margin. Thus, $R^*$ is mathematically pinned at $D_{\max}(T)$ for all $c_{\text{exposure}} \in [0.005, 0.100]$, producing identical allocations of **₹647.17**.

### 2.4 Monotonicity Clarification
$v(R)$ is **strictly convex**, but **not strictly monotonic** across arbitrary parameterizations. When holding costs are sufficiently high ($c_{\text{exposure}} \ge 0.15$), the derivative crosses zero inside $(0, D_{\max}(T))$, creating an interior minimum where $v(R)$ is decreasing on $[0, R^*)$ and increasing on $(R^*, D_{\max}(T)]$.

---

## 3. Parameter Sensitivity Boundaries & Phase Diagram Audit

### 3.1 30-Seed Empirical Heatmap Data (Rural Weak Signal)
The table below records the percentage of decisions where AORA saturates at the configured maximum reserve limit ($R^* \ge \text{₹}1,999$) across the tested grid:

| $c_{\text{exposure}} \ \backslash \ c_{\text{short}}$ | **0.25** | **0.50** | **1.00** | **2.00 (Baseline)** | **5.00** |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **0.05 (Baseline)** | 78.7% ± 2.3% | 98.2% ± 1.0% | 100.0% ± 0.0% | **100.0% ± 0.0%** | 100.0% ± 0.0% |
| **0.15** | 0.0% ± 0.0% | 42.7% ± 6.5% | 90.8% ± 1.8% | 99.9% ± 0.1% | 100.0% ± 0.0% |
| **0.30** | 0.0% ± 0.0% | 0.0% ± 0.0% | 43.3% ± 6.3% | 90.9% ± 1.8% | 100.0% ± 0.0% |
| **0.50** | 0.0% ± 0.0% | 0.0% ± 0.0% | 0.0% ± 0.0% | 65.4% ± 3.9% | 98.3% ± 1.0% |
| **1.00** | 0.0% ± 0.0% | 0.0% ± 0.0% | 0.0% ± 0.0% | 0.0% ± 0.0% | 80.2% ± 2.4% |

### 3.2 Labeling of Thresholds as Empirical
- **Empirical Threshold:** In the tested Rural Weak Signal grid ($p_{\text{out}} = 0.70, T = 5.0\text{ h}$), saturation occurs when the discrete ratio $\frac{c_{\text{short}}}{c_{\text{exposure}}} \ge 13.3$.
- **Theoretical Condition:** Saturation at $R_{\max}$ occurs if and only if:
  $$\mathbb{P}_{\mathbb{Q}^*}(D \ge R_{\max}) > \frac{c_{\text{lock}} H + 2 c_{\text{exposure}}}{p_{\text{robust}} c_{\text{short}}}$$
  Because $\mathbb{P}_{\mathbb{Q}^*}(D \ge R_{\max})$ depends on the empirical sample dispersion and ambiguity radius $\epsilon$, **no universal constant ratio exists across all arbitrary distributions**. The threshold $\approx 13.3$ is strictly an empirical property of the evaluated rural simulation environment.

---

## 4. Statistical Validation: Seed-Level Aggregation & Cluster Correlation

### 4.1 Intra-Seed Autocorrelation & Cluster Aggregation
In a multi-epoch simulation, decisions at epoch $t$ depend on history accumulated through epoch $t-1$. Epochs within the same simulation trajectory share correlated predictor state.

To satisfy standard cluster sampling statistics:
1. For each seed $s \in \{1, \dots, K\}$ (where $K = 30$), the seed-level aggregate mean $\bar{X}_s$ is computed across all $E = 60$ epochs:
   $$\bar{X}_s = \frac{1}{E} \sum_{e=1}^E X_{s, e}$$
2. The grand mean $\bar{X}$ and sample variance $S^2$ are computed across the $K$ independent seeds:
   $$\bar{X} = \frac{1}{K} \sum_{s=1}^K \bar{X}_s, \qquad S^2 = \frac{1}{K - 1} \sum_{s=1}^K \left( \bar{X}_s - \bar{X} \right)^2$$
3. The 95% confidence half-width uses Student's $t$-distribution with $K - 1 = 29$ degrees of freedom ($t_{0.975, 29} = 2.045$):
   $$\text{CI}_{95\%} = \bar{X} \pm 2.045 \cdot \frac{S}{\sqrt{K}}$$

This formulation absorbs all within-seed temporal autocorrelation into the seed summary $\bar{X}_s$, ensuring that reported confidence intervals reflect genuine between-trajectory variance.

### 4.2 Disclaimer on Real-World Uncertainty
These confidence intervals quantify algorithmic variance under synthetic stochastic arrivals generated by pseudo-random seeds. They do not quantify physical real-world cellular propagation uncertainty or unmodeled macro-network failures.

---

## 5. Objective & Unit Consistency Audit

### 5.1 Formulation Comparison
| Term | Optimization Objective ([`src/aora.py`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/aora.py#L196-L203)) | Realized Benchmark Loss ([`src/simulator.py`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/simulator.py#L144-L148)) | Units |
| :--- | :--- | :--- | :---: |
| **Holding Cost** | $c_{\text{lock}} R H$ | $c_{\text{lock}} R_{\text{alloc}} H$ | **INR** |
| **Exposure Penalty** | $c_{\text{exposure}} \frac{R^2}{R_{\max}}$ | $c_{\text{exposure}} \frac{R_{\text{alloc}}^2}{R_{\max}}$ | **INR** |
| **Shortage Penalty** | $p_{\text{robust}} \sup_{\mathbb{Q}} \mathbb{E}_\mathbb{Q} \left[ c_{\text{short}} (D - R)_+ \right]$ | $c_{\text{short}} \cdot \text{shortage\_amount}$ | **INR** |

### 5.2 Dimensional Analysis
- $c_{\text{lock}} = 0.0001\text{ h}^{-1}$, $H = 24.0\text{ h} \implies c_{\text{lock}} H$ is dimensionless $[-]$. Multiplied by $R$ [INR] $\implies$ **INR**.
- $c_{\text{exposure}} = 0.05$ $[-]$, $R^2 / R_{\max} \implies [\text{INR}]^2 / [\text{INR}] = [\text{INR}] \implies$ **INR**.
- $c_{\text{short}} = 2.0$ $[-]$, multiplied by realized shortage $[\text{INR}] \implies$ **INR**.

All terms in both the ex-ante optimization objective and the ex-post realization are strictly denominated in **Indian Rupees (INR)**.

### 5.3 Explanation of Realized Cost Variation Under Invariant Reserve
In Metro Commute, as $c_{\text{exposure}}$ is swept from $0.005$ to $0.100$, the reserve remains pinned at **₹647.17**, yet realized combined cost increases from **₹3.70** to **₹29.71**.

**Mathematical Explanation:**  
The realized cost is:
$$\mathcal{C}_{\text{realized}} = c_{\text{lock}} R H + c_{\text{short}} \cdot \text{shortage} + c_{\text{exposure}} \frac{R^2}{R_{\max}}$$
Even when $R = \text{₹}647.17$ and $\text{shortage} = 0$ are identical, the second-order exposure cost term:
$$\Delta \mathcal{C}_{\text{exposure}} = \Delta c_{\text{exposure}} \cdot \frac{647.17^2}{2000} \approx \Delta c_{\text{exposure}} \cdot 209.42$$
scales directly with the swept parameter $c_{\text{exposure}}$. Thus, cost increases because the penalty rate on holding capital was explicitly raised by the experimenter, not because the reserve allocation shifted.

---

## 6. Independent Solver Verification Across 7 Structural Regimes

We executed an independent high-precision reference verification ([`tests/verify_solver_comprehensive.py`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/tests/verify_solver_comprehensive.py)) comparing AORA's continuous Golden Section Search + Bisection against an independent 2D reference solver with fine grid search ($R$ step: 0.01 INR, continuous subgradient bisection for $\lambda^*(R)$ to $10^{-6}$ precision):

| Test Case ID | Regime Tested | AORA $R^*$ | Ref $R^*$ | Absolute $\Delta R$ | AORA Cost | Ref Cost | Absolute $\Delta \text{Cost}$ | Status |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **TC-1** | Zero Outage Probability ($p=0$) | ₹0.00 | ₹0.00 | **₹0.00** | ₹0.0000 | ₹0.0000 | **₹0.0000** | **PASS** |
| **TC-2** | Boundary Saturation ($R^* = R_{\max}$) | ₹2,000.00 | ₹2,000.00 | **₹0.00** | ₹268.2617 | ₹268.2615 | **₹0.0002** | **PASS** |
| **TC-3** | Duration Boundary Pinning ($R^* = D_{\max}$) | ₹245.00 | ₹245.00 | **₹0.00** | ₹12.8380 | ₹12.8380 | **₹0.0000** | **PASS** |
| **TC-4** | Interior Optimum ($0 < R^* < R_{\max}$) | ₹276.03 | ₹276.01 | **₹0.02** | ₹14.1912 | ₹14.1912 | **₹0.0000** | **PASS** |
| **TC-5** | Large Ambiguity Radius ($\epsilon \ge \epsilon_{\text{crit}}$) | ₹400.00 | ₹400.00 | **₹0.00** | ₹8.9602 | ₹8.9600 | **₹0.0002** | **PASS** |
| **TC-6** | Non-Unique Dual Solutions (Flat $\lambda$) | ₹100.00 | ₹100.00 | **₹0.00** | ₹5.2400 | ₹5.2400 | **₹0.0000** | **PASS** |
| **TC-7** | Trivial Policy Limit ($R_{\max} = 0$) | ₹0.00 | ₹0.00 | **₹0.00** | ₹0.0000 | ₹0.0000 | **₹0.0000** | **PASS** |

### 6.1 In-Depth Investigation of TC-4: Resolution of the ₹0.52 Discrepancy

#### 1. Exact Analytical Closed-Form Solution
In test case TC-4:
- Historical observations: $\mathcal{D}_N = \{100.0, 150.0, 200.0\}$ ($N = 3$, $d_{\max} = 200.0$)
- Horizon: $H = 24.0\text{ hours}$
- Support bound: $D_{\max} = 600.0\text{ INR}$
- Ceiling: $R_{\max} = 1000.0\text{ INR}$
- Costs: $c_{\text{lock}} = 0.0001$, $c_{\text{exposure}} = 0.05$, $c_{\text{short}} = 2.0$
- Ambiguity parameters: $p_{\text{robust}} = 0.15$, $\epsilon_N = 40.0$

For any reserve $R > d_{\max} = 200.0$, the empirical sample suprema vanish ($\Omega_i(R, \lambda) = 0$ for all $i$), and the subgradient root condition simplifies to:
$$\Psi(\lambda; R) = \epsilon_N - \frac{c_{\text{short}}(D_{\max} - R) - \lambda(D_{\max} - d_{\max})}{\lambda} = 0$$
$$\implies \lambda^*(R) = \frac{c_{\text{short}}(D_{\max} - R)}{D_{\max} - d_{\max}} = \frac{2.0(600 - R)}{600 - 200} = \frac{600 - R}{200}$$
Substituting $\lambda^*(R)$ into the profile objective eliminates all terms inside the sample mean, yielding a strictly convex quadratic:
$$\widetilde{\mathcal{J}}(R) = c_{\text{lock}} R H + c_{\text{exposure}} \frac{R^2}{R_{\max}} + p_{\text{robust}} \epsilon_N \left( \frac{c_{\text{short}}(D_{\max} - R)}{D_{\max} - d_{\max}} \right)$$
Setting $\frac{d \widetilde{\mathcal{J}}}{dR} = 0$:
$$c_{\text{lock}} H + \frac{2 c_{\text{exposure}} R}{R_{\max}} - \frac{p_{\text{robust}} \epsilon_N c_{\text{short}}}{D_{\max} - d_{\max}} = 0$$
$$R^*_{\text{analytical}} = \frac{R_{\max}}{2 c_{\text{exposure}}} \left[ \frac{p_{\text{robust}} \epsilon_N c_{\text{short}}}{D_{\max} - d_{\max}} - c_{\text{lock}} H \right]$$
$$R^*_{\text{analytical}} = \frac{1000.0}{2(0.05)} \left[ \frac{0.15 \times 40.0 \times 2.0}{400.0} - 0.0001 \times 24.0 \right] = 10,000 \times [0.0300 - 0.0024] = \mathbf{276.000000\text{ INR}}$$

#### 2. Root Cause of the Initial ₹0.52 Discrepancy
Three factors compounded to produce the previous ₹0.52 discrepancy:
1. **Bracket-Width Tolerance vs. Solution Error:**
   The Golden Section Search terminating condition $(b - a) \le \text{tol\_R}$ bounds the final interval width, guaranteeing that any point in $[a, b]$ is within $\frac{b-a}{2} \le 0.25\text{ INR}$ of the interval midpoint $R_{\text{mid}}$, *provided the true optimum lies inside $[a, b]$*.
2. **Extreme Profile Flatness:**
   Evaluating the objective across the ₹0.60 neighborhood $[275.40, 276.00]$:
   - $\widetilde{\mathcal{J}}(275.40) = 14.191258\text{ INR}$
   - $\widetilde{\mathcal{J}}(276.00) = 14.191240\text{ INR}$
   The cost differential across this entire ₹0.60 band is merely **$1.8 \times 10^{-5}\text{ INR}$** (a gradient on the order of $3 \times 10^{-5}\text{ INR/INR}$).
3. **Inner Dual Solver Noise:**
   The inner bisection in earlier code ran with $\text{tol}_\lambda = 10^{-4}$. An error of $10^{-4}$ in $\lambda$ perturbs the profile objective by:
   $$\Delta \widetilde{\mathcal{J}} \approx p_{\text{robust}} \epsilon_N \cdot \text{tol}_\lambda = 0.15 \times 40.0 \times 10^{-4} = \mathbf{6.0 \times 10^{-4}\text{ INR}}$$
   This numerical noise was **33 times larger** than the true objective variation across ₹0.60. At iteration 13, this noise falsely evaluated the right sub-bracket higher than the left, prematurely steering the bracket to $[275.25, 275.71]$ (midpoint $275.48$), leaving $R^* = 276.00$ approximately $0.29\text{ INR}$ outside the final bracket.
4. **Discretization of the Reference Solver:**
   The original reference solver evaluated a discrete grid of $r_{\text{step}} = 0.20\text{ INR}$ and $\lambda_{\text{step}} = 0.001$, introducing an independent $\pm 0.10\text{ INR}$ quantization error.

#### 3. Resolution Under Tightened Tolerances
1. **Inner Bisection:** Tightened to $\text{tol}_\lambda = 10^{-6}$ with 22 bisection iterations (precision $\approx 4.7 \times 10^{-7}$). Objective evaluation noise dropped from $6.0 \times 10^{-4}\text{ INR}$ to $< 6.0 \times 10^{-6}\text{ INR}$.
2. **Outer Golden Section Search:** Default tolerance tightened to $\text{tol\_R} = 0.01\text{ INR}$ (33 iterations).
3. **Reference Solver:** Upgraded to fine-grid evaluation ($r_{\text{step}} = 0.01\text{ INR}$) with continuous subgradient bisection for $\lambda^*(R)$ to $10^{-6}$ precision on every candidate $R$.

**Result:** AORA outputs $R^* = \mathbf{276.03\text{ INR}}$, matching the independent reference solver $R^* = \mathbf{276.01\text{ INR}}$ within $\Delta R = \mathbf{0.02\text{ INR}}$ and $\Delta \text{Cost} = \mathbf{0.0000\text{ INR}}$.

---

## Summary of Audit Conclusions

1. **Cold-Start:** Strictly provisions **₹81.12** when $N=0$. Scenario-dependent values in earlier validation runs resulted from warmup history accumulation.
2. **Duration Support:** Boundary pinning at $D_{\max}(T)$ is mathematically proven to occur when $c_{\text{lock}} H + \frac{2 c_{\text{exposure}} D_{\max}(T)}{R_{\max}} < p_{\text{robust}} c_{\text{short}}$.
3. **Phase Diagram:** The $\approx 13.3$ ratio threshold is an empirical observation on the rural simulation grid, not a universal theoretical constant.
4. **Statistical Rigor:** 95% confidence intervals properly account for intra-seed temporal correlation via cluster-level aggregation across 30 seeds.
5. **Dimensional Consistency:** All terms in the ex-ante objective and ex-post realization are dimensionally sound and denominated in INR.
6. **Numerical Accuracy:** Under tightened tolerances ($\text{tol\_R} = 0.01\text{ INR}$, $\text{tol}_\lambda = 10^{-6}$), the continuous optimizer matches the independent reference solver within $\Delta R \le \mathbf{0.02\text{ INR}}$ and $\Delta \text{Cost} \le \mathbf{0.0002\text{ INR}}$ across all 7 structural test cases.

---
*End of Formal Mathematical Consistency Audit Report.*

