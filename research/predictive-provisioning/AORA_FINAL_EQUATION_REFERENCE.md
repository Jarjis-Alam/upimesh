# AORA: Final Mathematical Equation & Implementation Reference

**Document Type:** Definitive Mathematical Specification & Equation Reference  
**Framework:** Predictive Adaptive Offline Provisioning Framework (PAOPF)  
**Algorithm:** Adaptive Offline Reserve Algorithm (AORA)  
**Target Codebase:** `research/predictive-provisioning/src/aora.py`  
**Classification:** Research Equation Reference (Non-Destructive)  
**Date:** November 2026  

---

## 1. Complete Variable & Parameter Definitions

| Symbol | Definition | Units | Default / Range | Source File Reference |
| :--- | :--- | :---: | :---: | :--- |
| $R$ | Decision variable: Offline cash reserve allocated into local escrow | INR | $[0, R_{\text{upper}}]$ | `src/aora.py:382` |
| $R_{\max}$ | Configured maximum reserve policy limit | INR | ₹2,000.00 | `src/models.py:53` |
| $B_{\text{avail}}$ | User's total available liquid bank balance | INR | ₹5,000.00 | `src/models.py:52` |
| $H$ | Planning horizon duration | hours | 24.0 h | `src/aora.py:383` |
| $T_{\text{forecast}}$ | Forecasted prospective outage duration | hours | $[0.1, H]$ | `src/aora.py:387` |
| $D_{\max}(T)$ | Conditioned prospective demand support upper bound | INR | $[\nu_{\max} T, \infty)$ | `src/aora.py:392-406` |
| $R_{\text{upper}}$ | Effective upper bound: $\min(R_{\max}, D_{\max}(T))$ | INR | $[0, R_{\max}]$ | `src/aora.py:409` |
| $c_{\text{lock}}$ | Unit capital lockup holding cost rate | $\text{h}^{-1}$ | $0.0001\text{ h}^{-1}$ | `src/config.py:27` |
| $c_{\text{exposure}}$ | Financial on-device exposure penalty weight | dimensionless | 0.05 | `src/config.py:29` |
| $c_{\text{short}}$ | Unit shortage penalty for unmet offline transaction demand | dimensionless | 2.0 | `src/config.py:28` |
| $p_{\text{robust}}$ | Outage occurrence probability upper confidence bound | dimensionless | $[0.0, 1.0]$ | `src/aora.py:124-140` |
| $\beta_D$ | Demand distribution ambiguity confidence parameter | dimensionless | 0.05 | `src/aora.py:56` |
| $\beta_p$ | Outage probability estimation significance parameter | dimensionless | 0.05 | `src/aora.py:57` |
| $\epsilon_N$ | Wasserstein-1 ambiguity radius around empirical distribution | INR | Equation (4) | `src/aora.py:168-185` |
| $\lambda$ | Dual Kantorovich multiplier for the Wasserstein constraint | dimensionless | $[0, c_{\text{short}}]$ | `src/aora.py:220-274` |
| $\tilde{d}_i$ | Regularized offline demand observation for historical blackout $i$ | INR | $\ge 0.0$ | `src/aora.py:116` |
| $N$ | Count of genuine realized historical outage events ($N = |\mathcal{H}_{\text{outage}}|$) | integer | $\ge 0$ | `src/aora.py:402` |

---

## 2. Primal Distributionally Robust Optimization (DRO) Problem

The primal reserve optimization problem minimizes the total ex-ante cost under the worst-case probability distribution $\mathbb{Q}$ within a Wasserstein-1 ball $\mathcal{B}_{\epsilon_N}(\widehat{\mathbb{P}}_N)$:

$$\min_{0 \le R \le R_{\text{upper}}} \mathcal{J}_{\text{primal}}(R) = c_{\text{lock}} R H + c_{\text{exposure}} \frac{R^2}{R_{\max}} + p_{\text{robust}} \sup_{\mathbb{Q} \in \mathcal{B}_{\epsilon_N}(\widehat{\mathbb{P}}_N)} \mathbb{E}_\mathbb{Q} \left[ c_{\text{short}} (D - R)_+ \right] \tag{1}$$

where:
- $(D - R)_+ \equiv \max(0, D - R)$ is the offline payment shortage.
- Demand support is compact: $\text{supp}(\mathbb{Q}) \subseteq [0, D_{\max}(T)]$.
- $R_{\text{upper}} = \min(R_{\max}, D_{\max}(T))$.

