package com.demo.upimesh.model;

import java.util.List;

/**
 * Result metrics capturing the outcome of simulated mesh gossip rounds.
 */
public record SimulationResult(
        int roundsRun,
        List<MeshPacket> deliveredPackets,
        List<PaymentInstruction> settledInstructions,
        List<MeshPacket> expiredPackets,
        List<MeshPacket> droppedNoNeighborPackets
) {
    public int getDeliveredCount() {
        return deliveredPackets.size();
    }

    public int getSettledCount() {
        return settledInstructions.size();
    }

    public int getExpiredCount() {
        return expiredPackets.size();
    }

    public int getDroppedNoNeighborCount() {
        return droppedNoNeighborPackets.size();
    }

    public boolean isFullyDelivered() {
        return !deliveredPackets.isEmpty() && expiredPackets.isEmpty() && droppedNoNeighborPackets.isEmpty();
    }
}
