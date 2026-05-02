import fs from "fs";

class Reader {
    constructor(data) { this.data = data; this.pos = 0; }
    eof() { return this.pos >= this.data.length; }
    g1() { return this.data[this.pos++] & 0xff; }
    g1b() { const b = this.data[this.pos++]; return (b << 24) >> 24; }
    g2() { return ((this.data[this.pos++] & 0xff) << 8) | (this.data[this.pos++] & 0xff); }
    g2b() { const v = this.g2(); return v >= 0x8000 ? v - 0x10000 : v; }
    g3() { return ((this.data[this.pos++] & 0xff) << 16) | ((this.data[this.pos++] & 0xff) << 8) | (this.data[this.pos++] & 0xff); }
    g4() {
        return (((this.data[this.pos++] & 0xff) << 24) |
            ((this.data[this.pos++] & 0xff) << 16) |
            ((this.data[this.pos++] & 0xff) << 8) |
            (this.data[this.pos++] & 0xff)) | 0;
    }
    gjstr() {
        let s = "";
        while (this.pos < this.data.length && this.data[this.pos] !== 0) s += String.fromCharCode(this.data[this.pos++]);
        if (this.pos < this.data.length) this.pos++;
        return s;
    }
}

const u16 = (v) => [(v >> 8) & 0xff, v & 0xff];
const i16 = (v) => u16(v < 0 ? 0x10000 + v : v);
const u24 = (v) => [(v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
const u32 = (v) => [(v >>> 24) & 0xff, (v >>> 16) & 0xff, (v >>> 8) & 0xff, v & 0xff];
const strz = (s) => [...Buffer.from(s, "latin1"), 0];

function blank(id) {
    return {
        id, parentId: -1, type: 0, ifVersion: 1,
        x: 0, y: 0, width: 0, height: 0,
        hidden: false, alpha: 0, buttonType: 0, optionBase: "",
        ops: [], color: 0,
    };
}

function parseIF1Component(bytes, id = 0) {
    const r = new Reader(bytes);
    const out = blank(id);
    out.ifVersion = 1;
    out.type = r.g1();
    out.buttonType = r.g1();
    r.g2();
    out.x = r.g2b();
    out.y = r.g2b();
    out.width = r.g2();
    out.height = r.g2();
    out.alpha = r.g1();
    const parent = r.g2();
    out.parentId = parent === 0xffff ? -1 : parent + (id & 0xffff0000);
    r.g2();
    const comparisons = r.g1();
    for (let i = 0; i < comparisons; i++) { r.g1(); r.g2(); }
    const scripts = r.g1();
    for (let i = 0; i < scripts; i++) {
        const len = r.g2();
        for (let j = 0; j < len; j++) r.g2();
    }
    if (out.type === 3) {
        r.g1();
        out.color = r.g4();
        r.g4(); r.g4(); r.g4();
    }
    return out;
}

function parseIF3Component(bytes, id = 0) {
    const r = new Reader(bytes);
    const out = blank(id);
    out.ifVersion = 3;
    r.g1();
    out.type = r.g1();
    r.g2();
    out.x = r.g2b();
    out.y = r.g2b();
    out.width = r.g2();
    out.height = r.g2();
    r.g1b(); r.g1b(); r.g1b(); r.g1b();
    const parent = r.g2();
    out.parentId = parent === 0xffff ? -1 : parent + (id & 0xffff0000);
    out.hidden = r.g1() === 1;
    if (out.type === 2) {
        const slotCount = Math.max(1, out.width * out.height);
        out.inventory = {
            slotCount,
            items: new Array(slotCount).fill(-1),
            itemAmounts: new Array(slotCount).fill(0),
            options: [],
        };
    } else if (out.type === 4) {
        const font = r.g2() === 0xffff ? -1 : bytes[r.pos - 2] << 8 | bytes[r.pos - 1];
        const text = r.gjstr();
        const valign = r.g1();
        const halign = r.g1();
        r.g1();
        const shadowed = r.g1() === 1;
        const color = r.g4();
        out.color = color;
        out.text = { text, activeText: "", color, activeColor: 0, font, halign, valign, shadowed };
    }
    if (!r.eof()) {
        r.g3();
        if (!r.eof()) out.optionBase = r.gjstr();
        if (!r.eof()) {
            const opMeta = r.g1();
            for (let i = 0; i < (opMeta & 0xf) && !r.eof(); i++) out.ops.push(r.gjstr());
        }
    }
    return out;
}

function parseInterfaceComponent(bytes, id = 0) {
    return (bytes[0] & 0xff) === 0xff ? parseIF3Component(bytes, id) : parseIF1Component(bytes, id);
}

function if3Header(type, x, y, width, height) {
    return [
        0xff, type,
        ...u16(0),
        ...i16(x), ...i16(y),
        ...u16(width), ...u16(height),
        0, 0, 0, 0,
        ...u16(0xffff),
        0,
    ];
}

const fixtures = [
    {
        name: "if3-inventory",
        bytes: new Uint8Array([...if3Header(2, 12, 18, 7, 4), ...u24(0), 0, 0]),
        expect: (c) => c.ifVersion === 3 && c.type === 2 && c.inventory && c.inventory.slotCount === 28 && c.inventory.items.length === 28,
    },
    {
        name: "if3-text",
        bytes: new Uint8Array([
            ...if3Header(4, 3, 5, 120, 20),
            ...u16(494), ...strz("Hello 530"), 1, 0, 0, 1, ...u32(0xffcc00),
            ...u24(0), 0, 0,
        ]),
        expect: (c) => c.ifVersion === 3 && c.type === 4 && c.text && c.text.text === "Hello 530",
    },
    {
        name: "if1-rect",
        bytes: new Uint8Array([
            3, 0, ...u16(0),
            ...i16(2), ...i16(4),
            ...u16(64), ...u16(32),
            0, ...u16(0xffff), ...u16(0xffff),
            0, 0,
            1, ...u32(0x112233), ...u32(0), ...u32(0), ...u32(0),
        ]),
        expect: (c) => c.ifVersion === 1 && c.type === 3 && c.x === 2 && c.y === 4 && c.width === 64 && c.height === 32,
    },
];

const lines = [];
for (let i = 0; i < fixtures.length; i++) {
    const fixture = fixtures[i];
    const parsed = parseInterfaceComponent(fixture.bytes, (12 << 16) | i);
    if (!fixture.expect(parsed)) throw new Error(`${fixture.name} parse assertion failed`);
    const format = parsed.ifVersion === 3 ? "IF3" : "IF1";
    lines.push(`[InterfaceComponent530] parsed format=${format} type=${parsed.type} id=${parsed.id} width=${parsed.width} height=${parsed.height}`);
}

if (parseInterfaceComponent(fixtures[0].bytes).ifVersion !== 3) throw new Error("IF3 dispatch failed");
if (parseInterfaceComponent(fixtures[2].bytes).ifVersion !== 1) throw new Error("IF1 dispatch failed");

fs.writeFileSync(new URL("./.interface-component-trace.txt", import.meta.url), lines.join("\n") + "\n");
console.log(lines.join("\n"));
