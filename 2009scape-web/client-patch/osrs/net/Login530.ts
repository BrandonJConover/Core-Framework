/**
 * Login530.ts — Rev 530 login handshake for 2009scape.
 *
 * This implements the full login flow as defined by the 2009scape server:
 *   Server/src/main/core/net/packet/in/Login.kt
 *   Server/src/main/core/net/event/HSReadEvent.java
 *   Server/src/main/core/net/event/LoginWriteEvent.java
 *
 * Protocol flow:
 *   1. Client sends: [14 (handshake opcode)] [nameHash byte]
 *   2. Server responds: [0x00 status] [8-byte serverKey (long)]
 *   3. Client sends login block (opcode 16 or 18)
 *   4. Server responds with AuthResponse ordinal + session data
 *
 * ISAAC cipher is DISABLED on the 2009scape server (getNextValue() returns 0),
 * so we still initialize it but opcodes are effectively plaintext.
 */

import { Buffer } from "./Buffer";
import { Configuration } from "./Configuration";
import { ISAACCipher } from "./ISAACCipher";

// ── Auth response codes from 2009scape AuthResponse enum ──
export const AuthResponse = {
    0:  "Unexpected server error.",
    1:  "Retry login (server loading)...",
    2:  "Success",
    3:  "Invalid username or password.",
    4:  "Your account has been disabled.",
    5:  "Your account is already logged in.",
    6:  "Client updated — please reload.",
    7:  "This world is full.",
    8:  "Login server offline.",
    9:  "Login limit exceeded. Try again in a few minutes.",
    10: "Bad session ID. Please reload.",
    11: "Login server rejected session.",
    12: "Members-only world.",
    13: "Could not complete login. Please try again.",
    14: "Server is being updated. Please wait.",
    15: "Login server connection error.",
    16: "Login attempts exceeded. Please wait.",
    17: "Standing in a members area. Move to a free area first.",
    18: "Invalid login server.",
    19: "Account transfer in progress. Try again later.",
    20: "Login server error.",
    21: "Login server error.",
} as Record<number, string>;

/**
 * Encode a username string to a long (BigInt-compatible number).
 * This is the standard RS2 username encoding (base-37).
 */
export function usernameToLong(username: string): bigint {
    let encoded = 0n;
    const clean = username.toLowerCase().trim();
    for (let i = 0; i < Math.min(clean.length, 12); i++) {
        const c = clean.charCodeAt(i);
        encoded *= 37n;
        if (c >= 97 && c <= 122) {       // a-z
            encoded += BigInt(c - 96);
        } else if (c >= 48 && c <= 57) {  // 0-9
            encoded += BigInt(c - 48 + 27);
        } else if (c === 95) {            // underscore
            // underscore = 0 in base37 (no addition)
        }
    }
    return encoded;
}

/**
 * Write a 64-bit value to a Buffer as 8 bytes (big-endian).
 * The 377 client Buffer may not have native bigint support,
 * so we write it manually.
 */
function writeLong(buf: Buffer, value: bigint): void {
    const high = Number((value >> 32n) & 0xFFFFFFFFn);
    const low = Number(value & 0xFFFFFFFFn);
    buf.putInt(high);
    buf.putInt(low);
}

export interface LoginResult {
    success: boolean;
    responseCode: number;
    message: string;
    playerIndex?: number;
    playerRights?: number;
    inCipher?: ISAACCipher;
    outCipher?: ISAACCipher;
}

/**
 * Perform the full rev 530 login handshake.
 *
 * @param socket     - The WebSocket connection wrapper (Socket class from 377 client)
 * @param username   - Player username
 * @param password   - Player password
 * @param reconnecting - Whether this is a reconnect (opcode 18) vs new login (16)
 * @param rsaEncrypt - Function to RSA-encrypt a byte array (from WASM module)
 * @param crcValues  - Array of 29 cache index CRC checksums
 */
