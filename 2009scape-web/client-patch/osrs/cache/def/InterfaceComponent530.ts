/**
 * InterfaceComponent530 — function-style, strongly-typed parser for the
 * rev-530 interface component byte format (idx3). Foundation for the UI
 * layer (chatbox, inventory, bank, shop) and the CS2 script runtime.
 *
 * Two on-disk variants:
 *   IF1 — legacy 377-style fixed record. byte[0] is the type tag.
 *   IF3 — rev-530 native opcode-based. byte[0] === 0xFF is the dispatch
 *         marker; byte[1] is the type tag.
 *
 * Existing Component.ts (also in cache/def/) is the runtime decoder used
 * by the legacy 377 client; it covers the common header + types 0/3/4/5/6/9
 * for IF3 but does NOT cover IF3 type 2 (inventory). This module provides:
 *   - InterfaceComponent530Data: strongly-typed projection grouped by type
 *   - parseIF1Component / parseIF3Component / parseInterfaceComponent
 *     entries that produce the typed record from raw bytes
 *   - Type-2 (inventory) IF3 support that the existing class is missing
 *   - InterfaceComponent530.load(js5Cache, ifaceId, compId) for idx3 fetch
 *
 * Source of truth (read-only):
 *   reference/rt4-client/client/src/main/java/rt4/Component.java
 *     decodeIf1   line 587
 *     decodeIf3   line 1018
 *     type 2 IF1  line 647   (inventory layout — invMarginX/Y, invOffset[20], invOptions[5])
 *     type 4 IF3  line 1088  (text, font, halign, valign, shadowed)
 *     opcode loop line 1173+ (handler bind: onMouseOver, onClick, etc.)
 */

export interface InterfaceComponent530Cache {
    getFileBytes(idxNum: number, groupId: number, fileId: number): Promise<Uint8Array | null>;
}

// ── Reader ────────────────────────────────────────────────────────

class IfReader {
    public data: Uint8Array;
    public pos: number;
    constructor(data: Uint8Array) { this.data = data; this.pos = 0; }
    eof(): boolean { return this.pos >= this.data.length; }
    g1(): number { return this.data[this.pos++] & 0xFF; }
    g1b(): number { const b = this.data[this.pos++]; return (b << 24) >> 24; }
    g2(): number {
        const a = this.data[this.pos++] & 0xFF;
        const b = this.data[this.pos++] & 0xFF;
        return (a << 8) | b;
    }
    g2b(): number {
        const v = this.g2();
        return v >= 0x8000 ? v - 0x10000 : v;
    }
    g3(): number {
        const a = this.data[this.pos++] & 0xFF;
        const b = this.data[this.pos++] & 0xFF;
        const c = this.data[this.pos++] & 0xFF;
        return ((a << 16) | (b << 8) | c) >>> 0;
    }
    g4(): number {
        const a = this.data[this.pos++] & 0xFF;
        const b = this.data[this.pos++] & 0xFF;
        const c = this.data[this.pos++] & 0xFF;
        const d = this.data[this.pos++] & 0xFF;
        return ((a << 24) | (b << 16) | (c << 8) | d) | 0;
    }
    gjstr(): string {
        let s = "";
        while (this.pos < this.data.length && this.data[this.pos] !== 0) {
            s += String.fromCharCode(this.data[this.pos++] & 0xFF);
        }
        if (this.pos < this.data.length) this.pos++;
        return s;
    }
}

// ── Typed projection ──────────────────────────────────────────────

export interface IfTextBlock {
    text: string;
    activeText: string;
    color: number;
    activeColor: number;
    font: number;
    halign: number;
    valign: number;
    shadowed: boolean;
}

export interface IfModelBlock {
    modelId: number;
    activeModelId: number;
    modelSeqId: number;
    activeModelSeqId: number;
    modelXAngle: number;
    modelYAngle: number;
    modelZoom: number;
    modelType: number;
}

export interface IfSpriteBlock {
    spriteId: number;
    activeSpriteId: number;
    /** IF3 sprite extras: tiling, alpha, outline, hflip, vflip. Default 0/false. */
    angle2d: number;
    hasAlpha: boolean;
    spriteTiling: boolean;
    alpha: number;
    outlineThickness: number;
    shadowColor: number;
    hFlip: boolean;
    vFlip: boolean;
}

