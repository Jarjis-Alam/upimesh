package com.demo.upimesh;

import java.util.Arrays;
import java.util.Objects;

public record EncryptedPacket(
        byte[] encryptedAesKey,
        byte[] iv,
        byte[] ciphertext
) {
    public EncryptedPacket {
        Objects.requireNonNull(encryptedAesKey, "encryptedAesKey must not be null");
        Objects.requireNonNull(iv, "iv must not be null");
        Objects.requireNonNull(ciphertext, "ciphertext must not be null");
    }

    public byte[] getEncryptedAesKey() {
        return encryptedAesKey;
    }

    public byte[] getIv() {
        return iv;
    }

    public byte[] getCiphertext() {
        return ciphertext;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof EncryptedPacket that)) return false;
        return Arrays.equals(encryptedAesKey, that.encryptedAesKey)
                && Arrays.equals(iv, that.iv)
                && Arrays.equals(ciphertext, that.ciphertext);
    }

    @Override
    public int hashCode() {
        int result = Arrays.hashCode(encryptedAesKey);
        result = 31 * result + Arrays.hashCode(iv);
        result = 31 * result + Arrays.hashCode(ciphertext);
        return result;
    }
}
