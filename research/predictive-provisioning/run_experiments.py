#!/usr/bin/env python3
"""
Main CLI entrypoint for running the predictive allowance provisioning experiments,
generating CSV results, and rendering publication-ready SVG charts and HTML dashboards.
Supports both single-seed and multi-seed Monte Carlo evaluations.
"""

import argparse
import csv
import os
import sys
from typing import List

from src.config import ProvisioningConfig
from src.data_generator import SyntheticDataGenerator
from src.simulator import ProvisioningSimulator
from src.visualizer import ResultsVisualizer


def run_all_experiments(
    epochs: int = 60,
    warmup_epochs: int = 10,
    seeds: List[int] = [42],
    output_dir: str = "results",
) -> None:
    """Executes the full experimental evaluation matrix across user archetypes and outage regimes."""
    is_multi_seed = len(seeds) > 1
    seed_desc = f"{len(seeds)} seeds: {seeds}" if is_multi_seed else f"seed={seeds[0]}"

    print("=" * 80)
    print(" UPIMesh Research: Predictive Offline Allowance Provisioning Simulator")
    print(f" Settings: epochs={epochs}, warmup={warmup_epochs}, {seed_desc}")
    print("=" * 80)

    config = ProvisioningConfig()
    simulator = ProvisioningSimulator(config=config, seed=seeds[0])

    user_profiles = SyntheticDataGenerator.get_standard_user_profiles()
    outage_profiles = SyntheticDataGenerator.get_standard_outage_profiles()

    all_summaries = []
    all_traces = []

    os.makedirs(output_dir, exist_ok=True)

    print("\nEvaluating 4 Competing Provisioning Strategies on Identical Scenarios:")
    print(" 1. Fixed Allowance (₹500 preset baseline)")
    print(" 2. Demand-Only (Outage-agnostic forecast baseline)")
    print(" 3. Proposed Joint Optimization (Milestone 1 baseline)")
    print(" 4. Uncertainty-Aware Joint Optimization (Milestone 2 proposed)")
    print("-" * 80)

    # Primary user evaluated across all scenarios (Alice Commuter)
    primary_user = user_profiles[0]

    for outage_prof in outage_profiles:
        print(f"-> Scenario: {outage_prof.profile_name:30} ... ", end="", flush=True)
        if is_multi_seed:
            summaries, traces = simulator.run_multi_seed_benchmark(
                user=primary_user,
                outage_profile=outage_prof,
                seeds=seeds,
                epochs=epochs,
                warmup_epochs=warmup_epochs,
            )
        else:
            summaries, traces = simulator.run_benchmark(
                user=primary_user,
                outage_profile=outage_prof,
                epochs=epochs,
                warmup_epochs=warmup_epochs,
            )
        all_summaries.extend(summaries)
        all_traces.extend(traces)
        print("DONE")

    # Write benchmark_summary.csv
    summary_csv_path = os.path.join(output_dir, "benchmark_summary.csv")
    with open(summary_csv_path, "w", newline="", encoding="utf-8") as f:
        fieldnames = [
            "outage_scenario",
            "strategy",
            "user_profile",
            "total_epochs",
            "outage_epochs_count",
            "offline_success_rate",
            "success_rate_std",
            "insufficient_reserve_rate",
            "average_locked_funds",
            "locked_funds_std",
            "average_unused_funds",
            "average_shortage_amount",
            "average_exposure",
            "demand_mae",
            "demand_rmse",
            "brier_score",
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for s in all_summaries:
            writer.writerow({
                "outage_scenario": s.outage_scenario,
                "strategy": s.strategy,
                "user_profile": s.user_profile,
                "total_epochs": s.total_epochs,
                "outage_epochs_count": s.outage_epochs_count,
                "offline_success_rate": s.offline_success_rate,
                "success_rate_std": s.success_rate_std,
                "insufficient_reserve_rate": s.insufficient_reserve_rate,
                "average_locked_funds": s.average_locked_funds,
                "locked_funds_std": s.locked_funds_std,
                "average_unused_funds": s.average_unused_funds,
                "average_shortage_amount": s.average_shortage_amount,
                "average_exposure": s.average_exposure,
                "demand_mae": s.demand_mae,
                "demand_rmse": s.demand_rmse,
                "brier_score": s.brier_score,
            })

    # Write detailed_traces.csv
    traces_csv_path = os.path.join(output_dir, "detailed_traces.csv")
    with open(traces_csv_path, "w", newline="", encoding="utf-8") as f:
        fieldnames = [
            "epoch_id",
            "outage_scenario",
            "strategy",
            "user_profile",
            "reserve_allocated",
            "actual_outage",
            "actual_outage_duration",
            "actual_demand_during_outage",
            "total_demand_in_epoch",
            "spent_from_reserve",
            "unused_reserve",
            "shortage_amount",
            "failed_transactions_count",
            "total_offline_transactions",
            "financial_exposure",
            "demand_prediction_error",
            "outage_prob_brier_score",
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for t in all_traces:
            writer.writerow({
                "epoch_id": t.epoch_id,
                "outage_scenario": t.outage_scenario,
                "strategy": t.strategy,
                "user_profile": t.user_profile,
                "reserve_allocated": t.reserve_allocated,
                "actual_outage": t.actual_outage,
                "actual_outage_duration": t.actual_outage_duration,
                "actual_demand_during_outage": t.actual_demand_during_outage,
                "total_demand_in_epoch": t.total_demand_in_epoch,
                "spent_from_reserve": t.spent_from_reserve,
                "unused_reserve": t.unused_reserve,
                "shortage_amount": t.shortage_amount,
                "failed_transactions_count": t.failed_transactions_count,
                "total_offline_transactions": t.total_offline_transactions,
                "financial_exposure": t.financial_exposure,
                "demand_prediction_error": t.demand_prediction_error,
                "outage_prob_brier_score": t.outage_prob_brier_score,
            })

    # Render Visualizations & HTML Report
    visualizer = ResultsVisualizer(output_dir=output_dir)
    rendered_files = visualizer.generate_all_visualizations(all_summaries, all_traces)

    print("\n" + "=" * 90)
    print(" EMPIRICAL RESULTS SUMMARY TABLE")
    print("=" * 90)
    if is_multi_seed:
        print(f"{'Scenario':<26} {'Strategy':<19} {'Success% (±std)':<18} {'Shortage%':<11} {'Avg Lock(₹)':<13} {'Avg Unused(₹)':<14}")
    else:
        print(f"{'Scenario':<26} {'Strategy':<19} {'Success%':<10} {'Shortage%':<11} {'Avg Lock(₹)':<13} {'Avg Unused(₹)':<14}")
    print("-" * 90)
    for s in all_summaries:
        if is_multi_seed and s.success_rate_std > 0:
            succ_str = f"{s.offline_success_rate:>5.1f}% ± {s.success_rate_std:<4.1f}"
        else:
            succ_str = f"{s.offline_success_rate:>8.1f}%"
        print(
            f"{s.outage_scenario:<26} "
            f"{s.strategy:<19} "
            f"{succ_str:<18} "
            f"{s.insufficient_reserve_rate:>9.1f}% "
            f"₹{s.average_locked_funds:>10.2f} "
            f"₹{s.average_unused_funds:>11.2f}"
        )

    print("-" * 90)
    print("\nArtifacts Successfully Generated:")
    print(f" [CSV] Benchmark Summary : {summary_csv_path}")
    print(f" [CSV] Detailed Traces   : {traces_csv_path}")
    print(f" [SVG] Metrics Bar Chart : {rendered_files['benchmark_metrics']}")
    print(f" [SVG] Trade-off Frontier: {rendered_files['trade_off_frontier']}")
    print(f" [HTML] Interactive Dash : {rendered_files['html_report']}")
    print("\nTo view the interactive dashboard on macOS, run:")
    print(f"  open {rendered_files['html_report']}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="UPIMesh Predictive Provisioning Simulator")
    parser.add_argument("--epochs", type=int, default=60, help="Number of simulated 24h epochs per scenario")
    parser.add_argument("--warmup", type=int, default=10, help="Number of warm-up history epochs")
    parser.add_argument("--seed", type=int, default=42, help="Single random number generator seed")
    parser.add_argument("--multi-seed", action="store_true", help="Run multi-seed Monte Carlo evaluation (5 seeds)")
    parser.add_argument("--output-dir", type=str, default="results", help="Directory to save CSVs and charts")

    args = parser.parse_args()

    if args.multi_seed:
        active_seeds = [42, 101, 2024, 777, 9999]
    else:
        active_seeds = [args.seed]

    run_all_experiments(
        epochs=args.epochs,
        warmup_epochs=args.warmup,
        seeds=active_seeds,
        output_dir=args.output_dir,
    )
