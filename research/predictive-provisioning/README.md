# Predictive Offline Payment Provisioning — Research Module

A standalone research simulation module developed for the **UPIMesh** project to model, predict, and optimize offline payment allowance reserves under non-stationary connectivity regimes and sudden outages.

---

## 1. Executive Summary & Problem Audit

In **UPIMesh**, offline peer-to-peer payments require pre-allocating an on-device cryptographic allowance voucher (`OfflineAllowanceVoucher`). Under core banking invariants (`OfflineAllowanceService.java`), allocated funds are atomically debited from the user's available balance and locked in `system-escrow` until settled or refunded.

Standard manual presets (e.g., ₹500, ₹1,000) introduce two fundamental failure modes:
1. **Idle Escrow Waste:** In reliable network environments, large reserves lock funds unnecessarily in escrow, incurring opportunity cost ($c_{\text{lock}}$) and handset exposure risk ($c_{\text{exposure}}$).
2. **Offline Payment Starvation:** In rural, non-stationary, or blackout regimes, static or under-provisioned reserves are exhausted, causing payment rejection ($c_{\text{short}}$).

### Milestone 1 Audit: Why the Initial Model Under-Reserved
Our initial Milestone 1 experiments revealed that while the naive joint-optimization formulation reduced locked funds by up to 90%, it suffered high shortage rates (up to 34%) in rural, shifting, and shock regimes. A systematic mathematical audit identified three primary root causes:

