#!/usr/bin/env python3
"""
Milestone 3 — Scientific Validation of Research Claims
Executes comprehensive validation experiments:
1. 30-Seed Monte Carlo Benchmark with 100 evaluation epochs (3,000 epochs per scenario).
2. Pareto Frontier: Payment Availability vs Average Locked Funds trade-off.
3. Distributional Robustness: Performance under Gaussian, Log-Normal, and Heavy-Tailed Pareto demand.
4. Cold-Start Dynamics: Evaluation across 0, 1, 2, 3, 5, and 10 historical warmup epochs.
5. Realized Combined Cost analysis.
"""

import argparse
import csv
import math
import os
import sys
from typing import Dict, List, Tuple

from src.config import ProvisioningConfig
from src.data_generator import SyntheticDataGenerator
from src.models import BenchmarkSummary, EpochResult, OutageProfile, UserProfile
from src.simulator import ProvisioningSimulator
from src.strategies import (
    BaseProvisioningStrategy,
    DemandOnlyStrategy,
    FixedAllowanceStrategy,
    ProposedJointOptimizationStrategy,
    UncertaintyAwareJointOptimizationStrategy,
)


# =============================================================================
# Helper: SVG Chart Generators (Pure Python Standard Library)
# =============================================================================

def render_pareto_svg(records: List[Dict], output_path: str) -> None:
    """Renders Availability (%) vs Locked Funds (INR) Pareto Frontier as standalone SVG."""
    width, height = 900, 520
    margin_l, margin_r, margin_t, margin_b = 80, 50, 70, 70
    plot_w = width - margin_l - margin_r
    plot_h = height - margin_t - margin_b

    # Axis ranges
    x_min, x_max = 0.0, 1000.0  # Locked funds (INR)
    y_min, y_max = 50.0, 101.0  # Success rate (%)

    def scale_x(val: float) -> float:
        clamped = max(x_min, min(x_max, val))
        return margin_l + ((clamped - x_min) / (x_max - x_min)) * plot_w

    def scale_y(val: float) -> float:
        clamped = max(y_min, min(y_max, val))
        return margin_t + plot_h - ((clamped - y_min) / (y_max - y_min)) * plot_h

    # Colors per strategy family
    family_colors = {
        "Fixed": "#f59e0b",
        "Demand-Only": "#ef4444",
        "Proposed-JointOpt": "#3b82f6",
        "Uncertainty-Aware": "#10b981",
    }

    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="100%" height="100%">',
        f'<rect width="{width}" height="{height}" fill="#0d1117" rx="12" />',
        f'<text x="{margin_l}" y="35" fill="#f0f6fc" font-family="system-ui, sans-serif" font-size="20" font-weight="700">Pareto Frontier: Payment Availability vs. Locked Funds</text>',
        f'<text x="{margin_l}" y="55" fill="#8b949e" font-family="system-ui, sans-serif" font-size="12">Rural Weak Signal &amp; Adversarial Scenarios (30-Seed Monte Carlo Envelope)</text>',
    ]

    # Gridlines
    for y_val in [60, 70, 80, 90, 100]:
        y_pos = scale_y(y_val)
        svg.append(f'<line x1="{margin_l}" y1="{y_pos}" x2="{width - margin_r}" y2="{y_pos}" stroke="#21262d" stroke-dasharray="4,4" />')
        svg.append(f'<text x="{margin_l - 12}" y="{y_pos + 4}" fill="#8b949e" font-family="system-ui, sans-serif" font-size="11" text-anchor="end">{y_val}%</text>')

    for x_val in [0, 200, 400, 600, 800, 1000]:
        x_pos = scale_x(x_val)
        svg.append(f'<line x1="{x_pos}" y1="{margin_t}" x2="{x_pos}" y2="{margin_t + plot_h}" stroke="#21262d" stroke-dasharray="4,4" />')
        svg.append(f'<text x="{x_pos}" y="{margin_t + plot_h + 20}" fill="#8b949e" font-family="system-ui, sans-serif" font-size="11" text-anchor="middle">₹{x_val}</text>')

    # Axis titles
    svg.append(f'<text x="{width / 2}" y="{height - 20}" fill="#c9d1d9" font-family="system-ui, sans-serif" font-size="13" font-weight="600" text-anchor="middle">Average Locked Funds (INR)</text>')
    svg.append(f'<text transform="rotate(-90)" x="-{margin_t + plot_h / 2}" y="25" fill="#c9d1d9" font-family="system-ui, sans-serif" font-size="13" font-weight="600" text-anchor="middle">Payment Availability / Offline Success Rate (%)</text>')

    # Scatter points
    for r in records:
        strat = r["strategy_family"]
        color = family_colors.get(strat, "#c9d1d9")
        cx = scale_x(r["average_locked_funds"])
        cy = scale_y(r["offline_success_rate"])
        is_pareto = r.get("is_pareto", False)
        radius = 7 if is_pareto else 5
        stroke = "#ffffff" if is_pareto else "none"
        stroke_w = "2" if is_pareto else "0"
        svg.append(f'<circle cx="{cx}" cy="{cy}" r="{radius}" fill="{color}" fill-opacity="0.85" stroke="{stroke}" stroke-width="{stroke_w}"><title>{r["label"]}: ₹{r["average_locked_funds"]} -> {r["offline_success_rate"]}%</title></circle>')

    # Legend
    leg_x = width - margin_r - 200
    leg_y = margin_t + 10
    svg.append(f'<rect x="{leg_x}" y="{leg_y}" width="190" height="120" fill="#161b22" stroke="#30363d" rx="6" />')
    for idx, (name, col) in enumerate(family_colors.items()):
        ly = leg_y + 22 + idx * 24
        svg.append(f'<circle cx="{leg_x + 18}" cy="{ly}" r="6" fill="{col}" />')
        svg.append(f'<text x="{leg_x + 34}" y="{ly + 4}" fill="#c9d1d9" font-family="system-ui, sans-serif" font-size="12">{name}</text>')

    svg.append('</svg>')
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(svg))


