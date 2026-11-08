"""
Implementation of competing offline allowance provisioning strategies:
A. Fixed Allowance (Static Baseline)
B. Demand-Only (Outage-Agnostic Baseline)
C. Proposed Method (Joint Optimization over outage probability, demand, holding cost, and risk)
"""

import math
from abc import ABC, abstractmethod
from typing import Tuple
from .config import ProvisioningConfig
from .models import AllocationDecision, UserProfile
from .predictor import OutageAndDemandPredictor


class BaseProvisioningStrategy(ABC):
    """Abstract base class for allowance allocation strategies."""

    def __init__(self, name: str, config: ProvisioningConfig = ProvisioningConfig()):
        self.name = name
        self.config = config

    @abstractmethod
    def compute_allocation(
        self,
        user: UserProfile,
        predictor: OutageAndDemandPredictor,
        horizon_hours: float = 24.0,
    ) -> AllocationDecision:
        """Computes the recommended reserve R for the given user and horizon."""
        pass

    def clamp_reserve(self, raw_reserve: float, available_balance: float, maximum_allowance: float) -> float:
        """Enforces the hard banking constraints: 0 <= R <= min(balance, maximum_allowance)."""
        upper_bound = min(max(0.0, available_balance), max(0.0, maximum_allowance))
        clamped = max(0.0, min(raw_reserve, upper_bound))
        return round(clamped, 2)


# =============================================================================
# Strategy A: Fixed Allowance (Static Preset Baseline)
# =============================================================================
class FixedAllowanceStrategy(BaseProvisioningStrategy):
    """
    Fixed Allowance Strategy (Standard UPIMesh UI baseline).
    Always recommends a fixed constant reserve (e.g., ₹500.0 or ₹1,000.0)
    clamped to user balance and allowance limits.
    """

    def __init__(self, fixed_amount: float = 500.0, config: ProvisioningConfig = ProvisioningConfig()):
        super().__init__(name=f"Fixed-₹{int(fixed_amount)}", config=config)
        self.fixed_amount = fixed_amount

    def compute_allocation(
        self,
        user: UserProfile,
        predictor: OutageAndDemandPredictor,
        horizon_hours: float = 24.0,
    ) -> AllocationDecision:
        p_out = predictor.estimate_outage_probability()
        mean_dur, _ = predictor.estimate_outage_duration()
        mean_demand, _ = predictor.estimate_demand_during_outage(mean_dur, horizon_hours)

        reserve = self.clamp_reserve(self.fixed_amount, user.available_balance, user.maximum_allowance)

        return AllocationDecision(
            strategy=self.name,
            recommended_reserve=reserve,
            predicted_outage_prob=p_out,
            predicted_outage_duration=mean_dur,
            predicted_demand=mean_demand,
            available_balance=user.available_balance,
            allowance_limit=user.maximum_allowance,
            objective_cost=0.0,
        )


# =============================================================================
# Strategy B: Demand-Only (Outage-Agnostic Baseline)
# =============================================================================
class DemandOnlyStrategy(BaseProvisioningStrategy):
    """
    Demand-Only Strategy.
    Estimates expected total payment demand across the horizon D_H,
    without considering the probability or duration of an outage.
    Effectively assumes an outage will occur or provisions for worst-case demand.
    """

    def __init__(self, safety_factor: float = 1.0, config: ProvisioningConfig = ProvisioningConfig()):
        super().__init__(name="Demand-Only", config=config)
        self.safety_factor = safety_factor

    def compute_allocation(
        self,
        user: UserProfile,
        predictor: OutageAndDemandPredictor,
        horizon_hours: float = 24.0,
    ) -> AllocationDecision:
        p_out = predictor.estimate_outage_probability()
        mean_dur, _ = predictor.estimate_outage_duration()
        mean_outage_demand, _ = predictor.estimate_demand_during_outage(mean_dur, horizon_hours)

        # Forecasts full horizon spending demand
        total_horizon_demand = predictor.estimate_total_horizon_demand(horizon_hours)
        raw_reserve = total_horizon_demand * self.safety_factor

        reserve = self.clamp_reserve(raw_reserve, user.available_balance, user.maximum_allowance)

        return AllocationDecision(
            strategy=self.name,
            recommended_reserve=reserve,
            predicted_outage_prob=p_out,
            predicted_outage_duration=mean_dur,
            predicted_demand=mean_outage_demand,
            available_balance=user.available_balance,
            allowance_limit=user.maximum_allowance,
            objective_cost=0.0,
        )


