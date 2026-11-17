package com.praxismonitor.patient.application;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;

import com.praxismonitor.common.concurrent.PracticeLock;
import com.praxismonitor.common.exception.InvalidStateTransitionException;
import com.praxismonitor.common.exception.NotFoundException;
import com.praxismonitor.patient.domain.Patient;
import com.praxismonitor.patient.domain.PatientRepository;
import com.praxismonitor.patient.domain.PatientStatus;
import com.praxismonitor.patient.domain.Urgency;
import com.praxismonitor.realtime.event.PatientAddedEvent;
import com.praxismonitor.realtime.event.PatientRemovedEvent;
import com.praxismonitor.realtime.event.PatientUrgencyChangedEvent;
import com.praxismonitor.realtime.event.QueueChangedEvent;
import com.praxismonitor.triage.application.TriageService;

/**
 * Patient use cases. Every mutation runs under the shared {@link PracticeLock}, keeps repository and
 * triage queue consistent, and publishes domain events (never talks to WebSocket directly).
 */
@Service
public class PatientService {

    private final PatientRepository patients;
    private final TriageService triage;
    private final PracticeLock lock;
    private final Clock clock;
    private final ApplicationEventPublisher events;
    private final int maxCompletedHistory;

    /**
     * @param maxCompletedHistory how many COMPLETED patients are kept in memory (oldest are evicted first), so a
     *                            long-running demo cannot grow without bound
     */
    public PatientService(PatientRepository patients, TriageService triage, PracticeLock lock, Clock clock,
            ApplicationEventPublisher events,
            @Value("${praxis.history.max-completed-patients:100}") int maxCompletedHistory) {
        this.patients = patients;
        this.triage = triage;
        this.lock = lock;
        this.clock = clock;
        this.events = events;
        this.maxCompletedHistory = Math.max(0, maxCompletedHistory);
    }

    public Patient admit(String name, Urgency urgency) {
        return lock.withLock(() -> {
            Patient patient = Patient.admit(UUID.randomUUID().toString(), name, urgency, Instant.now(clock));
            patients.save(patient);
            triage.enqueue(patient.id(), urgency);
            events.publishEvent(new PatientAddedEvent(patient));
            publishQueue();
            return patient;
        });
    }

    public Patient get(String id) {
        return patients.findById(id).orElseThrow(() -> new NotFoundException("Patient", id));
    }

    public List<Patient> findAll(PatientStatus statusFilter) {
        return lock.withLock(() -> patients.findAll().stream()
                .filter(p -> statusFilter == null || p.status() == statusFilter)
                .toList());
    }

    /** Waiting patients, next patient first (taken from the sorted triage snapshot). */
    public List<Patient> waitingQueue() {
        return lock.withLock(() -> triage.orderedIds().stream().map(this::get).toList());
    }

    public Patient update(String id, String name, Urgency urgency) {
        return lock.withLock(() -> {
            Patient current = get(id);
            Patient updated = current.update(name, urgency); // throws 409 unless WAITING
            patients.save(updated);
            if (current.urgency() != urgency) {
                triage.changeUrgency(id, urgency);
                events.publishEvent(new PatientUrgencyChangedEvent(updated, current.urgency()));
            }
            publishQueue();
            return updated;
        });
    }

    /** Removes a WAITING (leaves the queue) or COMPLETED patient. Patients in treatment cannot be removed. */
    public void remove(String id) {
        lock.withLock(() -> {
            Patient current = get(id);
            if (current.status() == PatientStatus.IN_TREATMENT) {
                throw new InvalidStateTransitionException(
                        "Patient " + id + " is IN_TREATMENT: complete the treatment before removing");
            }
            boolean wasWaiting = triage.remove(id);
            patients.deleteById(id);
            events.publishEvent(new PatientRemovedEvent(id));
            if (wasWaiting) {
                publishQueue();
            }
        });
    }

    /** WAITING -> IN_TREATMENT and leaves the queue. Called by RoomService inside its own lock scope. */
    public Patient startTreatment(String id) {
        return lock.withLock(() -> {
            Patient started = get(id).startTreatment();
            triage.remove(id);
            patients.save(started);
            publishQueue();
            return started;
        });
    }

    /** IN_TREATMENT -> COMPLETED. */
    public Patient completeTreatment(String id) {
        return lock.withLock(() -> {
            Patient completed = patients.save(get(id).completeTreatment());
            evictOldestCompleted();
            return completed;
        });
    }

    /** Keeps at most {@code maxCompletedHistory} COMPLETED patients (oldest arrival first out). O(n) per completion. */
    private void evictOldestCompleted() {
        List<Patient> completed = patients.findAll().stream()
                .filter(p -> p.status() == PatientStatus.COMPLETED)
                .toList(); // findAll() is ordered by arrival time
        for (int i = 0; i < completed.size() - maxCompletedHistory; i++) {
            patients.deleteById(completed.get(i).id());
        }
    }

    private void publishQueue() {
        events.publishEvent(new QueueChangedEvent(waitingQueue()));
    }
}