def render_heavy_tail_svg(records: List[Dict], output_path: str) -> None:
    """Renders grouped bar chart showing impact of Gaussian vs LogNormal vs Pareto demand."""
    width, height = 860, 480
    margin_l, margin_r, margin_t, margin_b = 80, 40, 70, 70
    plot_w = width - margin_l - margin_r
    plot_h = height - margin_t - margin_b

    strategies = ["Fixed-₹500", "Demand-Only", "Proposed-JointOpt", "Uncertainty-Aware"]
    dists = ["gaussian", "lognormal", "pareto"]
    dist_colors = {"gaussian": "#3b82f6", "lognormal": "#f59e0b", "pareto": "#ef4444"}

    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="100%" height="100%">',
        f'<rect width="{width}" height="{height}" fill="#0d1117" rx="12" />',
        f'<text x="{margin_l}" y="35" fill="#f0f6fc" font-family="system-ui, sans-serif" font-size="20" font-weight="700">Robustness to Heavy-Tailed Demand Distributions</text>',
        f'<text x="{margin_l}" y="55" fill="#8b949e" font-family="system-ui, sans-serif" font-size="12">Offline Success Rate (%) across Gaussian, Log-Normal, and Heavy-Tailed Pareto Spend</text>',
    ]

    # Grid
    for y_val in [40, 60, 80, 100]:
        y_pos = margin_t + plot_h - ((y_val / 100.0) * plot_h)
        svg.append(f'<line x1="{margin_l}" y1="{y_pos}" x2="{width - margin_r}" y2="{y_pos}" stroke="#21262d" stroke-dasharray="4,4" />')
        svg.append(f'<text x="{margin_l - 12}" y="{y_pos + 4}" fill="#8b949e" font-family="system-ui, sans-serif" font-size="11" text-anchor="end">{y_val}%</text>')

    group_w = plot_w / len(strategies)
    bar_w = group_w * 0.22

    for g_idx, strat in enumerate(strategies):
        gx = margin_l + g_idx * group_w
        svg.append(f'<text x="{gx + group_w / 2}" y="{margin_t + plot_h + 25}" fill="#c9d1d9" font-family="system-ui, sans-serif" font-size="12" font-weight="600" text-anchor="middle">{strat}</text>')

        for d_idx, dist in enumerate(dists):
            rec = next((r for r in records if r["strategy"] == strat and r["distribution"] == dist), None)
            val = rec["offline_success_rate"] if rec else 0.0
            bh = (val / 100.0) * plot_h
            bx = gx + (group_w * 0.12) + d_idx * (bar_w + 6)
            by = margin_t + plot_h - bh
            col = dist_colors[dist]

            svg.append(f'<rect x="{bx}" y="{by}" width="{bar_w}" height="{bh}" fill="{col}" rx="3"><title>{strat} ({dist}): {val}%</title></rect>')
            svg.append(f'<text x="{bx + bar_w / 2}" y="{by - 6}" fill="#f0f6fc" font-family="system-ui, sans-serif" font-size="10" font-weight="600" text-anchor="middle">{val:.1f}%</text>')

    # Legend
    leg_x = width - margin_r - 280
    leg_y = margin_t - 25
    for idx, (dist, col) in enumerate(dist_colors.items()):
        lx = leg_x + idx * 95
        svg.append(f'<rect x="{lx}" y="{leg_y}" width="12" height="12" fill="{col}" rx="2" />')
        svg.append(f'<text x="{lx + 18}" y="{leg_y + 10}" fill="#c9d1d9" font-family="system-ui, sans-serif" font-size="11">{dist.capitalize()}</text>')

    svg.append('</svg>')
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(svg))


