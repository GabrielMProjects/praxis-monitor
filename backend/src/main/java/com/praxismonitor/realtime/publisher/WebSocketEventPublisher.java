package com.praxismonitor.realtime.publisher;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.stream.IntStream;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.event.EventListener;
import org.springframework.messaging.simp.SimpMessageSendingOperations;
import org.springframework.stereotype.Component;

import com.praxismonitor.patient.api.dto.PatientResponse;
import com.praxismonitor.realtime.dto.EventType;
import com.praxismonitor.realtime.dto.Payloads;
import com.praxismonitor.realtime.dto.RealtimeMessage;
import com.praxismonitor.realtime.event.DomainEvent;
import com.praxismonitor.realtime.event.PatientAddedEvent;
import com.praxismonitor.realtime.event.PatientAssignedToRoomEvent;
import com.praxismonitor.realtime.event.PatientRemovedEvent;
import com.praxismonitor.realtime.event.PatientUrgencyChangedEvent;
import com.praxismonitor.realtime.event.QueueChangedEvent;
import com.praxismonitor.realtime.event.RoomStatusChangedEvent;
import com.praxismonitor.room.api.dto.RoomResponse;

/** Translates domain events into STOMP messages. The only class that knows about WebSocket messaging. */
@Component
public class WebSocketEventPublisher {

    public static final String QUEUE_TOPIC = "/topic/queue";
    public static final String ROOMS_TOPIC = "/topic/rooms";

    private static final Logger log = LoggerFactory.getLogger(WebSocketEventPublisher.class);

    private final SimpMessageSendingOperations messaging;
    private final Clock clock;

    public WebSocketEventPublisher(SimpMessageSendingOperations messaging, Clock clock) {
        this.messaging = messaging;
        this.clock = clock;
    }

    @EventListener
    public void on(DomainEvent event) {
        switch (event) {
            case PatientAddedEvent e -> send(QUEUE_TOPIC, EventType.PATIENT_ADDED, PatientResponse.from(e.patient(), null));
            case PatientRemovedEvent e -> send(QUEUE_TOPIC, EventType.PATIENT_REMOVED, new Payloads.PatientRemoved(e.patientId()));
            case PatientUrgencyChangedEvent e -> send(QUEUE_TOPIC, EventType.PATIENT_URGENCY_CHANGED,
                    new Payloads.UrgencyChanged(PatientResponse.from(e.patient(), null), e.previousUrgency()));
            case QueueChangedEvent e -> send(QUEUE_TOPIC, EventType.QUEUE_CHANGED,
                    new Payloads.QueueChanged(withPositions(e)));
            case RoomStatusChangedEvent e -> send(ROOMS_TOPIC, EventType.ROOM_STATUS_CHANGED, RoomResponse.from(e.room()));
            case PatientAssignedToRoomEvent e -> send(ROOMS_TOPIC, EventType.PATIENT_ASSIGNED,
                    new Payloads.PatientAssigned(PatientResponse.from(e.patient(), null), RoomResponse.from(e.room())));
        }
    }

    private static List<PatientResponse> withPositions(QueueChangedEvent e) {
        return IntStream.range(0, e.queue().size())
                .mapToObj(i -> PatientResponse.from(e.queue().get(i), i + 1))
                .toList();
    }

    private <T> void send(String topic, EventType type, T payload) {
        try {
            messaging.convertAndSend(topic, new RealtimeMessage<>(type, Instant.now(clock), payload));
        } catch (RuntimeException ex) {
            // A broken broadcast must never roll back or fail the business operation.
            log.warn("Could not publish {} to {}", type, topic, ex);
        }
    }
}