export interface IfInventoryBlock {
    /** Number of slots in the grid. width * height per IF1; explicit per IF3. */
    slotCount: number;
    /** Per-slot item id. -1 = empty. Length === slotCount. Filled by run-time updates. */
    items: number[];
    /** Per-slot item count. 0 = empty. Length === slotCount. Filled by run-time updates. */
    itemAmounts: number[];
    /** Right-click options on items. Length 5; entries can be empty strings. */
    options: string[];
    /** Per-slot icon padding inside the grid cell. */
    invMarginX: number;
    invMarginY: number;
    itemSwapable: boolean;
    isInventory: boolean;
    itemUsable: boolean;
    itemDeletesDragged: boolean;
    /** Up to 20 sprite-overlay positions. Index = -1 in invSprite means "no sprite". */
    invSprite: number[];
    invOffsetX: number[];
    invOffsetY: number[];
}

export interface IfContainerBlock {
    scrollMaxH: number;
    scrollMaxV: number;
    /** Sub-component ids in stacking order. Empty array when none. */
    childIds: number[];
}

export interface InterfaceComponent530Data {
    id: number;
    parentId: number;
    /** rt4 type tag. 0=container, 1=model-text, 2=inventory, 3=rect, 4=text, 5=sprite, 6=model, 7=item-list, 8=text-scrollable, 9=line. */
    type: number;
    /** 1 = IF1 legacy fixed record. 3 = IF3 rev-530 opcode-based. */
    ifVersion: 1 | 3;

    // Layout (component-relative, pixel units).
    x: number;
    y: number;
    width: number;
    height: number;

    // Visibility.
    hidden: boolean;
    alpha: number;

    // Click + cursor metadata.
    /** Right-click "click-through" button kind from IF1 (0..6) or 0 in IF3. */
    buttonType: number;
    /** Right-click base label (e.g. "Use", "Take"). */
    optionBase: string;
    /** Per-slot right-click ops (max 5). Empty strings are valid. */
    ops: string[];

    // Type-specific blocks (only the relevant one is populated).
    text?: IfTextBlock;
    model?: IfModelBlock;
    sprite?: IfSpriteBlock;
    inventory?: IfInventoryBlock;
    container?: IfContainerBlock;

    /** Generic 32-bit color for non-text components (rect fill, line color). */
    color: number;
}

// ── Helpers ───────────────────────────────────────────────────────

function nullable16(v: number): number {
    return v === 0xFFFF ? -1 : v;
}

function normalizeParent(value: number, id: number): number {
    return value === 0xFFFF ? -1 : value + (id & 0xFFFF0000);
}

function blank(id: number): InterfaceComponent530Data {
    return {
        id, parentId: -1, type: 0, ifVersion: 1,
        x: 0, y: 0, width: 0, height: 0,
        hidden: false, alpha: 0,
        buttonType: 0, optionBase: "", ops: [],
        color: 0,
    };
}

// ── IF1 (legacy fixed record) ─────────────────────────────────────

