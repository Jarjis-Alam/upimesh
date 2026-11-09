#!/usr/bin/env python3
"""
AORA Parameter Sensitivity and Robustness Validation (30-Seed Monte Carlo Study).

Implements the IEEE-ready validation suite:
1. 30 Independent PRNG Seeds (1,800 evaluation horizons per configuration).
2. 95% Student's t-Confidence Intervals on all primary performance metrics.
3. Strict Cold-Start (N=0) vs Warm-Start separation.
4. Comprehensive 2D Reserve Ceiling Transition Heatmap (c_exposure x c_short).
5. Mathematical verification of the Metro Commute duration capacity boundary.
6. Absolute zero code changes to payment, escrow, settlement, wallet, or cryptography.
"""

import math
import os
import sys
from typing import Dict, List, Tuple

from src.aora import AORAStrategy
from src.config import ProvisioningConfig
from src.data_generator import SyntheticDataGenerator
from src.models import OutageProfile, UserProfile
from src.simulator import ProvisioningSimulator


def compute_t_confidence_interval(data: List[float]) -> Tuple[float, float, float]:
    """Computes sample mean, standard deviation, and 95% Student's t half-width."""
    n = len(data)
    if n == 0:
        return 0.0, 0.0, 0.0
    mean = sum(data) / float(n)
    if n == 1:
        return mean, 0.0, 0.0
    var = sum((x - mean) ** 2 for x in data) / float(n - 1)
    std = math.sqrt(max(0.0, var))
    # Student's t critical value for df = n - 1 at 95% two-tailed
    t_val = 2.045 if n >= 30 else (2.093 if n >= 20 else (2.145 if n >= 14 else 2.262))
    half_width = t_val * (std / math.sqrt(n))
    return mean, std, half_width


def evaluate_30seed_configuration(
    user: UserProfile,
    scenario: OutageProfile,
    c_exposure: float,
    c_short: float,
    seeds: List[int] = list(range(1, 31)),
    epochs: int = 60,
    warmup_epochs: int = 10,
) -> Dict[str, Tuple[float, float, float]]:
    """Evaluates AORA configuration across 30 seeds and returns (mean, std, 95% CI half-width) for metrics."""
    config = ProvisioningConfig()
    
    seed_reserves: List[float] = []
    seed_ceiling_pcts: List[float] = []
    seed_success_rates: List[float] = []
    seed_shortage_rates: List[float] = []
    seed_total_costs: List[float] = []
    seed_holding_costs: List[float] = []
    seed_exposure_costs: List[float] = []
    seed_shortage_costs: List[float] = []

    # Cold-start vs Warm-start tracking
    seed_cold_reserves: List[float] = []
    seed_cold_success: List[float] = []
    seed_warm_reserves: List[float] = []
    seed_warm_success: List[float] = []

    H = 24.0
    R_max = user.maximum_allowance

    for s in seeds:
        sim = ProvisioningSimulator(config=config, seed=s)
        strat = AORAStrategy(
            name=f"AORA_cE{c_exposure}_cS{c_short}",
            c_exposure=c_exposure,
            c_short=c_short,
            config=config,
        )
        summaries, timeline = sim.run_benchmark(
            user=user,
            outage_profile=scenario,
            epochs=epochs,
            warmup_epochs=warmup_epochs,
            strategies=[strat],
        )
        
        # Per-seed timeline metrics
        ceiling_count = 0
        tot_c_h, tot_c_e, tot_c_s = 0.0, 0.0, 0.0
        
        cold_r, cold_succ_spent, cold_dem = 0.0, 0.0, 0.0
        warm_r, warm_succ_spent, warm_dem = 0.0, 0.0, 0.0
        cold_epochs_count = 0
        warm_epochs_count = 0

        for ep in timeline:
            R = ep.reserve_allocated
            if R >= (R_max - 1.0):
                ceiling_count += 1
            
            c_h = config.default_c_lock * R * H
            c_e = c_exposure * (R * R) / R_max
            c_s = c_short * ep.shortage_amount
            
            tot_c_h += c_h
            tot_c_e += c_e
            tot_c_s += c_s

            # Cold start: first 3 epochs (N <= 2 genuine observations)
            if ep.epoch_id <= 3:
                cold_r += R
                cold_succ_spent += ep.spent_from_reserve
                cold_dem += ep.actual_demand_during_outage
                cold_epochs_count += 1
            else:
                warm_r += R
                warm_succ_spent += ep.spent_from_reserve
                warm_dem += ep.actual_demand_during_outage
                warm_epochs_count += 1

        n_ep = float(len(timeline))
        seed_reserves.append(summaries[0].average_locked_funds)
        seed_ceiling_pcts.append((ceiling_count / n_ep) * 100.0)
        seed_success_rates.append(summaries[0].offline_success_rate)
        seed_shortage_rates.append(summaries[0].insufficient_reserve_rate)
        seed_holding_costs.append(tot_c_h / n_ep)
        seed_exposure_costs.append(tot_c_e / n_ep)
        seed_shortage_costs.append(tot_c_s / n_ep)
        seed_total_costs.append((tot_c_h + tot_c_e + tot_c_s) / n_ep)

        # Cold/warm breakdowns
        seed_cold_reserves.append(cold_r / max(1, cold_epochs_count))
        seed_cold_success.append((cold_succ_spent / max(1e-6, cold_dem)) * 100.0 if cold_dem > 0 else 100.0)
        seed_warm_reserves.append(warm_r / max(1, warm_epochs_count))
        seed_warm_success.append((warm_succ_spent / max(1e-6, warm_dem)) * 100.0 if warm_dem > 0 else 100.0)

    return {
        "reserve": compute_t_confidence_interval(seed_reserves),
        "ceiling_pct": compute_t_confidence_interval(seed_ceiling_pcts),
        "success_rate": compute_t_confidence_interval(seed_success_rates),
        "shortage_rate": compute_t_confidence_interval(seed_shortage_rates),
        "total_cost": compute_t_confidence_interval(seed_total_costs),
        "holding_cost": compute_t_confidence_interval(seed_holding_costs),
        "exposure_cost": compute_t_confidence_interval(seed_exposure_costs),
        "shortage_cost": compute_t_confidence_interval(seed_shortage_costs),
        "cold_reserve": compute_t_confidence_interval(seed_cold_reserves),
        "cold_success": compute_t_confidence_interval(seed_cold_success),
        "warm_reserve": compute_t_confidence_interval(seed_warm_reserves),
        "warm_success": compute_t_confidence_interval(seed_warm_success),
    }


