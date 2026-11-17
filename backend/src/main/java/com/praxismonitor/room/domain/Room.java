package com.praxismonitor.room.domain;

import java.util.Objects;

import com.praxismonitor.common.exception.InvalidStateTransitionException;

/**
 * Immutable treatment room. Invariant: OCCUPIED <=> a patient is assigned; otherwise patientId/patientName are null.
 * patientName is a denormalised display snapshot taken at assignment time.
 */
public record Room(String id, String name, RoomStatus status, String patientId, String patientName) {

    public Room {
        Objects.requireNonNull(id, "id");
        Objects.requireNonNull(name, "name");
        Objects.requireNonNull(status, "status");
        boolean occupied = status == RoomStatus.OCCUPIED;
        if (occupied != (patientId != null)) {
            throw new IllegalArgumentException("Room " + id + ": patient must be set exactly when OCCUPIED");
        }
    }

    public static Room available(String id, String name) {
        return new Room(id, name, RoomStatus.AVAILABLE, null, null);
    }

    /** AVAILABLE -> OCCUPIED */
    public Room occupy(String patientId, String patientName) {
        require(RoomStatus.AVAILABLE, "accept a patient");
        return new Room(id, name, RoomStatus.OCCUPIED, patientId, patientName);
    }

    /** OCCUPIED -> CLEANING (treatment finished; room is NOT free yet) */
    public Room completeTreatment() {
        require(RoomStatus.OCCUPIED, "complete a treatment");
        return new Room(id, name, RoomStatus.CLEANING, null, null);
    }

    /** CLEANING -> AVAILABLE (explicit end of cleaning) */
    public Room finishCleaning() {
        require(RoomStatus.CLEANING, "finish cleaning");
        return new Room(id, name, RoomStatus.AVAILABLE, null, null);
    }

    /** Manual status change requested via API. Occupying/leaving OCCUPIED is only possible via assignment/completion. */
    public Room transitionTo(RoomStatus target) {
        return switch (target) {
            case CLEANING -> {
                if (status == RoomStatus.OCCUPIED) {
                    throw new InvalidStateTransitionException(
                            "Room " + id + " is OCCUPIED: complete the treatment first");
                }
                require(RoomStatus.AVAILABLE, "start cleaning");
                yield new Room(id, name, RoomStatus.CLEANING, null, null);
            }
            case AVAILABLE -> finishCleaning();
            case OCCUPIED -> throw new InvalidStateTransitionException(
                    "Room " + id + " can only become OCCUPIED by assigning a waiting patient");
        };
    }

    private void require(RoomStatus required, String action) {
        if (status != required) {
            throw new InvalidStateTransitionException(
                    "Room " + id + " is " + status + " and cannot " + action + " (requires " + required + ")");
        }
    }
}
