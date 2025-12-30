package com.openrsc.server.infrastructure.serialization;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.EnumMap;
import java.util.Map;
import java.util.Optional;

/**
 * Factory for creating and managing serializers.
 * Provides a unified interface for accessing different serialization formats.
 */
public class SerializerFactory {
    private static final Logger LOGGER = LogManager.getLogger(SerializerFactory.class);

    private final Map<SerializationFormat, ISerializer> serializers = new EnumMap<>(SerializationFormat.class);
    private SerializationFormat defaultFormat = SerializationFormat.MESSAGE_PACK;

    public SerializerFactory() {
        // Register default serializers
        register(new MessagePackSerializer());
        register(new JsonSerializer());
        register(new FlatBuffersSerializer());

        LOGGER.info("SerializerFactory initialized with {} formats", serializers.size());
    }

    /**
     * Registers a serializer.
     */
    public void register(ISerializer serializer) {
        serializers.put(serializer.getFormat(), serializer);
        LOGGER.debug("Registered serializer for format: {}", serializer.getFormat());
    }

    /**
     * Gets a serializer by format.
     */
    public Optional<ISerializer> get(SerializationFormat format) {
        return Optional.ofNullable(serializers.get(format));
    }

    /**
     * Gets a serializer by format, throwing if not found.
     */
    public ISerializer getRequired(SerializationFormat format) {
        return get(format).orElseThrow(() ->
            new IllegalArgumentException("No serializer registered for format: " + format));
    }

    /**
     * Gets the default serializer.
     */
    public ISerializer getDefault() {
        return getRequired(defaultFormat);
    }

    /**
     * Sets the default serialization format.
     */
    public void setDefaultFormat(SerializationFormat format) {
        if (!serializers.containsKey(format)) {
            throw new IllegalArgumentException("Cannot set default to unregistered format: " + format);
        }
        this.defaultFormat = format;
        LOGGER.info("Default serialization format set to: {}", format);
    }

    /**
     * Gets the default serialization format.
     */
    public SerializationFormat getDefaultFormat() {
        return defaultFormat;
    }

    /**
     * Serializes an object using the default format.
     */
    public <T> byte[] serialize(T obj, Class<T> type) {
        return getDefault().serialize(obj, type);
    }

    /**
     * Deserializes bytes using the default format.
     */
    public <T> T deserialize(byte[] data, Class<T> type) {
        return getDefault().deserialize(data, type);
    }

    /**
     * Serializes an object using the specified format.
     */
    public <T> byte[] serialize(T obj, Class<T> type, SerializationFormat format) {
        return getRequired(format).serialize(obj, type);
    }

    /**
     * Deserializes bytes using the specified format.
     */
    public <T> T deserialize(byte[] data, Class<T> type, SerializationFormat format) {
        return getRequired(format).deserialize(data, type);
    }

    /**
     * Gets the FlatBuffers serializer for schema registration.
     */
    public FlatBuffersSerializer getFlatBuffers() {
        return (FlatBuffersSerializer) getRequired(SerializationFormat.FLAT_BUFFERS);
    }

    /**
     * Gets the JSON serializer for string operations.
     */
    public JsonSerializer getJson() {
        return (JsonSerializer) getRequired(SerializationFormat.JSON);
    }

    /**
     * Gets the MessagePack serializer.
     */
    public MessagePackSerializer getMessagePack() {
        return (MessagePackSerializer) getRequired(SerializationFormat.MESSAGE_PACK);
    }
}
