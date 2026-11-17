package com.praxismonitor.room.application;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.praxismonitor.PracticeFixture;
import com.praxismonitor.common.exception.InvalidStateTransitionException;
import com.praxismonitor.common.exception.NotFoundException;
import com.praxismonitor.patient.domain.Patient;
import com.praxismonitor.patient.domain.PatientStatus;
import com.praxismonitor.patient.domain.Urgency;
import com.praxismonitor.realtime.event.PatientAssignedToRoomEvent;
import com.praxismonitor.realtime.event.RoomStatusChangedEvent;
import com.praxismonitor.room.domain.RoomStatus;

class RoomServiceTest {

    private PracticeFixture practice;
    private RoomService rooms;

    @BeforeEach
    void setUp() {
        practice = new PracticeFixture(2);
        rooms = practice.rooms;
    }

    @Test
    void seedsConfiguredNumberOfAvailableRooms() {
        assertEquals(2, rooms.findAll().size());
        rooms.findAll().forEach(r -> assertEquals(RoomStatus.AVAILABLE, r.status()));
    }

    @Test
    void fullLifecycleWaitingToCompletedAndRoomCleaningCycle() {
        Patient p = practice.patients.admit("Demo", Urgency.HIGH);

        var assigned = rooms.assign("room-1", p.id());
        assertEquals(PatientStatus.IN_TREATMENT, assigned.patient().status());
        assertEquals(RoomStatus.OCCUPIED, assigned.room().status());
        assertEquals(p.id(), assigned.room().patientId());
        assertEquals(1, practice.count(PatientAssignedToRoomEvent.class));

        var done = rooms.completeTreatment("room-1");
        assertEquals(PatientStatus.COMPLETED, done.patient().status());
        assertEquals(RoomStatus.CLEANING, done.room().status()); // NOT automatically AVAILABLE
        assertNull(done.room().patientId());

        assertEquals(RoomStatus.AVAILABLE, rooms.changeStatus("room-1", RoomStatus.AVAILABLE).status());
        assertEquals(RoomStatus.AVAILABLE, rooms.get("room-1").status());
    }

    @Test
    void roomCannotHoldTwoPatients() {
        Patient a = practice.patients.admit("a", Urgency.HIGH);
        Patient b = practice.patients.admit("b", Urgency.HIGH);
        rooms.assign("room-1", a.id());

        assertThrows(InvalidStateTransitionException.class, () -> rooms.assign("room-1", b.id()));
        // rejected request left no half-applied state
        assertEquals(PatientStatus.WAITING, practice.patients.get(b.id()).status());
        assertEquals(1, practice.patients.waitingQueue().size());
        assertEquals(a.id(), rooms.get("room-1").patientId());
    }

    @Test
    void patientCannotBeInTwoRooms() {
        Patient a = practice.patients.admit("a", Urgency.HIGH);
        rooms.assign("room-1", a.id());

        assertThrows(InvalidStateTransitionException.class, () -> rooms.assign("room-2", a.id()));
        assertEquals(RoomStatus.AVAILABLE, rooms.get("room-2").status());
    }

    @Test
    void cannotAssignToCleaningRoom() {
        Patient a = practice.patients.admit("a", Urgency.HIGH);
        rooms.changeStatus("room-1", RoomStatus.CLEANING);
        assertThrows(InvalidStateTransitionException.class, () -> rooms.assign("room-1", a.id()));
        assertEquals(PatientStatus.WAITING, practice.patients.get(a.id()).status());
    }

    @Test
    void callNextTakesTheQueueHead() {
        practice.patients.admit("low", Urgency.LOW);
        Patient crit = practice.patients.admit("crit", Urgency.CRITICAL);

        var result = rooms.callNext("room-1");

        assertEquals(crit.id(), result.patient().id());
        assertEquals(1, practice.patients.waitingQueue().size());
    }

    @Test
    void callNextOnEmptyQueueOrBusyRoomIsRejected() {
        assertThrows(InvalidStateTransitionException.class, () -> rooms.callNext("room-1"));

        Patient a = practice.patients.admit("a", Urgency.LOW);
        practice.patients.admit("b", Urgency.LOW);
        rooms.assign("room-1", a.id());
        assertThrows(InvalidStateTransitionException.class, () -> rooms.callNext("room-1"));
        assertEquals(1, practice.patients.waitingQueue().size());
    }

    @Test
    void invalidManualTransitionsAreRejected() {
        assertThrows(InvalidStateTransitionException.class, () -> rooms.changeStatus("room-1", RoomStatus.OCCUPIED));
        assertThrows(InvalidStateTransitionException.class, () -> rooms.changeStatus("room-1", RoomStatus.AVAILABLE));

        Patient a = practice.patients.admit("a", Urgency.LOW);
        rooms.assign("room-1", a.id());
        assertThrows(InvalidStateTransitionException.class, () -> rooms.changeStatus("room-1", RoomStatus.CLEANING));
        assertThrows(InvalidStateTransitionException.class, () -> rooms.changeStatus("room-1", RoomStatus.AVAILABLE));
    }

    @Test
    void completeTreatmentRequiresOccupiedRoom() {
        assertThrows(InvalidStateTransitionException.class, () -> rooms.completeTreatment("room-1"));
    }

    @Test
    void manualCleaningCycleWorksAndPublishesEvents() {
        rooms.changeStatus("room-1", RoomStatus.CLEANING);
        rooms.changeStatus("room-1", RoomStatus.AVAILABLE);
        assertEquals(2, practice.count(RoomStatusChangedEvent.class));
    }

    @Test
    void concurrentAssignmentsToOneRoomLetExactlyOnePatientWin() throws Exception {
        int contenders = 16;
        java.util.List<String> ids = new java.util.ArrayList<>();
        for (int i = 0; i < contenders; i++) {
            ids.add(practice.patients.admit("p" + i, Urgency.MEDIUM).id());
        }
        var pool = java.util.concurrent.Executors.newFixedThreadPool(contenders);
        var start = new java.util.concurrent.CountDownLatch(1);
        var successes = new java.util.concurrent.atomic.AtomicInteger();
        var futures = new java.util.ArrayList<java.util.concurrent.Future<?>>();
        for (String id : ids) {
            futures.add(pool.submit(() -> {
                start.await();
                try {
                    rooms.assign("room-1", id);
                    successes.incrementAndGet();
                } catch (InvalidStateTransitionException expected) {
                    // lost the race
                }
                return null;
            }));
        }
        start.countDown();
        for (var f : futures) {
            f.get();
        }
        pool.shutdown();

        assertEquals(1, successes.get());
        assertEquals(contenders - 1, practice.patients.waitingQueue().size());
        assertEquals(1, practice.patients.findAll(PatientStatus.IN_TREATMENT).size());
        assertEquals(RoomStatus.OCCUPIED, rooms.get("room-1").status());
    }

    @Test
    void unknownRoomOrPatientIsNotFound() {
        assertThrows(NotFoundException.class, () -> rooms.get("nope"));
        assertThrows(NotFoundException.class, () -> rooms.assign("nope", "x"));
        assertThrows(NotFoundException.class, () -> rooms.assign("room-1", "ghost"));
        assertEquals(RoomStatus.AVAILABLE, rooms.get("room-1").status());
    }
}
