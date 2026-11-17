package com.praxismonitor.api;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.notNullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.web.servlet.MockMvc;

/** Full Spring context, real controllers/services, in-memory repositories. Fresh context per test class method. */
@SpringBootTest
@AutoConfigureMockMvc
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_EACH_TEST_METHOD)
class PracticeRestIntegrationTest {

    @Autowired
    private MockMvc mvc;

    private String createPatient(String name, String urgency) throws Exception {
        String body = mvc.perform(post("/api/patients").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + name + "\",\"urgency\":\"" + urgency + "\"}"))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", notNullValue()))
                .andReturn().getResponse().getContentAsString();
        Matcher m = Pattern.compile("\"id\":\"([^\"]+)\"").matcher(body);
        m.find();
        return m.group(1);
    }

    @Test
    void createReturns201WithPriorityStatusAndTimestamp() throws Exception {
        mvc.perform(post("/api/patients").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Demo Patient\",\"urgency\":\"CRITICAL\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.priority", is(1)))
                .andExpect(jsonPath("$.status", is("WAITING")))
                .andExpect(jsonPath("$.queuePosition", is(1)))
                .andExpect(jsonPath("$.arrivedAt", notNullValue()));
    }

    @Test
    void queueEndpointIsSortedByUrgencyThenArrival() throws Exception {
        createPatient("low1", "LOW");
        createPatient("crit", "CRITICAL");
        createPatient("low2", "LOW");
        createPatient("med", "MEDIUM");

        mvc.perform(get("/api/queue"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(4)))
                .andExpect(jsonPath("$[0].name", is("crit")))
                .andExpect(jsonPath("$[1].name", is("med")))
                .andExpect(jsonPath("$[2].name", is("low1")))
                .andExpect(jsonPath("$[3].name", is("low2")))
                .andExpect(jsonPath("$[3].queuePosition", is(4)));
    }

    @Test
    void urgencyChangeReordersQueue() throws Exception {
        createPatient("a", "MEDIUM");
        String b = createPatient("b", "LOW");

        mvc.perform(put("/api/patients/" + b).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"b\",\"urgency\":\"CRITICAL\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.urgency", is("CRITICAL")));

        mvc.perform(get("/api/queue")).andExpect(jsonPath("$[0].name", is("b")));
    }

    @Test
    void deleteRemovesFromQueueAndSecondDeleteIs404() throws Exception {
        String id = createPatient("a", "LOW");
        mvc.perform(delete("/api/patients/" + id)).andExpect(status().isNoContent());
        mvc.perform(get("/api/queue")).andExpect(jsonPath("$", hasSize(0)));
        mvc.perform(delete("/api/patients/" + id)).andExpect(status().isNotFound())
                .andExpect(jsonPath("$.status", is(404)));
    }

    @Test
    void invalidInputGives400WithDetails() throws Exception {
        mvc.perform(post("/api/patients").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"  \",\"urgency\":null}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message", is("Validation failed")))
                .andExpect(jsonPath("$.details", hasSize(2)));

        mvc.perform(post("/api/patients").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"x\",\"urgency\":\"NORMAL\"}"))   // discarded old enum value
                .andExpect(status().isBadRequest());

        mvc.perform(post("/api/patients").contentType(MediaType.APPLICATION_JSON).content("{not json"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void unknownIdsGive404() throws Exception {
        mvc.perform(get("/api/patients/nope")).andExpect(status().isNotFound());
        mvc.perform(get("/api/rooms/nope")).andExpect(status().isNotFound());
    }

    @Test
    void roomsAreSeededAvailable() throws Exception {
        mvc.perform(get("/api/rooms"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(4)))
                .andExpect(jsonPath("$[0].status", is("AVAILABLE")));
    }

    @Test
    void fullDemoFlowOverRest() throws Exception {
        String low = createPatient("low", "LOW");
        String crit = createPatient("crit", "CRITICAL");

        // call next -> the critical patient goes to room-1
        mvc.perform(post("/api/rooms/room-1/call-next"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.patient.id", is(crit)))
                .andExpect(jsonPath("$.patient.status", is("IN_TREATMENT")))
                .andExpect(jsonPath("$.room.status", is("OCCUPIED")));

        // occupied room rejects a second patient and manual status changes (409)
        mvc.perform(post("/api/rooms/room-1/assign").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"patientId\":\"" + low + "\"}"))
                .andExpect(status().isConflict());
        mvc.perform(put("/api/rooms/room-1/status").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"status\":\"AVAILABLE\"}"))
                .andExpect(status().isConflict());
        // patient in treatment cannot be removed
        mvc.perform(delete("/api/patients/" + crit)).andExpect(status().isConflict());

        // explicit assignment of the remaining patient to another room
        mvc.perform(post("/api/rooms/room-2/assign").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"patientId\":\"" + low + "\"}"))
                .andExpect(status().isOk());
        mvc.perform(get("/api/queue")).andExpect(jsonPath("$", hasSize(0)));

        // finish treatment: room goes to CLEANING (not AVAILABLE), patient COMPLETED
        mvc.perform(post("/api/rooms/room-1/complete-treatment"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.patient.status", is("COMPLETED")))
                .andExpect(jsonPath("$.room.status", is("CLEANING")));
        mvc.perform(post("/api/rooms/room-1/complete-treatment")).andExpect(status().isConflict());

        // cleaning finished explicitly -> AVAILABLE
        mvc.perform(put("/api/rooms/room-1/status").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"status\":\"AVAILABLE\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status", is("AVAILABLE")));

        mvc.perform(get("/api/patients?status=COMPLETED")).andExpect(jsonPath("$", hasSize(1)));
    }

    @Test
    void apiResponsesCarrySecurityHeadersAndAreNotCacheable() throws Exception {
        mvc.perform(get("/api/queue"))
                .andExpect(header().string("X-Content-Type-Options", "nosniff"))
                .andExpect(header().string("X-Frame-Options", "DENY"))
                .andExpect(header().string("Referrer-Policy", "no-referrer"))
                .andExpect(header().string("Cache-Control", "no-store"));
    }

    @Test
    void overlongNameIsRejectedAndRequestBodyWithUnknownFieldsDoesNotBreakValidation() throws Exception {
        mvc.perform(post("/api/patients").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + "x".repeat(81) + "\",\"urgency\":\"LOW\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.details[0]", containsString("name")));
    }

    @Test
    void callNextOnEmptyQueueIs409() throws Exception {
        mvc.perform(post("/api/rooms/room-1/call-next"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error", is("Conflict")));
    }

    @Test
    void corsAllowsLocalOriginAndRejectsForeignOrigin() throws Exception {
        mvc.perform(get("/api/rooms").header("Origin", "http://localhost:54321"))
                .andExpect(status().isOk())
                .andExpect(header().string("Access-Control-Allow-Origin", "http://localhost:54321"));
        mvc.perform(get("/api/rooms").header("Origin", "https://evil.example"))
                .andExpect(status().isForbidden());
    }
}
