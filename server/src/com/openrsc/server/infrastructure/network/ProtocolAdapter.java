package com.openrsc.server.infrastructure.network;

import com.openrsc.server.infrastructure.serialization.MessagePackSerializer;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.Optional;

/**
 * Protocol adapter for dual-protocol support.
 * Handles both MessagePack and RSC binary formats for backwards compatibility.
 */
public class ProtocolAdapter {
    private static final Logger LOGGER = LogManager.getLogger(ProtocolAdapter.class);

    public static final byte MSGPACK_MAGIC = (byte) 0xC1;
    public static final byte MSGPACK_VERSION = 1;

    private final MessagePackSerializer messagePackSerializer;

    public ProtocolAdapter() {
        this.messagePackSerializer = new MessagePackSerializer();
    }

    /**
     * Detects the protocol format from initial bytes.
     */
    public ProtocolFormat detectProtocol(byte[] initialBytes) {
        if (initialBytes == null || initialBytes.length == 0) {
            return ProtocolFormat.RSC_BINARY;
        }

        if (initialBytes[0] == MSGPACK_MAGIC) {
            return ProtocolFormat.MESSAGE_PACK;
        }

        return ProtocolFormat.RSC_BINARY;
    }

    /**
     * Creates an encoder for the specified protocol.
     */
    public IPacketEncoder createEncoder(ProtocolFormat format) {
        return switch (format) {
            case MESSAGE_PACK -> new MessagePackEncoder(messagePackSerializer);
            case RSC_BINARY -> new RscBinaryEncoder();
        };
    }

    /**
     * Creates a decoder for the specified protocol.
     */
    public IPacketDecoder createDecoder(ProtocolFormat format) {
        return switch (format) {
            case MESSAGE_PACK -> new MessagePackDecoder(messagePackSerializer);
            case RSC_BINARY -> new RscBinaryDecoder();
        };
    }

    /**
     * Protocol format enum.
     */
    public enum ProtocolFormat {
        RSC_BINARY,
        MESSAGE_PACK
    }

    /**
     * Packet encoder interface.
     */
    public interface IPacketEncoder {
        ProtocolFormat getFormat();
        byte[] encode(Packet packet);
        int encode(Packet packet, byte[] buffer);
    }

    /**
     * Packet decoder interface.
     */
    public interface IPacketDecoder {
        ProtocolFormat getFormat();
        Optional<Packet> decode(byte[] data);
    }

    /**
     * Generic packet structure.
     */
    public record Packet(int opcode, byte[] payload) {
        public static Packet of(int opcode, byte[] payload) {
            return new Packet(opcode, payload);
        }
    }

    /**
     * RSC binary format encoder.
     * Format: [length:2 bytes BE][opcode:1 byte][payload:variable]
     */
    public static class RscBinaryEncoder implements IPacketEncoder {
        @Override
        public ProtocolFormat getFormat() {
            return ProtocolFormat.RSC_BINARY;
        }

        @Override
        public byte[] encode(Packet packet) {
            int totalLength = 2 + 1 + packet.payload().length;
            byte[] result = new byte[totalLength];

            int packetLength = 1 + packet.payload().length;
            result[0] = (byte) ((packetLength >> 8) & 0xFF);
            result[1] = (byte) (packetLength & 0xFF);
            result[2] = (byte) packet.opcode();
            System.arraycopy(packet.payload(), 0, result, 3, packet.payload().length);

            return result;
        }

        @Override
        public int encode(Packet packet, byte[] buffer) {
            int totalLength = 2 + 1 + packet.payload().length;
            if (buffer.length < totalLength) {
                throw new IllegalArgumentException("Buffer too small");
            }

            int packetLength = 1 + packet.payload().length;
            buffer[0] = (byte) ((packetLength >> 8) & 0xFF);
            buffer[1] = (byte) (packetLength & 0xFF);
            buffer[2] = (byte) packet.opcode();
            System.arraycopy(packet.payload(), 0, buffer, 3, packet.payload().length);

            return totalLength;
        }
    }

