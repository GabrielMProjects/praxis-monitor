package com.praxismonitor.room.application;

import java.util.List;

import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;

import com.praxismonitor.common.concurrent.PracticeLock;
import com.praxismonitor.common.exception.InvalidStateTransitionException;
import com.praxismonitor.common.exception.NotFoundException;
import com.praxismonitor.patient.application.PatientService;
import com.praxismonitor.patient.domain.Patient;
import com.praxismonitor.realtime.event.PatientAssignedToRoomEvent;
import com.praxismonitor.realtime.event.RoomStatusChangedEvent;
import com.praxismonitor.room.domain.Room;
import com.praxismonitor.room.domain.RoomRepository;
import com.praxismonitor.room.domain.RoomStatus;
import com.praxismonitor.triage.application.TriageService;

/**
 * Room use cases incl. the cross-aggregate operations (assign, call next, complete).
 * All validation happens BEFORE the first write, so a rejected request never leaves half-applied state.
 */
@Service
public class RoomService {

    private final RoomRepository rooms;
    private final PatientService patients;
    private final TriageService triage;
    private final PracticeLock lock;
    private final ApplicationEventPublisher events;

    public RoomService(RoomRepository rooms, PatientService patients, TriageService triage, PracticeLock lock,
            ApplicationEventPublisher events) {
        this.rooms = rooms;
        this.patients = patients;
        this.triage = triage;
        this.lock = lock;
        this.events = events;
    }

    public List<Room> findAll() {
        return lock.withLock(rooms::findAll);
    }

    public Room get(String id) {
        return rooms.findById(id).orElseThrow(() -> new NotFoundException("Room", id));
    }

    /** Manual change: AVAILABLE -> CLEANING or CLEANING -> AVAILABLE. Everything else is 409. */
    public Room changeStatus(String roomId, RoomStatus target) {
        return lock.withLock(() -> {
            Room updated = rooms.save(get(roomId).transitionTo(target));
            events.publishEvent(new RoomStatusChangedEvent(updated));
            return updated;
        });
    }

    /** Assigns a specific WAITING patient to an AVAILABLE room. Returns the occupied room. */
    public Assignment assign(String roomId, String patientId) {
        return lock.withLock(() -> {
            Room room = get(roomId);
            Patient waiting = patients.get(patientId);
            Room occupied = room.occupy(patientId, waiting.name());   // validates room (409 if not AVAILABLE)
            Patient started = patients.startTreatment(patientId);      // validates patient (409 if not WAITING)
            rooms.save(occupied);
            events.publishEvent(new PatientAssignedToRoomEvent(started, occupied));
            events.publishEvent(new RoomStatusChangedEvent(occupied));
            return new Assignment(started, occupied);
        });
    }

    /** Calls the head of the triage queue into the given room. */
    public Assignment callNext(String roomId) {
        return lock.withLock(() -> {
            Room room = get(roomId);
            String nextId = triage.peekNext().orElseThrow(
                    () -> new InvalidStateTransitionException("The waiting queue is empty"));
            if (room.status() != RoomStatus.AVAILABLE) {
                throw new InvalidStateTransitionException("Room " + roomId + " is " + room.status() + ", not AVAILABLE");
            }
            return assign(roomId, nextId);
        });
    }

    /** OCCUPIED -> CLEANING and patient IN_TREATMENT -> COMPLETED. The room is freed only by finishing cleaning. */
    public Assignment completeTreatment(String roomId) {
        return lock.withLock(() -> {
            Room room = get(roomId);
            Room cleaning = room.completeTreatment();                  // validates OCCUPIED
            Patient done = patients.completeTreatment(room.patientId());
            rooms.save(cleaning);
            events.publishEvent(new RoomStatusChangedEvent(cleaning));
            return new Assignment(done, cleaning);
        });
    }

    public record Assignment(Patient patient, Room room) {
    }
}
