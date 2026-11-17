package com.praxismonitor.realtime.event;

import com.praxismonitor.patient.domain.Patient;

public record PatientAddedEvent(Patient patient) implements DomainEvent {
}
