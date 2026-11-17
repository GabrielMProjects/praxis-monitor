package com.praxismonitor.patient.api.dto;

import com.praxismonitor.patient.domain.Urgency;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/** Body for POST (create) and PUT (update) of a patient. */
public record PatientRequest(
        @NotBlank(message = "must not be blank") @Size(max = 80, message = "must be at most 80 characters") String name,
        @NotNull(message = "must not be null") Urgency urgency) {
}
