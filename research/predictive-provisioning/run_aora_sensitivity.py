#!/usr/bin/env python3
"""
AORA Cost-Weight & Outage Risk Sensitivity Experiment.

Rigorously evaluates how AORA's reserve allocation, ceiling hit rate (R* = 2000 INR),
payment success rate, and realized costs change when varying:
1. Exposure penalty weight (c_exposure): 0.01 to 1.00
2. Shortage penalty weight (c_short): 0.2 to 5.0
3. Outage risk / regime (Urban 5G, Metro, Rural Weak Signal)
4. Joint (c_exposure x c_short) grid in Rural regime to identify the exact unpegging boundary.
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


def evaluate_aora_configuration(
    user: UserProfile,
    scenario: OutageProfile,
    c_exposure: float,
    c_short: float,
    seeds: List[int] = list(range(1, 11)),
    epochs: int = 60,
    warmup_epochs: int = 10,
) -> Dict[str, float]:
    """Runs AORA over multiple random seeds and aggregates performance metrics."""
    config = ProvisioningConfig()
    
    reserves: List[float] = []
    ceiling_hits: List[int] = []
    success_rates: List[float] = []
    shortage_rates: List[float] = []
    total_costs: List[float] = []
    holding_costs: List[float] = []
    exposure_costs: List[float] = []
    shortage_costs: List[float] = []
    total_decisions = 0
    total_ceiling_count = 0

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
        reserves.append(summaries[0].average_locked_funds)
        success_rates.append(summaries[0].offline_success_rate)
        shortage_rates.append(summaries[0].insufficient_reserve_rate)

        # Compute cost decomposition and ceiling count directly from timeline
        strat_key = strat.name
        H = 24.0
        R_max = user.maximum_allowance
        
        for ep_data in timeline:
            total_decisions += 1
            R = ep_data.reserve_allocated
            if R >= (R_max - 1.0):
                total_ceiling_count += 1
            
            # Realized costs for epoch
            spent = ep_data.spent_from_reserve
            shortage = ep_data.shortage_amount
            
            c_h = config.default_c_lock * R * H
            c_e = c_exposure * (R * R) / R_max
            c_s = c_short * shortage
            
            holding_costs.append(c_h)
            exposure_costs.append(c_e)
            shortage_costs.append(c_s)
            total_costs.append(c_h + c_e + c_s)

    mean_res = sum(reserves) / len(reserves)
    mean_succ = sum(success_rates) / len(success_rates)
    mean_short = sum(shortage_rates) / len(shortage_rates)
    mean_tot_cost = sum(total_costs) / (len(seeds) * epochs)
    mean_hold_cost = sum(holding_costs) / (len(seeds) * epochs)
    mean_exp_cost = sum(exposure_costs) / (len(seeds) * epochs)
    mean_sh_cost = sum(shortage_costs) / (len(seeds) * epochs)
    ceiling_hit_pct = (total_ceiling_count / float(total_decisions)) * 100.0

    return {
        "c_exposure": c_exposure,
        "c_short": c_short,
        "mean_reserve": mean_res,
        "ceiling_hit_pct": ceiling_hit_pct,
        "success_rate": mean_succ,
        "shortage_rate": mean_short,
        "total_cost": mean_tot_cost,
        "holding_cost": mean_hold_cost,
        "exposure_cost": mean_exp_cost,
        "shortage_cost": mean_sh_cost,
    }


def main():
    print("=" * 90)
    print(" AORA COST-WEIGHT SENSITIVITY EXPERIMENT (EMPIRICAL UNPEGGING ANALYSIS)")
    print("=" * 90)

    user = SyntheticDataGenerator.get_standard_user_profiles()[0]  # Alice Commuter (R_max = 2000)
    scenarios = {p.profile_name: p for p in SyntheticDataGenerator.get_standard_outage_profiles()}
    
    rural_scen = scenarios["Rural Weak Signal"]
    metro_scen = scenarios["Urban Metro Commute"]
    urban_scen = scenarios["Reliable Urban 5G"]

    seeds = list(range(1, 16))  # 15 random seeds = 900 epochs per configuration

    # -------------------------------------------------------------------------
    # Experiment 1: Sweeping c_exposure in Rural Weak Signal (Baseline c_short = 2.0)
    # -------------------------------------------------------------------------
    print("\n--- EXPERIMENT 1: Sweeping c_exposure in Rural Weak Signal (c_short = 2.0) ---")
    c_exp_values = [0.01, 0.05, 0.10, 0.20, 0.35, 0.50, 0.75, 1.00]
    print(f"{'c_exposure':<12} | {'Reserve (₹)':<12} | {'Ceiling Hit %':<14} | {'Success %':<11} | {'Shortage %':<11} | {'Combined Cost (₹)':<18}")
    print("-" * 88)
    exp1_results = []
    for ce in c_exp_values:
        res = evaluate_aora_configuration(user, rural_scen, c_exposure=ce, c_short=2.0, seeds=seeds)
        exp1_results.append(res)
        print(f"{res['c_exposure']:<12.2f} | {res['mean_reserve']:<12.2f} | {res['ceiling_hit_pct']:<13.1f}% | {res['success_rate']:<10.1f}% | {res['shortage_rate']:<10.1f}% | ₹{res['total_cost']:<16.2f}")

    # -------------------------------------------------------------------------
    # Experiment 2: Sweeping c_short in Rural Weak Signal (Baseline c_exposure = 0.05)
    # -------------------------------------------------------------------------
    print("\n--- EXPERIMENT 2: Sweeping c_short in Rural Weak Signal (c_exposure = 0.05) ---")
    c_short_values = [0.10, 0.25, 0.50, 1.00, 2.00, 3.50, 5.00]
    print(f"{'c_short':<12} | {'Reserve (₹)':<12} | {'Ceiling Hit %':<14} | {'Success %':<11} | {'Shortage %':<11} | {'Combined Cost (₹)':<18}")
    print("-" * 88)
    exp2_results = []
    for cs in c_short_values:
        res = evaluate_aora_configuration(user, rural_scen, c_exposure=0.05, c_short=cs, seeds=seeds)
        exp2_results.append(res)
        print(f"{res['c_short']:<12.2f} | {res['mean_reserve']:<12.2f} | {res['ceiling_hit_pct']:<13.1f}% | {res['success_rate']:<10.1f}% | {res['shortage_rate']:<10.1f}% | ₹{res['total_cost']:<16.2f}")

    # -------------------------------------------------------------------------
    # Experiment 3: Joint Grid in Rural Weak Signal (c_exposure x c_short)
    # -------------------------------------------------------------------------
    print("\n--- EXPERIMENT 3: Joint (c_exposure x c_short) Ceiling Hit Boundary (Rural) ---")
    print(f"{'c_exp \\ c_short':<16} | {'0.25':<10} | {'0.50':<10} | {'1.00':<10} | {'2.00':<10} | {'5.00':<10}")
    print("-" * 75)
    for ce in [0.05, 0.15, 0.30, 0.50, 1.00]:
        row_str = f"c_exp = {ce:<7.2f} | "
        for cs in [0.25, 0.50, 1.00, 2.00, 5.00]:
            res = evaluate_aora_configuration(user, rural_scen, c_exposure=ce, c_short=cs, seeds=seeds[:6])
            row_str += f"{res['ceiling_hit_pct']:<5.1f}%    | "
        print(row_str)

    # -------------------------------------------------------------------------
    # Experiment 4: Metro Commute Sensitivity to c_exposure
    # -------------------------------------------------------------------------
    print("\n--- EXPERIMENT 4: Sweeping c_exposure in Urban Metro Commute (c_short = 2.0) ---")
    print(f"{'c_exposure':<12} | {'Reserve (₹)':<12} | {'Ceiling Hit %':<14} | {'Success %':<11} | {'Shortage %':<11} | {'Combined Cost (₹)':<18}")
    print("-" * 88)
    for ce in [0.01, 0.05, 0.10, 0.20, 0.50]:
        res = evaluate_aora_configuration(user, metro_scen, c_exposure=ce, c_short=2.0, seeds=seeds)
        print(f"{res['c_exposure']:<12.2f} | {res['mean_reserve']:<12.2f} | {res['ceiling_hit_pct']:<13.1f}% | {res['success_rate']:<10.1f}% | {res['shortage_rate']:<10.1f}% | ₹{res['total_cost']:<16.2f}")


if __name__ == "__main__":
    main()
