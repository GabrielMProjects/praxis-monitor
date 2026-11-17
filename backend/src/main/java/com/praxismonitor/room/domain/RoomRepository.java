package com.praxismonitor.room.domain;

import java.util.List;
import java.util.Optional;

public interface RoomRepository {

    Room save(Room room);

    Optional<Room> findById(String id);

    /** All rooms in stable (creation) order. */
    List<Room> findAll();
}
