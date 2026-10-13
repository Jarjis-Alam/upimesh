package com.demo.upimesh.model;

/**
 * Request payload for submitting a client-constructed, device-signed PaymentInstruction.
 */
public record SignedPaymentRequest(
        String deviceId,
        PaymentInstruction instruction
) {
    public SignedPaymentRequest {
        if (deviceId == null || deviceId.isBlank()) {
            throw new IllegalArgumentException("deviceId must not be blank");
        }
        if (instruction == null) {
            throw new IllegalArgumentException("instruction must not be null");
        }
    }
}
