package com.praxismonitor.patient.domain;

import java.time.Instant;
import java.util.Objects;

import com.praxismonitor.common.exception.InvalidStateTransitionException;

/**
 * Immutable patient aggregate (synthetic demo data only). State changes return new instances.
 * The arrival order is NOT stored here: it is the monotonic sequence assigned by the TriageQueue.
 */
public record Patient(String id, String name, Urgency urgency, Instant arrivedAt, PatientStatus status) {

    public Patient {
        Objects.requireNonNull(id, "id");
        Objects.requireNonNull(urgency, "urgency");
        Objects.requireNonNull(arrivedAt, "arrivedAt");
        Objects.requireNonNull(status, "status");
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("name must not be blank");
        }
    }

    public static Patient admit(String id, String name, Urgency urgency, Instant arrivedAt) {
        return new Patient(id, name.strip(), urgency, arrivedAt, PatientStatus.WAITING);
    }

    public Patient update(String newName, Urgency newUrgency) {
        requireStatus(PatientStatus.WAITING, "be edited");
        return new Patient(id, newName.strip(), newUrgency, arrivedAt, status);
    }

    public Patient startTreatment() {
        requireStatus(PatientStatus.WAITING, "start treatment");
        return new Patient(id, name, urgency, arrivedAt, PatientStatus.IN_TREATMENT);
    }

    public Patient completeTreatment() {
        requireStatus(PatientStatus.IN_TREATMENT, "complete treatment");
        return new Patient(id, name, urgency, arrivedAt, PatientStatus.COMPLETED);
    }

    private void requireStatus(PatientStatus required, String action) {
        if (status != required) {
            throw new InvalidStateTransitionException(
                    "Patient " + id + " is " + status + " and cannot " + action + " (requires " + required + ")");
        }
    }
}
