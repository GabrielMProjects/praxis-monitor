package com.praxismonitor.patient.infrastructure;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.springframework.stereotype.Repository;

import com.praxismonitor.patient.domain.Patient;
import com.praxismonitor.patient.domain.PatientRepository;

@Repository
public class InMemoryPatientRepository implements PatientRepository {

    private final Map<String, Patient> store = new LinkedHashMap<>();

    @Override
    public synchronized Patient save(Patient patient) {
        store.put(patient.id(), patient);
        return patient;
    }

    @Override
    public synchronized Optional<Patient> findById(String id) {
        return Optional.ofNullable(store.get(id));
    }

    @Override
    public synchronized List<Patient> findAll() {
        List<Patient> all = new ArrayList<>(store.values());
        all.sort(Comparator.comparing(Patient::arrivedAt));
        return all;
    }

    @Override
    public synchronized void deleteById(String id) {
        store.remove(id);
    }
}