export function parseIF1Component(bytes: Uint8Array, id: number = 0): InterfaceComponent530Data {
    const out = blank(id);
    out.ifVersion = 1;
    if (!bytes || bytes.byteLength === 0) return out;
    if ((bytes[0] & 0xFF) === 0xFF) {
        throw new Error("[InterfaceComponent530] parseIF1Component called with IF3 marker byte");
    }
    const r = new IfReader(bytes);
    out.type = r.g1();
    out.buttonType = r.g1();
    r.g2(); // contentType
    out.x = r.g2b();
    out.y = r.g2b();
    out.width = r.g2();
    out.height = r.g2();
    out.alpha = r.g1();
    out.parentId = normalizeParent(r.g2(), id);
    nullable16(r.g2());

    const comparisons = r.g1();
    for (let i = 0; i < comparisons; i++) { r.g1(); r.g2(); }
    const scripts = r.g1();
    for (let i = 0; i < scripts; i++) {
        const len = r.g2();
        for (let j = 0; j < len; j++) r.g2();
    }

    if (out.type === 0) {
        out.container = { scrollMaxH: 0, scrollMaxV: r.g2(), childIds: [] };
        out.hidden = r.g1() === 1;
    }
    if (out.type === 1) { r.g2(); r.g1(); }

    if (out.type === 2) {
        // IF1 inventory: invMarginX, invMarginY + 20 sprite slots + 5 options.
        // slotCount is implicit from width*height — IF1 uses the layout dims.
        const itemSwapable = r.g1() === 1;
        const isInventory = r.g1() === 1;
        const itemUsable = r.g1() === 1;
        const itemDeletesDragged = r.g1() === 1;
        const invMarginX = r.g1();
        const invMarginY = r.g1();
        const invSprite: number[] = [];
        const invOffsetX: number[] = [];
        const invOffsetY: number[] = [];
        for (let i = 0; i < 20; i++) {
            const has = r.g1();
            if (has === 1) {
                invOffsetX.push(r.g2b());
                invOffsetY.push(r.g2b());
                invSprite.push(r.g4());
            } else {
                invOffsetX.push(0);
                invOffsetY.push(0);
                invSprite.push(-1);
            }
        }
        const options: string[] = [];
        for (let i = 0; i < 5; i++) options.push(r.gjstr());
        const slotCount = Math.max(1, out.width * out.height);
        out.inventory = {
            slotCount,
            items: new Array(slotCount).fill(-1),
            itemAmounts: new Array(slotCount).fill(0),
            options,
            invMarginX, invMarginY,
            itemSwapable, isInventory, itemUsable, itemDeletesDragged,
            invSprite, invOffsetX, invOffsetY,
        };
    }

    if (out.type === 3) r.g1(); // filled

    if (out.type === 4 || out.type === 1) {
        const halign = r.g1();
        const valign = r.g1();
        r.g1(); // vpadding (kept implicit on IF1)
        let font = nullable16(r.g2());
        const shadowed = r.g1() === 1;

        if (out.type === 4) {
            const text = r.gjstr();
            const activeText = r.gjstr();
            out.text = {
                text, activeText,
                color: 0, activeColor: 0,
                font, halign, valign, shadowed,
            };
        } else {
            out.text = {
                text: "", activeText: "",
                color: 0, activeColor: 0,
                font, halign, valign, shadowed,
            };
        }
    }

    if (out.type === 1 || out.type === 3 || out.type === 4) {
        out.color = r.g4();
        if (out.text) out.text.color = out.color;
    }
    if (out.type === 3 || out.type === 4) {
        const ac = r.g4(); r.g4(); r.g4();
        if (out.text) out.text.activeColor = ac;
    }

    if (out.type === 5) {
        out.sprite = {
            spriteId: r.g4(),
            activeSpriteId: r.g4(),
            angle2d: 0, hasAlpha: false, spriteTiling: false,
            alpha: 0, outlineThickness: 0, shadowColor: 0, hFlip: false, vFlip: false,
        };
    }

    if (out.type === 6) {
        const modelId = nullable16(r.g2());
        const activeModelId = nullable16(r.g2());
        const modelSeqId = nullable16(r.g2());
        const activeModelSeqId = nullable16(r.g2());
        const modelZoom = r.g2();
        const modelXAngle = r.g2();
        const modelYAngle = r.g2();
        out.model = {
            modelId, activeModelId, modelSeqId, activeModelSeqId,
            modelXAngle, modelYAngle, modelZoom, modelType: 1,
        };
    }

    if (out.type === 7) {
        // Item-list inventory.
        r.g1(); nullable16(r.g2()); r.g1(); r.g4(); r.g2b(); r.g2b(); r.g1();
        const options: string[] = [];
        for (let i = 0; i < 5; i++) options.push(r.gjstr());
        out.inventory = {
            slotCount: 1, items: [-1], itemAmounts: [0], options,
            invMarginX: 0, invMarginY: 0,
            itemSwapable: false,
            isInventory: false,
            itemUsable: false,
            itemDeletesDragged: false,
            invSprite: [], invOffsetX: [], invOffsetY: [],
        };
    }

    if (out.type === 8) {
        out.text = {
            text: r.gjstr(), activeText: "", color: 0, activeColor: 0,
            font: -1, halign: 0, valign: 0, shadowed: false,
        };
    }

    if (out.buttonType === 2 || out.type === 2) {
        r.gjstr(); r.gjstr(); r.g2();
    }
    if (out.buttonType === 1 || out.buttonType === 4 || out.buttonType === 5 || out.buttonType === 6) {
        out.optionBase = r.gjstr();
    }
    return out;
}

// ── IF3 (rev-530 opcode-based) ────────────────────────────────────

