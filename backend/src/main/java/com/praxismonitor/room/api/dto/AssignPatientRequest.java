package com.praxismonitor.room.api.dto;

import jakarta.validation.constraints.NotBlank;

public record AssignPatientRequest(@NotBlank(message = "must not be blank") String patientId) {
}
