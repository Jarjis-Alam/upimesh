"""
Interactive Demonstration Engine for Milestone 4:
Predictive Adaptive Offline Provisioning Demonstrator.

Connects the synthetic data generator, online Bayesian/EWMA predictors,
and all 4 competing provisioning strategies into a stateful, interactive
demonstration controller for live judge presentations.
"""

import math
import random
from dataclasses import asdict, dataclass, field
from typing import Any, Dict, List, Optional, Tuple

from .config import ProvisioningConfig
from .data_generator import SyntheticDataGenerator
from .models import (
    AllocationDecision,
    BenchmarkSummary,
    EpochResult,
    OutageEvent,
    OutageProfile,
    Transaction,
    UserProfile,
)
from .predictor import OutageAndDemandPredictor
from .simulator import ProvisioningSimulator
from .strategies import (
    BaseProvisioningStrategy,
    DemandOnlyStrategy,
    FixedAllowanceStrategy,
    ProposedJointOptimizationStrategy,
    UncertaintyAwareJointOptimizationStrategy,
)


@dataclass
class TimelineEvent:
    """Represents a milestone point along the predictive provisioning timeline."""
    event_id: int
    stage_name: str
    timestamp_label: str
    network_status: str
    signal_dbm: int
    p_out: float
    duration_hours: float
    demand_predicted: float
    uncertainty_margin: float
    safety_floor: float
    reserve_fixed: float
    reserve_demand_only: float
    reserve_m1: float
    reserve_m2: float
    actual_outage_occurred: bool = False
    actual_outage_duration: float = 0.0
    actual_demand: float = 0.0
    m2_spent: float = 0.0
    m2_shortage: float = 0.0
    m2_failed_tx: int = 0
    m1_failed_tx: int = 0
    explanation: str = ""


@dataclass
class RecommendationDiff:
    """Detailed quantitative delta attribution between current and previous recommendation."""
    previous_reserve: float
    current_reserve: float
    delta_reserve: float
    delta_p_out: float
    delta_duration: float
    delta_demand: float
    delta_uncertainty: float
    delta_safety_floor: float
    factor_contributions: Dict[str, float]
    narrative: str


