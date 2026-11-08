"""
Data structures representing user profiles, outage events, transactions,
allocation decisions, and evaluation metrics.
"""

from dataclasses import dataclass, field
from typing import List, Optional


@dataclass
class UserProfile:
    """Represents a mobile user's financial capacity and behavioral payment profile."""
    user_id: str
    profile_name: str
    available_balance: float
    maximum_allowance: float = 2000.0
    spending_rate_mean: float = 40.0        # Expected INR spent per active hour
    spending_rate_std: float = 25.0         # Standard deviation of hourly spend
    tx_probability_per_hour: float = 0.35   # Probability of making >=1 transaction in an hour
    peak_hours: List[int] = field(default_factory=lambda: [8, 9, 13, 14, 18, 19, 20])


@dataclass
class OutageProfile:
    """Characterizes the connectivity environment and outage patterns of a location/network."""
    profile_name: str
    base_outage_probability: float          # Probability of experiencing an outage during horizon H
    mean_duration_hours: float              # Expected duration of an outage in hours
    std_duration_hours: float               # Standard deviation of outage duration
    burst_probability: float = 0.05         # Probability of an unexpected long blackout anomaly


@dataclass
class OutageEvent:
    """A concrete simulated connectivity outage event within a planning horizon."""
    occurred: bool
    start_hour: float = 0.0
    duration_hours: float = 0.0
    is_unexpected: bool = False

    @property
    def end_hour(self) -> float:
        return self.start_hour + self.duration_hours


@dataclass
class Transaction:
    """An individual payment transaction attempted by the user."""
    tx_id: str
    timestamp_hour: float
    amount: float
    occurred_during_outage: bool
    was_successful: bool = True
    shortage_amount: float = 0.0


@dataclass
class AllocationDecision:
    """The output of an allowance provisioning strategy for a specific horizon."""
    strategy: str
    recommended_reserve: float
    predicted_outage_prob: float
    predicted_outage_duration: float
    predicted_demand: float
    available_balance: float
    allowance_limit: float
    objective_cost: float = 0.0
    uncertainty_margin: float = 0.0
    safety_floor: float = 0.0


@dataclass
class EpochResult:
    """Comprehensive outcome trace for a single evaluation epoch (planning horizon)."""
    epoch_id: int
    strategy: str
    user_profile: str
    outage_scenario: str
    reserve_allocated: float
    actual_outage: bool
    actual_outage_duration: float
    actual_demand_during_outage: float
    total_demand_in_epoch: float
    spent_from_reserve: float
    unused_reserve: float
    shortage_amount: float
    failed_transactions_count: int
    total_offline_transactions: int
    financial_exposure: float
    demand_prediction_error: float
    outage_prob_brier_score: float


@dataclass
class BenchmarkSummary:
    """Aggregated empirical benchmark metrics across multiple simulated epochs."""
    strategy: str
    outage_scenario: str
    user_profile: str
    total_epochs: int
    outage_epochs_count: int
    offline_success_rate: float       # Percentage of offline payment demand successfully settled (0-100%)
    insufficient_reserve_rate: float  # Percentage of offline epochs with >=1 shortage failure (0-100%)
    average_locked_funds: float       # Mean reserve R held in escrow (INR)
    average_unused_funds: float       # Mean unspent reserve returned at horizon end (INR)
    average_shortage_amount: float    # Mean unsatisfied demand during outages (INR)
    average_exposure: float           # Mean financial risk exposure index Risk(R)
    demand_mae: float                 # Mean Absolute Error of demand forecast (INR)
    demand_rmse: float                # Root Mean Squared Error of demand forecast (INR)
    brier_score: float                # Brier score for outage probability calibration
    success_rate_std: float = 0.0     # Standard deviation of success rate across seeds
    locked_funds_std: float = 0.0     # Standard deviation of locked funds across seeds
    total_failed_transactions: int = 0  # Total count of discrete transaction failures
    atomic_success_rate: float = 0.0    # Discrete transaction count success rate (%)
    realized_combined_cost: float = 0.0 # Realized combined cost: c_lock*R*H + c_short*shortage + c_exposure*risk
    combined_cost_std: float = 0.0      # Standard deviation of realized combined cost across seeds

