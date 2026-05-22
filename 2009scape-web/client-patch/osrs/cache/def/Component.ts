import { InterfaceComponent530Data } from "./InterfaceComponent530";

class ComponentReader {
    pos: number = 0;
    constructor(readonly data: Uint8Array) {}

    private next(): number {
        return this.pos < this.data.length ? this.data[this.pos++] & 0xFF : 0;
    }
    g1(): number { return this.next(); }
    g1b(): number {
        const v = this.next();
        return v > 127 ? v - 256 : v;
    }
    g2(): number { return (this.next() << 8) | this.next(); }
    g2b(): number {
        const v = this.g2();
        return v > 32767 ? v - 65536 : v;
    }
    g3(): number { return (this.next() << 16) | (this.next() << 8) | this.next(); }
    g4(): number { return ((this.next() << 24) | (this.next() << 16) | (this.next() << 8) | this.next()) | 0; }
    gjstr(): string {
        let s = "";
        while (this.pos < this.data.length) {
            const b = this.next();
            if (b === 0) break;
            s += String.fromCharCode(b);
        }
        return s;
    }
    skipObjectArray(): void {
        const count = this.g1();
        for (let i = 0; i < count; i++) {
            const type = this.g1();
            if (type === 0) this.g4();
            else if (type === 1) this.gjstr();
        }
    }
    skipIntArray(): void {
        const count = this.g1();
        for (let i = 0; i < count; i++) this.g4();
    }
}

export class Component {
    id: number = 0;
    if3: boolean = false;
    ifVersion: number = 1;
    type: number = 0;
    buttonType: number = 0;
    contentType: number = 0;
    x: number = 0;
    y: number = 0;
    width: number = 0;
    height: number = 0;
    alpha: number = 0;
    parentId: number = -1;
    childIds: number[] = [];

    text: string | null = null;
    activeText: string | null = null;
    colour: number = 0;
    activeColour: number = 0;
    font: number = -1;
    horizontalAlignment: number = 0;
    verticalAlignment: number = 0;
    textShadowed: boolean = false;
    sprite: number = -1;
    activeSprite: number = -1;
    spriteAngle: number = 0;
    spriteHasAlpha: boolean = false;
    spriteTiling: boolean = false;
    spriteOutline: number = 0;
    spriteShadow: number = 0;
    spriteHFlip: boolean = false;
    spriteVFlip: boolean = false;
    modelId: number = -1;
    activeModelId: number = -1;
    modelSeqId: number = -1;
    activeModelSeqId: number = -1;
    modelType: number = 0;
    modelZoom: number = 0;
    modelXAngle: number = 0;
    modelYAngle: number = 0;
    inventorySlotCount: number = 0;
    inventoryItems: number[] = [];
    inventoryItemAmounts: number[] = [];
    inventoryOptions: string[] = [];
    invMarginX: number = 0;
    invMarginY: number = 0;
    itemSwapable: boolean = false;
    isInventory: boolean = false;
    itemUsable: boolean = false;
    itemDeletesDragged: boolean = false;
    invSprite: number[] = [];
    invOffsetX: number[] = [];
    invOffsetY: number[] = [];
    scrollPos: number = 0;
    scrollMaxH: number = 0;
    scrollMaxV: number = 0;
    hidden: boolean = false;
    option: string | null = null;
    optionBase: string | null = null;
    ops: string[] = [];

    // Update-only state filled by Tier 5c packet handlers.
    tracknum: number = 0;
    structValue: number = 0;
    structStart: number = -1;
    structEnd: number = -1;
    switchSource: number = -1;
    rotatePitchStep: number = 0;
    rotateYawStep: number = 0;
    serverActiveProperties: number = 0;
    serverActiveStartSlot: number = -1;
    serverActiveEndSlot: number = -1;

    static decode(id: number, bytes: Uint8Array): Component {
        const c = new Component();
        c.id = id;
        if (!bytes || bytes.length === 0) return c;
        const r = new ComponentReader(bytes);
        try {
            if ((bytes[0] & 0xFF) === 0xFF) c.decodeIf3(r);
            else c.decodeIf1(r);
        } catch (e) {
            (c as any).decodeError = (e as any)?.message || String(e);
        }
        return c;
    }

