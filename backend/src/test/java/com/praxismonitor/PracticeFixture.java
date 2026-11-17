package com.praxismonitor;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;

import com.praxismonitor.common.concurrent.PracticeLock;
import com.praxismonitor.patient.application.PatientService;
import com.praxismonitor.patient.infrastructure.InMemoryPatientRepository;
import com.praxismonitor.realtime.event.DomainEvent;
import com.praxismonitor.room.application.RoomService;
import com.praxismonitor.room.infrastructure.InMemoryRoomRepository;
import com.praxismonitor.triage.application.TriageService;

/** Plain-Java wiring of all services (no Spring) with a controllable clock and a capturing event sink. */
public class PracticeFixture {

    public final List<DomainEvent> events = new ArrayList<>();
    public final PatientService patients;
    public final RoomService rooms;
    public final TriageService triage;

    public PracticeFixture(int roomCount) {
        this(roomCount, 100);
    }

    public PracticeFixture(int roomCount, int maxCompletedHistory) {
        PracticeLock lock = new PracticeLock();
        Clock clock = Clock.fixed(Instant.parse("2026-01-01T10:00:00Z"), ZoneOffset.UTC);
        triage = new TriageService(lock);
        patients = new PatientService(new InMemoryPatientRepository(), triage, lock, clock,
                e -> events.add((DomainEvent) e), maxCompletedHistory);
        rooms = new RoomService(new InMemoryRoomRepository(roomCount), patients, triage, lock,
                e -> events.add((DomainEvent) e));
    }

    public <T extends DomainEvent> long count(Class<T> type) {
        return events.stream().filter(type::isInstance).count();
    }
}
