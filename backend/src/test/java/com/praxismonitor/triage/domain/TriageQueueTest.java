package com.praxismonitor.triage.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.ArrayList;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.Random;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

import com.praxismonitor.patient.domain.Urgency;

class TriageQueueTest {

    private final TriageQueue queue = new TriageQueue();

    private List<String> drain() {
        List<String> ids = new ArrayList<>();
        while (!queue.isEmpty()) {
            ids.add(queue.poll().orElseThrow().patientId());
        }
        return ids;
    }

    @Test
    void servesAllFourUrgenciesInPriorityOrder() {
        queue.enqueue("low", Urgency.LOW);
        queue.enqueue("medium", Urgency.MEDIUM);
        queue.enqueue("critical", Urgency.CRITICAL);
        queue.enqueue("high", Urgency.HIGH);

        assertEquals(List.of("critical", "high", "medium", "low"), drain());
    }

    @Test
    void urgencyPrioritiesAreExactlyOneToFour() {
        assertEquals(1, Urgency.CRITICAL.priority());
        assertEquals(2, Urgency.HIGH.priority());
        assertEquals(3, Urgency.MEDIUM.priority());
        assertEquals(4, Urgency.LOW.priority());
    }

    @ParameterizedTest
    @EnumSource(Urgency.class)
    void isFifoWithinSameUrgency(Urgency urgency) {
        // 50 entries is well beyond PriorityQueue's unstable tie behaviour for tiny heaps
        List<String> expected = new ArrayList<>();
        for (int i = 0; i < 50; i++) {
            queue.enqueue("p" + i, urgency);
            expected.add("p" + i);
        }
        assertEquals(expected, drain());
    }

    @Test
    void mixedUrgenciesKeepFifoInsideEachLevel() {
        Random random = new Random(42);
        Urgency[] all = Urgency.values();
        List<QueueEntry> admitted = new ArrayList<>();
        for (int i = 0; i < 200; i++) {
            Urgency u = all[random.nextInt(all.length)];
            long seq = queue.enqueue("p" + i, u);
            admitted.add(new QueueEntry("p" + i, u, seq));
        }
        List<String> expected = admitted.stream().sorted(QueueEntry.ORDER).map(QueueEntry::patientId).toList();
        assertEquals(expected, drain());
    }

    @Test
    void emptyQueueBehavesSafely() {
        assertTrue(queue.isEmpty());
        assertEquals(0, queue.size());
        assertTrue(queue.peek().isEmpty());
        assertTrue(queue.poll().isEmpty());
        assertTrue(queue.snapshot().isEmpty());
        assertFalse(queue.remove("nobody"));
        assertFalse(queue.contains("nobody"));
    }

    @Test
    void rejectsInvalidInput() {
        assertThrows(IllegalArgumentException.class, () -> queue.enqueue(null, Urgency.LOW));
        assertThrows(IllegalArgumentException.class, () -> queue.enqueue(" ", Urgency.LOW));
        assertThrows(IllegalArgumentException.class, () -> queue.enqueue("a", null));
    }

    @Test
    void rejectsDuplicateAndUnknownOperations() {
        queue.enqueue("a", Urgency.LOW);
        assertThrows(IllegalStateException.class, () -> queue.enqueue("a", Urgency.HIGH));
        assertThrows(NoSuchElementException.class, () -> queue.changeUrgency("ghost", Urgency.HIGH));
        assertEquals(1, queue.size());
    }

    @Test
    void removalLeavesNoStaleEntries() {
        queue.enqueue("a", Urgency.HIGH);
        queue.enqueue("b", Urgency.HIGH);
        queue.enqueue("c", Urgency.HIGH);

        assertTrue(queue.remove("b"));
        assertFalse(queue.remove("b"));
        assertFalse(queue.contains("b"));
        assertEquals(2, queue.size());
        assertEquals(2, queue.snapshot().size());
        assertEquals(List.of("a", "c"), drain());
    }

    @Test
    void removingTheHeadPromotesTheNext() {
        queue.enqueue("a", Urgency.CRITICAL);
        queue.enqueue("b", Urgency.LOW);
        queue.remove("a");
        assertEquals("b", queue.peek().orElseThrow().patientId());
    }

    @Test
    void urgencyChangeReordersButKeepsOriginalSequence() {
        long first = queue.enqueue("early", Urgency.LOW);
        queue.enqueue("late", Urgency.MEDIUM);
        queue.enqueue("later", Urgency.MEDIUM);

        queue.changeUrgency("early", Urgency.MEDIUM);

        // "early" arrived first, so it precedes the other MEDIUM patients (sequence preserved)
        assertEquals(List.of("early", "late", "later"), queue.snapshot().stream().map(QueueEntry::patientId).toList());
        assertEquals(first, queue.snapshot().get(0).sequence());
        assertEquals(3, queue.size());
    }

    @Test
    void escalationMovesPatientToFront() {
        queue.enqueue("a", Urgency.MEDIUM);
        queue.enqueue("b", Urgency.MEDIUM);
        queue.changeUrgency("b", Urgency.CRITICAL);
        assertEquals(List.of("b", "a"), drain());
    }

    @Test
    void unchangedUrgencyIsNoOp() {
        queue.enqueue("a", Urgency.HIGH);
        queue.changeUrgency("a", Urgency.HIGH);
        assertEquals(1, queue.snapshot().size());
    }

    @Test
    void readmissionGetsNewSequence() {
        long first = queue.enqueue("a", Urgency.LOW);
        queue.enqueue("b", Urgency.LOW);
        queue.poll(); // a leaves (treated)
        long again = queue.enqueue("a", Urgency.LOW); // genuine new admission
        assertTrue(again > first);
        assertEquals(List.of("b", "a"), drain());
    }

    @Test
    void snapshotIsSortedAndDetached() {
        queue.enqueue("l", Urgency.LOW);
        queue.enqueue("c", Urgency.CRITICAL);
        queue.enqueue("m", Urgency.MEDIUM);
        queue.enqueue("h", Urgency.HIGH);

        List<QueueEntry> snap = queue.snapshot();
        assertEquals(List.of("c", "h", "m", "l"), snap.stream().map(QueueEntry::patientId).toList());

        queue.poll();
        assertEquals(4, snap.size(), "earlier snapshot must not change");
        assertThrows(UnsupportedOperationException.class, () -> snap.remove(0));
    }

    @Test
    void heapAndIndexStayConsistentUnderRandomOperations() {
        Random random = new Random(7);
        Urgency[] all = Urgency.values();
        int counter = 0;
        for (int i = 0; i < 2000; i++) {
            switch (random.nextInt(4)) {
                case 0 -> queue.enqueue("p" + counter++, all[random.nextInt(4)]);
                case 1 -> queue.poll();
                case 2 -> queue.remove("p" + random.nextInt(Math.max(counter, 1)));
                default -> {
                    String id = "p" + random.nextInt(Math.max(counter, 1));
                    if (queue.contains(id)) {
                        queue.changeUrgency(id, all[random.nextInt(4)]);
                    }
                }
            }
            List<QueueEntry> snap = queue.snapshot();
            assertEquals(queue.size(), snap.size());
            assertEquals(snap.stream().map(QueueEntry::patientId).distinct().count(), snap.size());
            for (int k = 1; k < snap.size(); k++) {
                assertTrue(QueueEntry.ORDER.compare(snap.get(k - 1), snap.get(k)) < 0);
            }
        }
    }
}
