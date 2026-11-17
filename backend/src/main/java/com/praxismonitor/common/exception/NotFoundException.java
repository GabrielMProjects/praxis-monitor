package com.praxismonitor.common.exception;

/** A requested resource does not exist. Mapped to HTTP 404. */
public class NotFoundException extends RuntimeException {

    public NotFoundException(String resource, String id) {
        super(resource + " not found: " + id);
    }
}
