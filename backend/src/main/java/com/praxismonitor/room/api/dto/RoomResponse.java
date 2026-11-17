package com.praxismonitor.room.api.dto;

import com.praxismonitor.room.domain.Room;
import com.praxismonitor.room.domain.RoomStatus;

public record RoomResponse(String id, String name, RoomStatus status, String patientId, String patientName) {

    public static RoomResponse from(Room r) {
        return new RoomResponse(r.id(), r.name(), r.status(), r.patientId(), r.patientName());
    }
}
