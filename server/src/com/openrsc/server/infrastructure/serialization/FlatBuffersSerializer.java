package com.openrsc.server.infrastructure.serialization;

import com.google.flatbuffers.FlatBufferBuilder;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.ByteBuffer;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.BiFunction;
import java.util.function.Function;

/**
 * FlatBuffers serializer for zero-copy high-performance serialization.
 * Requires pre-generated FlatBuffer schema classes.
 */
public class FlatBuffersSerializer implements ISerializer {
    private static final Logger LOGGER = LogManager.getLogger(FlatBuffersSerializer.class);

    // Registry for type-specific serializers and deserializers
    private final Map<Class<?>, BiFunction<FlatBufferBuilder, Object, Integer>> serializers = new ConcurrentHashMap<>();
    private final Map<Class<?>, Function<ByteBuffer, Object>> deserializers = new ConcurrentHashMap<>();

    @Override
    public SerializationFormat getFormat() {
        return SerializationFormat.FLAT_BUFFERS;
    }

    /**
     * Registers a FlatBuffer serializer for a type.
     * @param type The class type
     * @param serializer Function that takes (builder, object) and returns the offset
     */
    public <T> void registerSerializer(Class<T> type, BiFunction<FlatBufferBuilder, T, Integer> serializer) {
        serializers.put(type, (builder, obj) -> serializer.apply(builder, type.cast(obj)));
        LOGGER.debug("Registered FlatBuffer serializer for {}", type.getSimpleName());
    }

    /**
     * Registers a FlatBuffer deserializer for a type.
     * @param type The class type
     * @param deserializer Function that takes ByteBuffer and returns the object
     */
    public <T> void registerDeserializer(Class<T> type, Function<ByteBuffer, T> deserializer) {
        deserializers.put(type, buf -> deserializer.apply(buf));
        LOGGER.debug("Registered FlatBuffer deserializer for {}", type.getSimpleName());
    }

    @Override
    public <T> byte[] serialize(T obj, Class<T> type) {
        var serializer = serializers.get(type);
        if (serializer == null) {
            throw new IllegalArgumentException("No FlatBuffer serializer registered for " + type.getSimpleName());
        }

        FlatBufferBuilder builder = new FlatBufferBuilder(256);
        int offset = serializer.apply(builder, obj);
        builder.finish(offset);

        ByteBuffer buffer = builder.dataBuffer();
        byte[] result = new byte[buffer.remaining()];
        buffer.get(result);
        return result;
    }

    @Override
    @SuppressWarnings("unchecked")
    public <T> T deserialize(byte[] data, Class<T> type) {
        var deserializer = deserializers.get(type);
        if (deserializer == null) {
            throw new IllegalArgumentException("No FlatBuffer deserializer registered for " + type.getSimpleName());
        }

        ByteBuffer buffer = ByteBuffer.wrap(data);
        return (T) deserializer.apply(buffer);
    }

    @Override
    public boolean canSerialize(Class<?> type) {
        return serializers.containsKey(type);
    }

    /**
     * Creates a new FlatBufferBuilder with default capacity.
     */
    public FlatBufferBuilder createBuilder() {
        return new FlatBufferBuilder(256);
    }

    /**
     * Creates a new FlatBufferBuilder with specified capacity.
     */
    public FlatBufferBuilder createBuilder(int initialCapacity) {
        return new FlatBufferBuilder(initialCapacity);
    }
}