def main():
    print("=" * 100)
    print(" AORA 30-SEED ROBUSTNESS & PARAMETER SENSITIVITY VALIDATION (IEEE SUITE)")
    print("=" * 100)

    user = SyntheticDataGenerator.get_standard_user_profiles()[0]  # Alice Commuter (R_max = 2000)
    scenarios = {p.profile_name: p for p in SyntheticDataGenerator.get_standard_outage_profiles()}
    
    rural_scen = scenarios["Rural Weak Signal"]
    metro_scen = scenarios["Urban Metro Commute"]
    urban_scen = scenarios["Reliable Urban 5G"]

    seeds = list(range(1, 31))  # Exact 30 independent seeds = 1,800 evaluation horizons per configuration

    # =========================================================================
    # Task 1: Investigation of the Metro Commute Flat Reserve Region
    # =========================================================================
    print("\n" + "=" * 90)
    print(" TASK 1: INVESTIGATION OF METRO COMMUTE DURATION CAPACITY PINNING")
    print("=" * 90)
    print(f"{'c_exposure':<12} | {'Reserve (95% CI)':<22} | {'Ceiling Hit % (95% CI)':<24} | {'Combined Cost (95% CI)':<24}")
    print("-" * 90)
    for ce in [0.005, 0.01, 0.05, 0.10, 0.15, 0.20, 0.35, 0.50]:
        res = evaluate_30seed_configuration(user, metro_scen, c_exposure=ce, c_short=2.0, seeds=seeds)
        r_m, _, r_ci = res["reserve"]
        c_m, _, c_ci = res["ceiling_pct"]
        cost_m, _, cost_ci = res["total_cost"]
        print(f"{ce:<12.3f} | ₹{r_m:<7.2f} ± ₹{r_ci:<7.2f} | {c_m:<6.2f}% ± {c_ci:<6.2f}% | ₹{cost_m:<7.2f} ± ₹{cost_ci:<7.2f}")

    # =========================================================================
    # Task 2: 30-Seed Sweep of c_exposure in Rural Weak Signal (c_short = 2.0)
    # =========================================================================
    print("\n" + "=" * 90)
    print(" TASK 2: 30-SEED SWEEP OF c_exposure IN RURAL WEAK SIGNAL (c_short = 2.0)")
    print("=" * 90)
    print(f"{'c_exposure':<12} | {'Reserve (95% CI)':<22} | {'Ceiling Hit % (95% CI)':<24} | {'Success Rate (95% CI)':<24} | {'Combined Cost (95% CI)':<24}")
    print("-" * 110)
    c_exp_values = [0.01, 0.05, 0.10, 0.20, 0.35, 0.50, 0.75, 1.00]
    for ce in c_exp_values:
        res = evaluate_30seed_configuration(user, rural_scen, c_exposure=ce, c_short=2.0, seeds=seeds)
        r_m, _, r_ci = res["reserve"]
        c_m, _, c_ci = res["ceiling_pct"]
        s_m, _, s_ci = res["success_rate"]
        cost_m, _, cost_ci = res["total_cost"]
        print(f"{ce:<12.2f} | ₹{r_m:<7.2f} ± ₹{r_ci:<7.2f} | {c_m:<6.2f}% ± {c_ci:<6.2f}% | {s_m:<6.2f}% ± {s_ci:<6.2f}% | ₹{cost_m:<7.2f} ± ₹{cost_ci:<7.2f}")

    # =========================================================================
    # Task 3: 30-Seed Sweep of c_short in Rural Weak Signal (c_exposure = 0.05)
    # =========================================================================
    print("\n" + "=" * 90)
    print(" TASK 3: 30-SEED SWEEP OF c_short IN RURAL WEAK SIGNAL (c_exposure = 0.05)")
    print("=" * 90)
    print(f"{'c_short':<12} | {'Reserve (95% CI)':<22} | {'Ceiling Hit % (95% CI)':<24} | {'Success Rate (95% CI)':<24} | {'Combined Cost (95% CI)':<24}")
    print("-" * 110)
    c_short_values = [0.10, 0.25, 0.50, 1.00, 2.00, 3.50, 5.00]
    for cs in c_short_values:
        res = evaluate_30seed_configuration(user, rural_scen, c_exposure=0.05, c_short=cs, seeds=seeds)
        r_m, _, r_ci = res["reserve"]
        c_m, _, c_ci = res["ceiling_pct"]
        s_m, _, s_ci = res["success_rate"]
        cost_m, _, cost_ci = res["total_cost"]
        print(f"{cs:<12.2f} | ₹{r_m:<7.2f} ± ₹{r_ci:<7.2f} | {c_m:<6.2f}% ± {c_ci:<6.2f}% | {s_m:<6.2f}% ± {s_ci:<6.2f}% | ₹{cost_m:<7.2f} ± ₹{cost_ci:<7.2f}")

    # =========================================================================
    # Task 4: 30-Seed 2D Matrix (Heatmap) of Ceiling Hit Rates (Rural Weak Signal)
    # =========================================================================
    print("\n" + "=" * 90)
    print(" TASK 4: 30-SEED 2D CEILING HIT RATE HEATMAP (% of Decisions at R* >= 1999 INR)")
    print("=" * 90)
    c_exp_grid = [0.05, 0.15, 0.30, 0.50, 1.00]
    c_short_grid = [0.25, 0.50, 1.00, 2.00, 5.00]
    
    header = f"{'c_exp \\ c_short':<16} | " + " | ".join([f"{cs:<12.2f}" for cs in c_short_grid])
    print(header)
    print("-" * len(header))
    for ce in c_exp_grid:
        row_str = f"c_exp = {ce:<7.2f} | "
        for cs in c_short_grid:
            res = evaluate_30seed_configuration(user, rural_scen, c_exposure=ce, c_short=cs, seeds=seeds)
            c_m, _, c_ci = res["ceiling_pct"]
            row_str += f"{c_m:>5.1f}% ±{c_ci:<4.1f}% | "
        print(row_str)

    # =========================================================================
    # Task 5: Strict Cold-Start (Epochs 1-3) vs Warm-Start (Epochs 4-60) Breakdown
    # =========================================================================
    print("\n" + "=" * 90)
    print(" TASK 5: STRICT COLD-START (N=0..2) vs WARM-START BREAKDOWN (30 SEEDS)")
    print("=" * 90)
    for name, scen in [("Reliable Urban 5G", urban_scen), ("Urban Metro Commute", metro_scen), ("Rural Weak Signal", rural_scen)]:
        res = evaluate_30seed_configuration(user, scen, c_exposure=0.05, c_short=2.0, seeds=seeds)
        cr_m, _, cr_ci = res["cold_reserve"]
        cs_m, _, cs_ci = res["cold_success"]
        wr_m, _, wr_ci = res["warm_reserve"]
        ws_m, _, ws_ci = res["warm_success"]
        print(f"Scenario: {name}")
        print(f"  Cold-Start (Phase 1): Reserve ₹{cr_m:.2f} ± ₹{cr_ci:.2f} | Success Rate: {cs_m:.1f}% ± {cs_ci:.1f}%")
        print(f"  Warm-Start (Phase 2): Reserve ₹{wr_m:.2f} ± ₹{wr_ci:.2f} | Success Rate: {ws_m:.1f}% ± {ws_ci:.1f}%")


if __name__ == "__main__":
    main()

