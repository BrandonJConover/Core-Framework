package com.openrsc.server.net.api;

import com.fasterxml.jackson.core.StreamReadConstraints;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.netty.buffer.ByteBufUtil;
import io.netty.buffer.Unpooled;
import io.netty.handler.codec.http.DefaultFullHttpResponse;
import io.netty.handler.codec.http.FullHttpRequest;
import io.netty.handler.codec.http.FullHttpResponse;
import io.netty.handler.codec.http.HttpResponseStatus;

import java.io.IOException;
import java.util.Map;

import static io.netty.handler.codec.http.HttpHeaderNames.CONTENT_LENGTH;
import static io.netty.handler.codec.http.HttpHeaderNames.CONTENT_TYPE;
import static io.netty.handler.codec.http.HttpVersion.HTTP_1_1;

/**
 * Minimal Jackson <-> Netty FullHttpResponse bridge for the JSON REST API.
 *
 * The mapper is shared across all endpoints; it's thread-safe per Jackson docs
 * once configured. Endpoints call {@link #json(HttpResponseStatus, Object)} to
 * build a 200/4xx/5xx response, or {@link #error(HttpResponseStatus, String)}
 * for the canonical {"error":"...","status":N} shape.
 */
public final class JsonHandler {

    private static final ObjectMapper MAPPER = buildMapper();

    private JsonHandler() {}

    /**
     * Build the shared mapper with explicit stream-read constraints. Untrusted
     * request bodies are capped at 1MB by the HTTP aggregator, but without
     * nesting/number/string limits a small deeply-nested payload can still
     * exhaust the worker thread's stack (CVE-2025-52999 class). Bound them.
     */
    private static ObjectMapper buildMapper() {
        ObjectMapper mapper = new ObjectMapper();
        mapper.getFactory().setStreamReadConstraints(
            StreamReadConstraints.builder()
                .maxNestingDepth(200)
                .maxStringLength(1_000_000)
                .maxNumberLength(1_000)
                .build());
        return mapper;
    }

    /** Serialise {@code body} as JSON and wrap in a Netty response with the given status. */
    public static FullHttpResponse json(HttpResponseStatus status, Object body) {
        try {
            byte[] bytes = MAPPER.writeValueAsBytes(body);
            FullHttpResponse resp = new DefaultFullHttpResponse(
                HTTP_1_1, status, Unpooled.wrappedBuffer(bytes));
            resp.headers().set(CONTENT_TYPE, "application/json; charset=utf-8");
            resp.headers().setInt(CONTENT_LENGTH, bytes.length);
            return resp;
        } catch (Exception e) {
            // Fall back to a plain text error if even json encoding broke.
            byte[] msg = ("{\"error\":\"json encode failed\",\"status\":500}").getBytes();
            FullHttpResponse resp = new DefaultFullHttpResponse(
                HTTP_1_1, HttpResponseStatus.INTERNAL_SERVER_ERROR, Unpooled.wrappedBuffer(msg));
            resp.headers().set(CONTENT_TYPE, "application/json; charset=utf-8");
            resp.headers().setInt(CONTENT_LENGTH, msg.length);
            return resp;
        }
    }

    /** Canonical error shape: {"error":"...","status":N}. */
    public static FullHttpResponse error(HttpResponseStatus status, String message) {
        return json(status, Map.of("error", message, "status", status.code()));
    }

    /** Parse the request body into {@code type}. Throws on malformed JSON. */
    public static <T> T parse(FullHttpRequest request, Class<T> type) throws IOException {
        byte[] body = ByteBufUtil.getBytes(request.content());
        return MAPPER.readValue(body, type);
    }
}
