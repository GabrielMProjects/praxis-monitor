package com.praxismonitor.realtime.dto;

import java.util.List;

import com.praxismonitor.patient.api.dto.PatientResponse;
import com.praxismonitor.patient.domain.Urgency;
import com.praxismonitor.room.api.dto.RoomResponse;

/** Payload records of the WebSocket messages. PATIENT_ADDED carries a PatientResponse, ROOM_STATUS_CHANGED a RoomResponse. */
public final class Payloads {

    private Payloads() {
    }

    public record PatientRemoved(String patientId) {
    }

    public record UrgencyChanged(PatientResponse patient, Urgency previousUrgency) {
    }

    public record QueueChanged(List<PatientResponse> patients) {
    }

    public record PatientAssigned(PatientResponse patient, RoomResponse room) {
    }
}