def render_cold_start_svg(records: List[Dict], output_path: str) -> None:
    """Renders line chart showing convergence of offline success rate from cold start (0 to 10 warmup epochs)."""
    width, height = 860, 480
    margin_l, margin_r, margin_t, margin_b = 80, 40, 70, 70
    plot_w = width - margin_l - margin_r
    plot_h = height - margin_t - margin_b

    warmup_steps = sorted(list(set(r["warmup_epochs"] for r in records)))
    strategies = ["Fixed-₹500", "Demand-Only", "Proposed-JointOpt", "Uncertainty-Aware"]
    strat_colors = {
        "Fixed-₹500": "#f59e0b",
        "Demand-Only": "#ef4444",
        "Proposed-JointOpt": "#3b82f6",
        "Uncertainty-Aware": "#10b981",
    }

    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="100%" height="100%">',
        f'<rect width="{width}" height="{height}" fill="#0d1117" rx="12" />',
        f'<text x="{margin_l}" y="35" fill="#f0f6fc" font-family="system-ui, sans-serif" font-size="20" font-weight="700">Cold-Start Convergence: Availability vs. Historical Epochs</text>',
        f'<text x="{margin_l}" y="55" fill="#8b949e" font-family="system-ui, sans-serif" font-size="12">Rural Weak Signal: Warmup Epochs 0 to 10 (Epistemic UCB Protection)</text>',
    ]

    for y_val in [40, 60, 80, 100]:
        y_pos = margin_t + plot_h - ((y_val / 100.0) * plot_h)
        svg.append(f'<line x1="{margin_l}" y1="{y_pos}" x2="{width - margin_r}" y2="{y_pos}" stroke="#21262d" stroke-dasharray="4,4" />')
        svg.append(f'<text x="{margin_l - 12}" y="{y_pos + 4}" fill="#8b949e" font-family="system-ui, sans-serif" font-size="11" text-anchor="end">{y_val}%</text>')

    def scale_x(w_val: int) -> float:
        return margin_l + (w_val / 10.0) * plot_w

    def scale_y(s_val: float) -> float:
        return margin_t + plot_h - (s_val / 100.0) * plot_h

    for w_val in warmup_steps:
        x_pos = scale_x(w_val)
        svg.append(f'<line x1="{x_pos}" y1="{margin_t}" x2="{x_pos}" y2="{margin_t + plot_h}" stroke="#21262d" stroke-dasharray="2,2" />')
        svg.append(f'<text x="{x_pos}" y="{margin_t + plot_h + 20}" fill="#8b949e" font-family="system-ui, sans-serif" font-size="11" text-anchor="middle">{w_val} ep</text>')

    svg.append(f'<text x="{width / 2}" y="{height - 20}" fill="#c9d1d9" font-family="system-ui, sans-serif" font-size="13" font-weight="600" text-anchor="middle">Warmup / Prior Historical Epochs Available</text>')

    for strat in strategies:
        col = strat_colors[strat]
        pts = []
        for w_val in warmup_steps:
            rec = next((r for r in records if r["strategy"] == strat and r["warmup_epochs"] == w_val), None)
            val = rec["offline_success_rate"] if rec else 0.0
            px = scale_x(w_val)
            py = scale_y(val)
            pts.append((px, py, val))

        # Polyline
        poly_str = " ".join(f"{p[0]},{p[1]}" for p in pts)
        svg.append(f'<polyline points="{poly_str}" fill="none" stroke="{col}" stroke-width="3" stroke-linecap="round" />')
        for p in pts:
            svg.append(f'<circle cx="{p[0]}" cy="{p[1]}" r="5" fill="{col}" stroke="#ffffff" stroke-width="1.5"><title>{strat} ({p[2]:.1f}%)</title></circle>')

    # Legend
    leg_x = width - margin_r - 450
    leg_y = margin_t - 25
    for idx, (name, col) in enumerate(strat_colors.items()):
        lx = leg_x + idx * 115
        svg.append(f'<line x1="{lx}" y1="{leg_y + 6}" x2="{lx + 16}" y2="{leg_y + 6}" stroke="{col}" stroke-width="3" />')
        svg.append(f'<text x="{lx + 22}" y="{leg_y + 10}" fill="#c9d1d9" font-family="system-ui, sans-serif" font-size="11">{name}</text>')

    svg.append('</svg>')
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(svg))


