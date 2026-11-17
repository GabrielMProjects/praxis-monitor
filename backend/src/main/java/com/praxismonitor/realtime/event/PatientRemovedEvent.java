package com.praxismonitor.realtime.event;

public record PatientRemovedEvent(String patientId) implements DomainEvent {
}