export async function performLogin530(
    socket: any,
    username: string,
    password: string,
    reconnecting: boolean,
    rsaEncrypt: (data: Uint8Array) => Uint8Array,
    crcValues: number[] = new Array(29).fill(0),
): Promise<LoginResult> {

    // ── Phase 1: Handshake ──
    const nameHash = Number((usernameToLong(username) >> 16n) & 31n);

    // Send handshake: [14] [nameHash]
    const hsBuffer = Buffer.create(2);
    hsBuffer.putByte(14);
    hsBuffer.putByte(nameHash);
    await socket.write(hsBuffer.data, 0, 2);

    // Read server response: 1 byte status
    const statusByte = await socket.read();
    if (statusByte !== 0) {
        return {
            success: false,
            responseCode: statusByte,
            message: AuthResponse[statusByte] || `Login failed (code ${statusByte})`,
        };
    }

    // Read 8-byte server key (as two 32-bit ints)
    const serverKey0 = await readInt(socket);
    const serverKey1 = await readInt(socket);

    // ── Phase 2: Build login block ──

    // Generate client ISAAC seeds (random)
    const clientSeed0 = (Math.random() * 0x7FFFFFFF) | 0;
    const clientSeed1 = (Math.random() * 0x7FFFFFFF) | 0;

    // Build the RSA block (to be encrypted)
    const rsaBlock = Buffer.create(128);
    rsaBlock.putByte(10); // verification magic byte
    rsaBlock.putInt(clientSeed0);
    rsaBlock.putInt(clientSeed1);
    rsaBlock.putInt(serverKey0);
    rsaBlock.putInt(serverKey1);
    writeLong(rsaBlock, usernameToLong(username));
    rsaBlock.putString(password);

    // RSA encrypt
    const rsaData = new Uint8Array(rsaBlock.data.buffer, 0, rsaBlock.offset);
    const encryptedRsa = rsaEncrypt(rsaData);

    // Build the full login packet
    // Total payload after opcode: everything below
    const loginBlock = Buffer.create(512);

    // Revision
    loginBlock.putInt(Configuration.CLIENT_REVISION);

    // Display info
    loginBlock.putByte(0);  // skip byte
    loginBlock.putByte(0);  // showAds = false
    loginBlock.putByte(0);  // skip byte
    loginBlock.putByte(2);  // windowMode (2 = fixed)
    loginBlock.putShort(Configuration.DEFAULT_WIDTH);
    loginBlock.putShort(Configuration.DEFAULT_HEIGHT);
    loginBlock.putByte(0);  // displayMode (0 = SD)

    // 24 bytes of random data (server skips these)
    for (let i = 0; i < 24; i++) {
        loginBlock.putByte((Math.random() * 256) | 0);
    }

    // String (skipped by server) — NUL-terminated
    loginBlock.putString("");

    // Affiliate ID and settings
    loginBlock.putInt(0);   // adAffiliateId
    loginBlock.putInt(0);   // settingsHash
    loginBlock.putShort(0); // currentPacketCount

    // 29 CRC checksums (one per cache index)
    for (let i = 0; i < Configuration.CACHE_INDEX_COUNT; i++) {
        loginBlock.putInt(crcValues[i] || 0);
    }

    // RSA encrypted block
    loginBlock.putByte(encryptedRsa.length);
    for (let i = 0; i < encryptedRsa.length; i++) {
        loginBlock.putByte(encryptedRsa[i]);
    }

    // Now wrap it all with the login opcode + size header
    const loginPacket = Buffer.create(loginBlock.offset + 3);
    loginPacket.putByte(reconnecting ? 18 : 16);  // login opcode
    loginPacket.putShort(loginBlock.offset);       // payload length

    // Copy login block payload
    for (let i = 0; i < loginBlock.offset; i++) {
        loginPacket.putByte(loginBlock.data[i]);
    }

    await socket.write(loginPacket.data, 0, loginPacket.offset);

    // ── Phase 3: Read login response ──
    const responseCode = await socket.read();

    if (responseCode === 1) {
        // Server says "retry" — wait and try again
        return {
            success: false,
            responseCode: 1,
            message: "Server loading, please retry...",
        };
    }

    if (responseCode !== 2) {
        return {
            success: false,
            responseCode,
            message: AuthResponse[responseCode] || `Login failed (code ${responseCode})`,
        };
    }

    // Success! Read the 10 response bytes
    const playerRights = await socket.read();    // 0=normal, 1=pmod, 2=admin
    await socket.read();                          // skip
    await socket.read();                          // skip
    await socket.read();                          // skip
    await socket.read();                          // members flag
    await socket.read();                          // skip
    await socket.read();                          // skip
    const playerIndexHigh = await socket.read();
    const playerIndexLow = await socket.read();
    const playerIndex = (playerIndexHigh << 8) | playerIndexLow;
    await socket.read();                          // GE enabled flag

    // ── Initialize ISAAC ciphers ──
    // NOTE: 2009scape has ISAAC disabled (always returns 0),
    // but we initialize them correctly for compatibility with servers that enable it.
    const inSeed = [clientSeed0, clientSeed1, serverKey0, serverKey1];
    const outSeed = [clientSeed0 + 50, clientSeed1 + 50, serverKey0 + 50, serverKey1 + 50];

    const inCipher = new ISAACCipher(inSeed);
    const outCipher = new ISAACCipher(outSeed);

    return {
        success: true,
        responseCode: 2,
        message: "Login successful",
        playerIndex,
        playerRights,
        inCipher,
        outCipher,
    };
}

/**
 * Read a 32-bit big-endian integer from the socket.
 */
async function readInt(socket: any): Promise<number> {
    const b0 = await socket.read();
    const b1 = await socket.read();
    const b2 = await socket.read();
    const b3 = await socket.read();
    return ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3) | 0;
}
