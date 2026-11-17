package com.praxismonitor.common.concurrent;

import java.util.concurrent.locks.ReentrantLock;
import java.util.function.Supplier;

import org.springframework.stereotype.Component;

/**
 * One coarse, reentrant lock guarding all practice state (patients, rooms, triage queue).
 * Operations like "assign patient to room" touch three structures and must be atomic;
 * for an in-memory demo a single lock is the simplest correct choice (see ADR-004).
 */
@Component
public class PracticeLock {

    private final ReentrantLock lock = new ReentrantLock();

    public <T> T withLock(Supplier<T> action) {
        lock.lock();
        try {
            return action.get();
        } finally {
            lock.unlock();
        }
    }

    public void withLock(Runnable action) {
        withLock(() -> {
            action.run();
            return null;
        });
    }
}
