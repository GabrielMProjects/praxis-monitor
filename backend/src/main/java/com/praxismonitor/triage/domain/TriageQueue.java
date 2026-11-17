package com.praxismonitor.triage.domain;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.Optional;
import java.util.PriorityQueue;

import com.praxismonitor.patient.domain.Urgency;

/**
 * Priority queue for waiting patients - pure Java, no framework dependency, NOT thread-safe
 * (callers synchronise; see PracticeLock).
 *
 * <h2>Data structures</h2>
 * <ul>
 *   <li>{@code PriorityQueue<QueueEntry>} (binary min-heap) ordered by {@link QueueEntry#ORDER}.</li>
 *   <li>{@code HashMap<patientId, QueueEntry>} index = single source of truth for membership.
 *       Heap and index always hold exactly the same entries (eager removal, no stale entries).</li>
 *   <li>{@code long nextSequence}: monotonic counter, tie-breaker for FIFO at equal urgency.</li>
 * </ul>
 *
 * <h2>Complexity (n = waiting patients)</h2>
 * <pre>
 * enqueue          O(log n)   heap offer + map put
 * peek             O(1)
 * poll             O(log n)   heap poll + map remove
 * contains         O(1)       index lookup
 * remove(id)       O(n)       PriorityQueue.remove(Object) must search the array, then O(log n) sift
 * changeUrgency    O(n)       remove + offer (sequence is kept)
 * snapshot         O(n log n) copy + sort; PriorityQueue.iterator() is NOT sorted and is never used for display
 * memory           O(n)       heap array + hash map (+ O(n) per snapshot)
 * </pre>
 * Updates/removals are O(n), not O(log n); for a practice waiting room (n in the tens) this is
 * irrelevant, and an indexed heap or lazy deletion would be the next step (see ADR-001).
 */
public class TriageQueue {

    private final PriorityQueue<QueueEntry> heap = new PriorityQueue<>(QueueEntry.ORDER);
    private final Map<String, QueueEntry> index = new HashMap<>();
    private long nextSequence = 1;

    /** Admits a patient and returns the assigned arrival sequence. */
    public long enqueue(String patientId, Urgency urgency) {
        requireId(patientId);
        if (urgency == null) {
            throw new IllegalArgumentException("urgency must not be null");
        }
        if (index.containsKey(patientId)) {
            throw new IllegalStateException("Patient already queued: " + patientId);
        }
        QueueEntry entry = new QueueEntry(patientId, urgency, nextSequence++);
        heap.offer(entry);
        index.put(patientId, entry);
        return entry.sequence();
    }

    /** Changes urgency but keeps the original arrival sequence. No-op if unchanged. */
    public void changeUrgency(String patientId, Urgency newUrgency) {
        requireId(patientId);
        if (newUrgency == null) {
            throw new IllegalArgumentException("urgency must not be null");
        }
        QueueEntry old = index.get(patientId);
        if (old == null) {
            throw new NoSuchElementException("Patient not in queue: " + patientId);
        }
        if (old.urgency() == newUrgency) {
            return;
        }
        heap.remove(old);
        QueueEntry updated = new QueueEntry(patientId, newUrgency, old.sequence());
        heap.offer(updated);
        index.put(patientId, updated);
    }

    /** @return true if the patient was queued and has been removed */
    public boolean remove(String patientId) {
        QueueEntry entry = index.remove(patientId);
        if (entry == null) {
            return false;
        }
        heap.remove(entry);
        return true;
    }

    public Optional<QueueEntry> peek() {
        return Optional.ofNullable(heap.peek());
    }

    /** Removes and returns the next patient; empty if the queue is empty. */
    public Optional<QueueEntry> poll() {
        QueueEntry entry = heap.poll();
        if (entry != null) {
            index.remove(entry.patientId());
        }
        return Optional.ofNullable(entry);
    }

    public boolean contains(String patientId) {
        return index.containsKey(patientId);
    }

    public int size() {
        return index.size();
    }

    public boolean isEmpty() {
        return index.isEmpty();
    }

    /** Sorted copy (next patient first). Safe to hand out; later queue changes do not affect it. */
    public List<QueueEntry> snapshot() {
        List<QueueEntry> copy = new ArrayList<>(heap);
        copy.sort(QueueEntry.ORDER);
        return List.copyOf(copy);
    }

    private static void requireId(String patientId) {
        if (patientId == null || patientId.isBlank()) {
            throw new IllegalArgumentException("patientId must not be blank");
        }
    }
}
