#!/usr/bin/env python3
"""
Sensitivity analysis runner evaluating the impact of:
- Shortage penalties (c_short)
- Fund lock cost rates (c_lock)
- Exposure penalty weights (c_exposure)
- Prediction confidence levels (kappa)
"""

import argparse
import csv
import math
import os
from typing import Dict, List

from src.config import ProvisioningConfig
from src.data_generator import SyntheticDataGenerator
from src.simulator import ProvisioningSimulator
from src.strategies import UncertaintyAwareJointOptimizationStrategy


def run_sensitivity_analysis(
    output_dir: str = "results",
    epochs: int = 40,
    seed: int = 42,
) -> None:
    print("=" * 80)
    print(" Running Sensitivity Analysis for Uncertainty-Aware Provisioning")
    print("=" * 80)

    os.makedirs(output_dir, exist_ok=True)
    charts_dir = os.path.join(output_dir, "charts")
    os.makedirs(charts_dir, exist_ok=True)

    config = ProvisioningConfig()
    simulator = ProvisioningSimulator(config=config, seed=seed)

    user = SyntheticDataGenerator.get_standard_user_profiles()[0]  # Alice Commuter
    scenario = SyntheticDataGenerator.get_standard_outage_profiles()[1]  # Rural Weak Signal (difficult scenario)

    sensitivity_records = []

    # 1. Sweep Shortage Penalty c_short
    print("1. Sweeping c_short (Shortage Penalty: 1.0 to 5.0)...")
    for c_s in [1.0, 1.5, 2.0, 3.0, 5.0]:
        strat = UncertaintyAwareJointOptimizationStrategy(
            confidence_level=0.85,
            c_short=c_s,
            c_lock=config.default_c_lock,
            c_exposure=config.default_c_exposure,
            config=config,
        )
        sums, _ = simulator.run_benchmark(
            user=user,
            outage_profile=scenario,
            epochs=epochs,
            warmup_epochs=10,
            strategies=[strat],
        )
        s = sums[0]
        sensitivity_records.append({
            "parameter_swept": "c_short",
            "parameter_value": c_s,
            "offline_success_rate": s.offline_success_rate,
            "average_locked_funds": s.average_locked_funds,
            "average_unused_funds": s.average_unused_funds,
            "insufficient_reserve_rate": s.insufficient_reserve_rate,
            "average_exposure": s.average_exposure,
        })

    # 2. Sweep Lock Cost c_lock
    print("2. Sweeping c_lock (Fund Lock Cost Rate: 0.00002 to 0.0005)...")
    for c_l in [0.00002, 0.00005, 0.0001, 0.0003, 0.0008]:
        strat = UncertaintyAwareJointOptimizationStrategy(
            confidence_level=0.85,
            c_short=config.default_c_short,
            c_lock=c_l,
            c_exposure=config.default_c_exposure,
            config=config,
        )
        sums, _ = simulator.run_benchmark(
            user=user,
            outage_profile=scenario,
            epochs=epochs,
            warmup_epochs=10,
            strategies=[strat],
        )
        s = sums[0]
        sensitivity_records.append({
            "parameter_swept": "c_lock",
            "parameter_value": c_l,
            "offline_success_rate": s.offline_success_rate,
            "average_locked_funds": s.average_locked_funds,
            "average_unused_funds": s.average_unused_funds,
            "insufficient_reserve_rate": s.insufficient_reserve_rate,
            "average_exposure": s.average_exposure,
        })

    # 3. Sweep Exposure Weight c_exposure
    print("3. Sweeping c_exposure (Financial Exposure Weight: 0.01 to 0.20)...")
    for c_e in [0.01, 0.03, 0.05, 0.10, 0.20]:
        strat = UncertaintyAwareJointOptimizationStrategy(
            confidence_level=0.85,
            c_short=config.default_c_short,
            c_lock=config.default_c_lock,
            c_exposure=c_e,
            config=config,
        )
        sums, _ = simulator.run_benchmark(
            user=user,
            outage_profile=scenario,
            epochs=epochs,
            warmup_epochs=10,
            strategies=[strat],
        )
        s = sums[0]
        sensitivity_records.append({
            "parameter_swept": "c_exposure",
            "parameter_value": c_e,
            "offline_success_rate": s.offline_success_rate,
            "average_locked_funds": s.average_locked_funds,
            "average_unused_funds": s.average_unused_funds,
            "insufficient_reserve_rate": s.insufficient_reserve_rate,
            "average_exposure": s.average_exposure,
        })

    # 4. Sweep Prediction Confidence Level kappa
    print("4. Sweeping confidence_level (0.50 to 0.95)...")
    for conf in [0.50, 0.70, 0.80, 0.85, 0.90, 0.95]:
        strat = UncertaintyAwareJointOptimizationStrategy(
            confidence_level=conf,
            c_short=config.default_c_short,
            c_lock=config.default_c_lock,
            c_exposure=config.default_c_exposure,
            config=config,
        )
        sums, _ = simulator.run_benchmark(
            user=user,
            outage_profile=scenario,
            epochs=epochs,
            warmup_epochs=10,
            strategies=[strat],
        )
        s = sums[0]
        sensitivity_records.append({
            "parameter_swept": "confidence_level",
            "parameter_value": conf,
            "offline_success_rate": s.offline_success_rate,
            "average_locked_funds": s.average_locked_funds,
            "average_unused_funds": s.average_unused_funds,
            "insufficient_reserve_rate": s.insufficient_reserve_rate,
            "average_exposure": s.average_exposure,
        })

    # Write CSV
    csv_path = os.path.join(output_dir, "sensitivity_analysis.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        fieldnames = [
            "parameter_swept",
            "parameter_value",
            "offline_success_rate",
            "average_locked_funds",
            "average_unused_funds",
            "insufficient_reserve_rate",
            "average_exposure",
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(sensitivity_records)

    # Render Sensitivity SVG
    svg_path = os.path.join(charts_dir, "sensitivity_analysis.svg")
    _render_sensitivity_svg(sensitivity_records, svg_path)

    print("\nSensitivity Analysis Complete:")
    print(f" [CSV] Sensitivity Data : {csv_path}")
    print(f" [SVG] Sensitivity Chart: {svg_path}")


def _render_sensitivity_svg(records: List[Dict], output_path: str) -> None:
    width = 900
    height = 520
    bg = "#0d1117"
    text_color = "#c9d1d9"
    text_muted = "#8b949e"
    grid = "#21262d"

    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" style="background-color: {bg}; font-family: -apple-system, sans-serif;">',
        f'<rect width="{width}" height="{height}" fill="{bg}" />',
        f'<text x="40" y="32" fill="{text_color}" font-size="18" font-weight="bold">Parameter Sensitivity Analysis (Rural Weak Signal Regime)</text>',
        f'<text x="40" y="52" fill="{text_muted}" font-size="12">Impact of Shortage Penalty, Lock Cost, Exposure Penalty, and Confidence Level on Success & Locked Funds</text>',
    ]

    # 4 subplots: c_short, c_lock, c_exposure, confidence_level
    subplots = [
        ("c_short", "Shortage Penalty (c_short)", 40, 70, 380, 180),
        ("c_lock", "Lock Cost (c_lock)", 480, 70, 380, 180),
        ("c_exposure", "Exposure Weight (c_exposure)", 40, 290, 380, 180),
        ("confidence_level", "Confidence Level (kappa)", 480, 290, 380, 180),
    ]

    for param, title, px, py, pw, ph in subplots:
        subset = [r for r in records if r["parameter_swept"] == param]
        if not subset:
            continue

        # Border & Title
        svg.append(f'<rect x="{px}" y="{py}" width="{pw}" height="{ph}" rx="6" fill="#161b22" stroke="#30363d" stroke-width="1" />')
        svg.append(f'<text x="{px + 12}" y="{py + 20}" fill="{text_color}" font-size="12" font-weight="bold">{title}</text>')

        # Plot area
        mx, my, mw, mh = px + 45, py + 35, pw - 60, ph - 65

        # Horizontal Gridlines for Success Rate (60% to 100%)
        for pct in [60, 80, 100]:
            y = my + mh - ((pct - 50) / 50.0) * mh
            svg.append(f'<line x1="{mx}" y1="{y}" x2="{mx + mw}" y2="{y}" stroke="{grid}" stroke-width="1" />')
            svg.append(f'<text x="{mx - 6}" y="{y + 3}" fill="{text_muted}" font-size="9" text-anchor="end">{pct}%</text>')

        # Points & Line
        n = len(subset)
        points_success = []
        for i, r in enumerate(subset):
            x = mx + (i / max(1, n - 1)) * mw
            y_succ = my + mh - ((r["offline_success_rate"] - 50) / 50.0) * mh
            points_success.append((x, y_succ, r["parameter_value"], r["offline_success_rate"], r["average_locked_funds"]))

        # Draw Success Line
        path_d = " ".join([f"{'M' if i==0 else 'L'} {p[0]:.1f} {p[1]:.1f}" for i, p in enumerate(points_success)])
        svg.append(f'<path d="{path_d}" fill="none" stroke="#10b981" stroke-width="2" />')

        # Draw Points
        for x, y, val, succ, locked in points_success:
            svg.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="4" fill="#10b981" />')
            # Label
            val_str = f"{val:.4f}" if param == "c_lock" else (f"{val:.2f}" if param in ["c_exposure", "confidence_level"] else f"{val:.1f}")
            svg.append(f'<text x="{x:.1f}" y="{my + mh + 15}" fill="{text_muted}" font-size="9" text-anchor="middle">{val_str}</text>')
            svg.append(f'<text x="{x:.1f}" y="{y - 7}" fill="#10b981" font-size="8" text-anchor="middle" font-weight="bold">{succ:.0f}%</text>')

    svg.append('</svg>')
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(svg))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="UPIMesh Sensitivity Analysis")
    parser.add_argument("--epochs", type=int, default=40, help="Epochs per sensitivity evaluation point")
    parser.add_argument("--seed", type=int, default=42, help="RNG seed")
    parser.add_argument("--output-dir", type=str, default="results", help="Output directory")
    args = parser.parse_args()

    run_sensitivity_analysis(output_dir=args.output_dir, epochs=args.epochs, seed=args.seed)

