import { ClientOpcode, PacketConstants } from "./PacketConstants";
import { Outgoing530 } from "./Outgoing530";

class TestBuffer {
    bytes: number[] = [];

    putOpcode530(value: number) { this.putByte(value); }
    putOpcode(value: number) { this.putByte(value); }
    putByte(value: number) { this.bytes.push(value & 0xFF); }
    putShort(value: number) {
        this.putByte(value >> 8);
        this.putByte(value);
    }
    putShortAdded(value: number) {
        this.putByte(value >> 8);
        this.putByte(value + 128);
    }
    putLEShort(value: number) {
        this.putByte(value);
        this.putByte(value >> 8);
    }
    putLEShortAdded(value: number) {
        this.putByte(value + 128);
        this.putByte(value >> 8);
    }
    putInt(value: number) {
        this.putByte(value >> 24);
        this.putByte(value >> 16);
        this.putByte(value >> 8);
        this.putByte(value);
    }
    putLEInt(value: number) {
        this.putByte(value);
        this.putByte(value >> 8);
        this.putByte(value >> 16);
        this.putByte(value >> 24);
    }
}

function encode(write: (buf: any) => void): number[] {
    const buf = new TestBuffer();
    write(buf);
    return buf.bytes;
}

describe("Outgoing530 golden packets", () => {
    test("NPC actions use rt4 opcodes and byte order", () => {
        expect(encode((buf) => Outgoing530.npcAction1(buf, 0x1234))).toEqual([
            ClientOpcode.NPC_ACTION_1, 0x34, 0x12,
        ]);
        expect(encode((buf) => Outgoing530.npcAction2(buf, 0x1234))).toEqual([
            ClientOpcode.NPC_ACTION_2, 0xB4, 0x12,
        ]);
    });

    test("loc action 2 and ground item action 2 match reference byte order", () => {
        expect(encode((buf) => Outgoing530.locAction2(buf, 0x0123, 0x0456, 0x0789))).toEqual([
            ClientOpcode.SCENERY_ACTION_2, 0xD6, 0x04, 0x23, 0x01, 0x07, 0x89,
        ]);
        expect(encode((buf) => Outgoing530.objstackAction2(buf, 0x0123, 0x0456, 0x0789))).toEqual([
            ClientOpcode.GROUND_ITEM_ACTION_2, 0x07, 0x89, 0x01, 0x23, 0x56, 0x04,
        ]);
    });

    test("item action 3 writes component, slot, and object as little-endian fields", () => {
        expect(encode((buf) => Outgoing530.objAction3(buf, 0x09AB, 0x0CDE, 0x12345678))).toEqual([
            ClientOpcode.ITEM_ACTION_3, 0x78, 0x56, 0x34, 0x12, 0xAB, 0x09, 0xDE, 0x0C,
        ]);
    });

    test("use item on item writes the 16-byte reference body", () => {
        expect(encode((buf) => Outgoing530.useOnItem(
            buf,
            0x0102,
            0x0304,
            0x11223344,
            0x0506,
            0x0708,
            0x55667788,
        ))).toEqual([
            ClientOpcode.USE_ON_ITEM,
            0x01, 0x02,
            0x88, 0x77, 0x66, 0x55,
            0x06, 0x05,
            0x44, 0x33, 0x22, 0x11,
            0x84, 0x03,
            0x88, 0x07,
        ]);
    });

    test("interface button action 10 keeps the shared six-byte body", () => {
        expect(encode((buf) => Outgoing530.ifButton(buf, 10, 0x12345678, 0x09AB))).toEqual([
            ClientOpcode.IF_ACTION_10, 0x12, 0x34, 0x56, 0x78, 0x09, 0xAB,
        ]);
    });

    test("component CS2 and continue-dialogue actions match rt4 byte order", () => {
        expect(encode((buf) => Outgoing530.ifCs2(buf, 0x12345678))).toEqual([
            ClientOpcode.IF_CS2, 0x12, 0x34, 0x56, 0x78,
        ]);
        expect(encode((buf) => Outgoing530.continueDialogue(buf, 0x12345678, 0x0102))).toEqual([
            ClientOpcode.CONTINUE_DIALOGUE, 0x34, 0x12, 0x78, 0x56, 0x02, 0x01,
        ]);
        expect(encode((buf) => Outgoing530.dialogAction(buf, 0x1234))).toEqual([
            ClientOpcode.DIALOG_ACTION, 0x12, 0x34,
        ]);
    });

    test("component item actions use rt4 opcodes and field order", () => {
        expect(encode((buf) => Outgoing530.objInComponentAction1(buf, 0x0102, 0x0304, 0x12345678))).toEqual([
            ClientOpcode.ITEM_IN_COMPONENT_ACTION_1, 0x01, 0x82, 0x03, 0x04, 0x34, 0x12, 0x78, 0x56,
        ]);
        expect(encode((buf) => Outgoing530.objOperate(buf, 0x0102, 0x0304, 0x12345678))).toEqual([
            ClientOpcode.ITEM_OPERATE, 0x03, 0x84, 0x02, 0x01, 0x78, 0x56, 0x34, 0x12,
        ]);
        expect(encode((buf) => Outgoing530.objInComponentAction2(buf, 0x0102, 0x0304, 0x12345678))).toEqual([
            ClientOpcode.ITEM_IN_COMPONENT_ACTION_2, 0x02, 0x01, 0x34, 0x12, 0x78, 0x56, 0x84, 0x03,
        ]);
        expect(encode((buf) => Outgoing530.objInComponentAction3(buf, 0x0102, 0x0304, 0x12345678))).toEqual([
            ClientOpcode.ITEM_IN_COMPONENT_ACTION_3, 0x34, 0x12, 0x78, 0x56, 0x01, 0x02, 0x03, 0x84,
        ]);
        expect(encode((buf) => Outgoing530.objInComponentAction5(buf, 0x0102, 0x0304, 0x12345678))).toEqual([
            ClientOpcode.ITEM_IN_COMPONENT_ACTION_5, 0x12, 0x34, 0x56, 0x78, 0x01, 0x82, 0x04, 0x03,
        ]);
    });

    test("ground item action 5 matches rt4 UNKNOWN_24 byte order", () => {
        expect(encode((buf) => Outgoing530.objstackAction5(buf, 0x0123, 0x0456, 0x0789))).toEqual([
            ClientOpcode.GROUND_ITEM_ACTION_5, 0x01, 0xA3, 0x09, 0x07, 0x56, 0x04,
        ]);
    });

    test("public chat writes rt4 variable-byte frame with wordpack payload", () => {
        const passthroughHuffman = {
            encode(len: number, src: Uint8Array, srcOffset: number, dst: Uint8Array, dstOffset: number): number {
                for (let i = 0; i < len; i++) dst[dstOffset + i] = src[srcOffset + i];
                return len;
            },
        } as any;
        expect(encode((buf) => Outgoing530.publicChat(buf, 2, 3, "hi", passthroughHuffman))).toEqual([
            ClientOpcode.CHAT_MESSAGE,
            5,
            2,
            3,
            2,
            "h".charCodeAt(0),
            "i".charCodeAt(0),
        ]);
    });

    test("declared packet sizes match the fixed-size action encoders", () => {
        const fixedSizes: Array<[number, number]> = [
            [ClientOpcode.NPC_ACTION_1, 2],
            [ClientOpcode.NPC_ACTION_2, 2],
            [ClientOpcode.NPC_ACTION_3, 2],
            [ClientOpcode.NPC_ACTION_4, 2],
            [ClientOpcode.NPC_ACTION_5, 2],
            [ClientOpcode.SCENERY_ACTION_1, 6],
            [ClientOpcode.SCENERY_ACTION_2, 6],
            [ClientOpcode.SCENERY_ACTION_3, 6],
            [ClientOpcode.SCENERY_ACTION_4, 6],
            [ClientOpcode.SCENERY_ACTION_5, 6],
            [ClientOpcode.ITEM_ACTION_1, 8],
            [ClientOpcode.ITEM_ACTION_2, 8],
            [ClientOpcode.ITEM_ACTION_3, 8],
            [ClientOpcode.ITEM_ACTION_4, 8],
            [ClientOpcode.ITEM_ACTION_5, 8],
            [ClientOpcode.ITEM_OPERATE, 8],
            [ClientOpcode.ITEM_IN_COMPONENT_ACTION_1, 8],
            [ClientOpcode.ITEM_IN_COMPONENT_ACTION_2, 8],
            [ClientOpcode.ITEM_IN_COMPONENT_ACTION_3, 8],
            [ClientOpcode.ITEM_IN_COMPONENT_ACTION_5, 8],
            [ClientOpcode.GROUND_ITEM_ACTION_1, 6],
            [ClientOpcode.GROUND_ITEM_ACTION_2, 6],
            [ClientOpcode.GROUND_ITEM_ACTION_5, 6],
            [ClientOpcode.PLAYER_ACTION_1, 2],
            [ClientOpcode.PLAYER_ACTION_FOLLOW, 2],
            [ClientOpcode.PLAYER_ACTION_TRADE, 2],
            [ClientOpcode.PLAYER_REQ_ASSIST, 2],
            [ClientOpcode.PLAYER_ACTION_5, 2],
            [ClientOpcode.USE_ON_NPC, 10],
            [ClientOpcode.USE_ON_PLAYER, 10],
            [ClientOpcode.USE_ON_ITEM, 16],
            [ClientOpcode.USE_ON_SCENERY, 14],
            [ClientOpcode.USE_ON_GROUND_ITEM, 14],
            [ClientOpcode.COMPONENT_NPC_ACTION, 8],
            [ClientOpcode.COMPONENT_ITEM_ACTION, 14],
            [ClientOpcode.COMPONENT_SCENERY_ACTION, 12],
            [ClientOpcode.COMPONENT_PLAYER_ACTION, 8],
            [ClientOpcode.COMPONENT_GROUND_ITEM_ACTION, 12],
            [ClientOpcode.IF_ACTION_1, 6],
            [ClientOpcode.IF_ACTION_10, 6],
            [ClientOpcode.IF_CS2, 4],
            [ClientOpcode.DIALOG_ACTION, 2],
            [ClientOpcode.CONTINUE_DIALOGUE, 6],
        ];

        for (const [opcode, size] of fixedSizes) {
            expect(PacketConstants.PACKET_SIZES[opcode]).toBe(size);
        }
        expect(PacketConstants.PACKET_SIZES[ClientOpcode.CHAT_MESSAGE]).toBe(-1);
    });

    test("character-design submit remains unmapped rather than reusing the 377 opcode", () => {
        expect(PacketConstants.PACKET_SIZES[163]).toBe(-3);
        expect((ClientOpcode as any).CHARACTER_DESIGN).toBeUndefined();
    });
});
