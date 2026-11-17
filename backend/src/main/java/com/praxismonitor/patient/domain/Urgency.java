package com.praxismonitor.patient.domain;

/**
 * Demo urgency levels. Lower priority number = served first.
 * Technical demonstration only - NOT a clinically validated triage scale.
 */
public enum Urgency {
    CRITICAL(1),
    HIGH(2),
    MEDIUM(3),
    LOW(4);

    private final int priority;

    Urgency(int priority) {
        this.priority = priority;
    }

    public int priority() {
        return priority;
    }
}