*Source code mapping:* [`src/aora.py:13-28`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/aora.py#L13-L28).

---

## 3. Wasserstein Ambiguity Set & Concentration Radius

The ambiguity set $\mathcal{B}_{\epsilon_N}(\widehat{\mathbb{P}}_N)$ is the ball of probability distributions centered on the empirical distribution $\widehat{\mathbb{P}}_N = \frac{1}{N} \sum_{i=1}^N \delta_{\tilde{d}_i}$:

$$\mathcal{B}_{\epsilon_N}(\widehat{\mathbb{P}}_N) = \left\{ \mathbb{Q} \in \mathcal{P}([0, D_{\max}]) : W_1(\mathbb{Q}, \widehat{\mathbb{P}}_N) \le \epsilon_N \right\} \tag{2}$$

where $W_1$ is the 1-Wasserstein (Kantorovich-Rubinstein) metric:
$$W_1(\mathbb{Q}, \widehat{\mathbb{P}}_N) = \inf_{\Pi \in \Gamma(\mathbb{Q}, \widehat{\mathbb{P}}_N)} \int_{[0, D_{\max}]^2} |\xi - \zeta| \, \Pi(d\xi, d\zeta) \tag{3}$$

### Finite-Sample Concentration Radius $\epsilon_N$
Derived from the Fournié-Houdré (2010) and Esfahani-Kuhn (2018) concentration inequalities for 1D distributions on bounded support $[0, D_{\max}]$:

$$\epsilon_N = D_{\max}(T) \cdot \sqrt{\frac{\ln(2 / \beta_D)}{2 N}} \tag{4}$$

*Source code mapping:* [`src/aora.py:177-185`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/aora.py#L177-L185).

---

## 4. Kantorovich Dual Reduction

Applying strong duality for Wasserstein distributionally robust optimization (Gao and Kleywegt, 2016; Esfahani and Kuhn, 2018), the infinite-dimensional inner supremum over distributions reduces to a finite-dimensional dual problem:

$$\sup_{\mathbb{Q} \in \mathcal{B}_{\epsilon_N}} \mathbb{E}_\mathbb{Q} \left[ c_{\text{short}} (D - R)_+ \right] = \inf_{\lambda \ge 0} \left\{ \lambda \epsilon_N + \frac{1}{N} \sum_{i=1}^N \sup_{\xi \in [0, D_{\max}]} \left[ c_{\text{short}} (\xi - R)_+ - \lambda |\xi - \tilde{d}_i| \right] \right\} \tag{5}$$

### Bounded Multiplier Property
Because the loss function $c_{\text{short}} (\xi - R)_+$ is Lipschitz continuous with constant $L = c_{\text{short}}$, any multiplier $\lambda > c_{\text{short}}$ yields an objective strictly dominated by $\lambda = c_{\text{short}}$. Hence:

$$\lambda^* \in [0, c_{\text{short}}] \tag{6}$$

*Source code mapping:* [`src/aora.py:21-25`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/aora.py#L21-L25).

---

## 5. Piecewise Evaluation of the Inner Suprema $\Omega_i(R, \lambda)$

For each sample $\tilde{d}_i \in [0, D_{\max}]$, the 1D inner supremum over $\xi \in [0, D_{\max}]$ evaluates to the maximum over three canonical critical points:
1. $\xi = 0$ (no demand): value $= 0$.
2. $\xi = \tilde{d}_i$ (demand equals historical sample): value $= c_{\text{short}} (\tilde{d}_i - R)$.
3. $\xi = D_{\max}$ (adversary pushes demand to physical maximum): value $= c_{\text{short}} (D_{\max} - R) - \lambda (D_{\max} - \tilde{d}_i)$.

$$\Omega_i(R, \lambda) \equiv \max \left\{ 0, \, c_{\text{short}}(\tilde{d}_i - R), \, c_{\text{short}}(D_{\max} - R) - \lambda(D_{\max} - \tilde{d}_i) \right\} \tag{7}$$

### Reduced 2D Master Profile Objective
Substituting (7) into (5) yields the exact 2D convex optimization problem:

$$\min_{R \in [0, R_{\text{upper}}]} \min_{\lambda \in [0, c_{\text{short}}]} \widetilde{\mathcal{J}}(R, \lambda) \equiv c_{\text{lock}} R H + c_{\text{exposure}} \frac{R^2}{R_{\max}} + p_{\text{robust}} \lambda \epsilon_N + \frac{p_{\text{robust}}}{N} \sum_{i=1}^N \Omega_i(R, \lambda) \tag{8}$$

*Source code mapping:* [`src/aora.py:192-218`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/aora.py#L192-L218).

---

## 6. Closed-Form Dual Multiplier Subgradient & 1D Bisection

For a fixed candidate reserve $R$, $\widetilde{\mathcal{J}}(R, \lambda)$ is convex and piecewise linear in $\lambda$. Its subgradient is:

$$g_\lambda(\lambda) \equiv \frac{\partial \widetilde{\mathcal{J}}}{\partial \lambda} = p_{\text{robust}} \left[ \epsilon_N - \frac{1}{N} \sum_{i \in \mathcal{A}(R, \lambda)} (D_{\max} - \tilde{d}_i) \right] \tag{9}$$

where the active set $\mathcal{A}(R, \lambda)$ contains indices where Piece 3 strictly dominates Pieces 1 and 2:
$$\mathcal{A}(R, \lambda) = \left\{ i \in \{1, \dots, N\} : c_{\text{short}}(D_{\max} - R) - \lambda(D_{\max} - \tilde{d}_i) > \max\left(0, \, c_{\text{short}}(\tilde{d}_i - R)\right) \right\} \tag{10}$$

### Bisection Solver & Tie-Breaking Rule
Because $g_\lambda(\lambda)$ is monotonically non-decreasing in $\lambda$, the optimal $\lambda^*(R)$ is determined via 1D bisection on $[0, c_{\text{short}}]$ in 18 iterations ($2^{-18} \cdot c_{\text{short}} \approx 7.6 \times 10^{-6}$ precision):
- If $g_\lambda(0) \ge 0 \implies \lambda^*(R) = 0$.
- If $g_\lambda(c_{\text{short}}) \le 0 \implies \lambda^*(R) = c_{\text{short}}$.
- If non-unique dual solutions exist (flat profile where $g_\lambda(\lambda) = 0$ on an interval $[\lambda_{\min}^*, \lambda_{\max}^*]$), bisection selects the unique deterministic lower bound $\lambda_{\min}^*$.

*Source code mapping:* [`src/aora.py:220-274`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/aora.py#L220-L274).

---

## 7. Master 1D Convex Profile Function $v(R)$

The 2D problem reduces to a 1D strictly convex profile function over $R \in [0, R_{\text{upper}}]$:

$$v(R) \equiv \widetilde{\mathcal{J}}(R, \lambda^*(R)) = \min_{\lambda \in [0, c_{\text{short}}]} \widetilde{\mathcal{J}}(R, \lambda) \tag{11}$$

$v(R)$ is minimized using 1D Golden Section Search on $[0, R_{\text{upper}}]$ with stopping tolerance $\text{tol}_R = 0.50\text{ INR}$.

*Source code mapping:* [`src/aora.py:278-361`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/aora.py#L278-L361).

---

## 8. Cold-Start Prior Formulation ($N = 0$)

When zero genuine historical blackout observations are available ($N = 0$), empirical DRO cannot form an empirical distribution. AORA provisions via the prior moments heuristic without generating synthetic empirical samples:

$$\mu_D^0 = \nu_{\text{prior}} \cdot T_{\text{prior}} = 40.0 \times 1.0 = 40.0\text{ INR} \tag{12}$$
$$\sigma_D^0 = \sigma_{\text{prior}} \cdot \sqrt{T_{\text{prior}}} = 25.0 \times \sqrt{1.0} = 25.0\text{ INR} \tag{13}$$
$$R_{\text{cold}} = \min\left( R_{\text{upper}}, \, \mu_D^0 + z_{\text{cold}} \sigma_D^0 \right) = \min\left( R_{\text{upper}}, \, 40.0 + 1.645 \times 25.0 \right) = \mathbf{\text{₹}81.13} \tag{14}$$

*Source code mapping:* [`src/aora.py:451-456`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/aora.py#L451-L456).

---

## 9. Prospective Outage Duration & Regularized Demands

### Regularized Spend Intensity Shrinkage
For each historical blackout event $i \in \{1, \dots, N\}$ with observed outage duration $T_i$ and offline spend $d_i$:

$$\tilde{\nu}_i = \frac{d_i + \alpha_0 \cdot \nu_{\text{prior}}}{T_i + \alpha_0} \quad (\text{INR/h}) \tag{15}$$

where $\alpha_0 = 0.5\text{ h}$ is the pseudo-duration Bayesian regularizer.

### Forecast-Conditioned Demand Observations
Projected onto prospective forecasted duration $T_{\text{forecast}}$:

$$\tilde{d}_i = \min\left( D_{\max}, \, \max\left(0, \, \tilde{\nu}_i \cdot T_{\text{forecast}}\right) \right) \quad (\text{INR}) \tag{16}$$

*Source code mapping:* [`src/aora.py:113-117`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/aora.py#L113-L117).

---

## 10. Robust Outage Probability Upper Bound ($p_{\text{robust}}$)

Computed as the upper confidence bound of a Bernoulli parameter using sample standard error over $M = |\mathcal{H}_{\text{history}}|$ epochs:

$$p_{\text{robust}} = \min\left( 1.0, \, \hat{p} + z_p \cdot \sqrt{\frac{\max\left(10^{-4}, \, \hat{p}(1 - \hat{p})\right)}{M + 1}} \right) \tag{17}$$

where $z_p = 1.645$ (95% one-sided quantile).

*Source code mapping:* [`src/aora.py:133-140`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/aora.py#L133-L140).

---

## 11. Theoretical Boundary Conditions

### Condition for Saturation at Configured Limit ($R^* = R_{\max}$)
Occurs when the worst-case probability mass above $R_{\max}$ exceeds the ratio of maximum marginal holding cost to marginal shortage penalty:

$$\mathbb{P}_{\mathbb{Q}^*}(D \ge R_{\max}) > \frac{c_{\text{lock}} H + \frac{2 c_{\text{exposure}} R_{\max}}{R_{\max}}}{p_{\text{robust}} c_{\text{short}}} = \frac{c_{\text{lock}} H + 2 c_{\text{exposure}}}{p_{\text{robust}} c_{\text{short}}} \tag{18}$$

Under baseline parameters ($c_{\text{lock}} H = 0.0024, c_{\text{exposure}} = 0.05, c_{\text{short}} = 2.0, p_{\text{robust}} = 0.8645$):
$$\frac{0.1024}{1.7290} \approx \mathbf{5.92\%}$$
If the worst-case distribution places $> 5.92\%$ probability mass above ₹2,000, $R^* = R_{\max} = \text{₹}2,000.00$.

### Condition for Duration Boundary Pinning ($R^* = D_{\max}(T)$)
When $T_{\text{forecast}} < 2.0\text{ h}$ and $D_{\max}(T) < R_{\max}$:

$$\left. \frac{\partial v(R)}{\partial R} \right|_{R = D_{\max}(T)^-} = c_{\text{lock}} H + \frac{2 c_{\text{exposure}} D_{\max}(T)}{R_{\max}} - p_{\text{robust}} c_{\text{short}} < 0 \tag{19}$$

Whenever this left derivative is strictly negative, $R^* = D_{\max}(T)$ identically.

---

## 12. Realized Benchmark Loss Formula

During simulation epoch $e$, realized cost is evaluated ex-post across the observed timeline:

$$\mathcal{C}_{\text{realized}}(e) = \underbrace{c_{\text{lock}} \cdot R_{\text{alloc}}(e) \cdot H}_{\text{Capital Holding Cost}} + \underbrace{c_{\text{exposure}} \cdot \frac{R_{\text{alloc}}(e)^2}{R_{\max}}}_{\text{Financial Exposure Penalty}} + \underbrace{c_{\text{short}} \cdot \text{shortage}(e)}_{\text{Realized Shortage Penalty}} \tag{20}$$

where $\text{shortage}(e) = \max\left(0, \, \text{demand}_{\text{outage}}(e) - R_{\text{alloc}}(e)\right)$. All terms evaluate strictly in **INR**.

*Source code mapping:* [`src/simulator.py:144-148`](file:///Users/munshijarjisalam/Documents/Projects/upimesh/research/predictive-provisioning/src/simulator.py#L144-L148).

---
*End of Final Mathematical Equation Reference.*