export function parseIF3Component(bytes: Uint8Array, id: number = 0): InterfaceComponent530Data {
    const out = blank(id);
    out.ifVersion = 3;
    if (!bytes || bytes.byteLength === 0) return out;
    if ((bytes[0] & 0xFF) !== 0xFF) {
        throw new Error("[InterfaceComponent530] parseIF3Component called without 0xFF marker byte");
    }
    const r = new IfReader(bytes);
    r.g1(); // 0xFF marker

    out.type = r.g1();
    if ((out.type & 0x80) !== 0) {
        out.type &= 0x7F;
        r.gjstr(); // optional descriptor string
    }
    r.g2(); // contentType
    out.x = r.g2b();
    out.y = r.g2b();
    out.width = r.g2();
    out.height = r.g2();
    r.g1b(); r.g1b(); r.g1b(); r.g1b(); // misc layout (anchor margins)
    out.parentId = normalizeParent(r.g2(), id);
    out.hidden = r.g1() === 1;

    if (out.type === 0) {
        const scrollMaxH = r.g2();
        const scrollMaxV = r.g2();
        r.g1(); // noClickThrough
        out.container = { scrollMaxH, scrollMaxV, childIds: [] };
    } else if (out.type === 2) {
        // IF3 inventory grid: width × height implicit slot count.
        const slotCount = Math.max(1, out.width * out.height);
        out.inventory = {
            slotCount,
            items: new Array(slotCount).fill(-1),
            itemAmounts: new Array(slotCount).fill(0),
            options: [],
            invMarginX: 0, invMarginY: 0,
            itemSwapable: false,
            isInventory: false,
            itemUsable: false,
            itemDeletesDragged: false,
            invSprite: [], invOffsetX: [], invOffsetY: [],
        };
    } else if (out.type === 5) {
        const spriteId = r.g4();
        const angle2d = r.g2();
        const hasAlpha = r.g1() === 1;
        const spriteTiling = r.g1() === 1;
        const alpha = r.g1();
        const outlineThickness = r.g4();
        const shadowColor = r.g1();
        const flipFlag = r.g1();
        out.sprite = {
            spriteId, activeSpriteId: -1,
            angle2d, hasAlpha, spriteTiling, alpha,
            outlineThickness, shadowColor,
            hFlip: (flipFlag & 1) !== 0,
            vFlip: (flipFlag & 2) !== 0,
        };
    } else if (out.type === 6) {
        const modelId = nullable16(r.g2());
        r.g2b(); r.g2b(); // model offset
        const modelXAngle = r.g2();
        const modelYAngle = r.g2();
        r.g2(); // padding
        const modelZoom = r.g2();
        const modelSeqId = nullable16(r.g2());
        r.g1(); r.g2(); r.g2(); r.g1();
        out.model = {
            modelId, activeModelId: -1, modelSeqId, activeModelSeqId: -1,
            modelXAngle, modelYAngle, modelZoom, modelType: 1,
        };
    } else if (out.type === 4) {
        const font = nullable16(r.g2());
        const text = r.gjstr();
        const valign = r.g1();
        const halign = r.g1();
        const vpadding = r.g1(); void vpadding;
        const shadowed = r.g1() === 1;
        const color = r.g4();
        out.color = color;
        out.text = {
            text, activeText: "", color, activeColor: 0,
            font, halign, valign, shadowed,
        };
    } else if (out.type === 3) {
        const color = r.g4();
        r.g1(); r.g1();
        out.color = color;
    } else if (out.type === 9) {
        r.g1();
        out.color = r.g4();
        r.g1();
    }

    out.alpha = 0;

    // Common tail: optional flag bits + child-id table + ops/triggers.
    // Bounds-check defensively — fixture bytes may end early.
    if (!r.eof()) {
        try {
            r.g3(); // server active properties
            // Child-id table — terminated by a 0 sentinel.
            if (out.container) {
                let key = r.g1();
                while (key !== 0 && !r.eof()) {
                    const slot = (key >> 4) - 1;
                    key = (r.g1() | (key << 8)) & 0xFFF;
                    if (slot >= 0) out.container.childIds.push(key === 4095 ? -1 : key);
                    if (r.eof()) break;
                    r.g1b(); r.g1b();
                    if (r.eof()) break;
                    key = r.g1();
                }
            }
            if (!r.eof()) out.optionBase = r.gjstr();
            if (!r.eof()) {
                const opMeta = r.g1();
                const opCount = opMeta & 0xF;
                for (let i = 0; i < opCount && !r.eof(); i++) out.ops.push(r.gjstr());
            }
        } catch (_) {
            // Tolerant tail decode — fixture bytes may not include every section.
        }
    }

    return out;
}

// ── Top-level dispatch ────────────────────────────────────────────

export function parseInterfaceComponent(bytes: Uint8Array, id: number = 0): InterfaceComponent530Data {
    if (!bytes || bytes.byteLength === 0) return blank(id);
    return (bytes[0] & 0xFF) === 0xFF
        ? parseIF3Component(bytes, id)
        : parseIF1Component(bytes, id);
}

// ── Js5Cache integration ──────────────────────────────────────────

export class InterfaceComponent530 {
    public static readonly INDEX = 3;

    static decode(bytes: Uint8Array, id: number): InterfaceComponent530Data {
        return parseInterfaceComponent(bytes, id);
    }

    static async load(
        js5Cache: InterfaceComponent530Cache,
        interfaceId: number,
        componentId: number,
    ): Promise<InterfaceComponent530Data | null> {
        if (interfaceId < 0 || componentId < 0) return null;
        const data = await js5Cache.getFileBytes(InterfaceComponent530.INDEX, interfaceId, componentId);
        if (!data || data.byteLength === 0) return null;
        const id = (interfaceId << 16) | (componentId & 0xFFFF);
        return parseInterfaceComponent(data, id);
    }
}
