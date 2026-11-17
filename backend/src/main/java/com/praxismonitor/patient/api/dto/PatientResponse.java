package com.praxismonitor.patient.api.dto;

import java.time.Instant;

import com.praxismonitor.patient.domain.Patient;
import com.praxismonitor.patient.domain.PatientStatus;
import com.praxismonitor.patient.domain.Urgency;

/**
 * @param queuePosition 1-based position in the waiting queue; null unless status is WAITING
 */
public record PatientResponse(String id, String name, Urgency urgency, int priority, Instant arrivedAt,
        PatientStatus status, Integer queuePosition) {

    public static PatientResponse from(Patient p, Integer queuePosition) {
        return new PatientResponse(p.id(), p.name(), p.urgency(), p.urgency().priority(), p.arrivedAt(), p.status(),
                queuePosition);
    }
}
