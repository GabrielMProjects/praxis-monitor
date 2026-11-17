package com.praxismonitor.room.domain;

/** AVAILABLE -> OCCUPIED -> CLEANING -> AVAILABLE (plus manual AVAILABLE -> CLEANING). */
public enum RoomStatus {
    AVAILABLE,
    OCCUPIED,
    CLEANING
}
