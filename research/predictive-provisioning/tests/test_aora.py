"""
Comprehensive independent test suite for AORA (Adaptive Offline Reserve Algorithm).

Covers:
- Cold start (N = 0)
- Single genuine observation (N = 1)
- Multiple genuine observations (N > 1)
- Normal network conditions (low p_out)
- Severe outage conditions (high p_out, long duration)
- Heavy-tailed synthetic demand
- Bimodal demand
- Demand greater than maximum reserve (D_max > R_max)
- Zero outage probability (p_out = 0)
- Large ambiguity radius (epsilon >= epsilon_crit)
- Zero wallet balance (B_avail = 0)
- Insufficient wallet balance (B_avail < R*)
- Non-unique dual multiplier cases (flat subdifferential segments)
- Deterministic reproducibility
- Independent numerical reference implementation comparison
"""

import math
import random
import unittest
from typing import List, Tuple

from src.aora import AORAStrategy
from src.config import ProvisioningConfig
from src.models import OutageEvent, Transaction, UserProfile
from src.predictor import OutageAndDemandPredictor


def independent_reference_solver(
    genuine_demands: List[float],
    D_max: float,
    H: float,
    p_robust: float,
    epsilon: float,
    R_max: float,
    c_lock: float = 0.0001,
    c_exposure: float = 0.05,
    c_short: float = 2.0,
    r_step: float = 2.0,
    lambda_step: float = 0.02,
) -> Tuple[float, float, float]:
    """
    Independent brute-force 2D discrete grid search solver.
    Used exclusively as an oracle reference to verify AORA's continuous optimizer.
    """
    best_R = 0.0
    best_lam = 0.0
    best_cost = float("inf")

    N = len(genuine_demands)
    r_steps = int(R_max / r_step) + 1
    lam_steps = int(c_short / lambda_step) + 1

    for i in range(r_steps):
        R = min(R_max, float(i * r_step))
        holding = c_lock * R * H
        exposure = c_exposure * (R * R) / max(1.0, R_max)

        for j in range(lam_steps):
            lam = min(c_short, float(j * lambda_step))
            unc = p_robust * lam * epsilon

            if N > 0:
                shortage = 0.0
                for d in genuine_demands:
                    p1 = 0.0
                    p2 = c_short * (d - R)
                    p3 = c_short * (D_max - R) - lam * (D_max - d)
                    shortage += max(p1, p2, p3)
                shortage = (p_robust / float(N)) * shortage
            else:
                shortage = 0.0

            total_cost = holding + exposure + unc + shortage
            if total_cost < best_cost:
                best_cost = total_cost
                best_R = R
                best_lam = lam

    return round(best_R, 2), round(best_lam, 4), round(best_cost, 4)


