"""
Milestone 3 Validation Unit Tests:
- Dimensional consistency of objective function terms.
- Verification of Eve's Law compound variance.
- Support for Log-Normal and heavy-tailed Pareto demand.
- Cold-start safety and uncertainty interval widening.
- Atomic vs volume success rate metric validation.
"""

import math
import random
import unittest

from src.config import ProvisioningConfig
from src.data_generator import SyntheticDataGenerator
from src.models import OutageEvent, OutageProfile, Transaction, UserProfile
from src.predictor import OutageAndDemandPredictor
from src.simulator import ProvisioningSimulator
from src.strategies import (
    FixedAllowanceStrategy,
    DemandOnlyStrategy,
    ProposedJointOptimizationStrategy,
    UncertaintyAwareJointOptimizationStrategy,
)


class TestMilestone3Validation(unittest.TestCase):
    """Rigorous audit tests for Milestone 3 mathematical models and metrics."""

    def setUp(self):
        self.config = ProvisioningConfig()
        self.user = UserProfile(
            user_id="test_user",
            profile_name="Standard Tester",
            available_balance=5000.0,
            maximum_allowance=2000.0,
            spending_rate_mean=60.0,
            spending_rate_std=30.0,
            tx_probability_per_hour=0.4,
            peak_hours=[9, 13, 18],
        )

    def test_dimensional_consistency_of_objective_terms(self):
        """
        Verify that all 3 terms in J(R) evaluate to INR (Rupees):
        Term 1: c_lock [h^-1] * R [INR] * H [h] = [INR]
        Term 2: p_out [1] * c_short [1] * E[shortage] [INR] = [INR]
        Term 3: c_exposure [1] * (R^2 / R_max) [INR] = [INR]
        """
        strat = ProposedJointOptimizationStrategy(
            c_lock=0.0001,
            c_short=2.0,
            c_exposure=0.05,
            config=self.config,
        )

        R = 300.0
        H = 24.0
        p_out = 0.5
        mu_D = 200.0
        sigma_D = 50.0
        R_max = 2000.0

        # Term 1: Holding cost
        term1 = strat.c_lock * R * H
        # 0.0001 * 300 * 24 = 0.72 INR
        self.assertAlmostEqual(term1, 0.72, places=4)

        # Term 2: Shortage cost
        shortage = strat.expected_shortage(R, mu_D, sigma_D)
        term2 = p_out * strat.c_short * shortage
        self.assertGreater(shortage, 0.0)
        self.assertGreater(term2, 0.0)

        # Term 3: Financial exposure risk
        risk = strat.financial_risk_exposure(R, R_max)
        term3 = strat.c_exposure * risk
        # 0.05 * (300^2 / 2000) = 0.05 * 45 = 2.25 INR
        self.assertAlmostEqual(term3, 2.25, places=4)

        total_J = strat.evaluate_objective(R, H, p_out, mu_D, sigma_D, R_max)
        self.assertAlmostEqual(total_J, term1 + term2 + term3, places=4)

    def test_compound_variance_eves_law(self):
        """
        Verify Eve's Law (Law of Total Variance):
        Var(D_T) = E[T]*Var(X) + (E[X])^2 * Var(T)
        against empirical Monte Carlo sampling of compound sum.
        """
        rng = random.Random(42)
        mu_T = 3.0
        sigma_T = 1.0
        mu_X = 50.0
        sigma_X = 20.0

        theoretical_var = (mu_T * (sigma_X ** 2)) + ((mu_X ** 2) * (sigma_T ** 2))
        # 3.0 * 400 + 2500 * 1.0 = 1200 + 2500 = 3700

        # Monte Carlo simulation of compound spending
        mc_samples = []
        for _ in range(50000):
            T = max(0.1, rng.gauss(mu_T, sigma_T))
            # Integral / sum over duration T
            # For spending rate process with hourly variance sigma_X^2:
            # spend ~ N(T * mu_X, T * sigma_X^2)
            spend = rng.gauss(T * mu_X, math.sqrt(T) * sigma_X)
            mc_samples.append(spend)

        mc_mean = sum(mc_samples) / len(mc_samples)
        mc_var = sum((s - mc_mean) ** 2 for s in mc_samples) / (len(mc_samples) - 1)

        # Verify within 5% error margin of Monte Carlo
        error_ratio = abs(mc_var - theoretical_var) / theoretical_var
        self.assertLess(error_ratio, 0.05, f"Theoretical {theoretical_var} vs MC {mc_var}")

    def test_heavy_tailed_distributions_in_generator(self):
        """Verify that Log-Normal and Pareto demand generators produce valid and skewed transactions."""
        gen = SyntheticDataGenerator(seed=123)
        outage = OutageEvent(occurred=True, start_hour=8.0, duration_hours=4.0)

        # 1. Gaussian
        txs_gauss = gen.generate_transactions_for_horizon(self.user, outage, demand_distribution="gaussian")
        amounts_gauss = [t.amount for t in txs_gauss]
        self.assertTrue(all(a >= 10.0 for a in amounts_gauss))

        # 2. Log-Normal
        txs_log = gen.generate_transactions_for_horizon(self.user, outage, demand_distribution="lognormal")
        amounts_log = [t.amount for t in txs_log]
        self.assertTrue(all(10.0 <= a <= self.user.maximum_allowance for a in amounts_log))

        # 3. Pareto (Power-Law)
        txs_pareto = gen.generate_transactions_for_horizon(self.user, outage, demand_distribution="pareto")
        amounts_pareto = [t.amount for t in txs_pareto]
        self.assertTrue(all(10.0 <= a <= self.user.maximum_allowance for a in amounts_pareto))

        # Verify Pareto max is higher than Gaussian max over multiple epochs due to heavy tail
        all_p_max = []
        all_g_max = []
        for ep in range(50):
            tg = gen.generate_transactions_for_horizon(self.user, outage, demand_distribution="gaussian")
            tp = gen.generate_transactions_for_horizon(self.user, outage, demand_distribution="pareto")
            if tg:
                all_g_max.append(max(t.amount for t in tg))
            if tp:
                all_p_max.append(max(t.amount for t in tp))

        # Power-law generates higher peak transactions
        self.assertGreater(max(all_p_max), max(all_g_max))

    def test_cold_start_handling_and_epistemic_bounds(self):
        """Verify predictor handles 0 observations safely and widens confidence bounds."""
        pred = OutageAndDemandPredictor()

        # Completely empty memory
        self.assertEqual(len(pred.outage_history), 0)
        self.assertEqual(len(pred.transaction_history), 0)

        p_base = pred.estimate_outage_probability()
        self.assertEqual(p_base, pred.prior_outage_prob)

        p_robust, mu_D, sigma_D, R_floor = pred.estimate_robust_parameters(
            confidence_level=0.85,
            horizon_hours=24.0,
            maximum_allowance=2000.0,
        )

        # UCB must strictly expand outage probability above point prior
        self.assertGreater(p_robust, p_base)
        self.assertGreater(mu_D, 0.0)
        self.assertGreater(sigma_D, 0.0)
        self.assertGreaterEqual(R_floor, 0.0)

    def test_discrete_atomic_vs_volume_success_calculation(self):
        """Verify that insufficient reserve records discrete failed transactions accurately."""
        sim = ProvisioningSimulator(config=self.config, seed=42)
        strat = FixedAllowanceStrategy(fixed_amount=50.0, config=self.config)
        outage_scen = OutageProfile(
            profile_name="High Demand Outage",
            base_outage_probability=1.0,
            mean_duration_hours=8.0,
            std_duration_hours=0.5,
            burst_probability=0.0,
        )

        sums, traces = sim.run_benchmark(
            user=self.user,
            outage_profile=outage_scen,
            epochs=15,
            warmup_epochs=0,
            strategies=[strat],
        )

        summary = sums[0]
        # In this scenario, with fixed reserve = ₹50, payments > ₹50 will fail
        self.assertGreater(summary.total_failed_transactions, 0)
        self.assertLessEqual(summary.atomic_success_rate, 100.0)
        self.assertGreaterEqual(summary.realized_combined_cost, 0.0)


if __name__ == "__main__":
    unittest.main()
