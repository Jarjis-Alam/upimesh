"""
Synthetic trace generator for user spending habits and network connectivity outages.
Supports non-stationary regime shifts, unexpected outages, and deterministic reproducibility.
"""

import math
import random
from typing import List, Tuple
from .models import UserProfile, OutageProfile, OutageEvent, Transaction


class SyntheticDataGenerator:
    """
    Generates reproducible traces of user payment behaviors and connectivity outage events.
    """

    def __init__(self, seed: int = 42):
        self.seed = seed
        self.rng = random.Random(seed)

    def set_seed(self, seed: int) -> None:
        """Resets the random number generator seed for deterministic reproducibility."""
        self.seed = seed
        self.rng = random.Random(seed)

    # -------------------------------------------------------------------------
    # Pre-defined User Archetypes
    # -------------------------------------------------------------------------
    @staticmethod
    def get_standard_user_profiles() -> List[UserProfile]:
        return [
            UserProfile(
                user_id="alice_commuter",
                profile_name="Daily Commuter",
                available_balance=5000.0,
                maximum_allowance=2000.0,
                spending_rate_mean=60.0,
                spending_rate_std=30.0,
                tx_probability_per_hour=0.45,
                peak_hours=[8, 9, 10, 13, 17, 18, 19],
            ),
            UserProfile(
                user_id="bob_shopper",
                profile_name="Occasional Shopper",
                available_balance=10000.0,
                maximum_allowance=2000.0,
                spending_rate_mean=180.0,
                spending_rate_std=90.0,
                tx_probability_per_hour=0.15,
                peak_hours=[14, 15, 16, 20, 21],
            ),
            UserProfile(
                user_id="carol_courier",
                profile_name="Active Courier",
                available_balance=8000.0,
                maximum_allowance=2000.0,
                spending_rate_mean=85.0,
                spending_rate_std=40.0,
                tx_probability_per_hour=0.60,
                peak_hours=[9, 10, 11, 12, 14, 15, 16, 17, 18],
            ),
            UserProfile(
                user_id="david_budget",
                profile_name="Budget Cautious",
                available_balance=1500.0,
                maximum_allowance=1000.0,
                spending_rate_mean=25.0,
                spending_rate_std=12.0,
                tx_probability_per_hour=0.20,
                peak_hours=[12, 13, 19, 20],
            ),
        ]

    # -------------------------------------------------------------------------
    # Pre-defined Connectivity Outage Scenarios
    # -------------------------------------------------------------------------
    @staticmethod
    def get_standard_outage_profiles() -> List[OutageProfile]:
        return [
            OutageProfile(
                profile_name="Urban Metro Commute",
                base_outage_probability=0.75,
                mean_duration_hours=0.75,     # 45 minutes
                std_duration_hours=0.25,
                burst_probability=0.03,
            ),
            OutageProfile(
                profile_name="Rural Weak Signal",
                base_outage_probability=0.70,
                mean_duration_hours=5.00,     # 5 hours
                std_duration_hours=2.00,
                burst_probability=0.10,
            ),
            OutageProfile(
                profile_name="Reliable Urban 5G",
                base_outage_probability=0.08,  # Rare outage
                mean_duration_hours=0.30,     # 18 minutes
                std_duration_hours=0.10,
                burst_probability=0.01,
            ),
            OutageProfile(
                profile_name="Non-Stationary Travel Shift",
                base_outage_probability=0.10,  # Dynamically shifts mid-simulation
                mean_duration_hours=1.00,
                std_duration_hours=0.50,
                burst_probability=0.05,
            ),
            OutageProfile(
                profile_name="Adversarial Grid Shock",
                base_outage_probability=0.20,
                mean_duration_hours=2.00,
                std_duration_hours=1.00,
                burst_probability=0.30,       # High probability of unexpected multi-hour blackout
            ),
        ]

    # -------------------------------------------------------------------------
    # Event and Transaction Generation
    # -------------------------------------------------------------------------
    def generate_outage_event(
        self,
        profile: OutageProfile,
        epoch_idx: int = 0,
        total_epochs: int = 60,
        horizon_hours: float = 24.0,
    ) -> OutageEvent:
        """
        Simulates whether an outage occurs during this horizon, its start time and duration.
        Accounts for non-stationary regime shifts and unexpected burst outages.
        """
        effective_prob = profile.base_outage_probability
        mean_dur = profile.mean_duration_hours
        std_dur = profile.std_duration_hours

        # Handle non-stationary travel shift (regime shift in second half of simulation)
        if "Non-Stationary" in profile.profile_name:
            if epoch_idx >= total_epochs // 2:
                # Travel into poor network zone: outage probability jumps to 80%, duration to 4 hours
                effective_prob = 0.80
                mean_dur = 4.0
                std_dur = 1.5

        # Check if outage occurs
        occurred = self.rng.random() < effective_prob
        if not occurred:
            return OutageEvent(occurred=False)

        # Check for unexpected burst anomaly (e.g. severe infrastructure blackout)
        is_burst = self.rng.random() < profile.burst_probability
        if is_burst:
            # Burst duration 6 to 14 hours
            duration = min(horizon_hours, max(4.0, self.rng.gauss(8.0, 2.5)))
            start_hour = self.rng.uniform(0.0, max(0.0, horizon_hours - duration))
            return OutageEvent(
                occurred=True,
                start_hour=round(start_hour, 2),
                duration_hours=round(duration, 2),
                is_unexpected=True,
            )

        # Standard modeled outage duration (lognormal-like / bounded Gaussian)
        raw_duration = self.rng.gauss(mean_dur, std_dur)
        duration = min(horizon_hours * 0.9, max(0.15, raw_duration))

        # Start time biased towards commuter peak hours if metro scenario
        if "Metro" in profile.profile_name and self.rng.random() < 0.8:
            commute_peaks = [8.5, 17.5]
            center = self.rng.choice(commute_peaks)
            start_hour = max(0.0, min(horizon_hours - duration, self.rng.gauss(center, 0.5)))
        else:
            start_hour = self.rng.uniform(0.0, max(0.0, horizon_hours - duration))

        return OutageEvent(
            occurred=True,
            start_hour=round(start_hour, 2),
            duration_hours=round(duration, 2),
            is_unexpected=False,
        )

    def generate_transactions_for_horizon(
        self,
        user: UserProfile,
        outage: OutageEvent,
        horizon_hours: float = 24.0,
        demand_distribution: str = "gaussian",
    ) -> List[Transaction]:
        """
        Simulates discrete payment transactions across the horizon hours according to user habits.
        Marks transactions that fall within the outage interval.
        Supports 'gaussian', 'lognormal', and 'pareto' (heavy-tailed) spending distributions.
        """
        transactions: List[Transaction] = []
        tx_counter = 0

        for hour in range(int(horizon_hours)):
            is_peak = hour in user.peak_hours
            hourly_prob = user.tx_probability_per_hour * (1.8 if is_peak else 0.5)
            hourly_prob = min(0.95, hourly_prob)

            # Poisson/Bernoulli arrival of payments in this hour
            if self.rng.random() < hourly_prob:
                # Multiple sub-transactions possible during peak commute (e.g. coffee + metro ticket)
                num_tx = 1
                if is_peak and self.rng.random() < 0.35:
                    num_tx = 2

                for _ in range(num_tx):
                    tx_counter += 1
                    sub_minute = self.rng.uniform(0.0, 0.98)
                    tx_time = round(float(hour) + sub_minute, 2)

                    mean_val = user.spending_rate_mean * (1.3 if is_peak else 0.8)
                    std_val = max(5.0, user.spending_rate_std)

                    if demand_distribution == "lognormal":
                        # Log-normal distribution with matching mean and std
                        var_val = std_val ** 2
                        sigma_ln = math.sqrt(math.log(1.0 + var_val / (mean_val ** 2)))
                        mu_ln = math.log(mean_val) - 0.5 * (sigma_ln ** 2)
                        raw_amount = math.exp(self.rng.gauss(mu_ln, sigma_ln))
                        amount = max(10.0, min(user.maximum_allowance, round(raw_amount, 2)))
                    elif demand_distribution == "pareto":
                        # Heavy-tailed Pareto Type I distribution (alpha=2.2)
                        # Mean = alpha * xm / (alpha - 1) => xm = mean * (alpha - 1) / alpha
                        alpha = 2.2
                        xm = mean_val * (alpha - 1.0) / alpha
                        u = max(1e-5, min(0.9995, self.rng.random()))
                        raw_amount = xm * ((1.0 - u) ** (-1.0 / alpha))
                        amount = max(10.0, min(user.maximum_allowance, round(raw_amount, 2)))
                    else:
                        # Default Gaussian spend amount truncated at 10.0
                        raw_amount = self.rng.gauss(mean_val, std_val)
                        amount = max(10.0, round(raw_amount, 2))

                    in_outage = False
                    if outage.occurred:
                        if outage.start_hour <= tx_time <= outage.end_hour:
                            in_outage = True

                    transactions.append(
                        Transaction(
                            tx_id=f"tx_{user.user_id}_{tx_counter}",
                            timestamp_hour=tx_time,
                            amount=amount,
                            occurred_during_outage=in_outage,
                        )
                    )

        # Sort chronologically by timestamp
        transactions.sort(key=lambda t: t.timestamp_hour)
        return transactions