    /**
     * RSC binary format decoder.
     */
    public static class RscBinaryDecoder implements IPacketDecoder {
        @Override
        public ProtocolFormat getFormat() {
            return ProtocolFormat.RSC_BINARY;
        }

        @Override
        public Optional<Packet> decode(byte[] data) {
            if (data.length < 3) {
                return Optional.empty();
            }

            int length = ((data[0] & 0xFF) << 8) | (data[1] & 0xFF);
            if (data.length < 2 + length) {
                return Optional.empty();
            }

            int opcode = data[2] & 0xFF;
            byte[] payload = new byte[length - 1];
            System.arraycopy(data, 3, payload, 0, length - 1);

            return Optional.of(new Packet(opcode, payload));
        }
    }

    /**
     * MessagePack format encoder.
     * Format: [magic:1][version:1][length:4 BE][messagepack payload]
     */
    public static class MessagePackEncoder implements IPacketEncoder {
        private final MessagePackSerializer serializer;

        public MessagePackEncoder(MessagePackSerializer serializer) {
            this.serializer = serializer;
        }

        @Override
        public ProtocolFormat getFormat() {
            return ProtocolFormat.MESSAGE_PACK;
        }

        @Override
        public byte[] encode(Packet packet) {
            try {
                return serializer.serializePacket(packet.opcode(), packet.payload());
            } catch (IOException e) {
                throw new RuntimeException("Failed to encode MessagePack packet", e);
            }
        }

        @Override
        public int encode(Packet packet, byte[] buffer) {
            byte[] encoded = encode(packet);
            if (buffer.length < encoded.length) {
                throw new IllegalArgumentException("Buffer too small");
            }
            System.arraycopy(encoded, 0, buffer, 0, encoded.length);
            return encoded.length;
        }
    }

    /**
     * MessagePack format decoder.
     */
    public static class MessagePackDecoder implements IPacketDecoder {
        private final MessagePackSerializer serializer;

        public MessagePackDecoder(MessagePackSerializer serializer) {
            this.serializer = serializer;
        }

        @Override
        public ProtocolFormat getFormat() {
            return ProtocolFormat.MESSAGE_PACK;
        }

        @Override
        public Optional<Packet> decode(byte[] data) {
            if (data.length < 6) {
                return Optional.empty();
            }

            if (data[0] != MSGPACK_MAGIC) {
                return Optional.empty();
            }

            try {
                MessagePackSerializer.GamePacket gamePacket = serializer.deserializePacket(data);
                return Optional.of(new Packet(gamePacket.opcode(), gamePacket.payload()));
            } catch (IOException e) {
                LOGGER.warn("Failed to decode MessagePack packet", e);
                return Optional.empty();
            }
        }
    }

    /**
     * Client protocol state tracking.
     */
    public static class ClientProtocolState {
        private ProtocolFormat format = ProtocolFormat.RSC_BINARY;
        private IPacketEncoder encoder;
        private IPacketDecoder decoder;
        private boolean negotiated = false;
        private int protocolVersion = 0;
        private boolean supportsCompression = false;

        public ClientProtocolState(ProtocolAdapter adapter) {
            this.encoder = adapter.createEncoder(format);
            this.decoder = adapter.createDecoder(format);
        }

        public void negotiate(ProtocolFormat format, ProtocolAdapter adapter) {
            this.format = format;
            this.encoder = adapter.createEncoder(format);
            this.decoder = adapter.createDecoder(format);
            this.negotiated = true;
        }

        public ProtocolFormat getFormat() { return format; }
        public IPacketEncoder getEncoder() { return encoder; }
        public IPacketDecoder getDecoder() { return decoder; }
        public boolean isNegotiated() { return negotiated; }
        public int getProtocolVersion() { return protocolVersion; }
        public void setProtocolVersion(int version) { this.protocolVersion = version; }
        public boolean supportsCompression() { return supportsCompression; }
        public void setSupportsCompression(boolean supports) { this.supportsCompression = supports; }
    }
}