1. **Duration Variance Neglect (Jensen's Inequality Violation):**
   The initial model substituted the point estimate of outage duration $\hat{T}_{\text{out}}$ directly into compound demand variance, scaling standard deviation as $\sigma_D \approx \sigma_{\text{tx}} \sqrt{T}$. By the **Law of Total Variance**, the true compound demand variance is:
   $$\text{Var}(D_T) = \mathbb{E}[T] \cdot \text{Var}(X) + (\mathbb{E}[X])^2 \cdot \text{Var}(T)$$
   Because the second term $(\mathbb{E}[X])^2 \cdot \text{Var}(T)$ was omitted, demand standard deviation was underestimated by more than $50\%$ in high-variance regimes (e.g., $5.0 \pm 2.0\text{ hours}$ in rural areas). The optimizer believed demand was tightly concentrated around the mean, failing to cover the heavy right tail.
2. **Epistemic Uncertainty Neglect:**
   Point estimates $(\hat{p}_{\text{out}}, \hat{T}_{\text{out}}, \hat{\mu}_D)$ were treated as ground truth with zero parameter variance. In cold-start or shifting regimes, small sample sizes induce high standard error, leaving zero margin for estimation error.
3. **Adaptation Inertia During Regime Shifts:**
   Fixed EWMA memory ($\alpha = 0.20$) caused a 5–10 epoch lag when users transitioned from urban 5G to rural zones, causing repeated payment failures before the predictor adjusted.
4. **Absence of a Lifeline Safety Floor:**
   When estimated outage probability was low, the model reduced reserve to near zero. An unexpected blackout (e.g., severe grid collapse) left the user stranded with zero offline spending capacity.

---

## 2. Mathematical Influence of Objective Parameters

The allowance reserve $R$ is optimized by minimizing expected total cost:

$$J(R) = \underbrace{c_{\text{lock}} \cdot R \cdot H}_{\text{Escrow Holding Cost}} + \underbrace{p_{\text{out}} \cdot c_{\text{short}} \cdot \mathbb{E}\big[\max(D_T - R, 0)\big]}_{\text{Expected Outage Shortage Cost}} + \underbrace{c_{\text{exposure}} \cdot \text{Risk}(R)}_{\text{Handset Theft/Compromise Penalty}}$$

Subject to:

$$0 \le R \le \min(\text{available\_balance}, \text{maximum\_allowance})$$

Setting the first derivative to zero yields the generalized Newsvendor critical-fractile condition:

$$\mathbb{P}(D_T > R^*) = 1 - \Phi\left(\frac{R^* - \mu_D}{\sigma_D}\right) = \frac{c_{\text{lock}} H + \frac{2 \cdot c_{\text{exposure}} \cdot R^*}{R_{\max}}}{p_{\text{out}} \cdot c_{\text{short}}}$$

### Parameter Sensitivity Analysis:
| Parameter | Unit / Meaning | Mathematical Impact on $R^*$ | Operational Rationale |
| :--- | :--- | :--- | :--- |
| **$p_{\text{out}}$** | Probability $[0, 1]$ | $\uparrow p_{\text{out}} \implies \uparrow R^*$ | Outage likelihood scales the shortage penalty weight. If $p_{\text{out}} \to 0$, $R^* \to 0$. |
| **$\mu_D, \mu_T$** | INR, Hours | $\uparrow \mu_D \implies \uparrow R^*$ | Shifts demand distribution rightward, requiring higher reserve for stockout parity. |
| **$\sigma_D, \sigma_T$** | INR, Hours | $\uparrow \sigma_D \implies \uparrow R^*$ | Broadens the right tail; a wider demand spread requires a larger safety buffer. |
| **$c_{\text{short}}$** | Dimensionless factor | $\uparrow c_{\text{short}} \implies \uparrow R^*$ | Increases the penalty for failed payments, driving stockout probability $\mathbb{P}(D > R)$ lower. |
| **$c_{\text{lock}}$** | $\text{INR}^{-1}\cdot\text{h}^{-1}$ | $\uparrow c_{\text{lock}} \implies \downarrow R^*$ | Increases the marginal cost of locked escrow, penalizing over-provisioning. |
| **$c_{\text{exposure}}$** | Dimensionless weight | $\uparrow c_{\text{exposure}} \implies \downarrow R^*$ | Increases penalty on large handset reserves ($R^2 / R_{\max}$), preventing hoarding. |

---

## 3. Uncertainty-Aware Allocation Formulation (Milestone 2)

To resolve under-provisioning without naively locking maximum funds, we introduce four principled mechanisms:

### A. Total Compound Variance Decomposition
We apply the Law of Total Variance to model compound demand over stochastic outage durations:
$$\text{Var}(D_T) = \mu_T \cdot \sigma_X^2 + \mu_X^2 \cdot \sigma_T^2$$
$$\sigma_{D, \text{robust}} = \sqrt{\text{Var}(D_T)}$$
Where $\mu_X, \sigma_X$ are the mean and standard deviation of hourly spending, and $\mu_T, \sigma_T$ are the mean and standard deviation of outage duration.

### B. Epistemic Upper Confidence Bounds (UCB)
For confidence level $\kappa \in [0.50, 0.95]$ with standard normal quantile $z_\kappa$:
$$p_{\text{robust}} = \min\left(1.0, \; \hat{p}_{\text{out}} + z_\kappa \sqrt{\frac{\hat{p}(1 - \hat{p})}{N_{\text{eff}} + 1}}\right)$$
$$\mu_{T, \text{robust}} = \hat{\mu}_T + z_\kappa \frac{\sigma_T}{\sqrt{N_{\text{outages}}}}$$
$$\mu_{D, \text{robust}} = \mu_X \cdot \mu_{T, \text{robust}}$$

### C. Shock-Triggered Dynamic Learning Rate Adaptation
Online forecast errors are monitored using Brier scores:
$$\text{Brier}_t = (\hat{p}_t - y_t)^2$$
When sudden prediction shocks or travel regime shifts occur ($\text{Brier} > 0.35$ or demand surprise $> 2.5\times$), the learning rate $\alpha$ is dynamically boosted from $0.20$ to $0.65$, rapidly shedding obsolete pre-shift history.

### D. Bounded Adaptive Essential Safety Floor ($R_{\text{floor}}$)
To absorb sudden shocks while preserving zero idle waste in confirmed reliable networks:
$$R_{\text{floor}} = \begin{cases} 
0.0 & \text{if } p_{\text{robust}} \le 0.05 \text{ (Reliable 5G/Fiber)} \\
\min\left(0.35 \cdot R_{\max}, \; 1.5 \cdot \bar{x}_{\text{essential}} \cdot \gamma_{\text{shock}} \cdot p_{\text{robust}}\right) & \text{if } p_{\text{robust}} > 0.05 
\end{cases}$$
Where $\bar{x}_{\text{essential}}$ is the median essential transaction size (e.g. ₹50 transit/food), and $\gamma_{\text{shock}} \in [1.0, 2.5]$ is scaled by recent shock frequency.

---

## 4. Multi-Seed Empirical Benchmark Results

Evaluated across **5 independent random seeds** (`[42, 101, 2024, 777, 9999]`) $\times 60$ epochs = **300 horizons per scenario** (1,500 total evaluation days):

| Scenario | Strategy | Offline Success Rate (±std) | Insufficient Reserve Rate | Avg Locked Reserve (₹) | Avg Unused Reserve (₹) |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **Reliable Urban 5G** | Fixed-₹500 | 100.0% | 0.0% | ₹500.00 | ₹498.13 |
| | Demand-Only | 100.0% | 0.0% | ₹806.85 | ₹804.99 |
| | Proposed-JointOpt (M1) | 61.1% ± 29.5 | 23.7% | ₹45.70 | ₹44.89 |
| | **Uncertainty-Aware (M2)** | **66.2% ± 25.9** | **23.7%** | **₹54.47** | **₹53.53** |
| **Urban Metro Commute** | Fixed-₹500 | 98.8% ± 2.5 | 0.8% | ₹500.00 | ₹449.24 |
| | Demand-Only | 100.0% | 0.0% | ₹759.52 | ₹708.01 |
| | Proposed-JointOpt (M1) | 67.0% ± 6.8 | 17.6% | ₹122.46 | ₹88.13 |
| | **Uncertainty-Aware (M2)** | **75.7% ± 6.7** | **13.1%** | **₹191.88** | **₹152.90** |
| **Rural Weak Signal** | Fixed-₹500 | 98.8% ± 0.8 | 4.4% | ₹500.00 | ₹357.75 |
| | Demand-Only | 100.0% | 0.0% | ₹795.64 | ₹651.60 |
| | Proposed-JointOpt (M1) | 89.2% ± 2.8 | 19.6% | ₹334.52 | ₹206.03 |
| | **Uncertainty-Aware (M2)** | **93.7% ± 3.0** | **14.5%** | **₹384.63** | **₹249.58** |
| **Non-Stationary Travel Shift** | Fixed-₹500 | 99.4% ± 1.0 | 1.5% | ₹500.00 | ₹436.57 |
| | Demand-Only | 100.0% | 0.0% | ₹803.36 | ₹739.61 |
| | Proposed-JointOpt (M1) | 79.9% ± 7.7 | 32.1% | ₹166.86 | ₹116.13 |
| | **Uncertainty-Aware (M2)** | **87.9% ± 7.2** | **19.6%** | **₹202.96** | **₹147.06** |
| **Adversarial Grid Shock** | Fixed-₹500 | 99.2% ± 1.8 | 1.2% | ₹500.00 | ₹477.61 |
| | Demand-Only | 100.0% | 0.0% | ₹800.35 | ₹777.73 |
| | Proposed-JointOpt (M1) | 76.8% ± 15.7 | 32.1% | ₹206.87 | ₹189.98 |
| | **Uncertainty-Aware (M2)** | **88.1% ± 8.2** | **22.1%** | **₹297.82** | **₹278.11** |

---

## 5. Parameter Sensitivity Analysis

Evaluated on the difficult *Rural Weak Signal* regime:

| Parameter Swept | Value | Offline Success Rate | Insufficient Reserve Rate | Avg Locked Reserve (₹) | Avg Unused Reserve (₹) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **$c_{\text{short}}$ (Shortage Penalty)** | 1.0 | 93.2% | 19.4% | ₹388.96 | ₹234.03 |
| | 2.0 | 95.0% | 12.9% | ₹415.54 | ₹257.51 |
| | 5.0 | 96.7% | 9.7% | ₹447.54 | ₹286.74 |
| **$c_{\text{lock}}$ (Lock Cost Rate)** | $0.00002$ | 95.2% | 12.9% | ₹418.69 | ₹260.36 |
| | $0.00010$ | 95.0% | 12.9% | ₹415.54 | ₹257.51 |
| | $0.00080$ | 93.5% | 16.1% | ₹394.04 | ₹238.49 |
| **$c_{\text{exposure}}$ (Exposure Weight)** | 0.01 | 97.2% | 6.5% | ₹459.79 | ₹298.11 |
| | 0.05 | 95.0% | 12.9% | ₹415.54 | ₹257.51 |
| | 0.20 | 90.2% | 29.0% | ₹363.79 | ₹213.86 |
| **$\kappa$ (Confidence Level)** | 0.50 | 93.1% | 19.4% | ₹389.99 | ₹235.26 |
| | 0.85 | 95.0% | 12.9% | ₹415.54 | ₹257.51 |
| | 0.95 | 95.9% | 12.9% | ₹430.23 | ₹270.77 |

---

## 6. Research Taxonomy: Established vs. Potential Contributions

| Module Component | Methodological Basis | Novelty Classification |
| :--- | :--- | :--- |
| **Single-Period Fractile Optimization** | Classical Newsvendor / Inventory Control (Arrow, Harris, Marschak, 1951) | **Established Technique** |
| **Compound Variance Modeling** | Law of Total Variance (Eve's Law) for compound Poisson processes | **Established Technique** |
| **Epistemic Parameter Bounds** | Upper Confidence Bound (UCB) / Bayesian Beta-binomial updates | **Established Technique** |
| **Drift Adaptation** | Online prediction error tracking / adaptive learning rates | **Established Technique** |
| **Dual-Layer Offline Payment Escrow Provisioning** | Jointly solving double-entry escrow conservation, hardware Secure Enclave exposure bounds, and zero-connectivity stochastic payment demand | **Potential Domain Contribution** |

---

## 7. How to Run on macOS

```bash
# 1. Run all 13 unit and difficult scenario regression tests
cd research/predictive-provisioning
python3 -m unittest discover -s tests -p "test_*.py"

# 2. Run multi-seed Monte Carlo benchmark (5 seeds x 60 epochs)
python3 run_experiments.py --multi-seed --epochs 60

# 3. Run parameter sensitivity sweeps
python3 run_sensitivity.py --epochs 40

# 4. View interactive HTML dashboard
open results/report.html
```
