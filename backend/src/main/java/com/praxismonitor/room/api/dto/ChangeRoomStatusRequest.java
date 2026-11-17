package com.praxismonitor.room.api.dto;

import com.praxismonitor.room.domain.RoomStatus;

import jakarta.validation.constraints.NotNull;

public record ChangeRoomStatusRequest(@NotNull(message = "must not be null") RoomStatus status) {
}
