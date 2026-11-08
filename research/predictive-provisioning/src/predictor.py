"""
Predictor estimating outage probability, expected outage duration,
and payment demand during offline periods with uncertainty awareness,
epistemic confidence bounds, and non-stationary regime shift tracking.
"""

import math
from typing import List, Optional, Tuple
from .models import OutageEvent, Transaction


class OutageAndDemandPredictor:
    """
    Online estimator that maintains historical observations of connectivity outages
    and spending patterns to provide forecasting inputs for provisioning strategies.
    Supports both baseline point estimates and uncertainty-aware robust bounds.
    """

    def __init__(
        self,
        ewma_alpha: float = 0.20,
        prior_outage_prob: float = 0.15,
        prior_outage_duration: float = 1.0,
        prior_hourly_demand: float = 40.0,
    ):
        self.base_alpha = ewma_alpha
        self.current_alpha = ewma_alpha
        self.prior_outage_prob = prior_outage_prob
        self.prior_outage_duration = prior_outage_duration
        self.prior_hourly_demand = prior_hourly_demand

        # Historical memory
        self.outage_history: List[OutageEvent] = []
        self.transaction_history: List[Transaction] = []

        # Online forecast verification history (for drift / shock detection)
        self.recent_brier_scores: List[float] = []
        self.recent_demand_errors: List[float] = []
        self.consecutive_shocks: int = 0

    def record_epoch_observation(
        self,
        outage: OutageEvent,
        transactions: List[Transaction],
    ) -> None:
        """Appends observed ground truth from a completed epoch into predictor memory."""
        self.outage_history.append(outage)
        self.transaction_history.extend(transactions)

    def record_forecast_error(
        self,
        predicted_p: float,
        actual_outage: bool,
        predicted_demand: float,
        actual_demand: float,
    ) -> None:
        """
        Tracks prediction errors to detect non-stationary regime shifts or sudden shocks.
        Dynamically adjusts the learning rate alpha to adapt faster when drift occurs.
        """
        brier = (predicted_p - (1.0 if actual_outage else 0.0)) ** 2
        self.recent_brier_scores.append(brier)
        if len(self.recent_brier_scores) > 10:
            self.recent_brier_scores.pop(0)

        if actual_outage:
            err = abs(predicted_demand - actual_demand)
            self.recent_demand_errors.append(err)
            if len(self.recent_demand_errors) > 10:
                self.recent_demand_errors.pop(0)

        # Detect regime shift or sudden severe shock
        # E.g. 2 consecutive severe surprises (Brier > 0.35 or sudden long blackout)
        is_burst = actual_outage and (actual_demand > 2.5 * max(10.0, predicted_demand))
        is_shock = (brier > 0.35) or is_burst
        if is_shock:
            self.consecutive_shocks += 1
            # Temporarily boost learning rate to quickly flush stale pre-shift data
            self.current_alpha = min(0.65, self.base_alpha * 2.5)
        else:
            self.consecutive_shocks = max(0, self.consecutive_shocks - 1)
            # Slowly decay learning rate back to baseline
            self.current_alpha = max(self.base_alpha, self.current_alpha * 0.85)

    def estimate_outage_probability(self) -> float:
        """
        Estimates the probability p_out that an outage will occur in the upcoming horizon H.
        Combines empirical EWMA with a Bayesian prior for cold-start safety.
        """
        if not self.outage_history:
            return self.prior_outage_prob

        # Bayesian smoothing: prior count equivalent to 4 pseudo-observations
        prior_weight = 4.0

        # Compute EWMA on recent history (up to last 30 epochs)
        recent = self.outage_history[-30:]
        if not recent:
            return self.prior_outage_prob

        weighted_sum = 0.0
        weight_norm = 0.0
        current_weight = 1.0

        for event in reversed(recent):
            val = 1.0 if event.occurred else 0.0
            weighted_sum += val * current_weight
            weight_norm += current_weight
            current_weight *= (1.0 - self.current_alpha)

        empirical_p = weighted_sum / max(1e-6, weight_norm)

        # Blend empirical estimate with prior based on sample count
        n = len(recent)
        blend_factor = n / (n + prior_weight)
        p_est = (blend_factor * empirical_p) + ((1.0 - blend_factor) * self.prior_outage_prob)

        return max(0.0, min(1.0, round(p_est, 4)))

    def estimate_outage_duration(self) -> Tuple[float, float]:
        """
        Estimates the expected duration (mean and standard deviation) of an outage,
        conditioned on an outage occurring.
        Returns: (mean_duration_hours, std_duration_hours)
        """
        observed_durations = [e.duration_hours for e in self.outage_history if e.occurred]

        if not observed_durations:
            # Cold-start fallback
            return (self.prior_outage_duration, max(0.25, self.prior_outage_duration * 0.5))

        # Recent observed durations (last 15 outages)
        recent = observed_durations[-15:]
        mean_dur = sum(recent) / len(recent)
        if len(recent) > 1:
            variance = sum((d - mean_dur) ** 2 for d in recent) / (len(recent) - 1)
            std_dur = math.sqrt(max(0.04, variance))
        else:
            std_dur = max(0.25, mean_dur * 0.5)

        return (round(mean_dur, 2), round(std_dur, 2))

    def estimate_demand_during_outage(
        self,
        expected_duration_hours: float,
        horizon_hours: float = 24.0,
    ) -> Tuple[float, float]:
        """
        Forecasts baseline spending demand D_T during an outage of expected duration T.
        Returns: (mean_demand_inr, std_demand_inr)
        """
        if not self.transaction_history:
            mean_demand = self.prior_hourly_demand * expected_duration_hours
            std_demand = max(10.0, mean_demand * 0.5)
            return (round(mean_demand, 2), round(std_demand, 2))

        # Calculate empirical average hourly spending rate
        total_epochs = max(1, len(self.outage_history))
        total_tracked_hours = total_epochs * horizon_hours
        total_spent = sum(t.amount for t in self.transaction_history)
        hourly_rate = total_spent / max(1.0, total_tracked_hours)

        # Spend per transaction distribution
        amounts = [t.amount for t in self.transaction_history]
        mean_tx = sum(amounts) / len(amounts)
        if len(amounts) > 1:
            var_tx = sum((a - mean_tx) ** 2 for a in amounts) / (len(amounts) - 1)
            std_tx = math.sqrt(max(1.0, var_tx))
        else:
            std_tx = mean_tx * 0.5

        expected_demand = hourly_rate * expected_duration_hours
        scale_factor = math.sqrt(max(0.2, expected_duration_hours))
        std_demand = max(15.0, std_tx * scale_factor)

        return (round(expected_demand, 2), round(std_demand, 2))

    def estimate_total_horizon_demand(self, horizon_hours: float = 24.0) -> float:
        """Forecasts total demand across the entire horizon regardless of outages (for Demand-Only strategy)."""
        if not self.transaction_history:
            return self.prior_hourly_demand * horizon_hours

        total_epochs = max(1, len(self.outage_history))
        total_tracked_hours = total_epochs * horizon_hours
        total_spent = sum(t.amount for t in self.transaction_history)
        hourly_rate = total_spent / max(1.0, total_tracked_hours)

        return round(hourly_rate * horizon_hours, 2)

    # =========================================================================
    # Milestone 2: Uncertainty-Aware & Robust Estimations
    # =========================================================================
    @staticmethod
    def _confidence_to_z(confidence_level: float) -> float:
        """Converts confidence level kappa (e.g. 0.85) to standard normal quantile z."""
        # Common quantile approximations
        if confidence_level >= 0.99:
            return 2.326
        elif confidence_level >= 0.95:
            return 1.645
        elif confidence_level >= 0.90:
            return 1.282
        elif confidence_level >= 0.85:
            return 1.036
        elif confidence_level >= 0.80:
            return 0.842
        elif confidence_level >= 0.70:
            return 0.524
        elif confidence_level >= 0.60:
            return 0.253
        return 0.0

    def estimate_robust_parameters(
        self,
        confidence_level: float = 0.85,
        horizon_hours: float = 24.0,
        maximum_allowance: float = 2000.0,
    ) -> Tuple[float, float, float, float]:
        """
        Computes uncertainty-aware robust parameters:
        1. Outage Probability UCB: p_robust = min(1.0, p_hat + z * SE(p))
        2. Total Variance of Compound Demand via Law of Total Variance:
           Var(D_T) = E[T]*Var(X) + (E[X])^2 * Var(T)
        3. Duration UCB: T_robust = mu_T + z * SE(mu_T)
        4. Bounded Essential Safety Floor R_floor for sudden shock absorption.

        Returns: (p_robust, mu_D_robust, sigma_D_robust, R_floor)
        """
        z_k = self._confidence_to_z(confidence_level)

        # 1. Outage Probability Point Estimate & Epistemic Standard Error
        p_hat = self.estimate_outage_probability()
        n_eff = max(1, min(30, len(self.outage_history)))
        # Standard error of Bernoulli parameter
        se_p = math.sqrt(max(1e-4, p_hat * (1.0 - p_hat)) / (n_eff + 1.0))
        p_robust = min(1.0, max(0.0, p_hat + z_k * se_p))

        # 2. Outage Duration Mean and Variance
        mu_T, sigma_T = self.estimate_outage_duration()
        observed_outages_count = max(1, sum(1 for e in self.outage_history if e.occurred))
        se_mu_T = sigma_T / math.sqrt(observed_outages_count)
        # Robust duration accounts for duration sampling error
        T_robust = min(horizon_hours * 0.9, max(0.2, mu_T + z_k * se_mu_T))

        # 3. Hourly Spending Rate Distribution
        if self.transaction_history:
            total_epochs = max(1, len(self.outage_history))
            total_tracked_hours = total_epochs * horizon_hours
            total_spent = sum(t.amount for t in self.transaction_history)
            mu_X = total_spent / max(1.0, total_tracked_hours)

            amounts = [t.amount for t in self.transaction_history]
            mean_a = sum(amounts) / len(amounts)
            var_a = sum((a - mean_a) ** 2 for a in amounts) / max(1, len(amounts) - 1)
            # Hourly variance scales with transactions per hour
            tx_per_hour = len(amounts) / max(1.0, total_tracked_hours)
            var_X = max(25.0, tx_per_hour * var_a)
            sigma_X = math.sqrt(var_X)
            median_tx = sorted(amounts)[len(amounts) // 2]
        else:
            mu_X = self.prior_hourly_demand
            var_X = (self.prior_hourly_demand * 0.5) ** 2
            sigma_X = math.sqrt(var_X)
            median_tx = 50.0

        # 4. Total Compound Variance via Law of Total Variance
        # Var(D_T) = E[T] * Var(X) + (E[X])^2 * Var(T)
        compound_var = (T_robust * var_X) + ((mu_X ** 2) * (sigma_T ** 2))
        sigma_D_total = math.sqrt(max(100.0, compound_var))

        # Expected robust demand
        mu_D_robust = round(mu_X * T_robust, 2)
        sigma_D_robust = round(sigma_D_total, 2)

        # 5. Bounded Adaptive Essential Safety Floor (R_floor)
        # Guarantees the ability to execute 1-2 lifeline essential transactions during unforeseen shocks.
        # Strict Invariant: If p_robust <= 0.05 (confirmed reliable network), R_floor is strictly 0.0!
        if p_robust > 0.05:
            # Baseline: 1.5x median essential transaction (e.g. ₹60 - ₹120)
            base_essential = max(30.0, median_tx * 1.5)

            # Inflate if recent shocks or volatility observed
            shock_factor = 1.0 + (0.5 * min(3, self.consecutive_shocks))
            calculated_floor = base_essential * shock_factor * p_robust

            # Cap floor to 35% of maximum allowance so it never forces an aggressive lock-in
            R_floor = min(maximum_allowance * 0.35, max(0.0, calculated_floor))
        else:
            R_floor = 0.0

        return (round(p_robust, 4), mu_D_robust, sigma_D_robust, round(R_floor, 2))
