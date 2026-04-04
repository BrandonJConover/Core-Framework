package com.openrsc.server.infrastructure.serialization;

/**
 * Supported serialization formats.
 */
public enum SerializationFormat {
    /**
     * Original RSC binary format - legacy client compatibility.
     */
    RSC_BINARY,

    /**
     * MessagePack - compact cross-platform binary format.
     */
    MESSAGE_PACK,

    /**
     * FlatBuffers - zero-copy serialization for large data.
     */
    FLAT_BUFFERS,

    /**
     * JSON - human-readable, useful for debugging and APIs.
     */
    JSON
}
