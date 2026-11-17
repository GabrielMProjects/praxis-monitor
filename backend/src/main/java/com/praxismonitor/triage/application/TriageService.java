package com.praxismonitor.triage.application;

import java.util.List;
import java.util.Optional;

import org.springframework.stereotype.Service;

import com.praxismonitor.common.concurrent.PracticeLock;
import com.praxismonitor.patient.domain.Urgency;
import com.praxismonitor.triage.domain.QueueEntry;
import com.praxismonitor.triage.domain.TriageQueue;

/** Thin, lock-guarded Spring wrapper around the framework-free {@link TriageQueue}. */
@Service
public class TriageService {

    private final TriageQueue queue = new TriageQueue();
    private final PracticeLock lock;

    public TriageService(PracticeLock lock) {
        this.lock = lock;
    }

    public void enqueue(String patientId, Urgency urgency) {
        lock.withLock(() -> queue.enqueue(patientId, urgency));
    }

    public void changeUrgency(String patientId, Urgency urgency) {
        lock.withLock(() -> queue.changeUrgency(patientId, urgency));
    }

    public boolean remove(String patientId) {
        return lock.withLock(() -> queue.remove(patientId));
    }

    public Optional<String> peekNext() {
        return lock.withLock(() -> queue.peek().map(QueueEntry::patientId));
    }

    /** Patient ids, next patient first. */
    public List<String> orderedIds() {
        return lock.withLock(() -> queue.snapshot().stream().map(QueueEntry::patientId).toList());
    }
}