    static fromInterfaceComponent(data: InterfaceComponent530Data): Component {
        const c = new Component();
        c.id = data.id;
        c.if3 = data.ifVersion === 3;
        c.ifVersion = data.ifVersion;
        c.type = data.type;
        c.buttonType = data.buttonType;
        c.x = data.x;
        c.y = data.y;
        c.width = data.width;
        c.height = data.height;
        c.alpha = data.alpha;
        c.parentId = data.parentId;
        c.hidden = data.hidden;
        c.colour = data.color;
        c.optionBase = data.optionBase || null;
        c.ops = data.ops ? data.ops.slice() : [];

        if (data.container) {
            c.scrollMaxH = data.container.scrollMaxH;
            c.scrollMaxV = data.container.scrollMaxV;
            c.childIds = data.container.childIds.slice();
        }
        if (data.text) {
            c.text = data.text.text;
            c.activeText = data.text.activeText;
            c.colour = data.text.color;
            c.activeColour = data.text.activeColor;
            c.font = data.text.font;
            c.horizontalAlignment = data.text.halign;
            c.verticalAlignment = data.text.valign;
            c.textShadowed = data.text.shadowed;
        }
        if (data.sprite) {
            c.sprite = data.sprite.spriteId;
            c.activeSprite = data.sprite.activeSpriteId;
            c.spriteAngle = data.sprite.angle2d;
            c.spriteHasAlpha = data.sprite.hasAlpha;
            c.spriteTiling = data.sprite.spriteTiling;
            c.spriteOutline = data.sprite.outlineThickness;
            c.spriteShadow = data.sprite.shadowColor;
            c.spriteHFlip = data.sprite.hFlip;
            c.spriteVFlip = data.sprite.vFlip;
        }
        if (data.model) {
            c.modelId = data.model.modelId;
            c.activeModelId = data.model.activeModelId;
            c.modelSeqId = data.model.modelSeqId;
            c.activeModelSeqId = data.model.activeModelSeqId;
            c.modelType = data.model.modelType;
            c.modelZoom = data.model.modelZoom;
            c.modelXAngle = data.model.modelXAngle;
            c.modelYAngle = data.model.modelYAngle;
        }
        if (data.inventory) {
            c.inventorySlotCount = data.inventory.slotCount;
            c.inventoryItems = data.inventory.items.slice();
            c.inventoryItemAmounts = data.inventory.itemAmounts.slice();
            c.inventoryOptions = data.inventory.options.slice();
            if (c.ops.length === 0) c.ops = data.inventory.options.slice();
            c.invMarginX = data.inventory.invMarginX;
            c.invMarginY = data.inventory.invMarginY;
            c.itemSwapable = data.inventory.itemSwapable;
            c.isInventory = data.inventory.isInventory;
            c.itemUsable = data.inventory.itemUsable;
            c.itemDeletesDragged = data.inventory.itemDeletesDragged;
            c.invSprite = data.inventory.invSprite.slice();
            c.invOffsetX = data.inventory.invOffsetX.slice();
            c.invOffsetY = data.inventory.invOffsetY.slice();
        }
        return c;
    }

    private decodeIf1(r: ComponentReader): void {
        this.if3 = false;
        this.type = r.g1();
        this.buttonType = r.g1();
        this.contentType = r.g2();
        this.x = r.g2b();
        this.y = r.g2b();
        this.width = r.g2();
        this.height = r.g2();
        r.g1(); // alpha
        this.parentId = normalizeParent(r.g2(), this.id);
        normalizeNullable(r.g2());

        const comparisons = r.g1();
        for (let i = 0; i < comparisons; i++) { r.g1(); r.g2(); }
        const scripts = r.g1();
        for (let i = 0; i < scripts; i++) {
            const len = r.g2();
            for (let j = 0; j < len; j++) r.g2();
        }

        if (this.type === 0) { this.scrollMaxV = r.g2(); this.hidden = r.g1() === 1; }
        if (this.type === 1) { r.g2(); r.g1(); }
        if (this.type === 2) this.skipIf1Inventory(r);
        if (this.type === 3) r.g1();
        if (this.type === 4 || this.type === 1) {
            r.g1(); r.g1(); r.g1();
            normalizeNullable(r.g2());
            r.g1();
        }
        if (this.type === 4) {
            this.text = r.gjstr();
            this.activeText = r.gjstr();
        }
        if (this.type === 1 || this.type === 3 || this.type === 4) this.colour = r.g4();
        if (this.type === 3 || this.type === 4) { r.g4(); r.g4(); r.g4(); }
        if (this.type === 5) {
            this.sprite = r.g4();
            this.activeSprite = r.g4();
        }
        if (this.type === 6) {
            this.modelId = normalizeNullable(r.g2());
            normalizeNullable(r.g2());
            this.modelSeqId = normalizeNullable(r.g2());
            normalizeNullable(r.g2());
            this.modelZoom = r.g2();
            this.modelXAngle = r.g2();
            this.modelYAngle = r.g2();
        }
        if (this.type === 7) this.skipIf1InventoryList(r);
        if (this.type === 8) this.text = r.gjstr();
        if (this.buttonType === 2 || this.type === 2) { r.gjstr(); r.gjstr(); r.g2(); }
        if (this.buttonType === 1 || this.buttonType === 4 || this.buttonType === 5 || this.buttonType === 6) {
            this.option = r.gjstr();
        }
    }

