package com.praxismonitor.patient.domain;

/** WAITING -> IN_TREATMENT -> COMPLETED. No other transitions are allowed. */
public enum PatientStatus {
    WAITING,
    IN_TREATMENT,
    COMPLETED
}
