"""
Simulation engine orchestrating the evaluation of competing provisioning strategies
across multiple users, outage scenarios, temporal epochs, and random seeds.
"""

import math
from typing import Dict, List, Tuple
from .config import ProvisioningConfig
from .data_generator import SyntheticDataGenerator
from .models import (
    BenchmarkSummary,
    EpochResult,
    OutageProfile,
    UserProfile,
)
from .predictor import OutageAndDemandPredictor
from .strategies import (
    BaseProvisioningStrategy,
    DemandOnlyStrategy,
    FixedAllowanceStrategy,
    ProposedJointOptimizationStrategy,
    UncertaintyAwareJointOptimizationStrategy,
)


class ProvisioningSimulator:
    """
    Simulates consecutive planning horizons (epochs) under realistic user spending
    and network outage behaviors, recording detailed transaction and financial metrics.
    """

    def __init__(
        self,
        config: ProvisioningConfig = ProvisioningConfig(),
        seed: int = 42,
    ):
        self.config = config
        self.seed = seed
        self.data_gen = SyntheticDataGenerator(seed=seed)

    def run_benchmark(
        self,
        user: UserProfile,
        outage_profile: OutageProfile,
        epochs: int = 60,
        warmup_epochs: int = 10,
        horizon_hours: float = 24.0,
        strategies: List[BaseProvisioningStrategy] = None,
        demand_distribution: str = "gaussian",
    ) -> Tuple[List[BenchmarkSummary], List[EpochResult]]:
        """
        Runs a side-by-side benchmark of competing strategies on identical generated scenarios:
        1. Fixed Allowance (₹500 preset)
        2. Demand-Only
        3. Proposed Joint Optimization (Milestone 1)
        4. Uncertainty-Aware Joint Optimization (Milestone 2)

        Returns: (List of BenchmarkSummary for each strategy, List of detailed EpochResult traces)
        """
        if strategies is None:
            strategies = [
                FixedAllowanceStrategy(fixed_amount=500.0, config=self.config),
                DemandOnlyStrategy(safety_factor=1.0, config=self.config),
                ProposedJointOptimizationStrategy(config=self.config),
                UncertaintyAwareJointOptimizationStrategy(confidence_level=0.85, config=self.config),
            ]

        # Each strategy maintains its own predictor instance to mirror independent on-device deployment
        predictors: Dict[str, OutageAndDemandPredictor] = {
            s.name: OutageAndDemandPredictor() for s in strategies
        }

        all_epoch_results: List[EpochResult] = []

        # Reset synthetic data generator for this scenario
        self.data_gen.set_seed(self.seed)

        # Pre-generate ground truth for all epochs so all strategies experience the exact identical events
        ground_truth_epochs = []
        for ep in range(epochs):
            outage = self.data_gen.generate_outage_event(
                profile=outage_profile,
                epoch_idx=ep,
                total_epochs=epochs,
                horizon_hours=horizon_hours,
            )
            transactions = self.data_gen.generate_transactions_for_horizon(
                user=user,
                outage=outage,
                horizon_hours=horizon_hours,
                demand_distribution=demand_distribution,
            )
            ground_truth_epochs.append((outage, transactions))

        # Optional warmup phase to populate historical observations
        for ep in range(warmup_epochs):
            outage, transactions = ground_truth_epochs[ep % len(ground_truth_epochs)]
            for pred in predictors.values():
                pred.record_epoch_observation(outage, transactions)

        # Main evaluation loop
        for ep_idx, (outage, transactions) in enumerate(ground_truth_epochs):
            # Calculate actual ground-truth demand during outage
            offline_txs = [t for t in transactions if t.occurred_during_outage]
            actual_demand_offline = sum(t.amount for t in offline_txs)
            total_epoch_demand = sum(t.amount for t in transactions)

            for strat in strategies:
                pred = predictors[strat.name]

                # 1. Compute strategy recommendation
                decision = strat.compute_allocation(
                    user=user,
                    predictor=pred,
                    horizon_hours=horizon_hours,
                )
                allocated_reserve = decision.allocatable_reserve

                # 2. Simulate transaction execution against the allocated reserve
                remaining_reserve = allocated_reserve
                shortage_amount = 0.0
                failed_tx_count = 0
                successful_offline_spent = 0.0

                if outage.occurred:
                    for tx in offline_txs:
                        if remaining_reserve >= tx.amount:
                            # Successful offline payment
                            remaining_reserve -= tx.amount
                            successful_offline_spent += tx.amount
                        else:
                            # Shortage: reserve exhausted
                            unmet = tx.amount - remaining_reserve
                            shortage_amount += unmet
                            successful_offline_spent += remaining_reserve
                            remaining_reserve = 0.0
                            failed_tx_count += 1

                unused_reserve = remaining_reserve
                exposure = (allocated_reserve ** 2) / user.maximum_allowance

                # Prediction errors
                demand_error = abs(decision.predicted_demand - actual_demand_offline) if outage.occurred else 0.0
                actual_outage_val = 1.0 if outage.occurred else 0.0
                brier_score = (decision.predicted_outage_prob - actual_outage_val) ** 2

                epoch_res = EpochResult(
                    epoch_id=ep_idx + 1,
                    strategy=strat.name,
                    user_profile=user.profile_name,
                    outage_scenario=outage_profile.profile_name,
                    reserve_allocated=allocated_reserve,
                    actual_outage=outage.occurred,
                    actual_outage_duration=outage.duration_hours,
                    actual_demand_during_outage=round(actual_demand_offline, 2),
                    total_demand_in_epoch=round(total_epoch_demand, 2),
                    spent_from_reserve=round(successful_offline_spent, 2),
                    unused_reserve=round(unused_reserve, 2),
                    shortage_amount=round(shortage_amount, 2),
                    failed_transactions_count=failed_tx_count,
                    total_offline_transactions=len(offline_txs),
                    financial_exposure=round(exposure, 4),
                    demand_prediction_error=round(demand_error, 2),
                    outage_prob_brier_score=round(brier_score, 4),
                )
                all_epoch_results.append(epoch_res)

                # 3. Update strategy predictor with observed reality & error feedback
                pred.record_epoch_observation(outage, transactions)
                pred.record_forecast_error(
                    decision.predicted_outage_prob,
                    outage.occurred,
                    decision.predicted_demand,
                    actual_demand_offline,
                )

        # Aggregate benchmark summaries
        summaries: List[BenchmarkSummary] = []
        for strat in strategies:
            strat_results = [r for r in all_epoch_results if r.strategy == strat.name]
            total_n = len(strat_results)
            outage_results = [r for r in strat_results if r.actual_outage]
            outage_count = len(outage_results)

            total_offline_demand = sum(r.actual_demand_during_outage for r in strat_results)
            total_offline_spent = sum(r.spent_from_reserve for r in strat_results)
            total_shortage = sum(r.shortage_amount for r in strat_results)

            if total_offline_demand > 0:
                offline_success_rate = (total_offline_spent / total_offline_demand) * 100.0
            else:
                offline_success_rate = 100.0

            shortage_epochs = sum(1 for r in outage_results if r.shortage_amount > 0)
            insufficient_rate = (shortage_epochs / max(1, outage_count)) * 100.0

            avg_locked = sum(r.reserve_allocated for r in strat_results) / max(1, total_n)
            avg_unused = sum(r.unused_reserve for r in strat_results) / max(1, total_n)
            avg_shortage = sum(r.shortage_amount for r in strat_results) / max(1, total_n)
            avg_exposure = sum(r.financial_exposure for r in strat_results) / max(1, total_n)

            # Prediction errors
            outage_errors = [r.demand_prediction_error for r in strat_results if r.actual_outage]
            mae = (sum(outage_errors) / len(outage_errors)) if outage_errors else 0.0
            rmse = math.sqrt(sum(e ** 2 for e in outage_errors) / len(outage_errors)) if outage_errors else 0.0
            brier = sum(r.outage_prob_brier_score for r in strat_results) / max(1, total_n)

            # Atomic transaction failures and discrete success rate
            total_failed_tx = sum(r.failed_transactions_count for r in strat_results)
            total_offline_tx = sum(r.total_offline_transactions for r in strat_results)
            atomic_success = ((total_offline_tx - total_failed_tx) / max(1, total_offline_tx)) * 100.0 if total_offline_tx > 0 else 100.0

            # Realized combined cost:
            # J_realized = c_lock * avg_locked * H + c_short * avg_shortage + c_exposure * avg_exposure
            c_lock = self.config.default_c_lock
            c_short = self.config.default_c_short
            c_exposure = self.config.default_c_exposure
            realized_cost = (c_lock * avg_locked * horizon_hours) + (c_short * avg_shortage) + (c_exposure * avg_exposure)

            summary = BenchmarkSummary(
                strategy=strat.name,
                outage_scenario=outage_profile.profile_name,
                user_profile=user.profile_name,
                total_epochs=total_n,
                outage_epochs_count=outage_count,
                offline_success_rate=round(offline_success_rate, 2),
                insufficient_reserve_rate=round(insufficient_rate, 2),
                average_locked_funds=round(avg_locked, 2),
                average_unused_funds=round(avg_unused, 2),
                average_shortage_amount=round(avg_shortage, 2),
                average_exposure=round(avg_exposure, 2),
                demand_mae=round(mae, 2),
                demand_rmse=round(rmse, 2),
                brier_score=round(brier, 4),
                total_failed_transactions=total_failed_tx,
                atomic_success_rate=round(atomic_success, 2),
                realized_combined_cost=round(realized_cost, 4),
            )
            summaries.append(summary)

        return (summaries, all_epoch_results)

    def run_multi_seed_benchmark(
        self,
        user: UserProfile,
        outage_profile: OutageProfile,
        seeds: List[int] = [42, 101, 2024, 777, 9999],
        epochs: int = 60,
        warmup_epochs: int = 10,
        horizon_hours: float = 24.0,
        demand_distribution: str = "gaussian",
        strategies: List[BaseProvisioningStrategy] = None,
    ) -> Tuple[List[BenchmarkSummary], List[EpochResult]]:
        """
        Runs the benchmark across multiple random seeds and computes the mean and standard deviation
        of metrics to capture stochastic variability and prevent seed-cherry-picking.
        """
        seed_summaries: Dict[str, List[BenchmarkSummary]] = {}
        all_traces: List[EpochResult] = []

        for seed in seeds:
            self.seed = seed
            self.data_gen.set_seed(seed)
            sums, traces = self.run_benchmark(
                user=user,
                outage_profile=outage_profile,
                epochs=epochs,
                warmup_epochs=warmup_epochs,
                horizon_hours=horizon_hours,
                strategies=strategies,
                demand_distribution=demand_distribution,
            )
            all_traces.extend(traces)
            for s in sums:
                seed_summaries.setdefault(s.strategy, []).append(s)

        # Aggregate across seeds
        final_summaries: List[BenchmarkSummary] = []
        for strat_name, list_sums in seed_summaries.items():
            n = len(list_sums)
            mean_success = sum(s.offline_success_rate for s in list_sums) / n
            var_success = sum((s.offline_success_rate - mean_success) ** 2 for s in list_sums) / max(1, n - 1)
            std_success = math.sqrt(var_success) if n > 1 else 0.0

            mean_locked = sum(s.average_locked_funds for s in list_sums) / n
            var_locked = sum((s.average_locked_funds - mean_locked) ** 2 for s in list_sums) / max(1, n - 1)
            std_locked = math.sqrt(var_locked) if n > 1 else 0.0

            mean_shortage_rate = sum(s.insufficient_reserve_rate for s in list_sums) / n
            mean_unused = sum(s.average_unused_funds for s in list_sums) / n
            mean_shortage_amt = sum(s.average_shortage_amount for s in list_sums) / n
            mean_exposure = sum(s.average_exposure for s in list_sums) / n
            mean_mae = sum(s.demand_mae for s in list_sums) / n
            mean_rmse = sum(s.demand_rmse for s in list_sums) / n
            mean_brier = sum(s.brier_score for s in list_sums) / n

            total_failed_tx = sum(s.total_failed_transactions for s in list_sums)
            mean_atomic_success = sum(s.atomic_success_rate for s in list_sums) / n
            mean_cost = sum(s.realized_combined_cost for s in list_sums) / n
            var_cost = sum((s.realized_combined_cost - mean_cost) ** 2 for s in list_sums) / max(1, n - 1)
            std_cost = math.sqrt(var_cost) if n > 1 else 0.0

            base = list_sums[0]
            agg = BenchmarkSummary(
                strategy=strat_name,
                outage_scenario=base.outage_scenario,
                user_profile=base.user_profile,
                total_epochs=base.total_epochs * n,
                outage_epochs_count=sum(s.outage_epochs_count for s in list_sums),
                offline_success_rate=round(mean_success, 2),
                insufficient_reserve_rate=round(mean_shortage_rate, 2),
                average_locked_funds=round(mean_locked, 2),
                average_unused_funds=round(mean_unused, 2),
                average_shortage_amount=round(mean_shortage_amt, 2),
                average_exposure=round(mean_exposure, 2),
                demand_mae=round(mean_mae, 2),
                demand_rmse=round(mean_rmse, 2),
                brier_score=round(mean_brier, 4),
                success_rate_std=round(std_success, 2),
                locked_funds_std=round(std_locked, 2),
                total_failed_transactions=total_failed_tx,
                atomic_success_rate=round(mean_atomic_success, 2),
                realized_combined_cost=round(mean_cost, 4),
                combined_cost_std=round(std_cost, 4),
            )
            final_summaries.append(agg)

        return (final_summaries, all_traces)
