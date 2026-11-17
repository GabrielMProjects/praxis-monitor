package com.praxismonitor.common.exception;

import java.time.Instant;
import java.util.List;

/** Uniform JSON error body for all 4xx/5xx responses. */
public record ApiError(Instant timestamp, int status, String error, String message, List<String> details) {
}
