"""
Regression test suite specifically verifying robust provisioning performance
in difficult connectivity scenarios: rural weak signals, non-stationary travel shifts,
and sudden adversarial grid shocks.
"""

import unittest
from src.config import ProvisioningConfig
from src.data_generator import SyntheticDataGenerator
from src.models import OutageEvent, OutageProfile, Transaction, UserProfile
from src.predictor import OutageAndDemandPredictor
from src.simulator import ProvisioningSimulator
from src.strategies import (
    DemandOnlyStrategy,
    FixedAllowanceStrategy,
    ProposedJointOptimizationStrategy,
    UncertaintyAwareJointOptimizationStrategy,
)


class TestDifficultScenarioRegression(unittest.TestCase):
    """Regression test cases verifying resilience to high-variance, shifting, and shock environments."""

    def setUp(self):
        self.config = ProvisioningConfig()
        self.user = UserProfile(
            user_id="alice_test",
            profile_name="Alice Commuter",
            available_balance=5000.0,
            maximum_allowance=2000.0,
        )

    # -------------------------------------------------------------------------
    # Regression Test 1: Rural Weak Signal (High duration variance)
    # -------------------------------------------------------------------------
    def test_rural_weak_signal_significantly_outperforms_baseline(self):
        scenario = OutageProfile(
            profile_name="Rural Weak Signal",
            base_outage_probability=0.75,
            mean_duration_hours=5.0,
            std_duration_hours=2.0,
        )

        sim = ProvisioningSimulator(seed=101)
        summaries, _ = sim.run_benchmark(
            user=self.user,
            outage_profile=scenario,
            epochs=30,
            warmup_epochs=5,
        )

        s_baseline = next(s for s in summaries if s.strategy == "Proposed-JointOpt")
        s_robust = next(s for s in summaries if s.strategy == "Uncertainty-Aware")
        s_demand = next(s for s in summaries if s.strategy == "Demand-Only")

        # Uncertainty-Aware must achieve higher success rate than baseline
        self.assertGreater(
            s_robust.offline_success_rate,
            s_baseline.offline_success_rate,
            f"Robust ({s_robust.offline_success_rate}%) did not outperform baseline ({s_baseline.offline_success_rate}%) in Rural!",
        )

        # Uncertainty-Aware must still lock significantly less funds than Demand-Only
        self.assertLess(
            s_robust.average_locked_funds,
            s_demand.average_locked_funds,
            f"Robust locked ₹{s_robust.average_locked_funds}, which is not less than Demand-Only ₹{s_demand.average_locked_funds}",
        )

    # -------------------------------------------------------------------------
    # Regression Test 2: Non-Stationary Shift Adaptation
    # -------------------------------------------------------------------------
    def test_non_stationary_shift_adapts_quickly(self):
        pred = OutageAndDemandPredictor(ewma_alpha=0.20)

        # Phase 1: 20 epochs of reliable connectivity
        for _ in range(20):
            pred.record_epoch_observation(
                OutageEvent(occurred=False),
                [Transaction(tx_id="1", timestamp_hour=10.0, amount=50.0, occurred_during_outage=False)],
            )
            pred.record_forecast_error(predicted_p=0.05, actual_outage=False, predicted_demand=0.0, actual_demand=0.0)

        p_before = pred.estimate_outage_probability()
        self.assertLess(p_before, 0.15)

        # Phase 2: Sudden regime change (3 consecutive long outages)
        for _ in range(3):
            pred.record_epoch_observation(
                OutageEvent(occurred=True, duration_hours=4.0),
                [Transaction(tx_id="2", timestamp_hour=14.0, amount=200.0, occurred_during_outage=True)],
            )
            # Record surprise shock
            pred.record_forecast_error(predicted_p=p_before, actual_outage=True, predicted_demand=20.0, actual_demand=200.0)

        # Predictor must have boosted learning rate and adapted upwards
        p_after = pred.estimate_outage_probability()
        self.assertGreater(
            p_after,
            0.40,
            f"Predictor failed to adapt quickly to regime shift: p_after={p_after}",
        )

    # -------------------------------------------------------------------------
    # Regression Test 3: Adversarial Grid Shock & Safety Floor
    # -------------------------------------------------------------------------
    def test_adversarial_shock_activates_safety_floor(self):
        pred = OutageAndDemandPredictor()
        # Seed with transaction history
        for _ in range(5):
            pred.record_epoch_observation(
                OutageEvent(occurred=True, duration_hours=1.0),
                [Transaction(tx_id="1", timestamp_hour=12.0, amount=80.0, occurred_during_outage=True)],
            )
            # Record an unexpected shock
            pred.record_forecast_error(predicted_p=0.10, actual_outage=True, predicted_demand=10.0, actual_demand=250.0)

        p_rob, mu_rob, sig_rob, R_floor = pred.estimate_robust_parameters(confidence_level=0.85)

        self.assertGreater(
            R_floor,
            40.0,
            f"Safety floor did not activate under shock conditions: R_floor={R_floor}",
        )

        strat_robust = UncertaintyAwareJointOptimizationStrategy(confidence_level=0.85, use_safety_floor=True)
        decision = strat_robust.compute_allocation(self.user, pred)

        self.assertGreaterEqual(
            decision.recommended_reserve,
            R_floor,
            "Allocation fell below the safety floor!",
        )

    # -------------------------------------------------------------------------
    # Regression Test 4: Confidence Scaling Monotonicity
    # -------------------------------------------------------------------------
    def test_confidence_scaling_monotonicity(self):
        pred = OutageAndDemandPredictor(prior_outage_prob=0.5, prior_outage_duration=3.0)
        for _ in range(10):
            pred.record_epoch_observation(
                OutageEvent(occurred=True, duration_hours=3.0),
                [Transaction(tx_id="1", timestamp_hour=12.0, amount=60.0, occurred_during_outage=True)],
            )

        reserves = []
        for kappa in [0.50, 0.70, 0.85, 0.95]:
            strat = UncertaintyAwareJointOptimizationStrategy(confidence_level=kappa)
            dec = strat.compute_allocation(self.user, pred)
            reserves.append((kappa, dec.recommended_reserve))

        # Check monotonicity: R(kappa) must not decrease as kappa increases
        for i in range(len(reserves) - 1):
            k1, r1 = reserves[i]
            k2, r2 = reserves[i + 1]
            self.assertLessEqual(
                r1,
                r2,
                f"Confidence monotonicity violated: kappa={k1} gave R={r1}, kappa={k2} gave R={r2}",
            )

    # -------------------------------------------------------------------------
    # Regression Test 5: Confirmed Zero-Outage Environment Zero Floor
    # -------------------------------------------------------------------------
    def test_confirmed_connected_regime_has_zero_floor(self):
        pred = OutageAndDemandPredictor(prior_outage_prob=0.0)
        for _ in range(30):
            pred.record_epoch_observation(
                OutageEvent(occurred=False),
                [Transaction(tx_id="1", timestamp_hour=10.0, amount=50.0, occurred_during_outage=False)],
            )

        _, _, _, R_floor = pred.estimate_robust_parameters(confidence_level=0.85)
        self.assertEqual(
            R_floor,
            0.0,
            f"Safety floor must be 0.0 in confirmed reliable regime, got {R_floor}!",
        )


if __name__ == "__main__":
    unittest.main()