    private decodeIf3(r: ComponentReader): void {
        this.if3 = true;
        r.g1(); // 0xFF marker
        this.type = r.g1();
        if ((this.type & 0x80) !== 0) {
            this.type &= 0x7F;
            r.gjstr();
        }
        this.contentType = r.g2();
        this.x = r.g2b();
        this.y = r.g2b();
        this.width = r.g2();
        this.height = r.g2();
        r.g1b(); r.g1b(); r.g1b(); r.g1b();
        this.parentId = normalizeParent(r.g2(), this.id);
        this.hidden = r.g1() === 1;

        if (this.type === 0) {
            this.scrollMaxH = r.g2();
            this.scrollMaxV = r.g2();
            r.g1();
        } else if (this.type === 5) {
            this.sprite = r.g4();
            r.g2(); r.g1(); r.g1(); r.g1(); r.g4(); r.g1(); r.g1();
        } else if (this.type === 6) {
            this.modelId = normalizeNullable(r.g2());
            r.g2b(); r.g2b();
            this.modelXAngle = r.g2();
            this.modelYAngle = r.g2();
            r.g2();
            this.modelZoom = r.g2();
            this.modelSeqId = normalizeNullable(r.g2());
            r.g1(); r.g2(); r.g2(); r.g1();
        } else if (this.type === 4) {
            normalizeNullable(r.g2());
            this.text = r.gjstr();
            r.g1(); r.g1(); r.g1(); r.g1();
            this.colour = r.g4();
        } else if (this.type === 3) {
            this.colour = r.g4();
            r.g1(); r.g1();
        } else if (this.type === 9) {
            r.g1();
            this.colour = r.g4();
            r.g1();
        }

        r.g3(); // server active properties
        let key = r.g1();
        while (key !== 0) {
            const slot = (key >> 4) - 1;
            key = (r.g1() | (key << 8)) & 0xFFF;
            if (slot >= 0) this.childIds.push(key === 4095 ? -1 : key);
            r.g1b(); r.g1b();
            key = r.g1();
        }
        this.optionBase = r.gjstr();
        const opMeta = r.g1();
        const opCount = opMeta & 0xF;
        for (let i = 0; i < opCount; i++) this.ops[i] = r.gjstr();
        const triggerCount = opMeta >> 4;
        if (triggerCount > 0) {
            let slot = r.g1();
            for (let i = 0; i <= slot; i++) this.childIds.push(-1);
            this.childIds[slot] = r.g2();
        }
        if (triggerCount > 1) {
            this.childIds[r.g1()] = r.g2();
        }
        r.g1(); r.g1(); r.g1();
        r.gjstr();
        // Target masks may append three shorts. Bounds check keeps this
        // skeleton tolerant if our minimal properties decode misses a flag.
        if (r.pos + 6 <= r.data.length) {
            const save = r.pos;
            const possible = r.g2();
            if (possible !== 65535 && r.pos + 4 <= r.data.length) { r.g2(); r.g2(); }
            else r.pos = save;
        }
        for (let i = 0; i < 18; i++) r.skipObjectArray();
        for (let i = 0; i < 5; i++) r.skipIntArray();
    }

    private skipIf1Inventory(r: ComponentReader): void {
        r.g1(); r.g1(); r.g1(); r.g1(); r.g1(); r.g1();
        for (let i = 0; i < 20; i++) {
            const hasSprite = r.g1();
            if (hasSprite === 1) { r.g2b(); r.g2b(); r.g4(); }
        }
        for (let i = 0; i < 5; i++) this.ops[i] = r.gjstr();
    }

    private skipIf1InventoryList(r: ComponentReader): void {
        r.g1(); normalizeNullable(r.g2()); r.g1(); r.g4(); r.g2b(); r.g2b(); r.g1();
        for (let i = 0; i < 5; i++) this.ops[i] = r.gjstr();
    }
}

function normalizeNullable(value: number): number {
    return value === 65535 ? -1 : value;
}

function normalizeParent(value: number, id: number): number {
    return value === 65535 ? -1 : value + (id & 0xFFFF0000);
}
