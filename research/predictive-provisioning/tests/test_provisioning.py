"""
Unit and invariant verification test suite for predictive allowance provisioning.
Validates financial constraints, monotonicity, edge cases, cold-starts, and determinism.
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
)


class TestPredictiveProvisioningInvariants(unittest.TestCase):
    """Verifies that all theoretical invariants and edge cases hold strictly."""

    def setUp(self):
        self.config = ProvisioningConfig()
        self.user = UserProfile(
            user_id="test_user",
            profile_name="Standard Test User",
            available_balance=1500.0,
            maximum_allowance=1000.0,
        )
        self.predictor = OutageAndDemandPredictor()

    # -------------------------------------------------------------------------
    # Invariant 1: Reserve never exceeds available balance
    # -------------------------------------------------------------------------
    def test_reserve_never_exceeds_available_balance(self):
        low_balance_user = UserProfile(
            user_id="poor_user",
            profile_name="Low Balance User",
            available_balance=250.0,
            maximum_allowance=2000.0,
        )
        strategies = [
            FixedAllowanceStrategy(fixed_amount=800.0, config=self.config),
            DemandOnlyStrategy(config=self.config),
            ProposedJointOptimizationStrategy(config=self.config),
        ]

        # Simulate high demand history
        for _ in range(10):
            self.predictor.record_epoch_observation(
                OutageEvent(occurred=True, duration_hours=6.0),
                [Transaction(tx_id="1", timestamp_hour=1.0, amount=500.0, occurred_during_outage=True)],
            )

        for strat in strategies:
            decision = strat.compute_allocation(low_balance_user, self.predictor)
            self.assertLessEqual(
                decision.recommended_reserve,
                low_balance_user.available_balance,
                f"Strategy {strat.name} exceeded available balance!",
            )
            self.assertGreaterEqual(decision.recommended_reserve, 0.0)

    # -------------------------------------------------------------------------
    # Invariant 2: Reserve never exceeds configured allowance limit
    # -------------------------------------------------------------------------
    def test_reserve_never_exceeds_allowance_limit(self):
        rich_user = UserProfile(
            user_id="rich_user",
            profile_name="High Balance User",
            available_balance=50000.0,
            maximum_allowance=800.0,
        )
        strategies = [
            FixedAllowanceStrategy(fixed_amount=2000.0, config=self.config),
            DemandOnlyStrategy(config=self.config),
            ProposedJointOptimizationStrategy(config=self.config),
        ]

        for strat in strategies:
            decision = strat.compute_allocation(rich_user, self.predictor)
            self.assertLessEqual(
                decision.recommended_reserve,
                rich_user.maximum_allowance,
                f"Strategy {strat.name} exceeded maximum allowance limit!",
            )

    # -------------------------------------------------------------------------
    # Invariant 3: Zero outage probability should not cause maximum provisioning
    # -------------------------------------------------------------------------
    def test_zero_outage_probability_does_not_overprovision(self):
        # Set up a predictor with exclusively connected history (no outages)
        pred_connected = OutageAndDemandPredictor(prior_outage_prob=0.0)
        for _ in range(30):
            pred_connected.record_epoch_observation(
                OutageEvent(occurred=False),
                [Transaction(tx_id="1", timestamp_hour=2.0, amount=100.0, occurred_during_outage=False)],
            )

        strat_joint = ProposedJointOptimizationStrategy(config=self.config)
        decision = strat_joint.compute_allocation(self.user, pred_connected)

        # When outage probability is 0 (or near 0), optimal reserve must be 0
        # because locking funds has non-zero cost c_lock, while shortage risk is zero.
        self.assertEqual(
            decision.recommended_reserve,
            0.0,
            "Proposed strategy allocated non-zero reserve when outage probability is zero!",
        )

    # -------------------------------------------------------------------------
    # Invariant 4: Monotonicity — Higher predicted demand should not reduce reserve
    # -------------------------------------------------------------------------
    def test_higher_demand_does_not_reduce_reserve(self):
        strat = ProposedJointOptimizationStrategy(config=self.config)

        # Predictor A: Low spending history
        pred_low = OutageAndDemandPredictor(prior_outage_prob=0.5, prior_hourly_demand=20.0)
        pred_low.record_epoch_observation(
            OutageEvent(occurred=True, duration_hours=2.0),
            [Transaction(tx_id="1", timestamp_hour=1.0, amount=20.0, occurred_during_outage=True)],
        )

        # Predictor B: High spending history
        pred_high = OutageAndDemandPredictor(prior_outage_prob=0.5, prior_hourly_demand=120.0)
        pred_high.record_epoch_observation(
            OutageEvent(occurred=True, duration_hours=2.0),
            [Transaction(tx_id="1", timestamp_hour=1.0, amount=300.0, occurred_during_outage=True)],
        )

        decision_low = strat.compute_allocation(self.user, pred_low)
        decision_high = strat.compute_allocation(self.user, pred_high)

        self.assertGreaterEqual(
            decision_high.recommended_reserve,
            decision_low.recommended_reserve,
            f"Higher demand yielded lower reserve: low={decision_low.recommended_reserve}, high={decision_high.recommended_reserve}",
        )

    # -------------------------------------------------------------------------
    # Invariant 5: Identical random seeds reproduce identical experiments
    # -------------------------------------------------------------------------
    def test_reproducible_random_seeds(self):
        scenario = OutageProfile(
            profile_name="Test Scenario",
            base_outage_probability=0.5,
            mean_duration_hours=1.5,
            std_duration_hours=0.5,
        )

        sim1 = ProvisioningSimulator(seed=12345)
        summaries1, traces1 = sim1.run_benchmark(self.user, scenario, epochs=15, warmup_epochs=3)

        sim2 = ProvisioningSimulator(seed=12345)
        summaries2, traces2 = sim2.run_benchmark(self.user, scenario, epochs=15, warmup_epochs=3)

        self.assertEqual(len(traces1), len(traces2))
        for t1, t2 in zip(traces1, traces2):
            self.assertEqual(t1.reserve_allocated, t2.reserve_allocated)
            self.assertEqual(t1.actual_outage, t2.actual_outage)
            self.assertEqual(t1.actual_demand_during_outage, t2.actual_demand_during_outage)
            self.assertEqual(t1.shortage_amount, t2.shortage_amount)

        for s1, s2 in zip(summaries1, summaries2):
            self.assertEqual(s1.offline_success_rate, s2.offline_success_rate)
            self.assertEqual(s1.average_locked_funds, s2.average_locked_funds)
            self.assertEqual(s1.average_shortage_amount, s2.average_shortage_amount)

    # -------------------------------------------------------------------------
    # Invariant 6: Cold start / Missing / Insufficient data safety
    # -------------------------------------------------------------------------
    def test_missing_and_insufficient_historical_data_handled_safely(self):
        empty_predictor = OutageAndDemandPredictor()
        strategies = [
            FixedAllowanceStrategy(config=self.config),
            DemandOnlyStrategy(config=self.config),
            ProposedJointOptimizationStrategy(config=self.config),
        ]

        for strat in strategies:
            # Must not throw ZeroDivisionError, IndexError, or ValueError
            decision = strat.compute_allocation(self.user, empty_predictor)
            self.assertIsNotNone(decision)
            self.assertGreaterEqual(decision.recommended_reserve, 0.0)
            self.assertLessEqual(decision.recommended_reserve, self.user.maximum_allowance)

    # -------------------------------------------------------------------------
    # Invariant 7: Zero or negative balance yields exactly zero reserve
    # -------------------------------------------------------------------------
    def test_zero_or_negative_balance_yields_zero_reserve(self):
        zero_user = UserProfile(
            user_id="broke_user",
            profile_name="Broke User",
            available_balance=0.0,
            maximum_allowance=1000.0,
        )
        strat = ProposedJointOptimizationStrategy(config=self.config)
        decision = strat.compute_allocation(zero_user, self.predictor)
        self.assertEqual(decision.recommended_reserve, 0.0)

    # -------------------------------------------------------------------------
    # Invariant 8: Cost trade-off sensitivity
    # -------------------------------------------------------------------------
    def test_cost_sensitivity_tradeoff(self):
        # When shortage penalty is very high, reserve should be higher
        strat_low_penalty = ProposedJointOptimizationStrategy(c_short=1.1, c_lock=0.001)
        strat_high_penalty = ProposedJointOptimizationStrategy(c_short=5.0, c_lock=0.00001)

        pred = OutageAndDemandPredictor(prior_outage_prob=0.6, prior_hourly_demand=50.0)

        decision_low = strat_low_penalty.compute_allocation(self.user, pred)
        decision_high = strat_high_penalty.compute_allocation(self.user, pred)

        self.assertGreater(
            decision_high.recommended_reserve,
            decision_low.recommended_reserve,
            "Higher shortage penalty did not increase reserve!",
        )


if __name__ == "__main__":
    unittest.main()

