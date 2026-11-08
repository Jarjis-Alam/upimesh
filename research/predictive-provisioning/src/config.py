"""
Configuration parameters, defaults, and physical/financial constraints
for the predictive offline allowance provisioning module.

Aligned with UPIMesh backend rules in OfflineAllowanceService:
- Maximum allowance duration: 1 to 72 hours (default: 24 hours)
- Standard allowance limits: Up to ₹2,000.00 (configured per account)
- Escrow conservation: Funds are locked in system-escrow and refunded upon expiry
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class ProvisioningConfig:
    """
    Parameters governing the predictive provisioning objective function and constraints.

    Objective:
      J(R) = c_lock * R * H + p_out * c_short * E[max(D_T - R, 0)] + c_exposure * Risk(R)

    Subject to:
      0 <= R <= min(available_balance, maximum_allowance)

    Units and Assumptions:
    - R: Recommended reserve in Indian Rupees (INR).
    - H: Planning horizon in hours (default: 24.0 hours).
    - p_out: Estimated probability of an outage occurring in horizon H (dimensionless, [0, 1]).
    - D_T: Predicted total spending demand during the outage window (INR).
    - c_lock: Cost rate of locking funds per INR per hour (dimension: INR^-1 * hour^-1).
              Represents liquidity preference and lost yield on locked escrow.
              Default: 0.0001 / hour (corresponds to approx 0.24% daily opportunity cost).
    - c_short: Unit shortage penalty multiplier per INR of unmet demand (dimensionless, > 1.0).
               Represents user distress, merchant transaction rejection, and reputational penalty.
               Default: 2.0 (unmet offline payment is penalized at 2x monetary value).
    - c_exposure: Weight of the on-device exposure risk penalty (dimensionless).
                  Default: 0.05.
    - Risk(R): Convex financial exposure function: R^2 / maximum_allowance.
               Penalizes disproportionately large offline reserves susceptible to handset theft or key compromise.
    """
    default_horizon_hours: float = 24.0
    min_horizon_hours: float = 1.0
    max_horizon_hours: float = 72.0

    default_maximum_allowance: float = 2000.0
    default_c_lock: float = 0.0001
    default_c_short: float = 2.0
    default_c_exposure: float = 0.05

    # Discrete step size for currency reserve allocation (whole Rupees)
    grid_step_inr: float = 10.0

    currency: str = "INR"

