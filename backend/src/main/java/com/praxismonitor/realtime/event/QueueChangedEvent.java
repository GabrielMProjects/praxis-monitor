package com.praxismonitor.realtime.event;

import java.util.List;

import com.praxismonitor.patient.domain.Patient;

/** The waiting queue changed in any way. Carries the full, correctly sorted queue (next patient first). */
public record QueueChangedEvent(List<Patient> queue) implements DomainEvent {
}
