package com.praxismonitor.patient.application;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Instant;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.praxismonitor.PracticeFixture;
import com.praxismonitor.common.exception.InvalidStateTransitionException;
import com.praxismonitor.common.exception.NotFoundException;
import com.praxismonitor.patient.domain.Patient;
import com.praxismonitor.patient.domain.PatientStatus;
import com.praxismonitor.patient.domain.Urgency;
import com.praxismonitor.realtime.event.PatientAddedEvent;
import com.praxismonitor.realtime.event.PatientRemovedEvent;
import com.praxismonitor.realtime.event.PatientUrgencyChangedEvent;
import com.praxismonitor.realtime.event.QueueChangedEvent;

class PatientServiceTest {

    private PracticeFixture practice;
    private PatientService service;

    @BeforeEach
    void setUp() {
        practice = new PracticeFixture(2);
        service = practice.patients;
    }

    private List<String> queueNames() {
        return service.waitingQueue().stream().map(Patient::name).toList();
    }

    @Test
    void admitCreatesWaitingPatientWithBackendTimestampAndEvents() {
        Patient p = service.admit("  Demo One ", Urgency.HIGH);

        assertEquals("Demo One", p.name());
        assertEquals(PatientStatus.WAITING, p.status());
        assertEquals(Instant.parse("2026-01-01T10:00:00Z"), p.arrivedAt());
        assertEquals(1, practice.count(PatientAddedEvent.class));
        assertEquals(1, practice.count(QueueChangedEvent.class));
    }

    @Test
    void queueIsSortedByUrgencyThenArrival() {
        service.admit("low1", Urgency.LOW);
        service.admit("crit", Urgency.CRITICAL);
        service.admit("low2", Urgency.LOW);
        service.admit("high", Urgency.HIGH);

        assertEquals(List.of("crit", "high", "low1", "low2"), queueNames());
    }

    @Test
    void updateChangesUrgencyKeepsArrivalOrderAndPublishesEvents() {
        service.admit("a", Urgency.MEDIUM);
        Patient b = service.admit("b", Urgency.LOW);
        service.admit("c", Urgency.MEDIUM);

        service.update(b.id(), "b", Urgency.MEDIUM);

        assertEquals(List.of("a", "b", "c"), queueNames());
        assertEquals(1, practice.count(PatientUrgencyChangedEvent.class));
    }

    @Test
    void updateOnlyNameDoesNotPublishUrgencyEvent() {
        Patient a = service.admit("a", Urgency.MEDIUM);
        service.update(a.id(), "renamed", Urgency.MEDIUM);
        assertEquals(0, practice.count(PatientUrgencyChangedEvent.class));
        assertEquals("renamed", service.get(a.id()).name());
    }

    @Test
    void removeTakesPatientOutOfQueueAndRepository() {
        Patient a = service.admit("a", Urgency.HIGH);
        service.admit("b", Urgency.LOW);

        service.remove(a.id());

        assertEquals(List.of("b"), queueNames());
        assertThrows(NotFoundException.class, () -> service.get(a.id()));
        assertEquals(1, practice.count(PatientRemovedEvent.class));
    }

    @Test
    void unknownPatientIsNotFound() {
        assertThrows(NotFoundException.class, () -> service.get("nope"));
        assertThrows(NotFoundException.class, () -> service.remove("nope"));
        assertThrows(NotFoundException.class, () -> service.update("nope", "x", Urgency.LOW));
    }

    @Test
    void patientInTreatmentCannotBeRemovedOrEdited() {
        Patient a = service.admit("a", Urgency.HIGH);
        practice.rooms.assign("room-1", a.id());

        assertThrows(InvalidStateTransitionException.class, () -> service.remove(a.id()));
        assertThrows(InvalidStateTransitionException.class, () -> service.update(a.id(), "x", Urgency.LOW));
        assertTrue(service.waitingQueue().isEmpty());
    }

    @Test
    void completedPatientNeverReappearsInQueue() {
        Patient a = service.admit("a", Urgency.HIGH);
        practice.rooms.assign("room-1", a.id());
        practice.rooms.completeTreatment("room-1");

        assertEquals(PatientStatus.COMPLETED, service.get(a.id()).status());
        assertTrue(service.waitingQueue().isEmpty());
        assertThrows(InvalidStateTransitionException.class, () -> service.update(a.id(), "x", Urgency.LOW));
        service.remove(a.id()); // completed patients may be cleaned up
    }

    @Test
    void completedHistoryIsBoundedAndEvictsOldestFirst() {
        PracticeFixture small = new PracticeFixture(1, 2);
        List<String> ids = new java.util.ArrayList<>();
        for (int i = 1; i <= 5; i++) {
            Patient p = small.patients.admit("p" + i, Urgency.MEDIUM);
            ids.add(p.id());
            small.rooms.assign("room-1", p.id());
            small.rooms.completeTreatment("room-1");
            small.rooms.changeStatus("room-1", com.praxismonitor.room.domain.RoomStatus.AVAILABLE);
        }

        List<Patient> completed = small.patients.findAll(PatientStatus.COMPLETED);
        assertEquals(List.of("p4", "p5"), completed.stream().map(Patient::name).toList());
        assertThrows(NotFoundException.class, () -> small.patients.get(ids.get(0)));
        assertTrue(small.patients.waitingQueue().isEmpty());
    }

    @Test
    void historyLimitNeverTouchesWaitingOrInTreatmentPatients() {
        PracticeFixture none = new PracticeFixture(2, 0);
        Patient waiting = none.patients.admit("waiting", Urgency.LOW);
        Patient treating = none.patients.admit("treating", Urgency.HIGH);
        none.rooms.assign("room-1", treating.id());
        Patient done = none.patients.admit("done", Urgency.CRITICAL);
        none.rooms.assign("room-2", done.id());
        none.rooms.completeTreatment("room-2");

        assertEquals(0, none.patients.findAll(PatientStatus.COMPLETED).size());
        assertEquals(PatientStatus.WAITING, none.patients.get(waiting.id()).status());
        assertEquals(PatientStatus.IN_TREATMENT, none.patients.get(treating.id()).status());
    }

    @Test
    void statusFilterWorks() {
        Patient a = service.admit("a", Urgency.HIGH);
        service.admit("b", Urgency.LOW);
        practice.rooms.assign("room-1", a.id());

        assertEquals(1, service.findAll(PatientStatus.WAITING).size());
        assertEquals(1, service.findAll(PatientStatus.IN_TREATMENT).size());
        assertEquals(2, service.findAll(null).size());
    }

    @Test
    void concurrentAdmissionsKeepQueueConsistent() throws Exception {
        int threads = 8;
        int perThread = 50;
        var pool = java.util.concurrent.Executors.newFixedThreadPool(threads);
        var tasks = new java.util.ArrayList<java.util.concurrent.Future<?>>();
        for (int t = 0; t < threads; t++) {
            int tt = t;
            tasks.add(pool.submit(() -> {
                for (int i = 0; i < perThread; i++) {
                    service.admit("p" + tt + "-" + i, Urgency.values()[i % 4]);
                }
            }));
        }
        for (var f : tasks) {
            f.get();
        }
        pool.shutdown();

        List<Patient> queue = service.waitingQueue();
        assertEquals(threads * perThread, queue.size());
        assertEquals(queue.size(), queue.stream().map(Patient::id).distinct().count());
        for (int i = 1; i < queue.size(); i++) {
            assertTrue(queue.get(i - 1).urgency().priority() <= queue.get(i).urgency().priority());
        }
    }
}
