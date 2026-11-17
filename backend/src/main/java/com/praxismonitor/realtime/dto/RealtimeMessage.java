package com.praxismonitor.realtime.dto;

import java.time.Instant;

/**
 * Envelope of every WebSocket message: {@code {"type": "...", "occurredAt": "...", "payload": {...}}}.
 * Payload shapes are documented in docs/architecture.md (they reuse the REST DTO JSON shapes).
 */
public record RealtimeMessage<T>(EventType type, Instant occurredAt, T payload) {
}
