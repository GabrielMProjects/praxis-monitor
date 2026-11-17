package com.praxismonitor.room.api;

import java.util.List;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.praxismonitor.room.api.dto.AssignPatientRequest;
import com.praxismonitor.room.api.dto.AssignmentResponse;
import com.praxismonitor.room.api.dto.ChangeRoomStatusRequest;
import com.praxismonitor.room.api.dto.RoomResponse;
import com.praxismonitor.room.application.RoomService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/rooms")
public class RoomController {

    private final RoomService service;

    public RoomController(RoomService service) {
        this.service = service;
    }

    @GetMapping
    List<RoomResponse> list() {
        return service.findAll().stream().map(RoomResponse::from).toList();
    }

    @GetMapping("/{id}")
    RoomResponse get(@PathVariable String id) {
        return RoomResponse.from(service.get(id));
    }

    /** Manual: AVAILABLE -> CLEANING, CLEANING -> AVAILABLE. */
    @PutMapping("/{id}/status")
    RoomResponse changeStatus(@PathVariable String id, @Valid @RequestBody ChangeRoomStatusRequest request) {
        return RoomResponse.from(service.changeStatus(id, request.status()));
    }

    @PostMapping("/{id}/assign")
    AssignmentResponse assign(@PathVariable String id, @Valid @RequestBody AssignPatientRequest request) {
        return AssignmentResponse.from(service.assign(id, request.patientId()));
    }

    /** Calls the next patient of the triage queue into this room. */
    @PostMapping("/{id}/call-next")
    AssignmentResponse callNext(@PathVariable String id) {
        return AssignmentResponse.from(service.callNext(id));
    }

    /** Finishes the treatment: patient COMPLETED, room OCCUPIED -> CLEANING. */
    @PostMapping("/{id}/complete-treatment")
    AssignmentResponse completeTreatment(@PathVariable String id) {
        return AssignmentResponse.from(service.completeTreatment(id));
    }
}
