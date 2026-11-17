package com.praxismonitor.realtime.event;

import com.praxismonitor.room.domain.Room;

public record RoomStatusChangedEvent(Room room) implements DomainEvent {
}
