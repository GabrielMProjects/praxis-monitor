package com.praxismonitor.room.api.dto;

import com.praxismonitor.patient.api.dto.PatientResponse;
import com.praxismonitor.room.application.RoomService.Assignment;

public record AssignmentResponse(PatientResponse patient, RoomResponse room) {

    public static AssignmentResponse from(Assignment a) {
        return new AssignmentResponse(PatientResponse.from(a.patient(), null), RoomResponse.from(a.room()));
    }
}
