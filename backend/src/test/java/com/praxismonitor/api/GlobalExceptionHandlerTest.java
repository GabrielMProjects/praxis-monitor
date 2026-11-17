package com.praxismonitor.api;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.not;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Reproducible test of the central error handling, in particular the HTTP 500 path: a test-only controller
 * throws an unexpected exception, the real {@code GlobalExceptionHandler} must answer with a generic 500 body
 * and must not leak the internal message.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(GlobalExceptionHandlerTest.FailingController.class)
class GlobalExceptionHandlerTest {

    @RestController
    @TestConfiguration
    static class FailingController {
        @GetMapping("/test-only/boom")
        String boom() {
            throw new IllegalStateException("secret internal detail that must never reach the client");
        }
    }

    @Autowired
    private MockMvc mvc;

    @Test
    void unexpectedExceptionBecomes500WithGenericMessageAndNoLeak() throws Exception {
        mvc.perform(get("/test-only/boom"))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.status", is(500)))
                .andExpect(jsonPath("$.error", is("Internal Server Error")))
                .andExpect(jsonPath("$.message", is("Unexpected server error")))
                .andExpect(jsonPath("$.message", not(containsString("secret"))))
                .andExpect(jsonPath("$.details", hasSize(0)))
                .andExpect(jsonPath("$.timestamp").exists());
    }

    @Test
    void framework4xxErrorsKeepTheirStatusInsteadOfBecoming500() throws Exception {
        mvc.perform(post("/api/rooms")).andExpect(status().isMethodNotAllowed());
        mvc.perform(get("/api/does-not-exist")).andExpect(status().isNotFound());
        mvc.perform(post("/api/patients").contentType(MediaType.TEXT_PLAIN).content("x"))
                .andExpect(status().isUnsupportedMediaType());
    }
}
