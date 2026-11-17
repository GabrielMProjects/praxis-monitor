package com.praxismonitor.realtime.event;

import com.praxismonitor.patient.domain.Patient;
import com.praxismonitor.patient.domain.Urgency;

public record PatientUrgencyChangedEvent(Patient patient, Urgency previousUrgency) implements DomainEvent {
}