# =============================================================================
# Main Validation Orchestrator
# =============================================================================

def run_milestone3_validation(
    output_dir: str = "results/milestone3",
    num_seeds: int = 30,
    epochs_per_seed: int = 100,
) -> None:
    print("=" * 85)
    print(" UPIMesh Milestone 3: Research Claim Scientific Validation")
    print(f" Monte Carlo Parameters: {num_seeds} Seeds x {epochs_per_seed} Epochs ({num_seeds * epochs_per_seed} Total Epochs/Scenario)")
    print("=" * 85)

    os.makedirs(output_dir, exist_ok=True)
    charts_dir = os.path.join(output_dir, "charts")
    os.makedirs(charts_dir, exist_ok=True)

    config = ProvisioningConfig()
    simulator = ProvisioningSimulator(config=config, seed=100)
    seeds = list(range(100, 100 + num_seeds))

    user_profiles = SyntheticDataGenerator.get_standard_user_profiles()
    outage_profiles = SyntheticDataGenerator.get_standard_outage_profiles()
    primary_user = user_profiles[0]  # Alice Commuter

    # =========================================================================
    # PART 1: 30-Seed Main Benchmark with 100 Epochs per Seed
    # =========================================================================
    print("\n--- PART 1: 30-Seed Main Benchmark Evaluation (5 Scenarios x 4 Strategies) ---")
    benchmark_30seeds_records: List[BenchmarkSummary] = []

    for outage_prof in outage_profiles:
        print(f"  -> Scenario: {outage_prof.profile_name:30} ... ", end="", flush=True)
        sums, _ = simulator.run_multi_seed_benchmark(
            user=primary_user,
            outage_profile=outage_prof,
            seeds=seeds,
            epochs=epochs_per_seed,
            warmup_epochs=10,
        )
        benchmark_30seeds_records.extend(sums)
        print("DONE")

    # Save benchmark_30seeds.csv
    csv_path_30seeds = os.path.join(output_dir, "benchmark_30seeds.csv")
    with open(csv_path_30seeds, "w", newline="", encoding="utf-8") as f:
        fieldnames = [
            "outage_scenario",
            "strategy",
            "user_profile",
            "total_epochs",
            "outage_epochs_count",
            "offline_success_rate",
            "success_rate_std",
            "atomic_success_rate",
            "total_failed_transactions",
            "insufficient_reserve_rate",
            "average_locked_funds",
            "locked_funds_std",
            "average_unused_funds",
            "average_shortage_amount",
            "average_exposure",
            "realized_combined_cost",
            "combined_cost_std",
            "demand_mae",
            "demand_rmse",
            "brier_score",
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for s in benchmark_30seeds_records:
            writer.writerow({
                "outage_scenario": s.outage_scenario,
                "strategy": s.strategy,
                "user_profile": s.user_profile,
                "total_epochs": s.total_epochs,
                "outage_epochs_count": s.outage_epochs_count,
                "offline_success_rate": s.offline_success_rate,
                "success_rate_std": s.success_rate_std,
                "atomic_success_rate": s.atomic_success_rate,
                "total_failed_transactions": s.total_failed_transactions,
                "insufficient_reserve_rate": s.insufficient_reserve_rate,
                "average_locked_funds": s.average_locked_funds,
                "locked_funds_std": s.locked_funds_std,
                "average_unused_funds": s.average_unused_funds,
                "average_shortage_amount": s.average_shortage_amount,
                "average_exposure": s.average_exposure,
                "realized_combined_cost": s.realized_combined_cost,
                "combined_cost_std": s.combined_cost_std,
                "demand_mae": s.demand_mae,
                "demand_rmse": s.demand_rmse,
                "brier_score": s.brier_score,
            })
    print(f"  [CSV] Saved 30-seed benchmark to {csv_path_30seeds}")

    # =========================================================================
    # PART 2: Pareto Frontier Sweep
    # =========================================================================
    print("\n--- PART 2: Pareto Frontier Analysis (Availability vs Locked Funds) ---")
    pareto_scenarios = [outage_profiles[1]]  # Rural Weak Signal
    pareto_seeds = seeds[:15]  # 15 seeds for speed & robustness

    pareto_candidates: List[Tuple[str, str, BaseProvisioningStrategy]] = []

    # 1. Fixed Allowance variants
    for amt in [100.0, 200.0, 350.0, 500.0, 750.0, 1000.0]:
        pareto_candidates.append(("Fixed", f"Fixed-₹{int(amt)}", FixedAllowanceStrategy(fixed_amount=amt, config=config)))

    # 2. Demand-Only variants
    for sf in [0.25, 0.5, 0.75, 1.0, 1.25]:
        pareto_candidates.append(("Demand-Only", f"DemandOnly-sf{sf}", DemandOnlyStrategy(safety_factor=sf, config=config)))

    # 3. Proposed-JointOpt (M1) variants (sweep c_short)
    for c_s in [0.5, 1.0, 2.0, 3.5, 6.0]:
        pareto_candidates.append(("Proposed-JointOpt", f"M1-cs{c_s}", ProposedJointOptimizationStrategy(c_short=c_s, config=config)))

    # 4. Uncertainty-Aware (M2) variants (sweep kappa & c_short)
    for c_s in [1.5, 2.0, 3.0]:
        for conf in [0.60, 0.75, 0.85, 0.92, 0.98]:
            pareto_candidates.append(("Uncertainty-Aware", f"M2-cs{c_s}-k{int(conf*100)}", UncertaintyAwareJointOptimizationStrategy(confidence_level=conf, c_short=c_s, config=config)))

    pareto_records = []
    for family, label, strat in pareto_candidates:
        sums, _ = simulator.run_multi_seed_benchmark(
            user=primary_user,
            outage_profile=pareto_scenarios[0],
            seeds=pareto_seeds,
            epochs=60,
            warmup_epochs=10,
            strategies=[strat],
        )
        s = sums[0]
        pareto_records.append({
            "strategy_family": family,
            "label": label,
            "average_locked_funds": s.average_locked_funds,
            "offline_success_rate": s.offline_success_rate,
            "atomic_success_rate": s.atomic_success_rate,
            "average_shortage_amount": s.average_shortage_amount,
            "realized_combined_cost": s.realized_combined_cost,
        })

    # Identify non-dominated points (Pareto optimal)
    for r in pareto_records:
        r_locked = r["average_locked_funds"]
        r_succ = r["offline_success_rate"]
        is_dominated = False
        for other in pareto_records:
            if other == r:
                continue
            if (other["average_locked_funds"] <= r_locked and other["offline_success_rate"] >= r_succ) and \
               (other["average_locked_funds"] < r_locked or other["offline_success_rate"] > r_succ):
                is_dominated = True
                break
        r["is_pareto"] = not is_dominated

    pareto_csv_path = os.path.join(output_dir, "pareto_frontier.csv")
    with open(pareto_csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(pareto_records[0].keys()))
        writer.writeheader()
        writer.writerows(pareto_records)
    print(f"  [CSV] Saved Pareto records to {pareto_csv_path}")

    pareto_svg_path = os.path.join(charts_dir, "pareto_frontier.svg")
    render_pareto_svg(pareto_records, pareto_svg_path)
    print(f"  [SVG] Rendered Pareto Frontier chart to {pareto_svg_path}")

    # =========================================================================
    # PART 3: Robustness to Heavy-Tailed Demand Distributions
    # =========================================================================
    print("\n--- PART 3: Heavy-Tailed Demand Evaluation (Gaussian vs LogNormal vs Pareto) ---")
    heavy_tail_records = []
    test_scenario = outage_profiles[1]  # Rural Weak Signal
    distributions = ["gaussian", "lognormal", "pareto"]

    for dist in distributions:
        print(f"  -> Testing Distribution: {dist:12} ... ", end="", flush=True)
        sums, _ = simulator.run_multi_seed_benchmark(
            user=primary_user,
            outage_profile=test_scenario,
            seeds=seeds[:15],
            epochs=60,
            warmup_epochs=10,
            demand_distribution=dist,
        )
        for s in sums:
            heavy_tail_records.append({
                "distribution": dist,
                "strategy": s.strategy,
                "offline_success_rate": s.offline_success_rate,
                "atomic_success_rate": s.atomic_success_rate,
                "average_locked_funds": s.average_locked_funds,
                "average_shortage_amount": s.average_shortage_amount,
                "realized_combined_cost": s.realized_combined_cost,
            })
        print("DONE")

    heavy_csv_path = os.path.join(output_dir, "heavy_tail_comparison.csv")
    with open(heavy_csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(heavy_tail_records[0].keys()))
        writer.writeheader()
        writer.writerows(heavy_tail_records)
    print(f"  [CSV] Saved heavy-tail comparison to {heavy_csv_path}")

    heavy_svg_path = os.path.join(charts_dir, "heavy_tail_comparison.svg")
    render_heavy_tail_svg(heavy_tail_records, heavy_svg_path)
    print(f"  [SVG] Rendered Heavy-Tail chart to {heavy_svg_path}")

    # =========================================================================
    # PART 4: Cold-Start Historical Scarcity Evaluation
    # =========================================================================
    print("\n--- PART 4: Cold-Start Evaluation (Warmup Epochs: 0, 1, 2, 3, 5, 10) ---")
    cold_start_records = []
    warmup_levels = [0, 1, 2, 3, 5, 10]

    for w_epochs in warmup_levels:
        print(f"  -> Testing Warmup Epochs: {w_epochs:2} ... ", end="", flush=True)
        sums, _ = simulator.run_multi_seed_benchmark(
            user=primary_user,
            outage_profile=test_scenario,
            seeds=seeds[:15],
            epochs=40,
            warmup_epochs=w_epochs,
        )
        for s in sums:
            cold_start_records.append({
                "warmup_epochs": w_epochs,
                "strategy": s.strategy,
                "offline_success_rate": s.offline_success_rate,
                "atomic_success_rate": s.atomic_success_rate,
                "average_locked_funds": s.average_locked_funds,
                "average_shortage_amount": s.average_shortage_amount,
                "realized_combined_cost": s.realized_combined_cost,
            })
        print("DONE")

    cold_csv_path = os.path.join(output_dir, "cold_start_evaluation.csv")
    with open(cold_csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(cold_start_records[0].keys()))
        writer.writeheader()
        writer.writerows(cold_start_records)
    print(f"  [CSV] Saved cold-start evaluation to {cold_csv_path}")

    cold_svg_path = os.path.join(charts_dir, "cold_start_convergence.svg")
    render_cold_start_svg(cold_start_records, cold_svg_path)
    print(f"  [SVG] Rendered Cold-Start chart to {cold_svg_path}")

    print("\n" + "=" * 85)
    print(f" Milestone 3 Validation Complete! All artifacts saved to '{output_dir}'.")
    print("=" * 85)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Milestone 3 Validation Runner")
    parser.add_argument("--output-dir", type=str, default="results/milestone3")
    parser.add_argument("--seeds", type=int, default=30, help="Number of random seeds (default: 30)")
    parser.add_argument("--epochs", type=int, default=100, help="Evaluation epochs per seed (default: 100)")
    args = parser.parse_args()

    run_milestone3_validation(
        output_dir=args.output_dir,
        num_seeds=args.seeds,
        epochs_per_seed=args.epochs,
    )

