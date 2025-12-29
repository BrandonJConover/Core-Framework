package com.openrsc.server.infrastructure.serialization;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.charset.StandardCharsets;

/**
 * JSON serializer using Gson.
 * Useful for debugging, APIs, and human-readable data.
 */
public class JsonSerializer implements ISerializer {
    private static final Logger LOGGER = LogManager.getLogger(JsonSerializer.class);

    private final Gson gson;
    private final Gson prettyGson;
    private final boolean usePrettyPrint;

    public JsonSerializer() {
        this(false);
    }

    public JsonSerializer(boolean prettyPrint) {
        this.usePrettyPrint = prettyPrint;
        this.gson = new GsonBuilder()
            .setDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ")
            .disableHtmlEscaping()
            .create();
        this.prettyGson = new GsonBuilder()
            .setDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ")
            .disableHtmlEscaping()
            .setPrettyPrinting()
            .create();
    }

    @Override
    public SerializationFormat getFormat() {
        return SerializationFormat.JSON;
    }

    @Override
    public <T> byte[] serialize(T obj, Class<T> type) {
        Gson g = usePrettyPrint ? prettyGson : gson;
        String json = g.toJson(obj);
        return json.getBytes(StandardCharsets.UTF_8);
    }

    @Override
    public <T> T deserialize(byte[] data, Class<T> type) {
        String json = new String(data, StandardCharsets.UTF_8);
        return gson.fromJson(json, type);
    }

    @Override
    public boolean canSerialize(Class<?> type) {
        return true; // JSON can serialize any object
    }

    /**
     * Serializes to a JSON string.
     */
    public <T> String toJson(T obj) {
        return (usePrettyPrint ? prettyGson : gson).toJson(obj);
    }

    /**
     * Deserializes from a JSON string.
     */
    public <T> T fromJson(String json, Class<T> type) {
        return gson.fromJson(json, type);
    }

    /**
     * Gets the underlying Gson instance.
     */
    public Gson getGson() {
        return gson;
    }
}