# =============================================================================
# Strategy C: Proposed Method (Joint Optimization)
# =============================================================================
class ProposedJointOptimizationStrategy(BaseProvisioningStrategy):
    """
    Proposed Joint Optimization Method.

    Minimizes the expected total cost objective:
      J(R) = c_lock * R * H
           + p_out * c_short * E[max(D_T - R, 0)]
           + c_exposure * Risk(R)

    Subject to:
      0 <= R <= min(available_balance, maximum_allowance)

    Mathematical Characterization:
    - Expected Shortage Function E[max(D_T - R, 0)]:
      Under a continuous normal/lognormal demand model D_T ~ N(mu_D, sigma_D^2),
      let z = (R - mu_D) / sigma_D:
      E[max(D_T - R, 0)] = (mu_D - R) * (1 - Phi(z)) + sigma_D * phi(z)
      Where Phi is standard normal CDF, and phi is standard normal PDF.
    - Financial Exposure Penalty Risk(R):
      Convex risk penalty: Risk(R) = R^2 / maximum_allowance
      Penalizes high idle on-device exposure.
    - First-order optimality generalizes the classical Newsvendor / inventory critical fractile:
      dJ/dR = c_lock * H - p_out * c_short * (1 - Phi(z)) + 2 * c_exposure * R / maximum_allowance = 0
    - If p_out -> 0: dJ/dR > 0 for all R > 0 => optimal reserve R* = 0 (no unneeded lock-in).
    - If mu_D increases: (1 - Phi(z)) increases, pushing optimal R* higher (monotonicity).
    """

    def __init__(
        self,
        c_lock: float = None,
        c_short: float = None,
        c_exposure: float = None,
        config: ProvisioningConfig = ProvisioningConfig(),
    ):
        super().__init__(name="Proposed-JointOpt", config=config)
        self.c_lock = c_lock if c_lock is not None else config.default_c_lock
        self.c_short = c_short if c_short is not None else config.default_c_short
        self.c_exposure = c_exposure if c_exposure is not None else config.default_c_exposure

    @staticmethod
    def _std_norm_pdf(z: float) -> float:
        """Standard normal probability density function phi(z)."""
        return (1.0 / math.sqrt(2.0 * math.pi)) * math.exp(-0.5 * z * z)

    @staticmethod
    def _std_norm_cdf(z: float) -> float:
        """Standard normal cumulative distribution function Phi(z) via math.erf."""
        return 0.5 * (1.0 + math.erf(z / math.sqrt(2.0)))

    def expected_shortage(self, R: float, mu_D: float, sigma_D: float) -> float:
        """
        Calculates E[max(D_T - R, 0)] for D_T ~ N(mu_D, sigma_D^2) truncated at 0.
        Uses the exact partial expectation formula of the normal distribution.
        """
        if sigma_D <= 1e-6:
            return max(0.0, mu_D - R)

        z = (R - mu_D) / sigma_D
        phi = self._std_norm_pdf(z)
        Phi = self._std_norm_cdf(z)

        # Standard partial expectation
        shortage = (mu_D - R) * (1.0 - Phi) + sigma_D * phi
        return max(0.0, shortage)

    def financial_risk_exposure(self, R: float, maximum_allowance: float) -> float:
        """
        Documented financial exposure function: Risk(R) = R^2 / maximum_allowance.
        Convex quadratic penalty scaling with on-device reserve.
        """
        if maximum_allowance <= 0:
            return 0.0
        return (R * R) / maximum_allowance

    def evaluate_objective(
        self,
        R: float,
        H: float,
        p_out: float,
        mu_D: float,
        sigma_D: float,
        maximum_allowance: float,
    ) -> float:
        """Evaluates J(R) = c_lock * R * H + p_out * c_short * E[max(D_T - R, 0)] + c_exposure * Risk(R)."""
        holding_cost = self.c_lock * R * H
        shortage_cost = p_out * self.c_short * self.expected_shortage(R, mu_D, sigma_D)
        exposure_penalty = self.c_exposure * self.financial_risk_exposure(R, maximum_allowance)
        return holding_cost + shortage_cost + exposure_penalty

    def compute_allocation(
        self,
        user: UserProfile,
        predictor: OutageAndDemandPredictor,
        horizon_hours: float = 24.0,
    ) -> AllocationDecision:
        p_out = predictor.estimate_outage_probability()
        mean_dur, _ = predictor.estimate_outage_duration()
        mu_D, sigma_D = predictor.estimate_demand_during_outage(mean_dur, horizon_hours)

        upper_bound = min(max(0.0, user.available_balance), max(0.0, user.maximum_allowance))

        # Trivial boundary condition: zero upper bound or zero balance
        if upper_bound <= 0.0:
            return AllocationDecision(
                strategy=self.name,
                recommended_reserve=0.0,
                predicted_outage_prob=p_out,
                predicted_outage_duration=mean_dur,
                predicted_demand=mu_D,
                available_balance=user.available_balance,
                allowance_limit=user.maximum_allowance,
                objective_cost=0.0,
            )

        # Exact discrete grid minimization over Rupee grid (resolution: 1.0 INR)
        # Evaluates full convex curve deterministically without numerical instability
        best_R = 0.0
        best_cost = float("inf")

        # Evaluate candidate points from 0 to upper_bound with 1.0 INR step
        step = 1.0
        steps_count = int(upper_bound / step) + 1

        for i in range(steps_count):
            R_candidate = min(upper_bound, float(i * step))
            cost = self.evaluate_objective(
                R=R_candidate,
                H=horizon_hours,
                p_out=p_out,
                mu_D=mu_D,
                sigma_D=sigma_D,
                maximum_allowance=user.maximum_allowance,
            )
            if cost < best_cost:
                best_cost = cost
                best_R = R_candidate

        # Explicitly check upper_bound edge point
        edge_cost = self.evaluate_objective(
            R=upper_bound,
            H=horizon_hours,
            p_out=p_out,
            mu_D=mu_D,
            sigma_D=sigma_D,
            maximum_allowance=user.maximum_allowance,
        )
        if edge_cost < best_cost:
            best_cost = edge_cost
            best_R = upper_bound

        final_R = self.clamp_reserve(best_R, user.available_balance, user.maximum_allowance)

        return AllocationDecision(
            strategy=self.name,
            recommended_reserve=final_R,
            predicted_outage_prob=p_out,
            predicted_outage_duration=mean_dur,
            predicted_demand=mu_D,
            available_balance=user.available_balance,
            allowance_limit=user.maximum_allowance,
            objective_cost=round(best_cost, 4),
        )