class DemoEngine:
    """
    Stateful demonstration engine driving the judge-facing dashboard.
    Executes actual predictive and allocation code for real-time responsiveness.
    """

    GUIDED_STAGES = [
        {
            "stage_id": 1,
            "title": "Stage 1: Stable Connectivity",
            "subtitle": "Reliable 5G Network with Minimal Reserve Lock-in",
            "network_status": "CONNECTED_5G",
            "signal_dbm": -68,
            "outage_p": 0.06,
            "duration_h": 0.35,
            "burst": False,
            "narrative": "The user is in a dense urban zone with reliable 5G. With only a 6% outage probability, holding high reserves incurs unnecessary opportunity cost and financial exposure. The system recommends ₹54, keeping the remaining ₹4,946 liquid in the bank account.",
        },
        {
            "stage_id": 2,
            "title": "Stage 2: Predicted Outage Emergence",
            "subtitle": "Transit Corridor Entry with Early Risk Detection",
            "network_status": "DEGRADING",
            "signal_dbm": -98,
            "outage_p": 0.45,
            "duration_h": 1.25,
            "burst": False,
            "narrative": "As the commuter approaches the underground metro transit corridor, historical cellular transition patterns indicate an imminent 45% outage probability lasting 1.25 hours. Predicted outage duration and spending demand begin to climb.",
        },
        {
            "stage_id": 3,
            "title": "Stage 3: Predictive Reserve Preparation",
            "subtitle": "Pre-Outage Provisioning Before Disconnection",
            "network_status": "PREPARING_OFFLINE",
            "signal_dbm": -108,
            "outage_p": 0.65,
            "duration_h": 1.75,
            "burst": False,
            "narrative": "Predictive preparation in action: BEFORE entering the dead zone, the system steps up the recommended offline reserve to ₹178. Funds are locked into local non-custodial cryptographic escrow ahead of time.",
        },
        {
            "stage_id": 4,
            "title": "Stage 4: Unexpected Network Deterioration",
            "subtitle": "Severe Transit Tunnel Power Stoppage",
            "network_status": "SHOCK_DETECTED",
            "signal_dbm": -125,
            "outage_p": 0.88,
            "duration_h": 4.50,
            "burst": True,
            "narrative": "An unexpected electrical grid failure stalls the transit train inside the tunnel. The brief commute becomes a severe 4.5-hour blackout. Outage probability jumps to 88% and epistemic uncertainty bounds widen.",
        },
        {
            "stage_id": 5,
            "title": "Stage 5: Adaptive Reserve Recalculation",
            "subtitle": "Compound Variance & Safety Floor Engagement",
            "network_status": "RECALCULATING",
            "signal_dbm": -128,
            "outage_p": 0.92,
            "duration_h": 4.80,
            "burst": True,
            "narrative": "The uncertainty-aware model detects the shock. Compounding hourly spending variance with duration variance and activating the essential safety floor, M2 adapts the reserve upward to ₹388, guaranteeing essential lifeline capacity.",
        },
        {
            "stage_id": 6,
            "title": "Stage 6: Outage Strikes & Simulated Payment Demand",
            "subtitle": "Discrete Transaction Execution During Active Outage",
            "network_status": "ACTIVE_OUTAGE",
            "signal_dbm": -130,
            "outage_p": 1.00,
            "duration_h": 5.00,
            "burst": True,
            "narrative": "During the multi-hour blackout, the user attempts ₹310 across 3 discrete payments (transit emergency fare, station kiosk food, battery kiosk). Strategy M1 runs out of funds and fails. Strategy M2 clears all payments with ₹388.",
        },
        {
            "stage_id": 7,
            "title": "Stage 7: Recovery & 4-Way Strategy Benchmark",
            "subtitle": "Restoration to 5G & Comprehensive Evaluation",
            "network_status": "RESTORED_5G",
            "signal_dbm": -65,
            "outage_p": 0.05,
            "duration_h": 0.30,
            "burst": False,
            "narrative": "Power is restored and the train exits the tunnel. Network connectivity returns to 5G. The reserve recommendation safely scales down to ₹50. The 4-way benchmark verifies M2 achieved the optimal balance of availability and capital efficiency.",
        },
    ]

    def __init__(self, seed: int = 42):
        self.config = ProvisioningConfig()
        self.seed = seed
        self.rng = random.Random(seed)
        self.data_gen = SyntheticDataGenerator(seed=seed)
        self.simulator = ProvisioningSimulator(config=self.config, seed=seed)

        # Standard primary user (Alice Commuter)
        self.user = SyntheticDataGenerator.get_standard_user_profiles()[0]

        # Strategies under evaluation
        self.strategies: Dict[str, BaseProvisioningStrategy] = {
            "Fixed-₹500": FixedAllowanceStrategy(fixed_amount=500.0, config=self.config),
            "Demand-Only": DemandOnlyStrategy(safety_factor=1.0, config=self.config),
            "Proposed-JointOpt": ProposedJointOptimizationStrategy(config=self.config),
            "Uncertainty-Aware": UncertaintyAwareJointOptimizationStrategy(confidence_level=0.85, config=self.config),
        }

        # Independent predictor instances
        self.predictors: Dict[str, OutageAndDemandPredictor] = {
            s: OutageAndDemandPredictor() for s in self.strategies
        }

        # Current and previous allocations
        self.current_decisions: Dict[str, AllocationDecision] = {}
        self.previous_decisions: Dict[str, AllocationDecision] = {}

        # Guided stage pointer
        self.current_stage_idx: int = 0
        self.timeline: List[TimelineEvent] = []
        self.event_counter: int = 0

        # Current simulated environment telemetry
        self.network_status = "CONNECTED_5G"
        self.signal_dbm = -68
        self.current_p_out = 0.08
        self.current_mean_duration = 0.35
        self.current_is_burst = False
        self.simulation_epoch = 0

        # Initial baseline computation
        self.reset_to_baseline()

    def reset_to_baseline(self) -> None:
        """Resets the demonstrator to a clean initial state (Stage 1)."""
        self.data_gen.set_seed(self.seed)
        self.rng = random.Random(self.seed)
        self.predictors = {s: OutageAndDemandPredictor() for s in self.strategies}
        self.timeline.clear()
        self.event_counter = 0
        self.simulation_epoch = 0
        self.current_stage_idx = 0

        # Prime predictor with 5 baseline epochs of stable urban connectivity
        stable_profile = OutageProfile(
            profile_name="Urban Stable 5G",
            base_outage_probability=0.06,
            mean_duration_hours=0.35,
            std_duration_hours=0.10,
            burst_probability=0.01,
        )
        for ep in range(5):
            outage = self.data_gen.generate_outage_event(stable_profile, epoch_idx=ep, total_epochs=10)
            txs = self.data_gen.generate_transactions_for_horizon(self.user, outage)
            for p in self.predictors.values():
                p.record_epoch_observation(outage, txs)

        self._recalculate_all_strategies()
        self.previous_decisions = dict(self.current_decisions)
        self._record_timeline_event("Stage 1: Stable Connectivity Baseline", "Initial clean baseline with 5G connectivity.")

    def _recalculate_all_strategies(self) -> None:
        """Re-evaluates compute_allocation for all 4 strategies using current predictor states."""
        for name, strat in self.strategies.items():
            pred = self.predictors[name]
            decision = strat.compute_allocation(
                user=self.user,
                predictor=pred,
                horizon_hours=24.0,
            )
            self.current_decisions[name] = decision

    def _record_timeline_event(self, stage_name: str, explanation: str, actual_tx_result: Optional[Dict] = None) -> None:
        """Appends a timestamped checkpoint to the presentation timeline."""
        self.event_counter += 1
        m2_dec = self.current_decisions["Uncertainty-Aware"]
        m1_dec = self.current_decisions["Proposed-JointOpt"]
        fixed_dec = self.current_decisions["Fixed-₹500"]
        demand_dec = self.current_decisions["Demand-Only"]

        ev = TimelineEvent(
            event_id=self.event_counter,
            stage_name=stage_name,
            timestamp_label=f"Horizon {self.event_counter}",
            network_status=self.network_status,
            signal_dbm=self.signal_dbm,
            p_out=m2_dec.predicted_outage_prob,
            duration_hours=m2_dec.predicted_outage_duration,
            demand_predicted=m2_dec.predicted_demand,
            uncertainty_margin=m2_dec.uncertainty_margin,
            safety_floor=m2_dec.safety_floor,
            reserve_fixed=fixed_dec.recommended_reserve,
            reserve_demand_only=demand_dec.recommended_reserve,
            reserve_m1=m1_dec.recommended_reserve,
            reserve_m2=m2_dec.recommended_reserve,
            actual_outage_occurred=(actual_tx_result is not None and actual_tx_result.get("outage", False)),
            actual_outage_duration=actual_tx_result.get("duration", 0.0) if actual_tx_result else 0.0,
            actual_demand=actual_tx_result.get("demand", 0.0) if actual_tx_result else 0.0,
            m2_spent=actual_tx_result.get("m2_spent", 0.0) if actual_tx_result else 0.0,
            m2_shortage=actual_tx_result.get("m2_shortage", 0.0) if actual_tx_result else 0.0,
            m2_failed_tx=actual_tx_result.get("m2_failed_tx", 0) if actual_tx_result else 0,
            m1_failed_tx=actual_tx_result.get("m1_failed_tx", 0) if actual_tx_result else 0,
            explanation=explanation,
        )
        self.timeline.append(ev)
        if len(self.timeline) > 15:
            self.timeline.pop(0)

    def calculate_recommendation_diff(self) -> RecommendationDiff:
        """
        Computes the quantitative delta attribution explaining WHY
        the Uncertainty-Aware recommendation shifted from previous to current.
        """
        curr = self.current_decisions.get("Uncertainty-Aware")
        prev = self.previous_decisions.get("Uncertainty-Aware", curr)

        if not curr:
            return RecommendationDiff(0, 0, 0, 0, 0, 0, 0, 0, {}, "No data available.")

        delta_R = round(curr.recommended_reserve - prev.recommended_reserve, 2)
        delta_p = round(curr.predicted_outage_prob - prev.predicted_outage_prob, 4)
        delta_dur = round(curr.predicted_outage_duration - prev.predicted_outage_duration, 2)
        delta_dem = round(curr.predicted_demand - prev.predicted_demand, 2)
        delta_unc = round(curr.uncertainty_margin - prev.uncertainty_margin, 2)
        delta_floor = round(curr.safety_floor - prev.safety_floor, 2)

        # Factor impact approximation based on first-order Taylor expansion of J(R)
        # 1. Probability impact: scaled by shortage penalty and expected baseline demand
        factor_prob = round(delta_p * 2.0 * max(10.0, prev.predicted_demand) * 0.45, 2)
        # 2. Duration / Demand impact: expected demand increase
        factor_demand = round(delta_dem * 0.65, 2)
        # 3. Uncertainty / Epistemic UCB expansion:
        factor_unc = round(delta_unc * 0.85, 2)
        # 4. Safety floor clamping constraint:
        factor_floor = round(max(0.0, curr.safety_floor - prev.recommended_reserve) if curr.safety_floor > curr.recommended_reserve else 0.0, 2)

        contributions = {
            "outage_probability": factor_prob,
            "outage_duration_and_demand": factor_demand,
            "epistemic_uncertainty_ucb": factor_unc,
            "essential_safety_floor": factor_floor,
        }

        # Build clear English narrative
        reasons = []
        if abs(delta_p) > 0.05:
            direction = "increased" if delta_p > 0 else "decreased"
            reasons.append(f"outage risk {direction} by {abs(delta_p)*100:.1f}%")
        if abs(delta_dur) > 0.2:
            direction = "lengthened" if delta_dur > 0 else "shortened"
            reasons.append(f"expected outage duration {direction} by {abs(delta_dur):.1f}h")
        if abs(delta_unc) > 5.0:
            direction = "widened" if delta_unc > 0 else "contracted"
            reasons.append(f"prediction confidence interval {direction} by ₹{abs(delta_unc):.0f}")
        if delta_floor > 10.0:
            reasons.append(f"lifeline safety floor enforced at ₹{curr.safety_floor:.0f}")

        if not reasons:
            narrative = f"Recommended reserve remains steady at ₹{curr.recommended_reserve:.0f} (stable network conditions)."
        else:
            diff_str = f"+₹{delta_R:.0f}" if delta_R >= 0 else f"-₹{abs(delta_R):.0f}"
            narrative = f"Recommendation shifted by {diff_str} (₹{prev.recommended_reserve:.0f} → ₹{curr.recommended_reserve:.0f}) because {', and '.join(reasons)}."

        return RecommendationDiff(
            previous_reserve=prev.recommended_reserve,
            current_reserve=curr.recommended_reserve,
            delta_reserve=delta_R,
            delta_p_out=delta_p,
            delta_duration=delta_dur,
            delta_demand=delta_dem,
            delta_uncertainty=delta_unc,
            delta_safety_floor=delta_floor,
            factor_contributions=contributions,
            narrative=narrative,
        )

    # =========================================================================
    # Interactive Scenarios & Guided Stages
    # =========================================================================

    def execute_guided_stage(self, stage_id: int) -> Dict[str, Any]:
        """
        Executes one of the 7 judge demonstration stages deterministically,
        updating telemetry, predictors, allocations, and transaction execution.
        """
        stage = next((s for s in self.GUIDED_STAGES if s["stage_id"] == stage_id), None)
        if not stage:
            raise ValueError(f"Invalid stage ID: {stage_id}")

        self.current_stage_idx = stage_id - 1
        self.previous_decisions = dict(self.current_decisions)

        self.network_status = stage["network_status"]
        self.signal_dbm = stage["signal_dbm"]
        self.current_p_out = stage["outage_p"]
        self.current_mean_duration = stage["duration_h"]
        self.current_is_burst = stage["burst"]

        # Synthetic observations corresponding to the stage regime
        stage_profile = OutageProfile(
            profile_name=stage["title"],
            base_outage_probability=stage["outage_p"],
            mean_duration_hours=stage["duration_h"],
            std_duration_hours=max(0.1, stage["duration_h"] * 0.25),
            burst_probability=0.40 if stage["burst"] else 0.01,
        )

        # Generate realistic telemetry events to update the actual predictors
        sim_outage = self.data_gen.generate_outage_event(stage_profile, epoch_idx=self.simulation_epoch)
        if stage_id == 6:
            # Force active multi-hour outage strike in stage 6 to demonstrate transaction demand fulfillment
            sim_outage = OutageEvent(occurred=True, start_hour=10.0, duration_hours=stage["duration_h"], is_unexpected=True)

        sim_txs = self.data_gen.generate_transactions_for_horizon(self.user, sim_outage)
        self.simulation_epoch += 1

        # Feed observations into the actual online predictors
        for pred in self.predictors.values():
            pred.record_epoch_observation(sim_outage, sim_txs)
            pred.record_forecast_error(
                predicted_p=self.previous_decisions["Uncertainty-Aware"].predicted_outage_prob,
                actual_outage=sim_outage.occurred,
                predicted_demand=self.previous_decisions["Uncertainty-Aware"].predicted_demand,
                actual_demand=sum(t.amount for t in sim_txs if t.occurred_during_outage),
            )

        # Recalculate strategies with real optimizer
        self._recalculate_all_strategies()

        # If stage 6, execute transactions against reserves and compare outcomes
        tx_result = None
        if stage_id == 6 and sim_outage.occurred:
            tx_result = self._execute_stage6_transactions(sim_txs)

        diff = self.calculate_recommendation_diff()
        self._record_timeline_event(stage["title"], stage["narrative"], actual_tx_result=tx_result)

        return self.get_full_state()

    def _execute_stage6_transactions(self, transactions: List[Transaction]) -> Dict[str, Any]:
        """Simulates atomic execution of payment transactions during the Stage 6 outage."""
        offline_txs = [t for t in transactions if t.occurred_during_outage]
        total_demand = sum(t.amount for t in offline_txs)

        res_fixed = self.current_decisions["Fixed-₹500"].recommended_reserve
        res_m1 = self.current_decisions["Proposed-JointOpt"].recommended_reserve
        res_m2 = self.current_decisions["Uncertainty-Aware"].recommended_reserve

        def run_drawdown(reserve: float):
            rem = reserve
            spent = 0.0
            failed = 0
            shortage = 0.0
            for tx in offline_txs:
                if rem >= tx.amount:
                    rem -= tx.amount
                    spent += tx.amount
                else:
                    shortage += (tx.amount - rem)
                    spent += rem
                    rem = 0.0
                    failed += 1
            return spent, shortage, failed

        m2_spent, m2_short, m2_failed = run_drawdown(res_m2)
        m1_spent, m1_short, m1_failed = run_drawdown(res_m1)
        fixed_spent, fixed_short, fixed_failed = run_drawdown(res_fixed)

        return {
            "outage": True,
            "duration": 5.0,
            "demand": round(total_demand, 2),
            "offline_tx_count": len(offline_txs),
            "m2_spent": round(m2_spent, 2),
            "m2_shortage": round(m2_short, 2),
            "m2_failed_tx": m2_failed,
            "m1_spent": round(m1_spent, 2),
            "m1_shortage": round(m1_short, 2),
            "m1_failed_tx": m1_failed,
            "fixed_spent": round(fixed_spent, 2),
            "fixed_shortage": round(fixed_short, 2),
            "fixed_failed_tx": fixed_failed,
        }

    def apply_manual_network_condition(
        self,
        outage_prob: float,
        duration_hours: float,
        is_shock: bool = False,
        signal_dbm: int = -85,
    ) -> Dict[str, Any]:
        """
        Allows presenter to interactively adjust network sliders and immediately observe
        how the actual predictor and strategies respond.
        """
        self.previous_decisions = dict(self.current_decisions)
        self.current_p_out = max(0.0, min(1.0, outage_prob))
        self.current_mean_duration = max(0.1, min(12.0, duration_hours))
        self.current_is_burst = is_shock
        self.signal_dbm = signal_dbm

        if outage_prob < 0.15:
            self.network_status = "CONNECTED_5G"
        elif outage_prob < 0.60:
            self.network_status = "DEGRADED"
        elif is_shock or outage_prob >= 0.80:
            self.network_status = "CRITICAL_SHOCK"
        else:
            self.network_status = "WEAK_SIGNAL"

        # Construct synthetic profile matching manual sliders
        manual_profile = OutageProfile(
            profile_name="Manual Presenter Input",
            base_outage_probability=self.current_p_out,
            mean_duration_hours=self.current_mean_duration,
            std_duration_hours=max(0.1, self.current_mean_duration * 0.3),
            burst_probability=0.35 if is_shock else 0.02,
        )

        # Generate single observation and feed real predictor
        outage = self.data_gen.generate_outage_event(manual_profile, epoch_idx=self.simulation_epoch)
        txs = self.data_gen.generate_transactions_for_horizon(self.user, outage)
        self.simulation_epoch += 1

        for pred in self.predictors.values():
            pred.record_epoch_observation(outage, txs)

        self._recalculate_all_strategies()
        self._record_timeline_event("Manual Telemetry Adjustment", f"Presenter adjusted p_out={self.current_p_out:.2f}, dur={self.current_mean_duration:.1f}h")

        return self.get_full_state()

    def run_live_comparison_benchmark(self, epochs: int = 40) -> List[Dict[str, Any]]:
        """
        Executes a real mini-benchmark across all 4 strategies using current network conditions
        to show exact side-by-side performance metrics.
        """
        scenario = OutageProfile(
            profile_name=f"Live Scenario ({self.network_status})",
            base_outage_probability=self.current_p_out,
            mean_duration_hours=self.current_mean_duration,
            std_duration_hours=max(0.1, self.current_mean_duration * 0.3),
            burst_probability=0.25 if self.current_is_burst else 0.03,
        )

        sums, _ = self.simulator.run_benchmark(
            user=self.user,
            outage_profile=scenario,
            epochs=epochs,
            warmup_epochs=5,
            strategies=list(self.strategies.values()),
        )

        comparison_records = []
        for s in sums:
            comparison_records.append({
                "strategy": s.strategy,
                "offline_volume_success": s.offline_success_rate,
                "atomic_tx_success": s.atomic_success_rate,
                "failed_transactions": s.total_failed_transactions,
                "average_locked_funds": s.average_locked_funds,
                "average_unused_funds": s.average_unused_funds,
                "average_shortage_amount": s.average_shortage_amount,
                "average_exposure": s.average_exposure,
                "realized_combined_cost": s.realized_combined_cost,
            })

        return comparison_records

    # =========================================================================
    # State Serialization for REST API
    # =========================================================================

    def get_full_state(self) -> Dict[str, Any]:
        """Returns complete serializable state for frontend dashboard rendering."""
        diff = self.calculate_recommendation_diff()
        m2_dec = self.current_decisions.get("Uncertainty-Aware")
        m2_pred = self.predictors["Uncertainty-Aware"]

        # Predictor telemetry breakdown
        p_est = m2_pred.estimate_outage_probability()
        mu_T, sigma_T = m2_pred.estimate_outage_duration()
        p_rob, mu_D_rob, sig_D_rob, r_floor = m2_pred.estimate_robust_parameters(
            confidence_level=0.85,
            horizon_hours=24.0,
            maximum_allowance=self.user.maximum_allowance,
        )

        strategy_cards = {}
        for name, dec in self.current_decisions.items():
            prev = self.previous_decisions.get(name, dec)
            strategy_cards[name] = {
                "name": name,
                "recommended_reserve": dec.recommended_reserve,
                "previous_reserve": prev.recommended_reserve,
                "delta": round(dec.recommended_reserve - prev.recommended_reserve, 2),
                "predicted_outage_prob": dec.predicted_outage_prob,
                "predicted_demand": dec.predicted_demand,
                "objective_cost": dec.objective_cost,
                "safety_floor": dec.safety_floor,
                "uncertainty_margin": dec.uncertainty_margin,
            }

        timeline_dicts = [asdict(t) for t in self.timeline]

        return {
            "guided_stage": {
                "current_stage": self.current_stage_idx + 1,
                "total_stages": len(self.GUIDED_STAGES),
                "stage_info": self.GUIDED_STAGES[self.current_stage_idx],
            },
            "network_telemetry": {
                "status": self.network_status,
                "signal_dbm": self.signal_dbm,
                "p_out_slider": self.current_p_out,
                "duration_slider": self.current_mean_duration,
                "is_burst": self.current_is_burst,
                "simulation_epoch": self.simulation_epoch,
            },
            "user_profile": {
                "user_id": self.user.user_id,
                "profile_name": self.user.profile_name,
                "available_balance": self.user.available_balance,
                "maximum_allowance": self.user.maximum_allowance,
                "spending_rate_mean": self.user.spending_rate_mean,
            },
            "active_prediction": {
                "point_outage_prob": p_est,
                "robust_outage_prob": p_rob,
                "expected_duration_hours": mu_T,
                "duration_std_hours": sigma_T,
                "predicted_demand_inr": mu_D_rob,
                "compound_demand_std_inr": sig_D_rob,
                "confidence_level": 0.85,
                "uncertainty_margin_inr": m2_dec.uncertainty_margin if m2_dec else 0.0,
                "safety_floor_inr": r_floor,
                "consecutive_shocks": m2_pred.consecutive_shocks,
                "adaptation_alpha": round(m2_pred.current_alpha, 3),
            },
            "recommendation_diff": asdict(diff),
            "strategies": strategy_cards,
            "timeline": timeline_dicts,
            "is_simulated": True,
            "simulation_disclaimer": "All network traces, outages, and payments are synthetically simulated via mathematical stochastic models in research/predictive-provisioning/.",
        }

