package com.praxismonitor.config;

import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import com.praxismonitor.patient.application.PatientService;
import com.praxismonitor.patient.domain.Urgency;

/** Seeds purely synthetic patients when praxis.demo.seed-patients=true (dev profile). */
@Component
@ConditionalOnProperty(name = "praxis.demo.seed-patients", havingValue = "true")
class DemoDataSeeder implements ApplicationRunner {

    private final PatientService patients;

    DemoDataSeeder(PatientService patients) {
        this.patients = patients;
    }

    @Override
    public void run(ApplicationArguments args) {
        patients.admit("Demo Patient A", Urgency.MEDIUM);
        patients.admit("Demo Patient B", Urgency.LOW);
        patients.admit("Demo Patient C", Urgency.HIGH);
    }
}