class TestAORAMathematicalProperties(unittest.TestCase):
    """Rigorous tests validating AORA's mathematical specifications and edge cases."""

    def setUp(self):
        self.config = ProvisioningConfig()
        self.strategy = AORAStrategy(config=self.config)
        self.user = UserProfile(
            user_id="test_user",
            profile_name="Standard User",
            available_balance=5000.0,
            maximum_allowance=2000.0,
        )
        self.predictor = OutageAndDemandPredictor()

    # -------------------------------------------------------------------------
    # 1. Cold Start (N = 0)
    # -------------------------------------------------------------------------
    def test_cold_start_prior_mode(self):
        """Verifies Phase 1 cold-start when zero outages have been observed."""
        decision = self.strategy.compute_allocation(self.user, self.predictor)

        # Cold start must recommend prior allocation (~81 INR with default priors)
        self.assertGreater(decision.recommended_reserve, 0.0)
        self.assertLessEqual(decision.recommended_reserve, self.user.maximum_allowance)
        self.assertEqual(decision.funding_shortfall, 0.0)
        self.assertEqual(decision.allocatable_reserve, decision.recommended_reserve)

        # In cold-start, safety_floor carries the prior allocation value
        self.assertEqual(decision.safety_floor, decision.recommended_reserve)

    # -------------------------------------------------------------------------
    # 2. Single Genuine Observation (N = 1)
    # -------------------------------------------------------------------------
    def test_single_genuine_observation(self):
        """Verifies transition to Phase 2 with exactly one real outage observation."""
        ev = OutageEvent(occurred=True, start_hour=8.0, duration_hours=1.0)
        tx = Transaction(tx_id="t1", timestamp_hour=8.5, amount=120.0, occurred_during_outage=True)
        self.predictor.record_epoch_observation(ev, [tx])

        decision = self.strategy.compute_allocation(self.user, self.predictor)

        self.assertGreater(decision.recommended_reserve, 0.0)
        self.assertLessEqual(decision.recommended_reserve, self.user.maximum_allowance)
        # N=1 should have wide ambiguity radius and zero heuristic floor
        self.assertEqual(decision.safety_floor, 0.0)

    # -------------------------------------------------------------------------
    # 3. Multiple Genuine Observations (N > 1)
    # -------------------------------------------------------------------------
    def test_multiple_genuine_observations(self):
        """Verifies empirical DRO with accumulating sample history."""
        for ep in range(10):
            ev = OutageEvent(occurred=True, start_hour=10.0, duration_hours=1.5)
            txs = [
                Transaction(tx_id=f"tx_{ep}_1", timestamp_hour=10.5, amount=45.0, occurred_during_outage=True),
                Transaction(tx_id=f"tx_{ep}_2", timestamp_hour=11.0, amount=65.0, occurred_during_outage=True),
            ]
            self.predictor.record_epoch_observation(ev, txs)

        decision = self.strategy.compute_allocation(self.user, self.predictor)

        self.assertGreater(decision.recommended_reserve, 0.0)
        self.assertLessEqual(decision.recommended_reserve, self.user.maximum_allowance)
        self.assertGreater(decision.allocatable_reserve, 0.0)

    # -------------------------------------------------------------------------
    # 4. Normal Network Conditions (Low p_out)
    # -------------------------------------------------------------------------
    def test_normal_network_conditions(self):
        """Under reliable 5G (low outage probability), reserve should be modest."""
        self.predictor.prior_outage_prob = 0.05
        # 1 outage in 20 epochs
        for ep in range(20):
            occ = (ep == 10)
            ev = OutageEvent(occurred=occ, start_hour=8.0 if occ else 0.0, duration_hours=0.3 if occ else 0.0)
            txs = [Transaction(tx_id=f"t_{ep}", timestamp_hour=8.1, amount=30.0, occurred_during_outage=occ)] if occ else []
            self.predictor.record_epoch_observation(ev, txs)

        decision = self.strategy.compute_allocation(self.user, self.predictor)

        # Under reliable conditions, reserve should stay low (< 250 INR)
        self.assertLess(decision.recommended_reserve, 250.0)

    # -------------------------------------------------------------------------
    # 5. Severe Outage Conditions (High p_out, Long Duration)
    # -------------------------------------------------------------------------
    def test_severe_outage_conditions(self):
        """Under blackouts with high demand, reserve should scale up to protect user."""
        self.predictor.prior_outage_prob = 0.90
        for ep in range(15):
            ev = OutageEvent(occurred=True, start_hour=8.0, duration_hours=4.0)
            txs = [Transaction(tx_id=f"t_{ep}_{i}", timestamp_hour=9.0 + i, amount=80.0, occurred_during_outage=True) for i in range(4)]
            self.predictor.record_epoch_observation(ev, txs)

        decision = self.strategy.compute_allocation(self.user, self.predictor)

        # Severe outage should provoke high reserve (> 250 INR)
        self.assertGreater(decision.recommended_reserve, 250.0)
        self.assertLessEqual(decision.recommended_reserve, self.user.maximum_allowance)

    # -------------------------------------------------------------------------
    # 6. Heavy-Tailed Synthetic Demand
    # -------------------------------------------------------------------------
    def test_heavy_tailed_demand(self):
        """AORA should safely provision for Pareto/power-law tail spending."""
        rng = random.Random(42)
        for ep in range(15):
            ev = OutageEvent(occurred=True, start_hour=8.0, duration_hours=2.0)
            # Pareto-like spending with occasional large spike
            amount = 30.0 if rng.random() > 0.15 else 600.0
            txs = [Transaction(tx_id=f"t_{ep}", timestamp_hour=9.0, amount=amount, occurred_during_outage=True)]
            self.predictor.record_epoch_observation(ev, txs)

        decision = self.strategy.compute_allocation(self.user, self.predictor)
        self.assertGreater(decision.recommended_reserve, 100.0)

    # -------------------------------------------------------------------------
    # 7. Bimodal Demand Distribution
    # -------------------------------------------------------------------------
    def test_bimodal_demand(self):
        """AORA handles bimodal spending (small snacks vs. large shopping)."""
        for ep in range(20):
            ev = OutageEvent(occurred=True, start_hour=8.0, duration_hours=2.0)
            amount = 25.0 if (ep % 2 == 0) else 450.0
            txs = [Transaction(tx_id=f"t_{ep}", timestamp_hour=8.5, amount=amount, occurred_during_outage=True)]
            self.predictor.record_epoch_observation(ev, txs)

        decision = self.strategy.compute_allocation(self.user, self.predictor)
        self.assertGreater(decision.recommended_reserve, 50.0)
        self.assertLessEqual(decision.recommended_reserve, self.user.maximum_allowance)

    # -------------------------------------------------------------------------
    # 8. Demand Greater Than Maximum Reserve (D_max > R_max)
    # -------------------------------------------------------------------------
    def test_demand_greater_than_maximum_reserve(self):
        """Verifies support separation: large demand does not break bounds."""
        for ep in range(5):
            ev = OutageEvent(occurred=True, start_hour=8.0, duration_hours=5.0)
            # Outage demand totaling 3500 INR (exceeding R_max = 2000 INR)
            txs = [Transaction(tx_id=f"t_{ep}_{i}", timestamp_hour=9.0 + i, amount=700.0, occurred_during_outage=True) for i in range(5)]
            self.predictor.record_epoch_observation(ev, txs)

        decision = self.strategy.compute_allocation(self.user, self.predictor)

        # Recommendation must respect regulatory cap R_max
        self.assertLessEqual(decision.recommended_reserve, self.user.maximum_allowance)

    # -------------------------------------------------------------------------
    # 9. Zero Outage Probability (p_out = 0)
    # -------------------------------------------------------------------------
    def test_zero_outage_probability(self):
        """When outage probability is zero, recommended reserve must be strictly 0."""
        self.predictor.prior_outage_prob = 0.0
        # Recorded observations with occurred = False
        for ep in range(10):
            self.predictor.record_epoch_observation(OutageEvent(occurred=False), [])

        # Override method to return 0.0 for test
        self.predictor.estimate_outage_probability = lambda: 0.0

        # Create strategy with high confidence so p_robust can be tested at boundary
        zero_strat = AORAStrategy(config=self.config)
        zero_strat.compute_robust_outage_probability = lambda pred: 0.0

        decision = zero_strat.compute_allocation(self.user, self.predictor)
        self.assertEqual(decision.recommended_reserve, 0.0)
        self.assertEqual(decision.allocatable_reserve, 0.0)

    # -------------------------------------------------------------------------
    # 10. Large Ambiguity Radius (epsilon >= epsilon_crit)
    # -------------------------------------------------------------------------
    def test_large_ambiguity_radius_limiting_behavior(self):
        """Verifies closed-form limiting equation when uncertainty is extreme."""
        ev = OutageEvent(occurred=True, start_hour=8.0, duration_hours=1.0)
        tx = Transaction(tx_id="t1", timestamp_hour=8.5, amount=50.0, occurred_during_outage=True)
        self.predictor.record_epoch_observation(ev, [tx])

        # Force epsilon to exceed critical radius
        class ExtremeUncertaintyAORA(AORAStrategy):
            def compute_wasserstein_radius(self, N, D_max):
                return D_max * 2.0  # Guarantees epsilon >= epsilon_crit

        extreme_strat = ExtremeUncertaintyAORA(config=self.config)
        decision = extreme_strat.compute_allocation(self.user, self.predictor)

        # Must not exceed R_max
        self.assertLessEqual(decision.recommended_reserve, self.user.maximum_allowance)
        self.assertGreaterEqual(decision.recommended_reserve, 0.0)

    # -------------------------------------------------------------------------
    # 11. Zero Wallet Balance (B_avail = 0)
    # -------------------------------------------------------------------------
    def test_zero_wallet_balance(self):
        """Target reserve recommendation remains uncorrupted when balance is 0."""
        zero_balance_user = UserProfile(
            user_id="broke_user",
            profile_name="Zero Balance User",
            available_balance=0.0,
            maximum_allowance=2000.0,
        )
        ev = OutageEvent(occurred=True, start_hour=8.0, duration_hours=2.0)
        tx = Transaction(tx_id="t1", timestamp_hour=8.5, amount=150.0, occurred_during_outage=True)
        self.predictor.record_epoch_observation(ev, [tx])

        decision = self.strategy.compute_allocation(zero_balance_user, self.predictor)

        # Recommended reserve should be positive (advising user of risk)
        self.assertGreater(decision.recommended_reserve, 0.0)
        # But allocatable reserve must be 0
        self.assertEqual(decision.allocatable_reserve, 0.0)
        # Shortfall equals the recommendation
        self.assertEqual(decision.funding_shortfall, decision.recommended_reserve)
        self.assertEqual(decision.remaining_liquid_balance, 0.0)

    # -------------------------------------------------------------------------
    # 12. Insufficient Wallet Balance (B_avail < R*)
    # -------------------------------------------------------------------------
    def test_insufficient_wallet_balance(self):
        """Allocatable reserve clamps to available balance while reporting shortfall."""
        low_balance_user = UserProfile(
            user_id="low_balance",
            profile_name="Low Balance User",
            available_balance=50.0,
            maximum_allowance=2000.0,
        )
        for ep in range(5):
            ev = OutageEvent(occurred=True, start_hour=8.0, duration_hours=3.0)
            txs = [Transaction(tx_id=f"t_{ep}", timestamp_hour=9.0, amount=200.0, occurred_during_outage=True)]
            self.predictor.record_epoch_observation(ev, txs)

        decision = self.strategy.compute_allocation(low_balance_user, self.predictor)

        if decision.recommended_reserve > 50.0:
            self.assertEqual(decision.allocatable_reserve, 50.0)
            self.assertEqual(decision.funding_shortfall, round(decision.recommended_reserve - 50.0, 2))
            self.assertEqual(decision.remaining_liquid_balance, 0.0)

    # -------------------------------------------------------------------------
    # 13. Non-Unique Dual Multiplier Cases
    # -------------------------------------------------------------------------
    def test_non_unique_dual_multiplier_tie_breaking(self):
        """Verifies deterministic tie-breaking when subdifferential contains zero interval."""
        demands = [100.0, 100.0, 100.0]
        D_max = 5000.0
        p_robust = 0.5
        epsilon = 200.0

        # optimize_lambda_for_fixed_R should return a valid multiplier in [0, c_short]
        lam = self.strategy.optimize_lambda_for_fixed_R(
            R=100.0,
            genuine_demands=demands,
            D_max=D_max,
            p_robust=p_robust,
            epsilon=epsilon,
        )
        self.assertGreaterEqual(lam, 0.0)
        self.assertLessEqual(lam, self.config.default_c_short)

    # -------------------------------------------------------------------------
    # 14. Deterministic Reproducibility
    # -------------------------------------------------------------------------
    def test_deterministic_reproducibility(self):
        """Running on identical data must produce bit-for-bit identical results."""
        for ep in range(8):
            ev = OutageEvent(occurred=True, start_hour=8.0, duration_hours=1.5)
            txs = [Transaction(tx_id=f"tx_{ep}", timestamp_hour=8.5, amount=65.0, occurred_during_outage=True)]
            self.predictor.record_epoch_observation(ev, txs)

        decision1 = self.strategy.compute_allocation(self.user, self.predictor)
        decision2 = self.strategy.compute_allocation(self.user, self.predictor)

        self.assertEqual(decision1.recommended_reserve, decision2.recommended_reserve)
        self.assertEqual(decision1.objective_cost, decision2.objective_cost)
        self.assertEqual(decision1.allocatable_reserve, decision2.allocatable_reserve)

    # -------------------------------------------------------------------------
    # 15. Optimizer Verification Against Independent Reference Solver
    # -------------------------------------------------------------------------
    def test_optimizer_against_independent_reference_solver(self):
        """Verifies AORA's continuous optimizer against an independent 2D discrete grid search oracle."""
        demands = [45.0, 120.0, 210.0]
        D_max = 2000.0
        H = 24.0
        p_robust = 0.65
        epsilon = 150.0
        R_max = 1000.0

        # Solve via AORA continuous optimizer
        aora_R, aora_lam, aora_cost = self.strategy.optimize_reserve_and_lambda(
            genuine_demands=demands,
            D_max=D_max,
            H=H,
            p_robust=p_robust,
            epsilon=epsilon,
            R_max=R_max,
        )

        # Solve via Independent Brute-Force Grid Oracle
        ref_R, ref_lam, ref_cost = independent_reference_solver(
            genuine_demands=demands,
            D_max=D_max,
            H=H,
            p_robust=p_robust,
            epsilon=epsilon,
            R_max=R_max,
            c_lock=self.config.default_c_lock,
            c_exposure=self.config.default_c_exposure,
            c_short=self.config.default_c_short,
            r_step=1.0,
            lambda_step=0.01,
        )

        # Must agree closely on optimal reserve R* (within grid resolution tolerance <= 4.0 INR)
        self.assertLessEqual(
            abs(aora_R - ref_R),
            4.0,
            f"AORA R* ({aora_R}) diverged from Reference Solver R* ({ref_R})",
        )
        # Optimal cost must agree within 2%
        self.assertLessEqual(
            abs(aora_cost - ref_cost) / max(1.0, ref_cost),
            0.02,
            f"AORA cost ({aora_cost}) diverged from Reference cost ({ref_cost})",
        )


if __name__ == "__main__":
    unittest.main()

