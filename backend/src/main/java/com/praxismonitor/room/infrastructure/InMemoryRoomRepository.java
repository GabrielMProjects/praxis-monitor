package com.praxismonitor.room.infrastructure;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Repository;

import com.praxismonitor.room.domain.Room;
import com.praxismonitor.room.domain.RoomRepository;

/** In-memory rooms, seeded as "Raum 1..N" (ids room-1..room-N), N from {@code praxis.rooms.count}. */
@Repository
public class InMemoryRoomRepository implements RoomRepository {

    private final Map<String, Room> store = new LinkedHashMap<>();

    public InMemoryRoomRepository(@Value("${praxis.rooms.count:4}") int roomCount) {
        for (int i = 1; i <= roomCount; i++) {
            store.put("room-" + i, Room.available("room-" + i, "Raum " + i));
        }
    }

    @Override
    public synchronized Room save(Room room) {
        store.put(room.id(), room);
        return room;
    }

    @Override
    public synchronized Optional<Room> findById(String id) {
        return Optional.ofNullable(store.get(id));
    }

    @Override
    public synchronized List<Room> findAll() {
        return new ArrayList<>(store.values());
    }
}
