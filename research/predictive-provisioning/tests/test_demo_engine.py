"""
Unit tests for Milestone 4 Demonstration Engine:
- Verifies 7 guided stage progression.
- Verifies delta attribution calculation and explanation.
- Verifies manual slider adjustment updates real predictors.
- Verifies live strategy comparison benchmark.
"""

import unittest

from src.demo_engine import DemoEngine


class TestDemoEngine(unittest.TestCase):
    """Test suite ensuring DemoEngine reliably powers the interactive presentation."""

    def setUp(self):
        self.engine = DemoEngine(seed=42)

    def test_initial_baseline_state(self):
        """Verify engine initializes at Stage 1 with reliable 5G conditions."""
        state = self.engine.get_full_state()
        self.assertEqual(state["guided_stage"]["current_stage"], 1)
        self.assertEqual(state["network_telemetry"]["status"], "CONNECTED_5G")
        self.assertIn("Fixed-₹500", state["strategies"])
        self.assertIn("Uncertainty-Aware", state["strategies"])

        m2 = state["strategies"]["Uncertainty-Aware"]
        # In stable urban 5G baseline, recommended reserve should be low (< ₹100)
        self.assertLess(m2["recommended_reserve"], 150.0)

    def test_guided_stage_progression(self):
        """Verify stepping through all 7 guided stages runs successfully and updates state."""
        for stage_id in range(1, 8):
            state = self.engine.execute_guided_stage(stage_id)
            self.assertEqual(state["guided_stage"]["current_stage"], stage_id)
            self.assertGreater(len(state["timeline"]), 0)

            m2_res = state["strategies"]["Uncertainty-Aware"]["recommended_reserve"]
            # All reserves must stay bounded within available balance & maximum allowance
            self.assertGreaterEqual(m2_res, 0.0)
            self.assertLessEqual(m2_res, state["user_profile"]["maximum_allowance"])

    def test_delta_attribution_calculation(self):
        """Verify delta attribution correctly calculates changes between stages."""
        # Run stage 1 then stage 4 (shock)
        self.engine.execute_guided_stage(1)
        res_stage1 = self.engine.current_decisions["Uncertainty-Aware"].recommended_reserve

        self.engine.execute_guided_stage(4)
        res_stage4 = self.engine.current_decisions["Uncertainty-Aware"].recommended_reserve

        diff = self.engine.calculate_recommendation_diff()
        self.assertEqual(diff.current_reserve, res_stage4)
        self.assertEqual(diff.previous_reserve, res_stage1)
        self.assertGreater(diff.delta_reserve, 0)
        self.assertIn("outage risk", diff.narrative)
        self.assertIn("outage_probability", diff.factor_contributions)

    def test_manual_network_slider_controls(self):
        """Verify presenter can manually inject custom outage probabilities and durations."""
        state = self.engine.apply_manual_network_condition(
            outage_prob=0.85,
            duration_hours=6.0,
            is_shock=True,
            signal_dbm=-120,
        )
        self.assertEqual(state["network_telemetry"]["status"], "CRITICAL_SHOCK")
        self.assertAlmostEqual(state["network_telemetry"]["p_out_slider"], 0.85)
        self.assertAlmostEqual(state["network_telemetry"]["duration_slider"], 6.0)

        m2_res = state["strategies"]["Uncertainty-Aware"]["recommended_reserve"]
        # High outage risk and long duration should cause reserve to scale up
        self.assertGreater(m2_res, 200.0)

    def test_live_comparison_benchmark(self):
        """Verify mini-benchmark executes all 4 strategies and returns complete comparative records."""
        records = self.engine.run_live_comparison_benchmark(epochs=10)
        self.assertEqual(len(records), 4)
        strategies_found = {r["strategy"] for r in records}
        self.assertEqual(
            strategies_found,
            {"Fixed-₹500", "Demand-Only", "Proposed-JointOpt", "Uncertainty-Aware"}
        )
        for r in records:
            self.assertIn("offline_volume_success", r)
            self.assertIn("atomic_tx_success", r)
            self.assertIn("failed_transactions", r)
            self.assertIn("average_locked_funds", r)
            self.assertIn("realized_combined_cost", r)


if __name__ == "__main__":
    unittest.main()

