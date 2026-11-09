"""
AORA: Adaptive Offline Reserve Algorithm (Experimental Research Strategy).

Distributionally Robust Optimization (DRO) using Wasserstein Ambiguity Sets.
Formulated, validated, and reviewed in:
- AORA_RESEARCH_DESIGN.md
- AORA_MATHEMATICAL_FORMULATION.md
- AORA_MATHEMATICAL_VALIDATION.md
- AORA_FINAL_MATHEMATICAL_REVIEW.md
- AORA_PRE_IMPLEMENTATION_SPEC.md
- AORA_FINAL_CORRECTIONS.md

Mathematical Core:
  Minimizes total expected cost under the worst-case probability distribution
  lying within a Wasserstein-1 ambiguity ball around genuine historical observations:

    min_{R, lambda, s}  c_lock * R * H + c_exposure * (R^2 / R_max) + p_robust * (lambda * epsilon + (1/N) * sum_{i=1}^N s_i)

    subject to:
      0 <= R <= R_max
      0 <= lambda <= c_short
      s_i >= 0,                                                                   forall i
      s_i + c_short * R >= c_short * d_tilde_i,                                  forall i
      s_i + c_short * R + (D_max - d_tilde_i) * lambda >= c_short * D_max,       forall i

Safety Boundary:
  Strictly experimental research module. Does not modify M1, M2, or application logic.
"""

import math
from typing import List, Optional, Tuple

from .config import ProvisioningConfig
from .models import AllocationDecision, UserProfile
from .predictor import OutageAndDemandPredictor
from .strategies import BaseProvisioningStrategy


