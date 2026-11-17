package com.praxismonitor.realtime.event;

import com.praxismonitor.patient.domain.Patient;
import com.praxismonitor.room.domain.Room;

public record PatientAssignedToRoomEvent(Patient patient, Room room) implements DomainEvent {
}
