#!/usr/bin/env python3
"""
AORA Multi-Seed Benchmark Runner.
Executes an empirical comparison of M1, M2, and AORA under identical conditions:
- Identical synthetic datasets
- Identical random seeds: [42, 101, 2024, 777, 9999]
- Identical wallet balances (Alice Commuter, available_balance = ₹5,000, max_allowance = ₹2,000)
- Identical network outage regimes

Preserves M1 and M2 without modification.
"""

import math
import os
import sys
from typing import Dict, List, Tuple

# Ensure predictive-provisioning directory is in sys.path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src.aora import AORAStrategy
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


def run_aora_side_by_side_benchmark(
    epochs: int = 60,
    warmup_epochs: int = 10,
    seeds: List[int] = [42, 101, 2024, 777, 9999],
) -> List[BenchmarkSummary]:
    """Runs M1, M2, and AORA side-by-side on identical traces."""
    config = ProvisioningConfig()
    simulator = ProvisioningSimulator(config=config, seed=seeds[0])

    user_profiles = SyntheticDataGenerator.get_standard_user_profiles()
    primary_user = user_profiles[0]  # Alice Commuter (balance: 5000, max: 2000)

    # Standard scenarios
    outage_profiles = [
        OutageProfile(
            profile_name="Reliable Urban 5G",
            base_outage_probability=0.08,
            mean_duration_hours=0.30,
            std_duration_hours=0.10,
            burst_probability=0.01,
        ),
        OutageProfile(
            profile_name="Urban Metro Commute",
            base_outage_probability=0.75,
            mean_duration_hours=0.75,
            std_duration_hours=0.25,
            burst_probability=0.03,
        ),
        OutageProfile(
            profile_name="Rural Weak Signal",
            base_outage_probability=0.70,
            mean_duration_hours=5.00,
            std_duration_hours=2.00,
            burst_probability=0.10,
        ),
        OutageProfile(
            profile_name="Non-Stationary Travel Shift",
            base_outage_probability=0.45,
            mean_duration_hours=2.50,
            std_duration_hours=1.20,
            burst_probability=0.08,
        ),
        OutageProfile(
            profile_name="Adversarial Grid Shock",
            base_outage_probability=0.60,
            mean_duration_hours=3.50,
            std_duration_hours=1.50,
            burst_probability=0.25,
        ),
    ]

    # Competing strategies under evaluation
    competing_strategies: List[BaseProvisioningStrategy] = [
        FixedAllowanceStrategy(fixed_amount=500.0, config=config),
        DemandOnlyStrategy(safety_factor=1.0, config=config),
        ProposedJointOptimizationStrategy(config=config),
        UncertaintyAwareJointOptimizationStrategy(confidence_level=0.85, config=config),
        AORAStrategy(name="AORA-DRO", confidence_level_demand=0.95, confidence_level_outage=0.95, config=config),
    ]

    all_summaries: List[BenchmarkSummary] = []

    print("\n" + "=" * 90)
    print(f" AORA BENCHMARK: Side-by-Side Comparison with M1 and M2")
    print(f" User: {primary_user.profile_name} (Balance: ₹{primary_user.available_balance:.0f}, Max: ₹{primary_user.maximum_allowance:.0f})")
    print(f" Seeds: {seeds} ({len(seeds)} x {epochs} = {len(seeds) * epochs} horizons per scenario)")
    print("=" * 90)

    for profile in outage_profiles:
        print(f"\n>> Regime: {profile.profile_name}")
        sums, _ = simulator.run_multi_seed_benchmark(
            user=primary_user,
            outage_profile=profile,
            seeds=seeds,
            epochs=epochs,
            warmup_epochs=warmup_epochs,
            strategies=competing_strategies,
        )
        all_summaries.extend(sums)

        # Print clean scenario table
        print(f"   {'Strategy':<24} | {'Success %':<11} | {'Shortage %':<11} | {'Avg Reserve':<12} | {'Avg Shortage':<13} | {'Combined Cost':<14}")
        print("   " + "-" * 95)
        for s in sums:
            print(f"   {s.strategy:<24} | {s.offline_success_rate:>6.1f}% (±{s.success_rate_std:.1f}) | {s.insufficient_reserve_rate:>6.1f}%    | ₹{s.average_locked_funds:>7.2f}    | ₹{s.average_shortage_amount:>7.2f}    | ₹{s.realized_combined_cost:>9.4f}")

    return all_summaries


if __name__ == "__main__":
    run_aora_side_by_side_benchmark()

