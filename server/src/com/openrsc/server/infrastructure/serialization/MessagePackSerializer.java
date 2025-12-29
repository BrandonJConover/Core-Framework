package com.openrsc.server.infrastructure.serialization;

import org.msgpack.core.*;
import org.msgpack.value.Value;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.io.*;
import java.nio.ByteBuffer;
import java.util.*;

/**
 * MessagePack serialization adapter for game packets.
 * Provides compact binary serialization with cross-platform support.
 */
public class MessagePackSerializer {
    private static final Logger LOGGER = LogManager.getLogger(MessagePackSerializer.class);

    private static final byte MSGPACK_MAGIC = (byte) 0xC1;
    private static final byte PROTOCOL_VERSION = 1;

    /**
     * Serializes an object to MessagePack format.
     */
    public byte[] serialize(Object obj) throws IOException {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        try (MessagePacker packer = MessagePack.newDefaultPacker(baos)) {
            packValue(packer, obj);
        }
        return baos.toByteArray();
    }

    /**
     * Deserializes MessagePack data to a map.
     */
    public Map<String, Object> deserialize(byte[] data) throws IOException {
        try (MessageUnpacker unpacker = MessagePack.newDefaultUnpacker(data)) {
            Value value = unpacker.unpackValue();
            return valueToMap(value);
        }
    }

    /**
     * Serializes a game packet with header.
     */
    public byte[] serializePacket(int opcode, byte[] payload) throws IOException {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        try (MessagePacker packer = MessagePack.newDefaultPacker(baos)) {
            packer.packMapHeader(2);
            packer.packString("o"); // opcode
            packer.packInt(opcode);
            packer.packString("p"); // payload
            packer.packBinaryHeader(payload.length);
            packer.writePayload(payload);
        }

        byte[] msgpackData = baos.toByteArray();

        // Add protocol header
        ByteBuffer buffer = ByteBuffer.allocate(6 + msgpackData.length);
        buffer.put(MSGPACK_MAGIC);
        buffer.put(PROTOCOL_VERSION);
        buffer.putInt(msgpackData.length);
        buffer.put(msgpackData);

        return buffer.array();
    }

    /**
     * Deserializes a game packet from wire format.
     */
    public GamePacket deserializePacket(byte[] data) throws IOException {
        if (data.length < 6) {
            throw new IOException("Packet too short");
        }

        ByteBuffer buffer = ByteBuffer.wrap(data);
        byte magic = buffer.get();
        byte version = buffer.get();
        int length = buffer.getInt();

        if (magic != MSGPACK_MAGIC) {
            throw new IOException("Invalid magic byte");
        }

        if (version != PROTOCOL_VERSION) {
            LOGGER.warn("Protocol version mismatch: expected {}, got {}", PROTOCOL_VERSION, version);
        }

        byte[] msgpackData = new byte[length];
        buffer.get(msgpackData);

        try (MessageUnpacker unpacker = MessagePack.newDefaultUnpacker(msgpackData)) {
            int mapSize = unpacker.unpackMapHeader();
            int opcode = 0;
            byte[] payload = new byte[0];

            for (int i = 0; i < mapSize; i++) {
                String key = unpacker.unpackString();
                if ("o".equals(key)) {
                    opcode = unpacker.unpackInt();
                } else if ("p".equals(key)) {
                    int payloadLength = unpacker.unpackBinaryHeader();
                    payload = new byte[payloadLength];
                    unpacker.readPayload(payload);
                }
            }

            return new GamePacket(opcode, payload);
        }
    }

    /**
     * Checks if data is MessagePack format.
     */
    public static boolean isMessagePackFormat(byte[] data) {
        return data.length > 0 && data[0] == MSGPACK_MAGIC;
    }

    private void packValue(MessagePacker packer, Object obj) throws IOException {
        if (obj == null) {
            packer.packNil();
        } else if (obj instanceof String s) {
            packer.packString(s);
        } else if (obj instanceof Integer i) {
            packer.packInt(i);
        } else if (obj instanceof Long l) {
            packer.packLong(l);
        } else if (obj instanceof Short s) {
            packer.packShort(s);
        } else if (obj instanceof Byte b) {
            packer.packByte(b);
        } else if (obj instanceof Boolean b) {
            packer.packBoolean(b);
        } else if (obj instanceof Float f) {
            packer.packFloat(f);
        } else if (obj instanceof Double d) {
            packer.packDouble(d);
        } else if (obj instanceof byte[] bytes) {
            packer.packBinaryHeader(bytes.length);
            packer.writePayload(bytes);
        } else if (obj instanceof List<?> list) {
            packer.packArrayHeader(list.size());
            for (Object item : list) {
                packValue(packer, item);
            }
        } else if (obj instanceof Map<?, ?> map) {
            packer.packMapHeader(map.size());
            for (Map.Entry<?, ?> entry : map.entrySet()) {
                packValue(packer, entry.getKey());
                packValue(packer, entry.getValue());
            }
        } else {
            // Fallback to string representation
            packer.packString(obj.toString());
        }
    }

    private Map<String, Object> valueToMap(Value value) {
        if (!value.isMapValue()) {
            throw new IllegalArgumentException("Expected map value");
        }

        Map<String, Object> result = new LinkedHashMap<>();
        for (Map.Entry<Value, Value> entry : value.asMapValue().map().entrySet()) {
            String key = entry.getKey().asStringValue().asString();
            Object val = valueToObject(entry.getValue());
            result.put(key, val);
        }
        return result;
    }

    private Object valueToObject(Value value) {
        if (value.isNilValue()) {
            return null;
        } else if (value.isBooleanValue()) {
            return value.asBooleanValue().getBoolean();
        } else if (value.isIntegerValue()) {
            return value.asIntegerValue().toLong();
        } else if (value.isFloatValue()) {
            return value.asFloatValue().toDouble();
        } else if (value.isStringValue()) {
            return value.asStringValue().asString();
        } else if (value.isBinaryValue()) {
            return value.asBinaryValue().asByteArray();
        } else if (value.isArrayValue()) {
            List<Object> list = new ArrayList<>();
            for (Value item : value.asArrayValue()) {
                list.add(valueToObject(item));
            }
            return list;
        } else if (value.isMapValue()) {
            return valueToMap(value);
        }
        return value.toString();
    }

    /**
     * Game packet record.
     */
    public record GamePacket(int opcode, byte[] payload) {}
}
