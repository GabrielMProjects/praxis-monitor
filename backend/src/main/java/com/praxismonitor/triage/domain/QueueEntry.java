package com.praxismonitor.triage.domain;

import java.util.Comparator;
import java.util.Objects;

import com.praxismonitor.patient.domain.Urgency;

/**
 * Immutable heap entry. Entries are never mutated: a change creates a new entry
 * (same sequence), so the heap invariant cannot be broken from outside.
 *
 * @param sequence monotonic arrival number assigned by {@link TriageQueue}; unique per admission
 */
public record QueueEntry(String patientId, Urgency urgency, long sequence) {

    /**
     * Explicit ordering: lower priority number first (CRITICAL=1 ... LOW=4);
     * on equal priority the lower (= earlier) sequence wins. Sequences are unique,
     * so the order is total and deterministic although PriorityQueue itself is not stable.
     */
    public static final Comparator<QueueEntry> ORDER = Comparator
            .comparingInt((QueueEntry e) -> e.urgency().priority())
            .thenComparingLong(QueueEntry::sequence);

    public QueueEntry {
        Objects.requireNonNull(patientId, "patientId");
        Objects.requireNonNull(urgency, "urgency");
    }
}
