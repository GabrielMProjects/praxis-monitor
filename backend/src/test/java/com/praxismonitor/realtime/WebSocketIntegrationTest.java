package com.praxismonitor.realtime;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.lang.reflect.Type;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.List;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.messaging.converter.StringMessageConverter;
import org.springframework.messaging.simp.stomp.StompFrameHandler;
import org.springframework.messaging.simp.stomp.StompHeaders;
import org.springframework.messaging.simp.stomp.StompSession;
import org.springframework.messaging.simp.stomp.StompSessionHandlerAdapter;
import org.springframework.web.socket.WebSocketHttpHeaders;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.messaging.WebSocketStompClient;

/** Real server on a random port, real STOMP client over WebSocket, real REST calls triggering events. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class WebSocketIntegrationTest {

    @LocalServerPort
    private int port;

    private final HttpClient http = HttpClient.newHttpClient();

    private String post(String path, String json) throws Exception {
        HttpRequest req = HttpRequest.newBuilder(URI.create("http://localhost:" + port + path))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(json == null ? "" : json)).build();
        return http.send(req, HttpResponse.BodyHandlers.ofString()).body();
    }

    private StompSession connect(String origin) throws Exception {
        WebSocketStompClient client = new WebSocketStompClient(new StandardWebSocketClient());
        // Server sends application/json; read it as raw text so the test can inspect the wire format.
        client.setMessageConverter(new StringMessageConverter() {
            {
                addSupportedMimeTypes(org.springframework.util.MimeTypeUtils.APPLICATION_JSON);
            }
        });
        WebSocketHttpHeaders headers = new WebSocketHttpHeaders();
        headers.setOrigin(origin);
        return client.connectAsync("ws://localhost:" + port + "/ws", headers, new StompHeaders(),
                new StompSessionHandlerAdapter() { }).get(5, TimeUnit.SECONDS);
    }

    private BlockingQueue<String> subscribe(StompSession session, String topic) {
        BlockingQueue<String> received = new LinkedBlockingQueue<>();
        session.subscribe(topic, new StompFrameHandler() {
            @Override
            public Type getPayloadType(StompHeaders headers) {
                return String.class;
            }

            @Override
            public void handleFrame(StompHeaders headers, Object payload) {
                received.add((String) payload);
            }
        });
        return received;
    }

    private List<String> drainUntil(BlockingQueue<String> q, int expectedAtLeast) throws Exception {
        List<String> out = new java.util.ArrayList<>();
        long deadline = System.currentTimeMillis() + 5000;
        while (out.size() < expectedAtLeast && System.currentTimeMillis() < deadline) {
            String m = q.poll(200, TimeUnit.MILLISECONDS);
            if (m != null) {
                out.add(m);
            }
        }
        return out;
    }

    @Test
    void queueAndRoomChangesAreBroadcast() throws Exception {
        StompSession session = connect("http://localhost:5555");
        BlockingQueue<String> queue = subscribe(session, "/topic/queue");
        BlockingQueue<String> rooms = subscribe(session, "/topic/rooms");
        Thread.sleep(300); // let subscriptions register on the broker

        String created = post("/api/patients", "{\"name\":\"WS Demo\",\"urgency\":\"HIGH\"}");
        assertNotNull(created);
        assertTrue(created.contains("\"id\""), "REST create failed: " + created);

        List<String> queueMessages = drainUntil(queue, 2);
        assertTrue(queueMessages.stream().anyMatch(m -> m.contains("\"type\":\"PATIENT_ADDED\"")), queueMessages.toString());
        String queueChanged = queueMessages.stream().filter(m -> m.contains("\"type\":\"QUEUE_CHANGED\"")).findFirst().orElse("");
        assertTrue(queueChanged.contains("\"name\":\"WS Demo\"") && queueChanged.contains("\"queuePosition\":1"), queueChanged);
        assertTrue(queueChanged.contains("\"occurredAt\":\"20"), "ISO timestamp expected: " + queueChanged);

        post("/api/rooms/room-1/call-next", null);
        List<String> roomMessages = drainUntil(rooms, 2);
        assertTrue(roomMessages.stream().anyMatch(m -> m.contains("\"type\":\"PATIENT_ASSIGNED\"")), roomMessages.toString());
        assertTrue(roomMessages.stream().anyMatch(m -> m.contains("\"type\":\"ROOM_STATUS_CHANGED\"") && m.contains("OCCUPIED")),
                roomMessages.toString());

        post("/api/rooms/room-1/complete-treatment", null);
        List<String> after = drainUntil(rooms, 1);
        assertEquals(1, after.size());
        assertTrue(after.get(0).contains("CLEANING"));

        session.disconnect();
    }

    private String put(String path, String json) throws Exception {
        HttpRequest req = HttpRequest.newBuilder(URI.create("http://localhost:" + port + path))
                .header("Content-Type", "application/json")
                .PUT(HttpRequest.BodyPublishers.ofString(json)).build();
        return http.send(req, HttpResponse.BodyHandlers.ofString()).body();
    }

    private int delete(String path) throws Exception {
        HttpRequest req = HttpRequest.newBuilder(URI.create("http://localhost:" + port + path)).DELETE().build();
        return http.send(req, HttpResponse.BodyHandlers.ofString()).statusCode();
    }

    @Test
    void urgencyChangeAndRemovalAreBroadcastOverRealConnection() throws Exception {
        StompSession session = connect("http://localhost:5555");
        BlockingQueue<String> queue = subscribe(session, "/topic/queue");
        Thread.sleep(300);

        String created = post("/api/patients", "{\"name\":\"WS Change\",\"urgency\":\"LOW\"}");
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("\"id\":\"([^\"]+)\"").matcher(created);
        assertTrue(m.find(), created);
        String id = m.group(1);
        drainUntil(queue, 2); // PATIENT_ADDED + QUEUE_CHANGED

        put("/api/patients/" + id, "{\"name\":\"WS Change\",\"urgency\":\"CRITICAL\"}");
        List<String> changed = drainUntil(queue, 2);
        String urgency = changed.stream().filter(s -> s.contains("\"type\":\"PATIENT_URGENCY_CHANGED\"")).findFirst().orElse("");
        assertTrue(urgency.contains("\"previousUrgency\":\"LOW\"") && urgency.contains("\"urgency\":\"CRITICAL\"")
                && urgency.contains("\"id\":\"" + id + "\""), changed.toString());
        assertTrue(changed.stream().anyMatch(s -> s.contains("\"type\":\"QUEUE_CHANGED\"")), changed.toString());

        assertEquals(204, delete("/api/patients/" + id));
        List<String> removed = drainUntil(queue, 2);
        String removedMsg = removed.stream().filter(s -> s.contains("\"type\":\"PATIENT_REMOVED\"")).findFirst().orElse("");
        assertTrue(removedMsg.contains("\"patientId\":\"" + id + "\""), removed.toString());
        String lastQueue = removed.stream().filter(s -> s.contains("\"type\":\"QUEUE_CHANGED\"")).findFirst().orElse("");
        assertTrue(lastQueue.contains("\"patients\":[]") && !lastQueue.contains(id), lastQueue);

        session.disconnect();
    }

    @Test
    void foreignOriginIsRejectedAtHandshake() {
        org.junit.jupiter.api.Assertions.assertThrows(Exception.class, () -> connect("https://evil.example"));
    }
}
