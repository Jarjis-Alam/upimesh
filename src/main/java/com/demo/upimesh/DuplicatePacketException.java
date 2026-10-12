package com.demo.upimesh;

public class DuplicatePacketException extends IllegalStateException {
    public DuplicatePacketException(String message) {
        super(message);
    }

    public DuplicatePacketException(String message, Throwable cause) {
        super(message, cause);
    }
}
