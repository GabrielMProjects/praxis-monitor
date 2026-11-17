package com.praxismonitor.patient.domain;

import java.util.List;
import java.util.Optional;

public interface PatientRepository {

    Patient save(Patient patient);

    Optional<Patient> findById(String id);

    /** All patients ordered by arrival time. */
    List<Patient> findAll();

    void deleteById(String id);
}
