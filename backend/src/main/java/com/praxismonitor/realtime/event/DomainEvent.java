package com.praxismonitor.realtime.event;

/** Business events raised by application services. They know nothing about WebSocket. */
public sealed interface DomainEvent
        permits PatientAddedEvent, PatientRemovedEvent, PatientUrgencyChangedEvent, QueueChangedEvent,
                RoomStatusChangedEvent, PatientAssignedToRoomEvent {
}
