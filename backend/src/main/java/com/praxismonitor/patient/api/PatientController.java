package com.praxismonitor.patient.api;

import java.net.URI;
import java.util.List;
import java.util.Map;
import java.util.stream.IntStream;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.praxismonitor.patient.api.dto.PatientRequest;
import com.praxismonitor.patient.api.dto.PatientResponse;
import com.praxismonitor.patient.application.PatientService;
import com.praxismonitor.patient.domain.Patient;
import com.praxismonitor.patient.domain.PatientStatus;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api")
public class PatientController {

    private final PatientService service;

    public PatientController(PatientService service) {
        this.service = service;
    }

    @PostMapping("/patients")
    ResponseEntity<PatientResponse> create(@Valid @RequestBody PatientRequest request) {
        Patient created = service.admit(request.name(), request.urgency());
        return ResponseEntity.created(URI.create("/api/patients/" + created.id()))
                .body(withPosition(created));
    }

    @GetMapping("/patients")
    List<PatientResponse> list(@RequestParam(required = false) PatientStatus status) {
        Map<String, Integer> positions = positions();
        return service.findAll(status).stream()
                .map(p -> PatientResponse.from(p, positions.get(p.id())))
                .toList();
    }

    @GetMapping("/patients/{id}")
    PatientResponse get(@PathVariable String id) {
        return withPosition(service.get(id));
    }

    @PutMapping("/patients/{id}")
    PatientResponse update(@PathVariable String id, @Valid @RequestBody PatientRequest request) {
        return withPosition(service.update(id, request.name(), request.urgency()));
    }

    @DeleteMapping("/patients/{id}")
    ResponseEntity<Void> remove(@PathVariable String id) {
        service.remove(id);
        return ResponseEntity.noContent().build();
    }

    /** Waiting queue, correctly sorted (priority, then arrival sequence). */
    @GetMapping("/queue")
    List<PatientResponse> queue() {
        List<Patient> queue = service.waitingQueue();
        return IntStream.range(0, queue.size())
                .mapToObj(i -> PatientResponse.from(queue.get(i), i + 1))
                .toList();
    }

    private PatientResponse withPosition(Patient patient) {
        return PatientResponse.from(patient, positions().get(patient.id()));
    }

    private Map<String, Integer> positions() {
        List<Patient> queue = service.waitingQueue();
        return IntStream.range(0, queue.size()).boxed()
                .collect(java.util.stream.Collectors.toMap(i -> queue.get(i).id(), i -> i + 1));
    }
}
