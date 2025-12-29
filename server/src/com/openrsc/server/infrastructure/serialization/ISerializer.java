package com.openrsc.server.infrastructure.serialization;

/**
 * Unified serialization interface supporting multiple formats.
 */
public interface ISerializer {

    /**
     * Gets the serialization format this serializer handles.
     */
    SerializationFormat getFormat();

    /**
     * Serializes an object to bytes.
     */
    <T> byte[] serialize(T obj, Class<T> type);

    /**
     * Deserializes bytes to an object.
     */
    <T> T deserialize(byte[] data, Class<T> type);

    /**
     * Checks if this serializer can handle the given type.
     */
    boolean canSerialize(Class<?> type);
}
