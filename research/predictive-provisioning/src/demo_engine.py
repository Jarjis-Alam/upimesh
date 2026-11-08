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
    available_balance: float = 0.0
    funding_shortfall: float = 0.0
    remaining_liquid_balance: float = 0.0
    allocatable_reserve: float = 0.0


class DemoEngine:
    """
    Stateful demonstration engine driving the judge-facing dashboard.
    Executes actual predictive and allocation code for real-time responsiveness.
    """

    DEMO_SCENARIOS = {
        1: {
            "scenario_id": 1,
            "name": "Normal 5G",
            "title": "Scenario 1: Normal 5G",
            "subtitle": "Dense Urban Coverage",
            "network_status": "CONNECTED_5G",
            "signal_dbm": -68,
            "outage_p": 0.06,
            "duration_h": 0.35,
            "is_shock": False,
            "narrative": "User is in a dense urban zone with reliable 5G coverage (-68 dBm). With low outage risk (6%) and short expected outage duration (0.35h), holding excess reserve incurs unnecessary liquidity lockup. The system recommends ₹57, keeping remaining funds liquid in the primary account.",
        },
        2: {
            "scenario_id": 2,
            "name": "Deteriorating",
            "title": "Scenario 2: Network Deterioration",
            "subtitle": "Transit Corridor Entry",
            "network_status": "DEGRADING",
            "signal_dbm": -98,
            "outage_p": 0.45,
            "duration_h": 1.25,
            "is_shock": False,
            "narrative": "Approaching the underground metro transit corridor (-98 dBm), historical patterns indicate an elevated 45% outage probability lasting 1.25h. Predicted demand climbs and M2 steps up the reserve proactively to ₹105 before disconnection.",
        },
        3: {
            "scenario_id": 3,
            "name": "Grid Shock",
            "title": "Scenario 3: Sudden Grid Shock",
            "subtitle": "Tunnel Power Blackout",
            "network_status": "CRITICAL_SHOCK",
            "signal_dbm": -125,
            "outage_p": 0.88,
            "duration_h": 4.50,
            "is_shock": True,
            "narrative": "An unexpected electrical grid failure stalls the train inside the tunnel (-125 dBm). Outage probability jumps to 88% and expected duration reaches 4.50h. M2 detects the shock, activates the emergency safety floor, and scales reserves up to ₹268.",
        },
        4: {
            "scenario_id": 4,
            "name": "Fully Offline",
            "title": "Scenario 4: Fully Offline Operation",
            "subtitle": "Zero Cellular Backhaul",
            "network_status": "ACTIVE_OUTAGE",
            "signal_dbm": -130,
            "outage_p": 0.95,
            "duration_h": 5.00,
            "is_shock": True,
            "narrative": "Complete communication blackout (-130 dBm, 95% outage risk, 5.00h expected duration). Active offline payments draw down reserve headroom while AWDL maintains peer communication without internet. M2 maintains peak offline protection at ₹286.",
        },
        5: {
            "scenario_id": 5,
            "name": "Recovery",
            "title": "Scenario 5: Connectivity Recovery",
            "subtitle": "Restoration to 5G",
            "network_status": "RESTORED_5G",
            "signal_dbm": -65,
            "outage_p": 0.05,
            "duration_h": 0.30,
            "is_shock": False,
            "narrative": "Power and cellular connectivity return to 5G (-65 dBm). Outage risk drops back to 5% and shocks clear. The reserve recommendation safely scales down to liquid baseline (₹53) as unspent escrow is released back to the user's primary balance.",
        },
    }

    # Backward compatibility with 7-stage Milestone 4 demonstrator
    GUIDED_STAGES = [
        DEMO_SCENARIOS[1],
        DEMO_SCENARIOS[2],
        DEMO_SCENARIOS[2],
        DEMO_SCENARIOS[3],
        DEMO_SCENARIOS[3],
        DEMO_SCENARIOS[4],
        DEMO_SCENARIOS[5],
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
        self.active_scenario_id: int = 1
        self.current_stage_idx: int = 0
        self.timeline: List[TimelineEvent] = []
        self.event_counter: int = 0

        # Current simulated environment telemetry
        self.network_status = "CONNECTED_5G"
        self.signal_dbm = -68
        self.current_p_out = 0.06
        self.current_mean_duration = 0.35
        self.current_is_burst = False
        self.simulation_epoch = 0

        # Initial baseline computation
        self.reset_to_baseline()

    def _calibrate_predictors_for_condition(
        self,
        p_out: float,
        duration_h: float,
        is_shock: bool,
        seed: int = 42,
    ) -> None:
        """
        Calibrates the observation histories of all active predictors to accurately and cleanly
        represent the target network regime without cross-scenario historical contamination.
        """
        clamped_p = max(0.01, min(0.99, p_out))
        clamped_dur = max(0.1, min(12.0, duration_h))

        for name, pred in self.predictors.items():
            pred.outage_history.clear()
            pred.transaction_history.clear()
            pred.recent_brier_scores.clear()
            pred.recent_demand_errors.clear()

            pred.prior_outage_prob = clamped_p
            pred.prior_outage_duration = clamped_dur
            pred.prior_hourly_demand = self.user.spending_rate_mean

            dg = SyntheticDataGenerator(seed=seed)

            # Determine event occurrences to achieve target p_out in EWMA
            if clamped_p <= 0.06:
                pos = 14 if clamped_p >= 0.06 else 13
                indices = {pos}
            else:
                k = max(1, round(clamped_p * 20))
                step = 20.0 / k
                indices = set(int(round(j * step)) for j in range(k))

            for ep in range(20):
                occ = ep in indices
                dur = clamped_dur if occ else 0.0
                ev = OutageEvent(
                    occurred=occ,
                    start_hour=8.0 if occ else 0.0,
                    duration_hours=dur,
                    is_unexpected=is_shock,
                )
                txs = dg.generate_transactions_for_horizon(self.user, ev)
                pred.record_epoch_observation(ev, txs)

            pred.consecutive_shocks = 2 if is_shock else 0
            pred.current_alpha = min(0.65, pred.base_alpha * 2.5) if is_shock else pred.base_alpha

    def reset_to_baseline(self) -> None:
        """Resets the demonstrator to a clean initial state (Scenario 1: Normal 5G)."""
        self.data_gen.set_seed(self.seed)
        self.rng = random.Random(self.seed)
        self.timeline.clear()
        self.event_counter = 0
        self.simulation_epoch = 0

        self.apply_scenario(1)
        self.previous_decisions = dict(self.current_decisions)
        self.timeline.clear()
        self._record_timeline_event(
            "Scenario 1: Normal 5G (Baseline)",
            "Initial clean baseline with 5G coverage (-68 dBm). Outage risk 6%, expected duration 0.35h. Reserve set to ₹57.",
        )

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

        curr_int = int(round(curr.recommended_reserve))
        prev_int = int(round(prev.recommended_reserve))
        delta_int = curr_int - prev_int

        if not reasons:
            narrative = f"Recommended reserve remains steady at ₹{curr_int} (stable network conditions)."
        else:
            diff_str = f"+₹{delta_int}" if delta_int >= 0 else f"-₹{abs(delta_int)}"
            narrative = f"Recommendation shifted by {diff_str} (₹{prev_int} → ₹{curr_int}) because {', and '.join(reasons)}."

        narrative_with_funding = narrative
        if curr.funding_shortfall > 0:
            narrative_with_funding += f" [Wallet shortfall: ₹{curr.funding_shortfall:.0f} (Available balance: ₹{curr.available_balance:.0f}, Recommended: ₹{curr.recommended_reserve:.0f})]"

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
            narrative=narrative_with_funding,
            available_balance=curr.available_balance,
            funding_shortfall=curr.funding_shortfall,
            remaining_liquid_balance=curr.remaining_liquid_balance,
            allocatable_reserve=curr.allocatable_reserve,
        )

    # =========================================================================
    # Interactive Scenarios & Guided Stages
    # =========================================================================

    def set_wallet_balance(self, balance: float) -> Dict[str, Any]:
        """Sets the user's available bank/wallet balance and recalculates allocations."""
        self.user.available_balance = max(0.0, float(balance))
        self._recalculate_all_strategies()
        return self.get_full_state()

    def apply_scenario(self, scenario_id: int, wallet_balance: Optional[float] = None) -> Dict[str, Any]:
        """
        Executes one of the 5 official demonstration scenarios deterministically,
        updating telemetry, predictors, allocations, and transaction execution.
        """
        if wallet_balance is not None:
            self.user.available_balance = max(0.0, float(wallet_balance))
        scenario = self.DEMO_SCENARIOS.get(scenario_id)
        if not scenario:
            raise ValueError(f"Invalid scenario ID: {scenario_id}. Must be 1 to 5.")

        self.active_scenario_id = scenario_id
        self.current_stage_idx = scenario_id - 1
        self.previous_decisions = dict(self.current_decisions)

        self.network_status = scenario["network_status"]
        self.signal_dbm = scenario["signal_dbm"]
        self.current_p_out = scenario["outage_p"]
        self.current_mean_duration = scenario["duration_h"]
        self.current_is_burst = scenario["is_shock"]
        self.simulation_epoch += 1

        # Cleanly calibrate predictors for this scenario's conditions
        self._calibrate_predictors_for_condition(
            p_out=self.current_p_out,
            duration_h=self.current_mean_duration,
            is_shock=self.current_is_burst,
            seed=self.seed + scenario_id * 100,
        )

        # Recalculate all 4 strategies using their real mathematical models
        self._recalculate_all_strategies()

        # If Scenario 4 (Fully Offline), execute simulated offline transactions against reserves
        tx_result = None
        if scenario_id == 4:
            tx_result = self._execute_stage6_transactions([])

        diff = self.calculate_recommendation_diff()
        self._record_timeline_event(scenario["title"], scenario["narrative"], actual_tx_result=tx_result)

        return self.get_full_state()

    def execute_guided_stage(self, stage_id: int) -> Dict[str, Any]:
        """Backward-compatible mapping of stage_id to official demonstration scenarios."""
        stage_to_scenario = {
            1: 1,  # Stage 1 -> Scenario 1 (Normal 5G)
            2: 2,  # Stage 2 -> Scenario 2 (Deteriorating)
            3: 2,  # Stage 3 -> Scenario 2 (Deteriorating preparation)
            4: 3,  # Stage 4 -> Scenario 3 (Grid Shock)
            5: 3,  # Stage 5 -> Scenario 3 (Grid Shock recalculation)
            6: 4,  # Stage 6 -> Scenario 4 (Fully Offline execution)
            7: 5,  # Stage 7 -> Scenario 5 (Recovery)
        }
        scen_id = stage_to_scenario.get(stage_id, 1)
        self.apply_scenario(scen_id)
        self.current_stage_idx = max(0, min(len(self.GUIDED_STAGES) - 1, stage_id - 1))
        return self.get_full_state()

    def _execute_stage6_transactions(self, transactions: Optional[List[Transaction]] = None) -> Dict[str, Any]:
        """Simulates atomic execution of payment transactions during the active outage."""
        res_fixed = self.current_decisions["Fixed-₹500"].recommended_reserve
        res_m1 = self.current_decisions["Proposed-JointOpt"].recommended_reserve
        res_m2 = self.current_decisions["Uncertainty-Aware"].recommended_reserve

        # 3 discrete lifeline payments during tunnel outage: ₹120 fare, ₹65 station food, ₹45 battery
        offline_tx_amounts = [120.0, 65.0, 45.0]
        total_demand = sum(offline_tx_amounts)

        def run_drawdown(reserve: float):
            rem = reserve
            spent = 0.0
            failed = 0
            shortage = 0.0
            for amt in offline_tx_amounts:
                if rem >= amt:
                    rem -= amt
                    spent += amt
                else:
                    shortage += (amt - rem)
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
            "offline_tx_count": len(offline_tx_amounts),
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
        how the actual predictor and strategies respond without historical contamination.
        """
        self.previous_decisions = dict(self.current_decisions)
        self.current_p_out = max(0.01, min(0.99, outage_prob))
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

        self.simulation_epoch += 1

        self._calibrate_predictors_for_condition(
            p_out=self.current_p_out,
            duration_h=self.current_mean_duration,
            is_shock=self.current_is_burst,
            seed=self.seed + self.simulation_epoch,
        )

        self._recalculate_all_strategies()
        diff = self.calculate_recommendation_diff()
        self._record_timeline_event(
            "Manual Telemetry Adjustment",
            f"Presenter adjusted p_out={self.current_p_out:.2f}, dur={self.current_mean_duration:.1f}h",
        )

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
                "available_balance": dec.available_balance,
                "funding_shortfall": dec.funding_shortfall,
                "remaining_liquid_balance": dec.remaining_liquid_balance,
                "allocatable_reserve": dec.allocatable_reserve,
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
                "available_balance_inr": self.user.available_balance,
                "funding_shortfall_inr": m2_dec.funding_shortfall if m2_dec else 0.0,
                "remaining_liquid_inr": m2_dec.remaining_liquid_balance if m2_dec else 0.0,
                "allocatable_reserve_inr": m2_dec.allocatable_reserve if m2_dec else 0.0,
            },
            "recommendation_diff": asdict(diff),
            "strategies": strategy_cards,
            "timeline": timeline_dicts,
            "is_simulated": True,
            "simulation_disclaimer": "All network traces, outages, and payments are synthetically simulated via mathematical stochastic models in research/predictive-provisioning/.",
        }


DEMO_SCENARIOS = DemoEngine.DEMO_SCENARIOS