# =============================================================================
# Strategy D: Uncertainty-Aware Joint Optimization (Milestone 2 Proposed)
# =============================================================================
class UncertaintyAwareJointOptimizationStrategy(ProposedJointOptimizationStrategy):
    """
    Uncertainty-Aware Joint Optimization Method.

    Directly addresses under-provisioning during shocks, regime shifts, and tail events by:
    1. Compound Demand Variance: Accounts for both hourly spend variance and outage duration
       variance via the Law of Total Variance: Var(D_T) = E[T]*Var(X) + (E[X])^2 * Var(T).
    2. Epistemic Confidence Intervals (UCB): Inflates p_out and duration parameters according
       to parameter estimation standard error at confidence level kappa (e.g. 0.85).
    3. Non-Stationary Shift / Volatility Adaptation: Increases learning rate and safety buffers
       when sudden prediction shocks or regime changes occur.
    4. Bounded Adaptive Essential Safety Floor: Enforces a minimal lifeline reserve (e.g. 1-2
       essential transit/food payments) strictly when outage risk is non-negligible (p > 0.05),
       guaranteeing zero idle lock-in when connectivity is confirmed reliable (p <= 0.05).
    """

    def __init__(
        self,
        confidence_level: float = 0.85,
        use_safety_floor: bool = True,
        c_lock: float = None,
        c_short: float = None,
        c_exposure: float = None,
        config: ProvisioningConfig = ProvisioningConfig(),
    ):
        super().__init__(c_lock=c_lock, c_short=c_short, c_exposure=c_exposure, config=config)
        self.name = "Uncertainty-Aware"
        self.confidence_level = confidence_level
        self.use_safety_floor = use_safety_floor

    def compute_allocation(
        self,
        user: UserProfile,
        predictor: OutageAndDemandPredictor,
        horizon_hours: float = 24.0,
    ) -> AllocationDecision:
        p_robust, mu_D_robust, sigma_D_robust, R_floor = predictor.estimate_robust_parameters(
            confidence_level=self.confidence_level,
            horizon_hours=horizon_hours,
            maximum_allowance=user.maximum_allowance,
        )

        upper_bound = min(max(0.0, user.available_balance), max(0.0, user.maximum_allowance))
        if upper_bound <= 0.0:
            return AllocationDecision(
                strategy=self.name,
                recommended_reserve=0.0,
                predicted_outage_prob=p_robust,
                predicted_outage_duration=0.0,
                predicted_demand=mu_D_robust,
                available_balance=user.available_balance,
                allowance_limit=user.maximum_allowance,
                objective_cost=0.0,
                uncertainty_margin=0.0,
                safety_floor=0.0,
            )

        lower_bound = min(upper_bound, R_floor) if self.use_safety_floor else 0.0

        best_R = lower_bound
        best_cost = float("inf")

        step = 1.0
        steps_count = int((upper_bound - lower_bound) / step) + 1

        for i in range(steps_count):
            R_candidate = min(upper_bound, lower_bound + float(i * step))
            cost = self.evaluate_objective(
                R=R_candidate,
                H=horizon_hours,
                p_out=p_robust,
                mu_D=mu_D_robust,
                sigma_D=sigma_D_robust,
                maximum_allowance=user.maximum_allowance,
            )
            if cost < best_cost:
                best_cost = cost
                best_R = R_candidate

        # Edge check
        edge_cost = self.evaluate_objective(
            R=upper_bound,
            H=horizon_hours,
            p_out=p_robust,
            mu_D=mu_D_robust,
            sigma_D=sigma_D_robust,
            maximum_allowance=user.maximum_allowance,
        )
        if edge_cost < best_cost:
            best_cost = edge_cost
            best_R = upper_bound

        final_R = self.clamp_reserve(best_R, user.available_balance, user.maximum_allowance)

        mean_baseline_dur, _ = predictor.estimate_outage_duration()
        mean_baseline_demand, _ = predictor.estimate_demand_during_outage(mean_baseline_dur, horizon_hours)
        uncertainty_margin = max(0.0, mu_D_robust - mean_baseline_demand)

        return AllocationDecision(
            strategy=self.name,
            recommended_reserve=final_R,
            predicted_outage_prob=p_robust,
            predicted_outage_duration=round(mu_D_robust / max(1.0, predictor.prior_hourly_demand), 2),
            predicted_demand=mu_D_robust,
            available_balance=user.available_balance,
            allowance_limit=user.maximum_allowance,
            objective_cost=round(best_cost, 4),
            uncertainty_margin=round(uncertainty_margin, 2),
            safety_floor=round(R_floor, 2),
        )