class AORAStrategy(BaseProvisioningStrategy):
    """
    Adaptive Offline Reserve Algorithm (AORA) using Wasserstein DRO.

    Solves the offline reserve allocation problem under non-parametric distributionally
    robust optimization without assuming Gaussian payment demand.
    """

    def __init__(
        self,
        name: str = "AORA-DRO",
        confidence_level_demand: float = 0.95,
        confidence_level_outage: float = 0.95,
        pseudo_duration_regularizer: float = 0.5,
        c_lock: Optional[float] = None,
        c_short: Optional[float] = None,
        c_exposure: Optional[float] = None,
        config: ProvisioningConfig = ProvisioningConfig(),
    ):
        super().__init__(name=name, config=config)
        self.c_lock = c_lock if c_lock is not None else config.default_c_lock
        self.c_short = c_short if c_short is not None else config.default_c_short
        self.c_exposure = c_exposure if c_exposure is not None else config.default_c_exposure
        self.beta_D = max(1e-4, min(0.50, 1.0 - confidence_level_demand))
        self.beta_p = max(1e-4, min(0.50, 1.0 - confidence_level_outage))
        self.alpha_0 = pseudo_duration_regularizer  # hours

        # Prior distribution parameters for cold-start (sourced from config/models)
        self.prior_spending_rate = 40.0  # INR/hour
        self.prior_duration = 1.0        # hours
        self.prior_spending_std = 25.0   # INR/hour
        self.z_cold = 1.645              # 95% normal quantile for cold-start heuristic
        self.z_p = 1.645                 # 95% normal quantile for Bernoulli UCB

    # =========================================================================
    # 1. Genuine Observation Extraction & Duration Regularization
    # =========================================================================
    def extract_regularized_demand_observations(
        self,
        predictor: OutageAndDemandPredictor,
        T_forecast: float,
        D_max: float,
    ) -> List[float]:
        """
        Extracts genuine realized outage spending observations from predictor memory.
        Applies pseudo-duration Bayesian shrinkage to regularize spending rate estimates:

            tilde_nu_i = (d_hat_i + alpha_0 * nu_prior) / (T_i + alpha_0)
            d_tilde_i  = min(D_max, max(0.0, tilde_nu_i * T_forecast))

        Synthetic pseudo-observations are NEVER injected into this list.
        """
        genuine_demands: List[float] = []

        outage_events = [e for e in predictor.outage_history if e.occurred and e.duration_hours > 0.0]

        if not outage_events or not predictor.transaction_history:
            return []

        for ev in outage_events:
            ev_start = ev.start_hour
            ev_end = ev.start_hour + ev.duration_hours
            T_i = max(0.01, ev.duration_hours)

            spent_in_outage = sum(
                t.amount
                for t in predictor.transaction_history
                if t.occurred_during_outage and (ev_start <= t.timestamp_hour <= ev_end)
            )

            if spent_in_outage == 0.0 and len(outage_events) == 1:
                spent_in_outage = sum(t.amount for t in predictor.transaction_history if t.occurred_during_outage)

            # Regularized spending intensity (INR / hour)
            tilde_nu_i = (spent_in_outage + self.alpha_0 * self.prior_spending_rate) / (T_i + self.alpha_0)

            # Projected demand for prospective forecasted duration (INR)
            d_tilde_i = min(D_max, max(0.0, tilde_nu_i * T_forecast))
            genuine_demands.append(round(d_tilde_i, 2))

        return genuine_demands

    # =========================================================================
    # 2. Outage Probability Upper Confidence Bound (p_robust)
    # =========================================================================
    def compute_robust_outage_probability(
        self,
        predictor: OutageAndDemandPredictor,
    ) -> float:
        """
        Computes the upper confidence bound p_robust on outage occurrence probability:
            p_robust = min(1.0, p_hat + z_p * se_p)
        Where se_p = sqrt(max(1e-4, p_hat * (1 - p_hat)) / (M + 1)).
        """
        p_hat = predictor.estimate_outage_probability()
        M = max(1, len(predictor.outage_history))

        # Standard error of Bernoulli trial
        var_p = max(1e-4, p_hat * (1.0 - p_hat))
        se_p = math.sqrt(var_p / (float(M) + 1.0))
        p_robust = min(1.0, max(0.0, p_hat + self.z_p * se_p))
        return round(p_robust, 4)

    # =========================================================================
    # 3. Wasserstein Ambiguity Radius (epsilon_N)
    # =========================================================================
    def compute_wasserstein_radius(
        self,
        N: int,
        D_max: float,
    ) -> float:
        """
        Computes the exact finite-sample 1-Wasserstein ambiguity radius:
            epsilon_N(beta) = (D_max / sqrt(N)) * (1/2 + sqrt(ln(1 / beta_D) / 2))
        Derived from McDiarmid's concentration inequality and Jensen's inequality
        on Binomial variance for 1D distributions on [0, D_max].
        """
        if N <= 0:
            return 0.0

        factor = 0.5 + math.sqrt(0.5 * math.log(1.0 / self.beta_D))
        epsilon = (D_max / math.sqrt(float(N))) * factor
        return round(epsilon, 2)

    # =========================================================================
    # 4. Exact Inner Supremum & Objective Evaluation
    # =========================================================================
    @staticmethod
    def evaluate_inner_supremum(
        R: float,
        lambda_val: float,
        d_tilde: float,
        D_max: float,
        c_short: float,
    ) -> float:
        """
        Evaluates the exact closed-form inner supremum:
            Omega_i(R, lambda) = max{ 0,
                                      c_short * (d_tilde_i - R),
                                      c_short * (D_max - R) - lambda * (D_max - d_tilde_i) }
        """
        piece1 = 0.0
        piece2 = c_short * (d_tilde - R)
        piece3 = c_short * (D_max - R) - lambda_val * (D_max - d_tilde)
        return max(piece1, piece2, piece3)

    def evaluate_profile_objective(
        self,
        R: float,
        lambda_val: float,
        genuine_demands: List[float],
        D_max: float,
        H: float,
        p_robust: float,
        epsilon: float,
        R_max: float,
    ) -> float:
        """
        Evaluates the reduced 2D profile objective J_tilde(R, lambda):
            J_tilde(R, lambda) = c_lock * R * H + c_exposure * (R^2 / R_max)
                                + p_robust * lambda * epsilon
                                + (p_robust / N) * sum_{i=1}^N Omega_i(R, lambda)
        """
        c_lock = self.c_lock
        c_exposure = self.c_exposure
        c_short = self.c_short

        holding_cost = c_lock * R * H
        exposure_cost = c_exposure * (R * R) / max(1.0, R_max)
        uncertainty_cost = p_robust * lambda_val * epsilon

        if genuine_demands:
            sum_suprema = sum(
                self.evaluate_inner_supremum(R, lambda_val, d, D_max, c_short)
                for d in genuine_demands
            )
            shortage_cost = (p_robust / float(len(genuine_demands))) * sum_suprema
        else:
            shortage_cost = 0.0

        return holding_cost + exposure_cost + uncertainty_cost + shortage_cost

    # =========================================================================
    # 5. Dual Subgradient Bisection for Optimal Lambda(R)
    # =========================================================================
    def optimize_lambda_for_fixed_R(
        self,
        R: float,
        genuine_demands: List[float],
        D_max: float,
        p_robust: float,
        epsilon: float,
        tol_lambda: float = 1e-6,
    ) -> float:
        """
        Finds the optimal dual multiplier lambda*(R) in [0, c_short] for a fixed R.
        Because J_tilde(R, lambda) is convex in lambda, its subgradient with respect to lambda is:
            g_lambda(lambda) = p_robust * epsilon - (p_robust / N) * sum_{i in Active(lambda)} (D_max - d_tilde_i)
        Where Active(lambda) contains indices where piece 3 strictly dominates pieces 1 and 2.

        Uses 1D bisection on [0, c_short] with deterministic tie-breaking: selects lambda_min*.
        """
        c_short = self.c_short
        if not genuine_demands or p_robust <= 0.0:
            return 0.0

        N = len(genuine_demands)

        def subgradient(lam: float) -> float:
            active_sum = 0.0
            for d in genuine_demands:
                p1 = 0.0
                p2 = c_short * (d - R)
                p3 = c_short * (D_max - R) - lam * (D_max - d)
                if p3 > max(p1, p2):
                    active_sum += (D_max - d)
            return p_robust * (epsilon - (active_sum / float(N)))

        # Boundary checks
        g_low = subgradient(0.0)
        if g_low >= 0.0:
            return 0.0

        g_high = subgradient(c_short)
        if g_high <= 0.0:
            return c_short

        # 1D Bisection on [0, c_short]
        low = 0.0
        high = c_short
        for _ in range(22):  # 2^(-22) * c_short approx 4.7e-7 precision
            mid = 0.5 * (low + high)
            g_mid = subgradient(mid)
            if g_mid < 0.0:
                low = mid
            else:
                high = mid
            if (high - low) < tol_lambda:
                break

        return round(0.5 * (low + high), 6)

    # =========================================================================
    # 6. Global 1D Golden Section Search on Strict Convex Profile v(R)
    # =========================================================================
    def optimize_reserve_and_lambda(
        self,
        genuine_demands: List[float],
        D_max: float,
        H: float,
        p_robust: float,
        epsilon: float,
        R_max: float,
        tol_R: float = 0.01,
    ) -> Tuple[float, float, float]:
        """
        Optimizes (R*, lambda*) by minimizing the 1D strictly convex profile function:
            v(R) = min_{lambda in [0, c_short]} J_tilde(R, lambda)
        Over R in [0, R_max] using Golden Section Search.
        Returns: (R*, lambda*, minimum_cost)
        """
        def eval_v(R_cand: float) -> Tuple[float, float]:
            lam_opt = self.optimize_lambda_for_fixed_R(
                R=R_cand,
                genuine_demands=genuine_demands,
                D_max=D_max,
                p_robust=p_robust,
                epsilon=epsilon,
            )
            cost = self.evaluate_profile_objective(
                R=R_cand,
                lambda_val=lam_opt,
                genuine_demands=genuine_demands,
                D_max=D_max,
                H=H,
                p_robust=p_robust,
                epsilon=epsilon,
                R_max=R_max,
            )
            return cost, lam_opt

        if R_max <= 0.0:
            cost, lam = eval_v(0.0)
            return 0.0, lam, cost

        # Golden Section Search on [0, R_max]
        inv_phi = (math.sqrt(5.0) - 1.0) / 2.0
        inv_phi_sq = (3.0 - math.sqrt(5.0)) / 2.0

        a = 0.0
        b = R_max
        h = b - a

        c = a + inv_phi_sq * h
        d = a + inv_phi * h

        cost_c, lam_c = eval_v(c)
        cost_d, lam_d = eval_v(d)

        while (b - a) > tol_R:
            if cost_c < cost_d:
                b = d
                d = c
                cost_d = cost_c
                lam_d = lam_c
                h = b - a
                c = a + inv_phi_sq * h
                cost_c, lam_c = eval_v(c)
            else:
                a = c
                c = d
                cost_c = cost_d
                lam_c = lam_d
                h = b - a
                d = a + inv_phi * h
                cost_d, lam_d = eval_v(d)

        best_R = 0.5 * (a + b)
        best_cost, best_lam = eval_v(best_R)

        cost_0, lam_0 = eval_v(0.0)
        if cost_0 < best_cost:
            best_R, best_cost, best_lam = 0.0, cost_0, lam_0

        cost_max, lam_max = eval_v(R_max)
        if cost_max < best_cost:
            best_R, best_cost, best_lam = R_max, cost_max, lam_max

        return round(best_R, 2), best_lam, round(best_cost, 4)

    # =========================================================================
    # 7. Complete Allocation Computation
    # =========================================================================
    def compute_allocation(
        self,
        user: UserProfile,
        predictor: OutageAndDemandPredictor,
        horizon_hours: float = 24.0,
    ) -> AllocationDecision:
        """
        Computes the recommended offline reserve R* under AORA-DRO.
        Preserves wallet decoupling invariants and handles all boundary cases.
        """
        R_max = max(0.0, user.maximum_allowance)
        H = max(1.0, horizon_hours)

        # Forecast prospective outage duration (hours)
        mean_dur, _ = predictor.estimate_outage_duration()
        T_forecast = max(0.1, min(H, mean_dur))

        # Conditioned maximum physical demand support during outage of duration T_forecast:
        # Scales with prospective duration so short blips (e.g. 18 mins) don't assume 24-hour demand,
        # while preserving D_max >= R_max for long outages or when observations exceed R_max.
        nu_max = max(500.0, user.spending_rate_mean * 4.0)
        duration_spend_bound = max(40.0, nu_max * T_forecast)
        D_max = max(duration_spend_bound, R_max) if T_forecast >= 2.0 else duration_spend_bound

        # Extract genuine observations
        genuine_demands = self.extract_regularized_demand_observations(
            predictor=predictor,
            T_forecast=T_forecast,
            D_max=max(D_max, 10000.0),
        )
        N = len(genuine_demands)

        # Ensure D_max strictly bounds all observed data points
        if genuine_demands:
            D_max = max(D_max, max(genuine_demands) * 1.05)

        # Upper bound R search space by D_max (cannot provision more than max demand in duration)
        effective_R_max = min(R_max, D_max)

        # Robust outage probability
        p_robust = self.compute_robust_outage_probability(predictor)

        mean_demand = sum(genuine_demands) / float(N) if N > 0 else (self.prior_spending_rate * T_forecast)

        # ---------------------------------------------------------------------
        # Boundary Case A: Trivial Policy Limit (R_max <= 0)
        # ---------------------------------------------------------------------
        if R_max <= 0.0 or effective_R_max <= 0.0:
            return self._build_decision(
                strategy=self.name,
                recommended_reserve=0.0,
                p_out=p_robust,
                duration=T_forecast,
                demand=mean_demand,
                user=user,
                cost=0.0,
                uncertainty_margin=0.0,
                safety_floor=0.0,
            )

        # ---------------------------------------------------------------------
        # Boundary Case B: Zero Outage Probability (p_robust <= 0)
        # ---------------------------------------------------------------------
        if p_robust <= 0.0:
            return self._build_decision(
                strategy=self.name,
                recommended_reserve=0.0,
                p_out=0.0,
                duration=T_forecast,
                demand=mean_demand,
                user=user,
                cost=0.0,
                uncertainty_margin=0.0,
                safety_floor=0.0,
            )

        # ---------------------------------------------------------------------
        # Phase 1: Cold-Start Prior Mode (N = 0)
        # ---------------------------------------------------------------------
        if N == 0:
            mu_D_0 = self.prior_spending_rate * self.prior_duration
            sigma_D_0 = self.prior_spending_std * math.sqrt(self.prior_duration)
            R_cold = min(effective_R_max, max(0.0, mu_D_0 + self.z_cold * sigma_D_0))
            R_cold = round(R_cold, 2)

            c_lock = self.c_lock
            c_exposure = self.c_exposure
            c_short = self.c_short
            holding = c_lock * R_cold * H
            exposure = c_exposure * (R_cold ** 2) / max(1.0, R_max)
            expected_shortage = max(0.0, mu_D_0 - R_cold)
            cost = holding + exposure + p_robust * c_short * expected_shortage

            return self._build_decision(
                strategy=self.name,
                recommended_reserve=R_cold,
                p_out=p_robust,
                duration=T_forecast,
                demand=round(mu_D_0, 2),
                user=user,
                cost=round(cost, 4),
                uncertainty_margin=round(self.z_cold * sigma_D_0, 2),
                safety_floor=R_cold,
            )

        # ---------------------------------------------------------------------
        # Phase 2: Active Data-Driven DRO Mode (N >= 1)
        # ---------------------------------------------------------------------
        epsilon_N = self.compute_wasserstein_radius(N=N, D_max=D_max)

        bar_d = sum(genuine_demands) / float(N)
        epsilon_crit = max(0.0, D_max - bar_d)

        # Boundary Case C: Extreme Uncertainty (epsilon >= epsilon_crit)
        if epsilon_N >= epsilon_crit:
            c_lock = self.c_lock
            c_exposure = self.c_exposure
            c_short = self.c_short

            R_unc = (R_max / (2.0 * c_exposure)) * (p_robust * c_short - c_lock * H)
            R_lim = min(effective_R_max, max(0.0, R_unc))
            R_lim = round(R_lim, 2)

            cost_lim = self.evaluate_profile_objective(
                R=R_lim,
                lambda_val=0.0,
                genuine_demands=genuine_demands,
                D_max=D_max,
                H=H,
                p_robust=p_robust,
                epsilon=epsilon_N,
                R_max=R_max,
            )

            return self._build_decision(
                strategy=self.name,
                recommended_reserve=R_lim,
                p_out=p_robust,
                duration=T_forecast,
                demand=round(bar_d, 2),
                user=user,
                cost=round(cost_lim, 4),
                uncertainty_margin=round(epsilon_N, 2),
                safety_floor=0.0,
            )

        # 3. Standard Non-Parametric DRO Optimization
        final_R, opt_lambda, min_cost = self.optimize_reserve_and_lambda(
            genuine_demands=genuine_demands,
            D_max=D_max,
            H=H,
            p_robust=p_robust,
            epsilon=epsilon_N,
            R_max=effective_R_max,
        )

        uncertainty_margin = max(0.0, final_R - bar_d)

        return self._build_decision(
            strategy=self.name,
            recommended_reserve=final_R,
            p_out=p_robust,
            duration=T_forecast,
            demand=round(bar_d, 2),
            user=user,
            cost=min_cost,
            uncertainty_margin=round(uncertainty_margin, 2),
            safety_floor=0.0,
        )

    # =========================================================================
    # 8. Wallet Decoupling Helper
    # =========================================================================
    @staticmethod
    def _build_decision(
        strategy: str,
        recommended_reserve: float,
        p_out: float,
        duration: float,
        demand: float,
        user: UserProfile,
        cost: float,
        uncertainty_margin: float,
        safety_floor: float,
    ) -> AllocationDecision:
        """Enforces downstream balance decoupling without biasing target recommendation."""
        final_R = round(max(0.0, recommended_reserve), 2)
        avail = max(0.0, user.available_balance)
        allocatable = round(min(final_R, avail), 2)
        shortfall = round(max(0.0, final_R - avail), 2)
        remaining = round(max(0.0, avail - final_R), 2)

        return AllocationDecision(
            strategy=strategy,
            recommended_reserve=final_R,
            predicted_outage_prob=p_out,
            predicted_outage_duration=duration,
            predicted_demand=demand,
            available_balance=user.available_balance,
            allowance_limit=user.maximum_allowance,
            objective_cost=cost,
            uncertainty_margin=uncertainty_margin,
            safety_floor=safety_floor,
            funding_shortfall=shortfall,
            remaining_liquid_balance=remaining,
            allocatable_reserve=allocatable,
        )
