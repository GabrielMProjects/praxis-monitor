package com.praxismonitor.common.exception;

/**
 * Pure-Java exception for forbidden state changes (e.g. assigning a patient to an occupied room).
 * Mapped to HTTP 409 by {@link GlobalExceptionHandler}.
 */
public class InvalidStateTransitionException extends RuntimeException {

    public InvalidStateTransitionException(String message) {
        super(message);
    }
}
