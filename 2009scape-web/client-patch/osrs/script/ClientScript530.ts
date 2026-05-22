/**
 * ClientScript530 — minimal CS2 (rev-530 client-script) bytecode interpreter.
 *
 * Source of truth (read-only):
 *   reference/rt4-client/client/src/main/java/rt4/ClientScriptList.java
 *     decode()  — script binary structure, lines ~30-110
 *   reference/rt4-client/client/src/main/java/rt4/ScriptRunner.java
 *     run()     — opcode dispatch loop, lines ~1886+
 *
 * Coverage: this implementation handles the core control-flow and variable
 * opcodes (0..51) plus the basic math/string opcodes (4000..4017, 37). Higher
 * ranges (component manipulation 100-1500, graphics 4100+, etc.) are NOT
 * implemented; encountering them halts the script with a captured trace
 * rather than crashing — sufficient for dialogue branches, varbit-driven UI
 * config, and most interface state scripts. Server-issued RUN_CS2 packets
 * are decoded by PacketHandler530.handleRunCs2 into game.cs2Pending; this
 * module is the consumer.
 */

// ── Script binary structure ──────────────────────────────────────

export interface ClientScript530Data {
    name: string;
    /** Per-instruction opcode (uint16). */
    opcodes: number[];
    /** Per-instruction int operand (signed 32-bit). */
    intOperands: number[];
    /** Per-instruction string operand (only set when opcode === 3). */
    stringOperands: (string | null)[];
    intLocalCount: number;
    stringLocalCount: number;
    intArgCount: number;
    stringArgCount: number;
    /** switch tables: switchTables[tableIndex] is a Map<caseValue, jumpDelta>. */
    switchTables: Array<Map<number, number>>;
}

// ── Reader ────────────────────────────────────────────────────────

class CsReader {
    constructor(public data: Uint8Array, public pos: number = 0) {}
    g1(): number { return this.data[this.pos++] & 0xFF; }
    g2(): number {
        const a = this.data[this.pos++] & 0xFF;
        const b = this.data[this.pos++] & 0xFF;
        return (a << 8) | b;
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

/**
 * Decode a CS2 script blob from cache bytes.
 *
 * Format (rt4 ClientScriptList.decode):
 *   [last-2 bytes]: trailerLen (u2). Header lives at (length - trailerLen - 14).
 *   [header @ trailerPos]:
 *     instructionCount (u4), intLocalCount (u2), stringLocalCount (u2),
 *     intArgCount (u2), stringArgCount (u2), switchCount (u1)
 *   [switch tables, switchCount of them]:
 *     cases (u2), then pairs of (value u4, offset u4)
 *   [body @ 0]:
 *     scriptName (jstr)
 *     repeated until trailerPos: opcode (u2), operand (varies by opcode)
 */
export function decodeClientScript(bytes: Uint8Array): ClientScript530Data | null {
    if (!bytes || bytes.byteLength < 16) return null;
    const trailerLen = ((bytes[bytes.length - 2] & 0xFF) << 8) | (bytes[bytes.length - 1] & 0xFF);
    const headerPos = bytes.length - trailerLen - 14;
    if (headerPos < 0) return null;

    const headerReader = new CsReader(bytes, headerPos);
    const instructionCount = headerReader.g4();
    const intLocalCount = headerReader.g2();
    const stringLocalCount = headerReader.g2();
    const intArgCount = headerReader.g2();
    const stringArgCount = headerReader.g2();
    const switchCount = headerReader.g1();

    const switchTables: Array<Map<number, number>> = [];
    for (let t = 0; t < switchCount; t++) {
        const cases = headerReader.g2();
        const tbl = new Map<number, number>();
        for (let i = 0; i < cases; i++) {
            const value = headerReader.g4();
            const offset = headerReader.g4();
            tbl.set(value, offset);
        }
        switchTables.push(tbl);
    }

    const body = new CsReader(bytes, 0);
    const name = body.gjstr();
    const opcodes: number[] = new Array(instructionCount);
    const intOperands: number[] = new Array(instructionCount);
    const stringOperands: (string | null)[] = new Array(instructionCount);

    let i = 0;
    while (i < instructionCount && body.pos < headerPos) {
        const opcode = body.g2();
        opcodes[i] = opcode;
        if (opcode === 3) {
            stringOperands[i] = body.gjstr();
            intOperands[i] = 0;
        } else {
            stringOperands[i] = null;
            // rt4: opcodes >=100 OR in {21,38,39} use a 1-byte operand.
            if (opcode >= 100 || opcode === 21 || opcode === 38 || opcode === 39) {
                intOperands[i] = body.g1();
            } else {
                intOperands[i] = body.g4();
            }
        }
        i++;
    }
    // Truncate if body ran short of declared instructionCount.
    if (i < instructionCount) {
        opcodes.length = i;
        intOperands.length = i;
        stringOperands.length = i;
    }
    return { name, opcodes, intOperands, stringOperands, intLocalCount, stringLocalCount, intArgCount, stringArgCount, switchTables };
}

// ── VM state ──────────────────────────────────────────────────────

const INT_STACK_SIZE = 1000;
const STR_STACK_SIZE = 1000;
const CALL_STACK_SIZE = 50;
const MAX_CYCLES = 500_000;

interface CallFrame {
    script: ClientScript530Data;
    pc: number;
    intLocals: Int32Array;
    stringLocals: string[];
}

export interface Cs2Result {
    /** "ok" = script returned normally. "halt" = unsupported opcode. "error" = decode/runtime error. */
    status: "ok" | "halt" | "error";
    /** Top-of-stack int (if any). */
    intResult: number | null;
    /** Top-of-stack string (if any). */
    stringResult: string | null;
    /** Cycles used. */
    cycles: number;
    /** Last-seen opcode when halted (for diagnostics). */
    lastOpcode?: number;
    /** Reason for halt/error. */
    reason?: string;
}

/**
 * Lookup hooks the embedder provides for variable reads/writes. All return-int
 * lookups default to 0 when the embedder hook is missing — matches rt4 client
 * behavior of treating unset varps/varbits as 0.
 */
export interface Cs2Hooks {
    getVarp?: (id: number) => number;
    setVarp?: (id: number, value: number) => void;
    getVarbit?: (id: number) => number;
    setVarbit?: (id: number, value: number) => void;
    getVarc?: (id: number) => number;
    setVarc?: (id: number, value: number) => void;
    getVarcString?: (id: number) => string;
    setVarcString?: (id: number, value: string) => void;
    /** Resolves a script id to its decoded ClientScript530Data. Required for opcode 40 (call). */
    loadScript?: (scriptId: number) => ClientScript530Data | null;
    /** Component-by-hash lookup. Required for the 1500/1600 getter range AND direct setters. */
    getComponent?: (hash: number) => Cs2Component | null;
    /** Optional lifecycle hooks for IF3 runtime-created children (opcodes 100-102). */
    createComponent?: (parentHash: number, type: number, childIndex: number, parent: Cs2Component) => Cs2Component | null;
    deleteComponent?: (component: Cs2Component, parent: Cs2Component | null) => void;
    deleteComponentChildren?: (parentHash: number, parent: Cs2Component) => void;
    /** Item-def lookup. Required for the 4200 range. */
    getItem?: (id: number) => Cs2Item | null;
    /** Player gender (0 = male, 1 = female). Required for opcode 4105. */
    getPlayerGender?: () => number;
    /** Skill stats lookup. Required for the 3305-3307 range. */
    getSkill?: (skillId: number) => Cs2Skill | null;
    /** Player run-energy / weight. Required for 3321-3322. */
    getRunEnergy?: () => number;
    getPlayerWeight?: () => number;
    getClientCycle?: () => number;
    getMyLocation?: () => number;
    isMembers?: () => boolean;
    getClientRights?: () => number;
    getSystemUpdateTimer?: () => number;
    getWorldId?: () => number;
    getBlackmarks?: () => number;
    getCombatLevel?: () => number;
    isMapQuickChat?: () => boolean;
    getLoginType?: () => number;
    getLanguage?: () => number;
    getAffiliate?: () => number;
    getEnum?: (enumId: number) => Cs2Enum | null;
    /** Container query. Required for 3303-3304, 3330-3332. */
    getContainer?: (containerId: number) => Cs2Container | null;
    /** NPC attribute. Required for 4300. */
    getNpcAttribute?: (npcId: number, attrId: number) => number | string | null;
    /** Item attribute. Required for 4208. */
    getItemAttribute?: (itemId: number, attrId: number) => number | string | null;
    /** Loc / Struct param lookup (4400 / 4500). */
    getLocParam?: (locId: number, paramId: number) => number | string | null;
    getStructParam?: (structId: number, paramId: number) => number | string | null;
    /** Item search hooks (4210/4211/4212). */
    searchItem?: (query: string, exact: number) => number;
    nextSearchResult?: () => number;
    resetSearch?: () => void;
    /** Friend / ignore / clan hooks (rt4 3600-3629 range). */
    getFriendListState?: () => number;
    getFriendCount?: () => number;
    getFriend?: (index: number) => Cs2Friend | null;
    getFriendIndex?: (name: string) => number;
    isFriend?: (name: string) => boolean;
    getIgnoreCount?: () => number;
    getIgnoreName?: (index: number) => string;
    isIgnored?: (name: string) => boolean;
    getClan?: () => Cs2Clan | null;
    getSelfName?: () => string;
    getCountry?: () => number;
    getGrandExchangeOffer?: (slot: number) => Cs2GrandExchangeOffer | null;
    getPublicChatSetting?: () => number;
    getPrivateChatSetting?: () => number;
    getTradeSetting?: () => number;
    setChatSettings?: (publicFilter: number, privateFilter: number, tradeFilter: number) => void;
    getChatMessage?: (index: number) => Cs2ChatMessage | null;
    getChatSize?: () => number;
    isKeyHeld?: (key: "alt" | "ctrl" | "shift") => boolean;
    getCurrentTimeMillis?: () => number;
    getDisplayModeCount?: () => number;
    getDisplayMode?: (index: number) => Cs2DisplayMode | null;
    getPreferredFullscreenMode?: () => number;
    requestFullscreen?: (width: number, height: number) => boolean;
    exitFullscreen?: () => void;
    getWindowMode?: () => number;
    setWindowMode?: (mode: number) => void;
    getPreferredWindowMode?: () => number;
    setPreferredWindowMode?: (mode: number) => void;
    setPreference?: (key: string, value: number) => number | void;
    getPreference?: (key: string) => number;
    setViewport?: (key: "near" | "far" | "clamp", values: number[]) => void;
    getViewport?: (key: "near" | "far" | "size") => number[];
    moveCameraTo?: (coord: number, height: number, speed: number, acceleration: number) => void;
    pointCameraAt?: (coord: number, height: number, speed: number, acceleration: number) => void;
    setCameraPath?: (values: number[]) => void;
    unlockCamera?: () => void;
    setCameraRotation?: (pitch: number, yaw: number) => void;
    getCameraRotation?: () => Cs2CameraRotation;
    requestDirectLogin?: (username: string, password: string, flags: number) => void;
    skipLoginStage?: () => void;
    resetLoginReply?: () => void;
    checkAccountInfo?: (a: number, b: number, c: number, d: number) => void;
    requestAccountName?: (name: string) => void;
    createAccount?: (username: string, password: string, a: number, b: number, c: number, d: number) => void;
    resetAccountCreateReply?: () => void;
    getGameLoginReply?: () => number;
    getWorldSwitchTimer?: () => number;
    getAccountCreateReply?: () => number;
    getSuggestedAccountNames?: () => string[];
    clearSuggestedAccountNames?: () => void;
    getDetailedLoginReply?: () => number;
    canShowVideoAd?: () => boolean;
    isShowingVideoAd?: () => boolean;
    fetchWorldList?: () => boolean;
    getFirstWorld?: () => Cs2World | null;
    getNextWorld?: () => Cs2World | null;
    hopWorld?: (worldId: number) => boolean;
    setLastWorld?: (worldId: number) => void;
    getLastWorld?: () => number;
    getWorldById?: (worldId: number) => Cs2World | null;
    sortWorldList?: (primaryKey: number, primaryAscending: boolean, secondaryKey: number, secondaryAscending: boolean) => void;
    setSiteSettingsMembers?: (members: boolean) => void;
    isSiteSettingsMembers?: () => boolean;
    setPlayerIdentikit?: (featureId: number, identikit: number) => void;
    setPlayerColor?: (slot: number, color: number) => void;
    setPlayerGender?: (female: boolean) => void;
    hasOpenInterface?: (parentId: number) => boolean;
    hasChildInterface?: (parentId: number, interfaceId: number) => boolean;
    measureTextLineCount?: (text: string, width: number, fontId: number) => number;
    measureTextMaxLineWidth?: (text: string, width: number, fontId: number) => number;
    addGameMessage?: (message: string) => void;
    animateSelf?: (seqId: number, delay: number) => void;
    closeWidgets?: () => void;
    resumeIntegerInput?: (value: number) => void;
    resumeNameInput?: (name: string) => void;
    resumeStringInput?: (value: string) => void;
    clickPlayerOption?: (option: string, playerIndex: number) => void;
    runWidgetAction?: (arg0: number, arg1: number, component: Cs2Component | null) => void;
    sendDialogAction?: (componentId: number) => void;
    playSoundEffect?: (soundId: number, loops: number, delay: number) => void;
    playMusic?: (songId: number) => void;
    playMusicEffect?: (jingleId: number, delay: number) => void;
}

export interface Cs2Skill {
    currentLevel: number;
    actualLevel: number;
    xp: number;
}

export interface Cs2Container {
    /** Per-slot item id. -1 = empty. */
    items: number[];
    /** Per-slot count. 0 = empty. */
    amounts: number[];
    /** Total slots in this container (capacity). */
    capacity: number;
}

export interface Cs2Enum {
    keyType: number;
    valueType: number;
    defaultString: string;
    defaultInt: number;
    intToString?: Map<number, string> | null;
    intToInt?: Map<number, number> | null;
}

export interface Cs2Friend {
    name: string;
    world: number;
    rank: number;
    worldName?: string;
    sameGame?: boolean;
}

export interface Cs2ClanMember {
    name: string;
    world: number;
    rank: number;
    worldName?: string;
}

export interface Cs2Clan {
    name: string;
    owner?: string;
    rank?: number;
    minKick?: number;
    members: Cs2ClanMember[];
}

export interface Cs2GrandExchangeOffer {
    type: number;
    status: number;
    item: number;
    price: number;
    count: number;
    completedCount: number;
    completedGold: number;
}

export interface Cs2ChatMessage {
    type: number;
    name: string;
    message: string;
    clan?: string;
    phraseId?: number;
}

export interface Cs2DisplayMode {
    width: number;
    height: number;
}

export interface Cs2CameraRotation {
    pitch: number;
    yaw: number;
}

export interface Cs2World {
    id: number;
    flags: number;
    activity: string;
    countryFlag: number;
    countryName: string;
    players: number;
}

/** The shape of a component the getters in the 1500/1600 range read AND the setters mutate. */
export interface Cs2Component {
    x: number; y: number; width: number; height: number;
    hidden: boolean;
    id?: number; type?: number; if3?: boolean; createdComponentId?: number;
    overlayer?: number; parentId?: number;
    createdComponents?: (Cs2Component | null)[];
    scrollPos?: number; scrollPosX?: number;
    text?: string | null;
    layer?: number;
    // Mutable fields the setters write back into:
    colour?: number; alpha?: number;
    baseX?: number; baseY?: number; baseWidth?: number; baseHeight?: number;
    xMode?: number; yMode?: number; widthMode?: number; heightMode?: number;
    aspectWidth?: number; aspectHeight?: number; noClickThrough?: boolean;
    filled?: boolean; lineWidth?: number; spriteTiling?: boolean; hasAlpha?: boolean;
    sprite?: number; spriteAngle?: number; spriteHFlip?: boolean; spriteVFlip?: boolean;
    modelId?: number; modelType?: number; modelSeqId?: number; modelOrtho?: boolean;
    modelXOffset?: number; modelYOffset?: number; modelZOffset?: number;
    modelXAngle?: number; modelYAngle?: number; modelZoom?: number;
    objId?: number; objCount?: number; objDrawText?: boolean;
    draggableComponent?: number | null; dragRenderBehavior?: boolean; dragDeadZone?: number; dragDeadTime?: number;
    targetVerb?: string | null; optionBase?: string | null; options?: (string | null)[]; ops?: (string | null)[];
    font?: number; horizontalAlignment?: number; verticalAlignment?: number; textShadowed?: boolean;
    scrollMaxH?: number; scrollMaxV?: number;
    spriteOutline?: number; spriteShadow?: number;
}

/** The shape of an item-def the 4200 range reads. */
export interface Cs2Item {
    name: string;
    cost: number;
    isStackable?: boolean;
    isMembers?: boolean;
    notedId?: number;
    realId?: number;
    groundOptions?: (string | null)[];
    inventoryOptions?: (string | null)[];
}

function normalizeSocialName(name: string): string {
    return (name || "")
        .replace(/^@cr\d+@/i, "")
        .replace(/^<img=\d+>/i, "")
        .trim()
        .toLowerCase();
}

export function runClientScript(
    script: ClientScript530Data,
    args: any[],
    hooks: Cs2Hooks = {},
): Cs2Result {
    const intStack = new Int32Array(INT_STACK_SIZE);
    const stringStack: string[] = new Array(STR_STACK_SIZE);
    let isp = 0;
    let ssp = 0;
    const callStack: CallFrame[] = [];

    // Push args onto the appropriate locals (rt4 convention: int args first, then string args).
    let frame = newFrame(script);
    let intArgIdx = 0;
    let strArgIdx = 0;
    for (const arg of args) {
        if (typeof arg === "string") {
            if (strArgIdx < script.stringArgCount) frame.stringLocals[strArgIdx++] = arg;
        } else {
            if (intArgIdx < script.intArgCount) frame.intLocals[intArgIdx++] = arg | 0;
        }
    }

    // rt4 ScriptRunner has two static active-component slots. Most component
    // opcodes select slot 1 when their byte operand is 1, otherwise slot 2.
    let activeComponent1: Cs2Component | null = null;
    let activeComponent2: Cs2Component | null = null;
    let activeComponent: Cs2Component | null = null;
    /** Per-VM-instance arrays. opcode 44 initializes; 45/46 read/write. */
    const arrays: Map<number, Int32Array> = new Map();

    let cycles = 0;
    let lastOpcode = -1;
    while (cycles < MAX_CYCLES) {
        cycles++;
        if (frame.pc >= frame.script.opcodes.length) {
            return finalize("ok", null);
        }
        const opcode = frame.script.opcodes[frame.pc];
        const intArg = frame.script.intOperands[frame.pc];
        const stringArg = frame.script.stringOperands[frame.pc];
        lastOpcode = opcode;
        frame.pc++;
        activeComponent = intArg === 1 ? activeComponent1 : activeComponent2;

        switch (opcode) {
            // ── Push / pop ──
            case 0: intStack[isp++] = intArg; break;                                    // PUSH_CONSTANT_INT
            case 3: stringStack[ssp++] = stringArg ?? ""; break;                         // PUSH_CONSTANT_STRING
            case 33: intStack[isp++] = frame.intLocals[intArg]; break;                  // PUSH_INT_LOCAL
            case 34: frame.intLocals[intArg] = intStack[--isp]; break;                  // SET_INT_LOCAL
            case 35: stringStack[ssp++] = frame.stringLocals[intArg] ?? ""; break;       // PUSH_STRING_LOCAL
            case 36: frame.stringLocals[intArg] = stringStack[--ssp]; break;             // SET_STRING_LOCAL
            case 38: --isp; break;                                                       // POP_INT
            case 39: --ssp; break;                                                       // POP_STRING

            // ── Branches ──
            case 6: frame.pc += intArg; break;                                           // JUMP
            case 7: { const b = intStack[--isp]; const a = intStack[--isp]; if (a !== b) frame.pc += intArg; break; }
            case 8: { const b = intStack[--isp]; const a = intStack[--isp]; if (a === b) frame.pc += intArg; break; }
            case 9: { const b = intStack[--isp]; const a = intStack[--isp]; if (a < b)  frame.pc += intArg; break; }
            case 10:{ const b = intStack[--isp]; const a = intStack[--isp]; if (a > b)  frame.pc += intArg; break; }
            case 31:{ const b = intStack[--isp]; const a = intStack[--isp]; if (a >= b) frame.pc += intArg; break; }
            case 32:{ const b = intStack[--isp]; const a = intStack[--isp]; if (a <= b) frame.pc += intArg; break; }

            // ── Vars ──
            case 1:  intStack[isp++] = (hooks.getVarp?.(intArg) ?? 0) | 0; break;
            case 2:  hooks.setVarp?.(intArg, intStack[--isp]); break;
            case 25: intStack[isp++] = (hooks.getVarbit?.(intArg) ?? 0) | 0; break;
            case 27: hooks.setVarbit?.(intArg, intStack[--isp]); break;
            case 42: intStack[isp++] = (hooks.getVarc?.(intArg) ?? 0) | 0; break;
            case 43: hooks.setVarc?.(intArg, intStack[--isp]); break;
            case 47: stringStack[ssp++] = hooks.getVarcString?.(intArg) ?? ""; break;
            case 48: hooks.setVarcString?.(intArg, stringStack[--ssp]); break;

            // ── Control flow ──
            case 21: { // RETURN
                if (callStack.length === 0) return finalize("ok", null);
                frame = callStack.pop()!;
                break;
            }
            case 40: { // CALL_SCRIPT
                if (!hooks.loadScript) return finalize("halt", "loadScript hook missing for CALL_SCRIPT");
                const sub = hooks.loadScript(intArg);
                if (!sub) return finalize("halt", `script ${intArg} not found`);
                if (callStack.length >= CALL_STACK_SIZE) return finalize("error", "call stack overflow");
                callStack.push(frame);
                frame = newFrame(sub);
                // Pop sub's args off the stacks (int args first, then string).
                for (let i = sub.intArgCount - 1; i >= 0; i--) frame.intLocals[i] = intStack[--isp];
                for (let i = sub.stringArgCount - 1; i >= 0; i--) frame.stringLocals[i] = stringStack[--ssp];
                break;
            }
            case 51: { // SWITCH_LOOKUP
                const key = intStack[--isp];
                const tbl = frame.script.switchTables[intArg];
                const delta = tbl ? tbl.get(key) : undefined;
                if (delta !== undefined) frame.pc += delta;
                break;
            }

            // ── Strings ──
            case 37: { // CONCAT_STRINGS — operand is the count of strings to concat
                const count = intArg;
                let s = "";
                const base = ssp - count;
                for (let i = 0; i < count; i++) s += stringStack[base + i] ?? "";
                ssp = base;
                stringStack[ssp++] = s;
                break;
            }

            // ── Math (rt4 4000-range) ──
            case 4000: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = (a + b) | 0; break; }
            case 4001: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = (a - b) | 0; break; }
            case 4002: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = Math.imul(a, b); break; }
            case 4003: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = b === 0 ? 0 : (a / b) | 0; break; }
            case 4004: { const a = intStack[--isp]; intStack[isp++] = a <= 0 ? 0 : (Math.random() * a) | 0; break; }
            case 4005: { const a = intStack[--isp]; intStack[isp++] = a < 0 ? 0 : (Math.random() * (a + 1)) | 0; break; }
            case 4006: { // LINEAR_INTERPOLATE: a + (b-a)*(x-x0)/(x1-x0)
                const x = intStack[--isp];
                const x1 = intStack[--isp];
                const x0 = intStack[--isp];
                const b = intStack[--isp];
                const a = intStack[--isp];
                intStack[isp++] = x1 === x0 ? a : (((b - a) * (x - x0)) / (x1 - x0) + a) | 0;
                break;
            }
            case 4007: { const percent = intStack[--isp]; const base = intStack[--isp]; intStack[isp++] = ((base * percent) / 100 + base) | 0; break; }
            case 4008: { const bit = intStack[--isp]; const value = intStack[--isp]; intStack[isp++] = (value | (1 << bit)) | 0; break; }
            case 4009: { const bit = intStack[--isp]; const value = intStack[--isp]; intStack[isp++] = (value & ~(1 << bit)) | 0; break; }
            case 4010: { const bit = intStack[--isp]; const value = intStack[--isp]; intStack[isp++] = (value & (1 << bit)) === 0 ? 0 : 1; break; }
            case 4011: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = b === 0 ? 0 : (a % b) | 0; break; }
            case 4012: { const exp = intStack[--isp]; const base = intStack[--isp]; intStack[isp++] = base === 0 ? 0 : Math.pow(base, exp) | 0; break; }
            case 4013: {
                const root = intStack[--isp];
                const value = intStack[--isp];
                intStack[isp++] = value === 0 ? 0 : root === 0 ? 2147483647 : Math.pow(value, 1 / root) | 0;
                break;
            }
            case 4014: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = (a & b) | 0; break; }
            case 4015: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = (a | b) | 0; break; }
            case 4016: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = Math.min(a, b) | 0; break; }
            case 4017: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = Math.max(a, b) | 0; break; }
            case 4018: { const scale = intStack[--isp]; const divisor = intStack[--isp]; const value = intStack[--isp]; intStack[isp++] = divisor === 0 ? 0 : ((value * scale) / divisor) | 0; break; }

            // ── Strings (rt4 4100-range) ──
            case 4100: { // CONCAT_INT: pop int → push string
                const i = intStack[--isp];
                const s = stringStack[--ssp] ?? "";
                stringStack[ssp++] = s + String(i);
                break;
            }
            case 4101: { // CONCAT_STRING: alias for opcode 37(2)
                const b = stringStack[--ssp] ?? "";
                const a = stringStack[--ssp] ?? "";
                stringStack[ssp++] = a + b;
                break;
            }
            case 4102: { // CONCAT_SIGNED_INT: pop int with formatted sign
                const i = intStack[--isp];
                const s = stringStack[--ssp] ?? "";
                stringStack[ssp++] = s + (i >= 0 ? `+${i}` : String(i));
                break;
            }
            case 4103: { // TO_LOWER_STR
                const s = stringStack[--ssp] ?? "";
                stringStack[ssp++] = s.toLowerCase();
                break;
            }
            case 4104: { // TIME_TO_STR: days since rt4 epoch → "d-MMM-yyyy"
                const days = intStack[--isp];
                const date = new Date(days * 86_400_000 + 1_014_768_000_000);
                const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
                stringStack[ssp++] = `${date.getUTCDate()}-${months[date.getUTCMonth()]}-${date.getUTCFullYear()}`;
                break;
            }
            case 4105: { // STR_FOR_GENDER
                const female = stringStack[--ssp] ?? "";
                const male = stringStack[--ssp] ?? "";
                stringStack[ssp++] = hooks.getPlayerGender?.() === 1 ? female : male;
                break;
            }
            case 4106: { // PARSE_INT: int → string of int (rt4 oddly named)
                const i = intStack[--isp];
                stringStack[ssp++] = String(i);
                break;
            }
            case 4107: { // COMPARE: pop two strings, push compare result
                const b = stringStack[--ssp] ?? "";
                const a = stringStack[--ssp] ?? "";
                intStack[isp++] = a < b ? -1 : a > b ? 1 : 0;
                break;
            }
            case 4108: { // GET_LINE_COUNT: pop string, width, font id
                const fontId = intStack[--isp];
                const width = intStack[--isp];
                const text = stringStack[--ssp] ?? "";
                intStack[isp++] = hooks.measureTextLineCount?.(text, width, fontId) ?? estimateLineCount(text, width);
                break;
            }
            case 4109: { // GET_MAX_LINE_WIDTH: pop string, width, font id
                const fontId = intStack[--isp];
                const width = intStack[--isp];
                const text = stringStack[--ssp] ?? "";
                intStack[isp++] = hooks.measureTextMaxLineWidth?.(text, width, fontId) ?? estimateMaxLineWidth(text, width);
                break;
            }
            case 4110: { // CHOOSE_STRING
                const s2 = stringStack[--ssp] ?? "";
                const s1 = stringStack[--ssp] ?? "";
                const cond = intStack[--isp];
                stringStack[ssp++] = cond !== 0 ? s1 : s2;
                break;
            }
            case 4111: { // ESCAPE
                const s = stringStack[--ssp] ?? "";
                let out = "";
                for (let i = 0; i < s.length; i++) {
                    const ch = s.charAt(i);
                    out += ch === "<" ? "<lt>" : ch === ">" ? "<gt>" : ch;
                }
                stringStack[ssp++] = out;
                break;
            }
            case 4112: { // CONCAT_CHAR
                const code = intStack[--isp];
                const s = stringStack[--ssp] ?? "";
                stringStack[ssp++] = s + String.fromCharCode(code);
                break;
            }
            case 4113: { // IS_VALID_CHAR
                const code = intStack[--isp];
                intStack[isp++] = (code >= 32 && code <= 126) ? 1 : 0;
                break;
            }
            case 4114: { // IS_ALPHANUMERIC
                const code = intStack[--isp];
                intStack[isp++] = ((code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122)) ? 1 : 0;
                break;
            }
            case 4115: { // IS_LETTER
                const code = intStack[--isp];
                intStack[isp++] = ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) ? 1 : 0;
                break;
            }
            case 4116: { // IS_DIGIT
                const code = intStack[--isp];
                intStack[isp++] = (code >= 48 && code <= 57) ? 1 : 0;
                break;
            }
            case 4117: { // LENGTH
                const s = stringStack[--ssp] ?? "";
                intStack[isp++] = s.length;
                break;
            }
            case 4118: { // SUBSTR
                const end = intStack[--isp];
                const start = intStack[--isp];
                const s = stringStack[--ssp] ?? "";
                const a = Math.max(0, Math.min(s.length, start));
                const b = Math.max(a, Math.min(s.length, end));
                stringStack[ssp++] = s.substring(a, b);
                break;
            }
            case 4119: { // REMOVE_TAGS
                const s = stringStack[--ssp] ?? "";
                stringStack[ssp++] = s.replace(/<[^>]*>/g, "");
                break;
            }
            case 4120: { // INDEX_OF_CHAR
                const startIdx = intStack[--isp];
                const code = intStack[--isp];
                const s = stringStack[--ssp] ?? "";
                intStack[isp++] = s.indexOf(String.fromCharCode(code), Math.max(0, startIdx));
                break;
            }
            case 4121: { // INDEX_OF_STR
                const startIdx = intStack[--isp];
                const needle = stringStack[--ssp] ?? "";
                const s = stringStack[--ssp] ?? "";
                intStack[isp++] = s.indexOf(needle, Math.max(0, startIdx));
                break;
            }
            case 4122: { // TO_LOWER (char)
                const code = intStack[--isp];
                intStack[isp++] = (code >= 65 && code <= 90) ? code + 32 : code;
                break;
            }
            case 4123: { // TO_UPPER (char)
                const code = intStack[--isp];
                intStack[isp++] = (code >= 97 && code <= 122) ? code - 32 : code;
                break;
            }
            case 4124: { // FORMAT_NUMBER (commas every 3 digits)
                const flag = intStack[--isp]; void flag;
                const value = intStack[--isp];
                stringStack[ssp++] = String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
                break;
            }

            // ── Items (rt4 4200-range) ──
            case 4200: { // GET_ITEM_NAME
                const id = intStack[--isp];
                stringStack[ssp++] = hooks.getItem?.(id)?.name ?? "";
                break;
            }
            case 4201: { // GET_ITEM_GROUND_OPTION
                const optIdx = intStack[--isp];
                const id = intStack[--isp];
                stringStack[ssp++] = hooks.getItem?.(id)?.groundOptions?.[optIdx] ?? "";
                break;
            }
            case 4202: { // GET_ITEM_OPTION (inventory)
                const optIdx = intStack[--isp];
                const id = intStack[--isp];
                stringStack[ssp++] = hooks.getItem?.(id)?.inventoryOptions?.[optIdx] ?? "";
                break;
            }
            case 4203: { // GET_ITEM_VALUE (cost)
                const id = intStack[--isp];
                intStack[isp++] = hooks.getItem?.(id)?.cost ?? 0;
                break;
            }
            case 4204: { // ITEM_IS_STACKABLE
                const id = intStack[--isp];
                intStack[isp++] = hooks.getItem?.(id)?.isStackable ? 1 : 0;
                break;
            }
            case 4205: { // GET_NOTED_ITEM
                const id = intStack[--isp];
                intStack[isp++] = hooks.getItem?.(id)?.notedId ?? id;
                break;
            }
            case 4206: { // GET_REAL_ITEM
                const id = intStack[--isp];
                intStack[isp++] = hooks.getItem?.(id)?.realId ?? id;
                break;
            }
            case 4207: { // ITEM_IS_MEMBERS
                const id = intStack[--isp];
                intStack[isp++] = hooks.getItem?.(id)?.isMembers ? 1 : 0;
                break;
            }
            case 4208: { // GET_ITEM_ATTRIBUTE
                const attrId = intStack[--isp];
                const itemId = intStack[--isp];
                const v = hooks.getItemAttribute?.(itemId, attrId);
                if (typeof v === "string") stringStack[ssp++] = v;
                else intStack[isp++] = (v as number) | 0;
                break;
            }

            // ── Arrays (rt4 44-46) ──
            case 44: { // INITIALIZE_ARRAY: high16=array id, low16=default fill type
                const length = intStack[--isp];
                const arrId = (intArg >>> 16) & 0xFFFF;
                const fillType = intArg & 0xFFFF;
                if (length < 0 || length > 5000) return finalize("error", `invalid array length ${length}`);
                const arr = new Int32Array(length);
                if (fillType !== 105) arr.fill(-1);
                arrays.set(arrId, arr);
                break;
            }
            case 45: { // READ_ARRAY: pop index → push array[id][index]
                const index = intStack[--isp];
                const arr = arrays.get(intArg);
                intStack[isp++] = (arr && index >= 0 && index < arr.length) ? arr[index] : 0;
                break;
            }
            case 46: { // WRITE_ARRAY: pop value, pop index → array[id][index] = value
                const value = intStack[--isp];
                const index = intStack[--isp];
                const arr = arrays.get(intArg);
                if (arr && index >= 0 && index < arr.length) arr[index] = value | 0;
                break;
            }

            // ── Character design opcodes (rt4 403/404/410) ──
            case 403: { // SET_BASE_IDKIT: pop feature id, identikit id
                const identikit = intStack[--isp];
                const featureId = intStack[--isp];
                hooks.setPlayerIdentikit?.(featureId, identikit);
                break;
            }
            case 404: { // SET_BASE_COLOR: pop color slot, color index
                const color = intStack[--isp];
                const slot = intStack[--isp];
                hooks.setPlayerColor?.(slot, color);
                break;
            }
            case 410: { // SET_FEMALE
                hooks.setPlayerGender?.(intStack[--isp] !== 0);
                break;
            }

            // ── IF3 component lifecycle (rt4 100-102). ──
            case 100: { // CC_CREATE — pop parent hash, type, child index
                const childIndex = intStack[--isp];
                const type = intStack[--isp];
                const parentHash = intStack[--isp];
                if (type === 0) return finalize("error", "cannot create component with type 0");
                if (childIndex < 0) return finalize("error", `invalid child index ${childIndex}`);
                const parent = hooks.getComponent?.(parentHash) ?? null;
                if (!parent) return finalize("error", `component ${parentHash} not found`);
                if (!parent.createdComponents) parent.createdComponents = [];
                while (parent.createdComponents.length <= childIndex) parent.createdComponents.push(null);
                if (childIndex > 0 && !parent.createdComponents[childIndex - 1]) {
                    return finalize("error", `gap at child index ${childIndex - 1}`);
                }
                const created = hooks.createComponent?.(parentHash, type, childIndex, parent) ?? {
                    x: 0,
                    y: 0,
                    width: 0,
                    height: 0,
                    hidden: false,
                    text: "",
                    id: parentHash,
                    overlayer: parentHash,
                    parentId: parentHash,
                    layer: parentHash,
                    type: type | 0,
                    if3: true,
                    createdComponentId: childIndex | 0,
                };
                parent.createdComponents[childIndex] = created;
                activeComponent = created;
                if (intArg === 1) activeComponent1 = created;
                else activeComponent2 = created;
                break;
            }
            case 101: { // CC_DELETE — delete selected active created child
                const selected = intArg === 1 ? activeComponent1 : activeComponent2;
                if (!selected) return finalize("error", "no active component to delete");
                const childIndex = selected.createdComponentId ?? -1;
                if (childIndex === -1) return finalize("error", "tried to delete a static active component");
                const parentHash = selected.id ?? selected.parentId ?? selected.layer ?? 0;
                const parent = hooks.getComponent?.(parentHash) ?? null;
                if (parent?.createdComponents && childIndex >= 0 && childIndex < parent.createdComponents.length) {
                    parent.createdComponents[childIndex] = null;
                }
                hooks.deleteComponent?.(selected, parent);
                if (intArg === 1) activeComponent1 = null;
                else activeComponent2 = null;
                activeComponent = null;
                break;
            }
            case 102: { // CC_DELETEALL — pop parent hash, clear runtime children
                const parentHash = intStack[--isp];
                const parent = hooks.getComponent?.(parentHash) ?? null;
                if (parent) {
                    parent.createdComponents = undefined;
                    hooks.deleteComponentChildren?.(parentHash, parent);
                }
                break;
            }

            // ── Active-component setters (rt4 200-201) ──
            case 200: { // setChild — pop interfaceId+childId, look up, set active, push success flag
                const childId = intStack[--isp];
                const interfaceId = intStack[--isp];
                if (childId === -1) {
                    if (intArg === 1) activeComponent1 = null;
                    else activeComponent2 = null;
                    intStack[isp++] = 0;
                } else {
                    const hash = (interfaceId << 16) | (childId & 0xFFFF);
                    activeComponent = hooks.getComponent?.(hash) ?? null;
                    if (intArg === 1) activeComponent1 = activeComponent;
                    else activeComponent2 = activeComponent;
                    intStack[isp++] = activeComponent ? 1 : 0;
                }
                break;
            }
            case 201: { // setChild2 — pop component hash, set active, push success
                const hash = intStack[--isp];
                activeComponent = hooks.getComponent?.(hash) ?? null;
                if (intArg === 1) activeComponent1 = activeComponent;
                else activeComponent2 = activeComponent;
                intStack[isp++] = activeComponent ? 1 : 0;
                break;
            }

            // ── Component setters (rt4 1000-1120). Mutate the active component. ──
            case 1000:
            case 2000: { // SET_POSITION: pop yMode, xMode, y, x
                const c = getSetterComponent(opcode);
                const yMode = intStack[--isp];
                const xMode = intStack[--isp];
                const y = intStack[--isp];
                const x = intStack[--isp];
                if (c) {
                    c.baseX = x | 0;
                    c.baseY = y | 0;
                    c.x = x | 0;
                    c.y = y | 0;
                    c.xMode = xMode | 0;
                    c.yMode = yMode | 0;
                }
                break;
            }
            case 1001:
            case 2001: { // SET_SIZE: pop hMode, wMode, h, w
                const c = getSetterComponent(opcode);
                const hMode = intStack[--isp];
                const wMode = intStack[--isp];
                const h = intStack[--isp];
                const w = intStack[--isp];
                if (c) {
                    c.baseWidth = w | 0;
                    c.baseHeight = h | 0;
                    c.width = w | 0;
                    c.height = h | 0;
                    c.widthMode = wMode | 0;
                    c.heightMode = hMode | 0;
                }
                break;
            }
            case 1004:
            case 2004: { // SET_ASPECT: pop h, w
                const c = getSetterComponent(opcode);
                const h = intStack[--isp];
                const w = intStack[--isp];
                if (c) {
                    c.aspectWidth = w | 0;
                    c.aspectHeight = h | 0;
                }
                break;
            }
            case 1003:
            case 2003: { // SET_HIDDEN
                const c = getSetterComponent(opcode);
                const hidden = intStack[--isp];
                if (c) c.hidden = hidden !== 0;
                break;
            }
            case 1005:
            case 2005: { // SET_NO_CLICK_THROUGH
                const c = getSetterComponent(opcode);
                const noClickThrough = intStack[--isp];
                if (c) c.noClickThrough = noClickThrough !== 0;
                break;
            }
            case 1100:
            case 2100: { // SET_SCROLL_POS — pop x, y
                const c = getSetterComponent(opcode);
                const y = intStack[--isp];
                const x = intStack[--isp];
                if (c) {
                    const maxX = Math.max(0, (c.scrollMaxH ?? x) - c.width);
                    const maxY = Math.max(0, (c.scrollMaxV ?? y) - c.height);
                    c.scrollPosX = Math.max(0, Math.min(maxX, x));
                    c.scrollPos = Math.max(0, Math.min(maxY, y));
                }
                break;
            }
            case 1101:
            case 2101: { // SET_RGB
                const c = getSetterComponent(opcode);
                const colour = intStack[--isp];
                if (c) c.colour = colour | 0;
                break;
            }
            case 1102:
            case 2102: { // SET_FILLED
                const c = getSetterComponent(opcode);
                const filled = intStack[--isp];
                if (c) c.filled = filled === 1;
                break;
            }
            case 1103:
            case 2103: { // SET_TRANS
                const c = getSetterComponent(opcode);
                const alpha = intStack[--isp];
                if (c) c.alpha = alpha | 0;
                break;
            }
            case 1104:
            case 2104: { // SET_LINE_WIDTH
                const c = getSetterComponent(opcode);
                const lineWidth = intStack[--isp];
                if (c) c.lineWidth = lineWidth | 0;
                break;
            }
            case 1105:
            case 2105: { // SET_SPRITE
                const c = getSetterComponent(opcode);
                const sprite = intStack[--isp];
                if (c) c.sprite = sprite | 0;
                break;
            }
            case 1106:
            case 2106: { // SET_2D_ANGLE
                const c = getSetterComponent(opcode);
                const angle = intStack[--isp];
                if (c) c.spriteAngle = angle | 0;
                break;
            }
            case 1107:
            case 2107: { // SET_SPRITE_TILING
                const c = getSetterComponent(opcode);
                const tiling = intStack[--isp];
                if (c) c.spriteTiling = tiling === 1;
                break;
            }
            case 1108:
            case 2108: { // SET_MODEL
                const c = getSetterComponent(opcode);
                const modelId = intStack[--isp];
                if (c) {
                    c.modelType = 1;
                    c.modelId = modelId | 0;
                }
                break;
            }
            case 1109:
            case 2109: { // SET_3D_ROTATION: pop zoom, yOffset, yAngle, xAngle, zOffset, xOffset
                const c = getSetterComponent(opcode);
                const zoom = intStack[--isp];
                const yOffset = intStack[--isp];
                const yAngle = intStack[--isp];
                const xAngle = intStack[--isp];
                const zOffset = intStack[--isp];
                const xOffset = intStack[--isp];
                if (c) {
                    c.modelXOffset = xOffset | 0;
                    c.modelZOffset = zOffset | 0;
                    c.modelXAngle = xAngle | 0;
                    c.modelYAngle = yAngle | 0;
                    c.modelYOffset = yOffset | 0;
                    c.modelZoom = zoom | 0;
                }
                break;
            }
            case 1110:
            case 2110: { // SET_ANIMATION
                const c = getSetterComponent(opcode);
                const animId = intStack[--isp];
                if (c) c.modelSeqId = animId | 0;
                break;
            }
            case 1111:
            case 2111: { // SET_MODEL_ORTHOG
                const c = getSetterComponent(opcode);
                const ortho = intStack[--isp];
                if (c) c.modelOrtho = ortho === 1;
                break;
            }
            case 1112:
            case 2112: { // SET_TEXT
                const c = getSetterComponent(opcode);
                const text = stringStack[--ssp] ?? "";
                if (c) c.text = text;
                break;
            }
            case 1113:
            case 2113: { // SET_FONT
                const c = getSetterComponent(opcode);
                const fontId = intStack[--isp];
                if (c) c.font = fontId | 0;
                break;
            }
            case 1114:
            case 2114: { // SET_TEXT_ALIGNMENT — pop halign, valign, vpad
                const c = getSetterComponent(opcode);
                const vpad = intStack[--isp]; void vpad;
                const valign = intStack[--isp];
                const halign = intStack[--isp];
                if (c) {
                    c.horizontalAlignment = halign | 0;
                    c.verticalAlignment = valign | 0;
                }
                break;
            }
            case 1115:
            case 2115: { // SET_TEXT_ANTI_MACRO (shadowed)
                const c = getSetterComponent(opcode);
                const shadowed = intStack[--isp];
                if (c) c.textShadowed = shadowed !== 0;
                break;
            }
            case 1116:
            case 2116: { // SET_OUTLINE_THICKNESS
                const c = getSetterComponent(opcode);
                const t = intStack[--isp];
                if (c) c.spriteOutline = t | 0;
                break;
            }
            case 1117:
            case 2117: { // SET_SHADOW_COLOR
                const component = getSetterComponent(opcode);
                const c = intStack[--isp];
                if (component) component.spriteShadow = c | 0;
                break;
            }
            case 1118:
            case 2118: { // SET_VFLIP
                const c = getSetterComponent(opcode);
                const v = intStack[--isp];
                if (c) c.spriteVFlip = v !== 0;
                break;
            }
            case 1119:
            case 2119: { // SET_HFLIP
                const c = getSetterComponent(opcode);
                const h = intStack[--isp];
                if (c) c.spriteHFlip = h !== 0;
                break;
            }
            case 1120:
            case 2120: { // SET_SCROLL_MAX
                const c = getSetterComponent(opcode);
                const maxV = intStack[--isp];
                const maxH = intStack[--isp];
                if (c) {
                    c.scrollMaxH = maxH | 0;
                    c.scrollMaxV = maxV | 0;
                }
                break;
            }
            case 1121:
            case 2121: { // SET_MODEL_ORIGIN_SHORTS
                const c = getSetterComponent(opcode);
                const y = intStack[--isp];
                const x = intStack[--isp];
                if (c) {
                    (c as any).modelOriginX = x | 0;
                    (c as any).modelOriginY = y | 0;
                }
                break;
            }
            case 1122:
            case 2122: { // SET_ALPHA
                const c = getSetterComponent(opcode);
                const hasAlpha = intStack[--isp];
                if (c) c.hasAlpha = hasAlpha === 1;
                break;
            }
            case 1123:
            case 2123: { // SET_3D_VIEW_DISTANCE
                const c = getSetterComponent(opcode);
                const zoom = intStack[--isp];
                if (c) c.modelZoom = zoom | 0;
                break;
            }

            // ── Component model setters (rt4 1200-1205). ──
            case 1200:
            case 1205:
            case 2200:
            case 2205: {
                const c = getSetterComponent(opcode);
                const baseOpcode = opcode >= 2000 ? opcode - 1000 : opcode;
                const count = intStack[--isp];
                const id = intStack[--isp];
                if (c) {
                    if (id === -1) {
                        c.modelType = 1;
                        c.modelId = -1;
                        c.objId = -1;
                        c.objCount = 0;
                    } else {
                        c.objId = id | 0;
                        c.objCount = count | 0;
                        c.objDrawText = baseOpcode !== 1205;
                    }
                }
                break;
            }
            case 1201:
            case 2201: { // SET_NPC_HEAD
                const c = getSetterComponent(opcode);
                const npcId = intStack[--isp];
                if (c) {
                    c.modelType = 2;
                    c.modelId = npcId | 0;
                }
                break;
            }
            case 1202:
            case 2202: { // SET_PLAYER_SELF_HEAD
                const c = getSetterComponent(opcode);
                if (c) {
                    c.modelType = 3;
                    c.modelId = 0;
                }
                break;
            }
            case 1203:
            case 2203: { // SET_PLAYER_HEAD
                const c = getSetterComponent(opcode);
                const playerHead = intStack[--isp];
                if (c) {
                    c.modelType = 6;
                    c.modelId = playerHead | 0;
                }
                break;
            }
            case 1204:
            case 2204: { // SET_PLAYER_FULL
                const c = getSetterComponent(opcode);
                if (c) {
                    c.modelType = 5;
                    c.modelId = 0;
                }
                break;
            }

            // ── Component interaction setters (rt4 1300-1308 and direct 2300-2308). ──
            case 1300:
            case 2300: {
                const c = opcode >= 2000 ? hooks.getComponent?.(intStack[--isp]) : activeComponent;
                const optionIndex = intStack[--isp] - 1;
                const option = stringStack[--ssp] ?? "";
                if (c && optionIndex >= 0 && optionIndex <= 9) {
                    const anyC = c as any;
                    if (!anyC.ops) anyC.ops = [];
                    if (!anyC.options) anyC.options = anyC.ops;
                    anyC.ops[optionIndex] = option;
                    anyC.options[optionIndex] = option;
                }
                break;
            }
            case 1301:
            case 2301: {
                const c = opcode >= 2000 ? hooks.getComponent?.(intStack[--isp]) : activeComponent;
                const childId = intStack[--isp];
                const interfaceId = intStack[--isp];
                if (c) c.draggableComponent = (interfaceId << 16) | (childId & 0xFFFF);
                break;
            }
            case 1302:
            case 2302: {
                const c = opcode >= 2000 ? hooks.getComponent?.(intStack[--isp]) : activeComponent;
                const value = intStack[--isp];
                if (c) c.dragRenderBehavior = value === 1;
                break;
            }
            case 1303:
            case 2303: {
                const c = opcode >= 2000 ? hooks.getComponent?.(intStack[--isp]) : activeComponent;
                const value = intStack[--isp];
                if (c) c.dragDeadZone = value | 0;
                break;
            }
            case 1304:
            case 2304: {
                const c = opcode >= 2000 ? hooks.getComponent?.(intStack[--isp]) : activeComponent;
                const value = intStack[--isp];
                if (c) c.dragDeadTime = value | 0;
                break;
            }
            case 1305:
            case 2305: {
                const c = opcode >= 2000 ? hooks.getComponent?.(intStack[--isp]) : activeComponent;
                const value = stringStack[--ssp] ?? "";
                if (c) c.optionBase = value;
                break;
            }
            case 1306:
            case 2306: {
                const c = opcode >= 2000 ? hooks.getComponent?.(intStack[--isp]) : activeComponent;
                const value = stringStack[--ssp] ?? "";
                if (c) c.targetVerb = value;
                break;
            }
            case 1307:
            case 2307: {
                const c = opcode >= 2000 ? hooks.getComponent?.(intStack[--isp]) : activeComponent;
                if (c) {
                    (c as any).ops = [];
                    (c as any).options = [];
                }
                break;
            }
            case 1308:
            case 2308: {
                const c = opcode >= 2000 ? hooks.getComponent?.(intStack[--isp]) : activeComponent;
                const b = intStack[--isp];
                const a = intStack[--isp];
                if (c) {
                    (c as any).dragParamA = a | 0;
                    (c as any).dragParamB = b | 0;
                }
                break;
            }
            case 1309:
            case 2309: {
                const c = opcode >= 2000 ? hooks.getComponent?.(intStack[--isp]) : activeComponent;
                const cursor = intStack[--isp];
                const optionIndex = intStack[--isp];
                if (c && optionIndex >= 1 && optionIndex <= 10) {
                    const anyC = c as any;
                    if (!anyC.optionCursors) anyC.optionCursors = [];
                    if (!anyC.anIntArray39) anyC.anIntArray39 = anyC.optionCursors;
                    anyC.optionCursors[optionIndex - 1] = cursor | 0;
                    anyC.anIntArray39[optionIndex - 1] = cursor | 0;
                }
                break;
            }

            // ── Client actions / media opcodes (rt4 3100-3202) ──
            case 3100: { // MSG
                const message = stringStack[--ssp] ?? "";
                hooks.addGameMessage?.(message);
                break;
            }
            case 3101: { // ANIMATE_SELF: pop seqId, delay
                const delay = intStack[--isp];
                const seqId = intStack[--isp];
                hooks.animateSelf?.(seqId, delay);
                break;
            }
            case 3103: { hooks.closeWidgets?.(); break; }
            case 3104: {
                const text = stringStack[--ssp] ?? "";
                const value = /^[-+]?\d+$/.test(text.trim()) ? parseInt(text, 10) | 0 : 0;
                hooks.resumeIntegerInput?.(value);
                break;
            }
            case 3105: { hooks.resumeNameInput?.(stringStack[--ssp] ?? ""); break; }
            case 3106: { hooks.resumeStringInput?.(stringStack[--ssp] ?? ""); break; }
            case 3107: {
                const playerIndex = intStack[--isp];
                const option = stringStack[--ssp] ?? "";
                hooks.clickPlayerOption?.(option, playerIndex);
                break;
            }
            case 3108: {
                const componentHash = intStack[--isp];
                const arg1 = intStack[--isp];
                const arg0 = intStack[--isp];
                hooks.runWidgetAction?.(arg0, arg1, hooks.getComponent?.(componentHash) ?? null);
                break;
            }
            case 3109: {
                const arg1 = intStack[--isp];
                const arg0 = intStack[--isp];
                hooks.runWidgetAction?.(arg0, arg1, activeComponent);
                break;
            }
            case 3110: { hooks.sendDialogAction?.(intStack[--isp]); break; }
            case 3200: {
                const delay = intStack[--isp];
                const loops = intStack[--isp];
                const soundId = intStack[--isp];
                hooks.playSoundEffect?.(soundId, loops, delay);
                break;
            }
            case 3201: { hooks.playMusic?.(intStack[--isp]); break; }
            case 3202: {
                const delay = intStack[--isp];
                const jingleId = intStack[--isp];
                hooks.playMusicEffect?.(jingleId, delay);
                break;
            }

            // ── Skill / player query opcodes (rt4 3305-3322) ──
            case 3300: { // GET_CLIENT_CYCLE
                intStack[isp++] = hooks.getClientCycle?.() ?? cycles;
                break;
            }
            case 3301: { // GET_ITEM_ID_IN_SLOT
                const slot = intStack[--isp];
                const containerId = intStack[--isp];
                const c = hooks.getContainer?.(containerId);
                intStack[isp++] = c && slot >= 0 && slot < c.items.length ? c.items[slot] : -1;
                break;
            }
            case 3302: { // GET_ITEM_AMT_IN_SLOT
                const slot = intStack[--isp];
                const containerId = intStack[--isp];
                const c = hooks.getContainer?.(containerId);
                intStack[isp++] = c && slot >= 0 && slot < c.amounts.length ? c.amounts[slot] : 0;
                break;
            }
            case 3305: { // GET_SKILL_CURRENT_LEVEL
                const skillId = intStack[--isp];
                intStack[isp++] = hooks.getSkill?.(skillId)?.currentLevel ?? 0;
                break;
            }
            case 3306: { // GET_SKILL_ACTUAL_LEVEL
                const skillId = intStack[--isp];
                intStack[isp++] = hooks.getSkill?.(skillId)?.actualLevel ?? 0;
                break;
            }
            case 3307: { // GET_SKILL_XP
                const skillId = intStack[--isp];
                intStack[isp++] = hooks.getSkill?.(skillId)?.xp ?? 0;
                break;
            }
            case 3308: { // GET_MY_LOCATION
                intStack[isp++] = hooks.getMyLocation?.() ?? 0;
                break;
            }
            case 3309: { const coord = intStack[--isp]; intStack[isp++] = (coord >> 14) & 0x3FFF; break; } // COORD_X
            case 3310: { const coord = intStack[--isp]; intStack[isp++] = (coord >> 28) & 0x3; break; } // COORD_PLANE
            case 3311: { const coord = intStack[--isp]; intStack[isp++] = coord & 0x3FFF; break; } // COORD_Y
            case 3312: { intStack[isp++] = hooks.isMembers?.() ? 1 : 0; break; }
            case 3313: { // GET_ITEM_ID_IN_INSPECTING_SLOT
                const slot = intStack[--isp];
                const containerId = intStack[--isp] + 32768;
                const c = hooks.getContainer?.(containerId);
                intStack[isp++] = c && slot >= 0 && slot < c.items.length ? c.items[slot] : -1;
                break;
            }
            case 3314: { // GET_ITEM_AMT_IN_INSPECTING_SLOT
                const slot = intStack[--isp];
                const containerId = intStack[--isp] + 32768;
                const c = hooks.getContainer?.(containerId);
                intStack[isp++] = c && slot >= 0 && slot < c.amounts.length ? c.amounts[slot] : 0;
                break;
            }
            case 3315: { // GET_ITEM_AMT_IN_INSPECTING_CONTAINER
                const itemId = intStack[--isp];
                const containerId = intStack[--isp] + 32768;
                const c = hooks.getContainer?.(containerId);
                let total = 0;
                if (c) for (let i = 0; i < c.items.length; i++) if (c.items[i] === itemId) total += c.amounts[i] || 0;
                intStack[isp++] = total;
                break;
            }
            case 3316: { intStack[isp++] = hooks.getClientRights?.() ?? 0; break; }
            case 3317: { intStack[isp++] = hooks.getSystemUpdateTimer?.() ?? 0; break; }
            case 3318: { intStack[isp++] = hooks.getWorldId?.() ?? 0; break; }
            case 3321: { // GET_RUN_ENERGY
                intStack[isp++] = hooks.getRunEnergy?.() ?? 0;
                break;
            }
            case 3322: { // GET_PLAYER_WEIGHT
                intStack[isp++] = hooks.getPlayerWeight?.() ?? 0;
                break;
            }
            case 3323: {
                const blackmarks = hooks.getBlackmarks?.() ?? 0;
                intStack[isp++] = blackmarks >= 5 && blackmarks <= 9 ? 1 : 0;
                break;
            }
            case 3324: {
                const blackmarks = hooks.getBlackmarks?.() ?? 0;
                intStack[isp++] = blackmarks >= 5 && blackmarks <= 9 ? blackmarks : 0;
                break;
            }
            case 3325: { intStack[isp++] = hooks.isMembers?.() ? 1 : 0; break; }
            case 3326: { intStack[isp++] = hooks.getCombatLevel?.() ?? 0; break; }
            case 3327: { intStack[isp++] = hooks.getPlayerGender?.() === 1 ? 1 : 0; break; }
            case 3328: { intStack[isp++] = 0; break; }
            case 3329: { intStack[isp++] = hooks.isMapQuickChat?.() ? 1 : 0; break; }

            // ── Container query opcodes (rt4 3303-3332) ──
            case 3303: { // GET_ITEM_AMT_IN_CONTAINER (pop itemId, containerId)
                const containerId = intStack[--isp];
                const itemId = intStack[--isp];
                const c = hooks.getContainer?.(containerId);
                let total = 0;
                if (c) for (let i = 0; i < c.items.length; i++) if (c.items[i] === itemId) total += c.amounts[i] || 0;
                intStack[isp++] = total;
                break;
            }
            case 3304: { // GET_ITEM_CONTAINER_LENGTH
                const containerId = intStack[--isp];
                intStack[isp++] = hooks.getContainer?.(containerId)?.capacity ?? 0;
                break;
            }
            case 3330: { // GET_CONTAINER_FREE_SLOTS
                const containerId = intStack[--isp];
                const c = hooks.getContainer?.(containerId);
                if (!c) { intStack[isp++] = 0; break; }
                let used = 0;
                for (let i = 0; i < c.items.length; i++) if (c.items[i] >= 0 && (c.amounts[i] || 0) > 0) used++;
                intStack[isp++] = Math.max(0, c.capacity - used);
                break;
            }
            case 3331: { // GET_CONTAINER_ITEM_COUNT_IGNORE_STACKS — count distinct slots
                const containerId = intStack[--isp];
                const c = hooks.getContainer?.(containerId);
                if (!c) { intStack[isp++] = 0; break; }
                let n = 0;
                for (let i = 0; i < c.items.length; i++) if (c.items[i] >= 0 && (c.amounts[i] || 0) > 0) n++;
                intStack[isp++] = n;
                break;
            }
            case 3332: { // GET_CONTAINER_ITEM_COUNT — sum of amounts
                const containerId = intStack[--isp];
                const c = hooks.getContainer?.(containerId);
                if (!c) { intStack[isp++] = 0; break; }
                let n = 0;
                for (let i = 0; i < c.items.length; i++) if (c.items[i] >= 0) n += c.amounts[i] || 0;
                intStack[isp++] = n;
                break;
            }
            case 3333: { intStack[isp++] = hooks.getLoginType?.() ?? 0; break; }
            case 3335: { intStack[isp++] = hooks.getLanguage?.() ?? 0; break; }
            case 3336: { // MOVE_COORD: plane, x, y packed from 4 ints
                const y = intStack[--isp];
                const plane = intStack[--isp];
                const x = intStack[--isp];
                const base = intStack[--isp];
                intStack[isp++] = (base + (x << 14) + (plane << 28) + y) | 0;
                break;
            }
            case 3337: { intStack[isp++] = hooks.getAffiliate?.() ?? 0; break; }

            // ── Friend / ignore / clan query opcodes (rt4 3600-3629) ──
            case 3600: { // GET_FRIEND_COUNT
                const state = hooks.getFriendListState?.() ?? 2;
                intStack[isp++] = state === 0 ? -2 : state === 1 ? -1 : (hooks.getFriendCount?.() ?? 0);
                break;
            }
            case 3601: { // GET_FRIEND_NAME
                const index = intStack[--isp];
                stringStack[ssp++] = hooks.getFriend?.(index)?.name ?? "";
                break;
            }
            case 3602: { // GET_FRIEND_WORLD
                const index = intStack[--isp];
                intStack[isp++] = hooks.getFriend?.(index)?.world ?? 0;
                break;
            }
            case 3603: { // GET_FRIEND_RANK
                const index = intStack[--isp];
                intStack[isp++] = hooks.getFriend?.(index)?.rank ?? 0;
                break;
            }
            case 3604: { --ssp; --isp; break; } // SEND_PRIVATE_MESSAGE (no-op until outbound social packets are wired)
            case 3605:
            case 3606:
            case 3607:
            case 3608: { --ssp; break; } // add/remove friend/ignore: consume string, no-op
            case 3609: { // IS_FRIEND
                const name = normalizeSocialName(stringStack[--ssp] ?? "");
                intStack[isp++] = hooks.isFriend?.(name) ? 1 : 0;
                break;
            }
            case 3610: { // GET_FRIEND_WORLD_NAME
                const index = intStack[--isp];
                stringStack[ssp++] = hooks.getFriend?.(index)?.worldName ?? "";
                break;
            }
            case 3611: { stringStack[ssp++] = hooks.getClan?.()?.name ?? ""; break; }
            case 3612: {
                const clan = hooks.getClan?.();
                intStack[isp++] = clan ? clan.members.length : 0;
                break;
            }
            case 3613: {
                const index = intStack[--isp];
                stringStack[ssp++] = hooks.getClan?.()?.members[index]?.name ?? "";
                break;
            }
            case 3614: {
                const index = intStack[--isp];
                intStack[isp++] = hooks.getClan?.()?.members[index]?.world ?? 0;
                break;
            }
            case 3615: {
                const index = intStack[--isp];
                intStack[isp++] = hooks.getClan?.()?.members[index]?.rank ?? 0;
                break;
            }
            case 3616: { intStack[isp++] = hooks.getClan?.()?.minKick ?? 0; break; }
            case 3617: { --ssp; break; } // JOIN_CLAN_CHAT no-op
            case 3618: { intStack[isp++] = hooks.getClan?.()?.rank ?? 0; break; }
            case 3619: { --ssp; break; } // CLAN_KICK_USER no-op
            case 3620: { break; }        // LEAVE_CLAN_CHAT no-op
            case 3621: {
                const state = hooks.getFriendListState?.() ?? 2;
                intStack[isp++] = state === 0 ? -1 : (hooks.getIgnoreCount?.() ?? 0);
                break;
            }
            case 3622: {
                const index = intStack[--isp];
                stringStack[ssp++] = hooks.getIgnoreName?.(index) ?? "";
                break;
            }
            case 3623: {
                const name = normalizeSocialName(stringStack[--ssp] ?? "");
                intStack[isp++] = hooks.isIgnored?.(name) ? 1 : 0;
                break;
            }
            case 3624: {
                const index = intStack[--isp];
                const memberName = hooks.getClan?.()?.members[index]?.name ?? "";
                intStack[isp++] = normalizeSocialName(memberName) === normalizeSocialName(hooks.getSelfName?.() ?? "") ? 1 : 0;
                break;
            }
            case 3625: { stringStack[ssp++] = hooks.getClan?.()?.owner ?? ""; break; }
            case 3626: {
                const index = intStack[--isp];
                stringStack[ssp++] = hooks.getClan?.()?.members[index]?.worldName ?? "";
                break;
            }
            case 3627: {
                const index = intStack[--isp];
                intStack[isp++] = hooks.getFriend?.(index)?.sameGame ? 1 : 0;
                break;
            }
            case 3628: {
                const name = normalizeSocialName(stringStack[--ssp] ?? "");
                intStack[isp++] = hooks.getFriendIndex?.(name) ?? -1;
                break;
            }
            case 3629: { intStack[isp++] = hooks.getCountry?.() ?? 0; break; }

            // ── Grand Exchange offer query opcodes (rt4 3903-3913) ──
            case 3903: {
                const slot = intStack[--isp];
                intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.type ?? 0;
                break;
            }
            case 3904: {
                const slot = intStack[--isp];
                intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.item ?? -1;
                break;
            }
            case 3905: {
                const slot = intStack[--isp];
                intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.price ?? 0;
                break;
            }
            case 3906: {
                const slot = intStack[--isp];
                intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.count ?? 0;
                break;
            }
            case 3907: {
                const slot = intStack[--isp];
                intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.completedCount ?? 0;
                break;
            }
            case 3908: {
                const slot = intStack[--isp];
                intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.completedGold ?? 0;
                break;
            }
            case 3910: {
                const slot = intStack[--isp];
                intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.status === 0 ? 1 : 0;
                break;
            }
            case 3911: {
                const slot = intStack[--isp];
                intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.status === 2 ? 1 : 0;
                break;
            }
            case 3912: {
                const slot = intStack[--isp];
                intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.status === 5 ? 1 : 0;
                break;
            }
            case 3913: {
                const slot = intStack[--isp];
                intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.status === 1 ? 1 : 0;
                break;
            }

            // ── Chat query/settings opcodes (rt4 5000-5017) ──
            case 5000: { intStack[isp++] = hooks.getPublicChatSetting?.() ?? 0; break; }
            case 5001: {
                const tradeFilter = intStack[--isp];
                const privateFilter = intStack[--isp];
                const publicFilter = intStack[--isp];
                hooks.setChatSettings?.(publicFilter, privateFilter, tradeFilter);
                break;
            }
            case 5002: { --ssp; isp -= 2; break; } // BUG_REPORT: consume string, type, rule; no outbound packet here.
            case 5003: {
                const index = intStack[--isp];
                stringStack[ssp++] = hooks.getChatMessage?.(index)?.message ?? "";
                break;
            }
            case 5004: {
                const index = intStack[--isp];
                const msg = hooks.getChatMessage?.(index);
                intStack[isp++] = msg && msg.message !== "" ? msg.type : -1;
                break;
            }
            case 5005: { intStack[isp++] = hooks.getPrivateChatSetting?.() ?? 0; break; }
            case 5008: { --ssp; break; } // SEND_PUBLIC_CHAT: consume message, no outbound packet here.
            case 5009: { ssp -= 2; break; } // SEND_PRIVATE_CHAT: consume target + body, no outbound packet here.
            case 5010: {
                const index = intStack[--isp];
                stringStack[ssp++] = hooks.getChatMessage?.(index)?.name ?? "";
                break;
            }
            case 5011: {
                const index = intStack[--isp];
                stringStack[ssp++] = hooks.getChatMessage?.(index)?.clan ?? "";
                break;
            }
            case 5012: {
                const index = intStack[--isp];
                intStack[isp++] = hooks.getChatMessage?.(index)?.phraseId ?? -1;
                break;
            }
            case 5015: { stringStack[ssp++] = hooks.getSelfName?.() ?? ""; break; }
            case 5016: { intStack[isp++] = hooks.getTradeSetting?.() ?? 0; break; }
            case 5017: { intStack[isp++] = hooks.getChatSize?.() ?? 0; break; }

            // ── Keyboard modifier opcodes (rt4 5100-5102) ──
            case 5100: { intStack[isp++] = hooks.isKeyHeld?.("alt") ? 1 : 0; break; }
            case 5101: { intStack[isp++] = hooks.isKeyHeld?.("ctrl") ? 1 : 0; break; }
            case 5102: { intStack[isp++] = hooks.isKeyHeld?.("shift") ? 1 : 0; break; }

            // ── Display/window mode opcodes (rt4 5300-5309) ──
            case 5300: {
                const height = intStack[--isp];
                const width = intStack[--isp];
                intStack[isp++] = hooks.requestFullscreen?.(width, height) ? 1 : 0;
                break;
            }
            case 5301: { hooks.exitFullscreen?.(); break; }
            case 5302: { intStack[isp++] = hooks.getDisplayModeCount?.() ?? 0; break; }
            case 5303: {
                const index = intStack[--isp];
                const mode = hooks.getDisplayMode?.(index);
                intStack[isp++] = mode?.width ?? 0;
                intStack[isp++] = mode?.height ?? 0;
                break;
            }
            case 5305: { intStack[isp++] = hooks.getPreferredFullscreenMode?.() ?? -1; break; }
            case 5306: { intStack[isp++] = hooks.getWindowMode?.() ?? 0; break; }
            case 5307: {
                let mode = intStack[--isp];
                if (mode < 0 || mode > 2) mode = 0;
                hooks.setWindowMode?.(mode);
                break;
            }
            case 5308: { intStack[isp++] = hooks.getPreferredWindowMode?.() ?? 0; break; }
            case 5309: {
                let mode = intStack[--isp];
                if (mode < 0 || mode > 2) mode = 0;
                hooks.setPreferredWindowMode?.(mode);
                break;
            }

            // ── Camera control/query opcodes (rt4 5500-5506) ──
            case 5500: {
                const acceleration = intStack[--isp];
                const speed = intStack[--isp];
                const height = intStack[--isp];
                const coord = intStack[--isp];
                hooks.moveCameraTo?.(coord, height, speed, acceleration);
                break;
            }
            case 5501: {
                const acceleration = intStack[--isp];
                const speed = intStack[--isp];
                const height = intStack[--isp];
                const coord = intStack[--isp];
                hooks.pointCameraAt?.(coord, height, speed, acceleration);
                break;
            }
            case 5502: {
                const values = new Array(6);
                for (let i = 5; i >= 0; i--) values[i] = intStack[--isp];
                hooks.setCameraPath?.(values);
                break;
            }
            case 5503: { hooks.unlockCamera?.(); break; }
            case 5504: {
                const yaw = intStack[--isp];
                const pitch = intStack[--isp];
                hooks.setCameraRotation?.(pitch, yaw);
                break;
            }
            case 5505: { intStack[isp++] = hooks.getCameraRotation?.().pitch ?? 0; break; }
            case 5506: { intStack[isp++] = hooks.getCameraRotation?.().yaw ?? 0; break; }

            // ── Login / account-create opcodes (rt4 5600-5611) ──
            case 5600: {
                const flags = intStack[--isp];
                const password = stringStack[--ssp] ?? "";
                const username = stringStack[--ssp] ?? "";
                hooks.requestDirectLogin?.(username, password, flags);
                break;
            }
            case 5601: { hooks.skipLoginStage?.(); break; }
            case 5602: { hooks.resetLoginReply?.(); break; }
            case 5603: {
                const d = intStack[--isp];
                const c = intStack[--isp];
                const b = intStack[--isp];
                const a = intStack[--isp];
                hooks.checkAccountInfo?.(a, b, c, d);
                break;
            }
            case 5604: {
                const name = stringStack[--ssp] ?? "";
                hooks.requestAccountName?.(name);
                break;
            }
            case 5605: {
                const d = intStack[--isp];
                const c = intStack[--isp];
                const b = intStack[--isp];
                const a = intStack[--isp];
                const password = stringStack[--ssp] ?? "";
                const username = stringStack[--ssp] ?? "";
                hooks.createAccount?.(username, password, a, b, c, d);
                break;
            }
            case 5606: { hooks.resetAccountCreateReply?.(); break; }
            case 5607: { intStack[isp++] = hooks.getGameLoginReply?.() ?? 0; break; }
            case 5608: { intStack[isp++] = hooks.getWorldSwitchTimer?.() ?? 0; break; }
            case 5609: { intStack[isp++] = hooks.getAccountCreateReply?.() ?? 0; break; }
            case 5610: {
                const names = hooks.getSuggestedAccountNames?.() ?? [];
                for (let i = 0; i < 5; i++) stringStack[ssp++] = names[i] ?? "";
                hooks.clearSuggestedAccountNames?.();
                break;
            }
            case 5611: { intStack[isp++] = hooks.getDetailedLoginReply?.() ?? 0; break; }

            // ── Preferences/options opcodes (rt4 6001-6128) ──
            case 6001: { let v = intStack[--isp]; if (v < 1) v = 1; if (v > 4) v = 4; hooks.setPreference?.("brightness", v); break; }
            case 6002: { hooks.setPreference?.("allLevelsVisible", intStack[--isp] === 1 ? 1 : 0); break; }
            case 6003: { hooks.setPreference?.("removeRoofsSelectively", intStack[--isp] === 1 ? 1 : 0); break; }
            case 6005: { hooks.setPreference?.("showGroundDecorations", intStack[--isp] === 1 ? 1 : 0); break; }
            case 6006: { hooks.setPreference?.("highDetailTextures", intStack[--isp] === 1 ? 1 : 0); break; }
            case 6007: { hooks.setPreference?.("manyIdleAnimations", intStack[--isp] === 1 ? 1 : 0); break; }
            case 6008: { hooks.setPreference?.("flickeringEffectsOn", intStack[--isp] === 1 ? 1 : 0); break; }
            case 6009: { hooks.setPreference?.("manyGroundTextures", intStack[--isp] === 1 ? 1 : 0); break; }
            case 6010: { hooks.setPreference?.("characterShadowsOn", intStack[--isp] === 1 ? 1 : 0); break; }
            case 6011: { let v = intStack[--isp]; if (v < 0 || v > 2) v = 0; hooks.setPreference?.("sceneryShadowsType", v); break; }
            case 6012: { hooks.setPreference?.("highDetailLighting", intStack[--isp] === 1 ? 1 : 0); break; }
            case 6014: { hooks.setPreference?.("highWaterDetail", intStack[--isp] === 1 ? 1 : 0); break; }
            case 6015: { hooks.setPreference?.("fogEnabled", intStack[--isp] === 1 ? 1 : 0); break; }
            case 6016: { let v = intStack[--isp]; if (v < 0 || v > 2) v = 0; hooks.setPreference?.("antiAliasingMode", v); break; }
            case 6017: { hooks.setPreference?.("stereo", intStack[--isp] === 1 ? 1 : 0); break; }
            case 6018: { let v = intStack[--isp]; if (v < 0) v = 0; if (v > 127) v = 127; hooks.setPreference?.("soundEffectVolume", v); break; }
            case 6019: { let v = intStack[--isp]; if (v < 0) v = 0; if (v > 255) v = 255; hooks.setPreference?.("musicVolume", v); break; }
            case 6020: { let v = intStack[--isp]; if (v < 0) v = 0; if (v > 127) v = 127; hooks.setPreference?.("ambientSoundsVolume", v); break; }
            case 6021: { hooks.setPreference?.("neverRemoveRoofs", intStack[--isp] === 1 ? 1 : 0); break; }
            case 6023: {
                let v = intStack[--isp];
                if (v < 0) v = 0;
                if (v > 2) v = 2;
                const ok = hooks.setPreference?.("particleSetting", v);
                intStack[isp++] = ok === 0 ? 0 : 1;
                break;
            }
            case 6024: { let v = intStack[--isp]; if (v < 0 || v > 2) v = 0; hooks.setPreference?.("windowMode", v); break; }
            case 6028: { hooks.setPreference?.("cursorsEnabled", intStack[--isp] !== 0 ? 1 : 0); break; }
            case 6101: { intStack[isp++] = hooks.getPreference?.("brightness") ?? 0; break; }
            case 6102: { intStack[isp++] = hooks.getPreference?.("allLevelsVisible") ?? 0; break; }
            case 6103: { intStack[isp++] = hooks.getPreference?.("removeRoofsSelectively") ?? 0; break; }
            case 6105: { intStack[isp++] = hooks.getPreference?.("showGroundDecorations") ?? 0; break; }
            case 6106: { intStack[isp++] = hooks.getPreference?.("highDetailTextures") ?? 0; break; }
            case 6107: { intStack[isp++] = hooks.getPreference?.("manyIdleAnimations") ?? 0; break; }
            case 6108: { intStack[isp++] = hooks.getPreference?.("flickeringEffectsOn") ?? 0; break; }
            case 6109: { intStack[isp++] = hooks.getPreference?.("manyGroundTextures") ?? 0; break; }
            case 6110: { intStack[isp++] = hooks.getPreference?.("characterShadowsOn") ?? 0; break; }
            case 6111: { intStack[isp++] = hooks.getPreference?.("sceneryShadowsType") ?? 0; break; }
            case 6112: { intStack[isp++] = hooks.getPreference?.("highDetailLighting") ?? 0; break; }
            case 6114: { intStack[isp++] = hooks.getPreference?.("highWaterDetail") ?? 0; break; }
            case 6115: { intStack[isp++] = hooks.getPreference?.("fogEnabled") ?? 0; break; }
            case 6116: { intStack[isp++] = hooks.getPreference?.("antiAliasingMode") ?? 0; break; }
            case 6117: { intStack[isp++] = hooks.getPreference?.("stereo") ?? 0; break; }
            case 6118: { intStack[isp++] = hooks.getPreference?.("soundEffectVolume") ?? 0; break; }
            case 6119: { intStack[isp++] = hooks.getPreference?.("musicVolume") ?? 0; break; }
            case 6120: { intStack[isp++] = hooks.getPreference?.("ambientSoundsVolume") ?? 0; break; }
            case 6121: { intStack[isp++] = hooks.getPreference?.("antiAliasingSupported") ?? 0; break; }
            case 6123: { intStack[isp++] = hooks.getPreference?.("particleSetting") ?? 0; break; }
            case 6124: { intStack[isp++] = hooks.getPreference?.("windowMode") ?? 0; break; }
            case 6128: { intStack[isp++] = hooks.getPreference?.("cursorsEnabled") ?? 0; break; }

            // ── Viewport/FOV opcodes (rt4 6200-6205) ──
            case 6200: {
                let far = intStack[--isp]; if (far <= 0) far = 205;
                let near = intStack[--isp]; if (near <= 0) near = 256;
                hooks.setViewport?.("near", [near, far]);
                break;
            }
            case 6201: {
                let far = intStack[--isp]; if (far <= 0) far = 320;
                let near = intStack[--isp]; if (near <= 0) near = 256;
                hooks.setViewport?.("far", [near, far]);
                break;
            }
            case 6202: {
                let maxY = intStack[--isp]; if (maxY <= 0) maxY = 32767;
                let minY = intStack[--isp]; if (minY <= 0) minY = 1;
                let maxX = intStack[--isp]; if (maxX <= 0) maxX = 32767;
                let minX = intStack[--isp]; if (minX <= 0) minX = 1;
                if (minX > maxX) maxX = minX;
                if (maxY < minY) maxY = minY;
                hooks.setViewport?.("clamp", [minX, maxX, minY, maxY]);
                break;
            }
            case 6203: {
                const size = hooks.getViewport?.("size") ?? [0, 0];
                intStack[isp++] = size[0] | 0;
                intStack[isp++] = size[1] | 0;
                break;
            }
            case 6204: {
                const v = hooks.getViewport?.("far") ?? [256, 320];
                intStack[isp++] = v[0] | 0;
                intStack[isp++] = v[1] | 0;
                break;
            }
            case 6205: {
                const v = hooks.getViewport?.("near") ?? [256, 205];
                intStack[isp++] = v[0] | 0;
                intStack[isp++] = v[1] | 0;
                break;
            }

            // ── Calendar / monotonic time opcodes (rt4 6300-6304) ──
            case 6300: {
                intStack[isp++] = ((hooks.getCurrentTimeMillis?.() ?? Date.now()) / 60000) | 0;
                break;
            }
            case 6301: {
                intStack[isp++] = (((hooks.getCurrentTimeMillis?.() ?? Date.now()) / 86400000) | 0) - 11745;
                break;
            }
            case 6302: {
                const year = intStack[--isp];
                const month = intStack[--isp];
                const day = intStack[--isp];
                intStack[isp++] = ((Date.UTC(year, month, day, 12, 0, 0, 0) / 86400000) | 0) - 11745;
                break;
            }
            case 6303: {
                intStack[isp++] = new Date(hooks.getCurrentTimeMillis?.() ?? Date.now()).getFullYear();
                break;
            }
            case 6304: {
                const year = intStack[--isp];
                let leap = true;
                if (year < 0) leap = (year + 1) % 4 === 0;
                else if (year < 1582) leap = year % 4 === 0;
                else if (year % 4 !== 0) leap = false;
                else if (year % 100 !== 0) leap = true;
                else if (year % 400 !== 0) leap = false;
                intStack[isp++] = leap ? 1 : 0;
                break;
            }

            // ── Ads / world-list opcodes (rt4 6405-6601) ──
            case 6405: { intStack[isp++] = hooks.canShowVideoAd?.() ? 1 : 0; break; }
            case 6406: { intStack[isp++] = hooks.isShowingVideoAd?.() ? 1 : 0; break; }
            case 6500: { intStack[isp++] = hooks.fetchWorldList?.() ? 1 : 0; break; }
            case 6501: {
                const world = hooks.getFirstWorld?.() ?? null;
                if (!world) {
                    intStack[isp++] = -1; intStack[isp++] = 0; stringStack[ssp++] = ""; intStack[isp++] = 0; stringStack[ssp++] = ""; intStack[isp++] = 0;
                } else {
                    intStack[isp++] = world.id | 0; intStack[isp++] = world.flags | 0; stringStack[ssp++] = world.activity || "";
                    intStack[isp++] = world.countryFlag | 0; stringStack[ssp++] = world.countryName || ""; intStack[isp++] = world.players | 0;
                }
                break;
            }
            case 6502: {
                const world = hooks.getNextWorld?.() ?? null;
                if (!world) {
                    intStack[isp++] = -1; intStack[isp++] = 0; stringStack[ssp++] = ""; intStack[isp++] = 0; stringStack[ssp++] = ""; intStack[isp++] = 0;
                } else {
                    intStack[isp++] = world.id | 0; intStack[isp++] = world.flags | 0; stringStack[ssp++] = world.activity || "";
                    intStack[isp++] = world.countryFlag | 0; stringStack[ssp++] = world.countryName || ""; intStack[isp++] = world.players | 0;
                }
                break;
            }
            case 6503: {
                const worldId = intStack[--isp];
                intStack[isp++] = hooks.hopWorld?.(worldId) ? 1 : 0;
                break;
            }
            case 6504: { hooks.setLastWorld?.(intStack[--isp]); break; }
            case 6505: { intStack[isp++] = hooks.getLastWorld?.() ?? 0; break; }
            case 6506: {
                const worldId = intStack[--isp];
                const world = hooks.getWorldById?.(worldId) ?? null;
                if (!world) {
                    intStack[isp++] = -1; stringStack[ssp++] = ""; intStack[isp++] = 0; stringStack[ssp++] = ""; intStack[isp++] = 0;
                } else {
                    intStack[isp++] = world.flags | 0; stringStack[ssp++] = world.activity || "";
                    intStack[isp++] = world.countryFlag | 0; stringStack[ssp++] = world.countryName || ""; intStack[isp++] = world.players | 0;
                }
                break;
            }
            case 6507: {
                const secondaryAscending = intStack[--isp] === 1;
                const secondaryKey = intStack[--isp];
                const primaryAscending = intStack[--isp] === 1;
                const primaryKey = intStack[--isp];
                hooks.sortWorldList?.(primaryKey, primaryAscending, secondaryKey, secondaryAscending);
                break;
            }
            case 6600: { hooks.setSiteSettingsMembers?.(intStack[--isp] === 1); break; }
            case 6601: { intStack[isp++] = hooks.isSiteSettingsMembers?.() ? 1 : 0; break; }

            // ── Enum/datamap lookups (rt4 3400-3411) ──
            case 3400: { // DATAMAP: pop enumId, key → push string
                const key = intStack[--isp];
                const enumId = intStack[--isp];
                const e = hooks.getEnum?.(enumId);
                stringStack[ssp++] = e?.intToString?.get(key) ?? e?.defaultString ?? "";
                break;
            }
            case 3408: { // DATAMAP_TYPED: pop keyType, valueType, enumId, key
                const key = intStack[--isp];
                const enumId = intStack[--isp];
                const valueType = intStack[--isp];
                const keyType = intStack[--isp];
                const e = hooks.getEnum?.(enumId);
                if (!e || e.keyType !== keyType || e.valueType !== valueType) {
                    if (valueType === 115) stringStack[ssp++] = "";
                    else intStack[isp++] = 0;
                } else if (valueType === 115) {
                    stringStack[ssp++] = e.intToString?.get(key) ?? e.defaultString ?? "";
                } else {
                    intStack[isp++] = e.intToInt?.get(key) ?? e.defaultInt ?? 0;
                }
                break;
            }
            case 3409: { // DATAMAP_CONTAINS_INT_VALUE: pop valueType, enumId, value
                const value = intStack[--isp];
                const enumId = intStack[--isp];
                const valueType = intStack[--isp];
                const e = hooks.getEnum?.(enumId);
                if (!e || e.valueType !== valueType || valueType === 115) {
                    intStack[isp++] = 0;
                } else {
                    let found = 0;
                    e.intToInt?.forEach((v) => { if (v === value) found = 1; });
                    intStack[isp++] = found;
                }
                break;
            }
            case 3410: { // DATAMAP_CONTAINS_STRING_VALUE: pop enumId, string value
                const enumId = intStack[--isp];
                const value = stringStack[--ssp] ?? "";
                const e = hooks.getEnum?.(enumId);
                if (!e || e.valueType !== 115) {
                    intStack[isp++] = 0;
                } else {
                    let found = 0;
                    e.intToString?.forEach((v) => { if (v === value) found = 1; });
                    intStack[isp++] = found;
                }
                break;
            }
            case 3411: { // DATAMAP_SIZE
                const enumId = intStack[--isp];
                const e = hooks.getEnum?.(enumId);
                intStack[isp++] = e ? (e.intToString?.size ?? e.intToInt?.size ?? 0) : 0;
                break;
            }

            // ── NPC query (rt4 4300) ──
            case 4300: { // GET_NPC_ATTRIBUTE
                const attrId = intStack[--isp];
                const npcId = intStack[--isp];
                const v = hooks.getNpcAttribute?.(npcId, attrId);
                if (typeof v === "string") stringStack[ssp++] = v;
                else intStack[isp++] = (v as number) | 0;
                break;
            }

            // ── Loc / Struct param lookup (rt4 4400 / 4500) ──
            case 4400: { // GET_LOC_PARAM
                const paramId = intStack[--isp];
                const locId = intStack[--isp];
                const v = hooks.getLocParam?.(locId, paramId);
                if (typeof v === "string") stringStack[ssp++] = v;
                else intStack[isp++] = (v as number) | 0;
                break;
            }
            case 4500: { // GET_STRUCT_PARAM
                const paramId = intStack[--isp];
                const structId = intStack[--isp];
                const v = hooks.getStructParam?.(structId, paramId);
                if (typeof v === "string") stringStack[ssp++] = v;
                else intStack[isp++] = (v as number) | 0;
                break;
            }

            // ── Item search (rt4 4210-4212) ──
            case 4210: { // SEARCH_ITEM: pop string query, pop int exact → push count
                const exact = intStack[--isp];
                const query = stringStack[--ssp] ?? "";
                intStack[isp++] = hooks.searchItem?.(query, exact) ?? 0;
                break;
            }
            case 4211: { // NEXT_SEARCH_RESULT
                intStack[isp++] = hooks.nextSearchResult?.() ?? -1;
                break;
            }
            case 4212: { // SEARCH_RESET
                hooks.resetSearch?.();
                break;
            }

            // ── Active component getters (rt4 1500-1802) ──
            case 1500: { const c = activeComponent; intStack[isp++] = c ? c.x : 0; break; } // GET_X
            case 1501: { const c = activeComponent; intStack[isp++] = c ? c.y : 0; break; } // GET_Y
            case 1502: { const c = activeComponent; intStack[isp++] = c ? c.width : 0; break; } // GET_WIDTH
            case 1503: { const c = activeComponent; intStack[isp++] = c ? c.height : 0; break; } // GET_HEIGHT
            case 1504: { const c = activeComponent; intStack[isp++] = c?.hidden ? 1 : 0; break; } // GET_HIDDEN
            case 1505: { const c = activeComponent; intStack[isp++] = c?.layer ?? 0; break; } // GET_LAYER
            case 1600: { const c = activeComponent; intStack[isp++] = c?.scrollPosX ?? 0; break; } // GET_SCROLL_X
            case 1601: { const c = activeComponent; intStack[isp++] = c?.scrollPos ?? 0; break; } // GET_SCROLL_Y
            case 1602: { // GET_TEXT
                const c = activeComponent;
                stringStack[ssp++] = c?.text ?? "";
                break;
            }
            case 1603: { const c = activeComponent; intStack[isp++] = c?.scrollMaxH ?? 0; break; }
            case 1604: { const c = activeComponent; intStack[isp++] = c?.scrollMaxV ?? 0; break; }
            case 1605: { const c = activeComponent; intStack[isp++] = c?.modelZoom ?? 0; break; }
            case 1606: { const c = activeComponent; intStack[isp++] = c?.modelXAngle ?? 0; break; }
            case 1607: { const c = activeComponent; intStack[isp++] = c?.modelYOffset ?? 0; break; }
            case 1608: { const c = activeComponent; intStack[isp++] = c?.modelYAngle ?? 0; break; }
            case 1609: { const c = activeComponent; intStack[isp++] = c?.alpha ?? 0; break; }
            case 1610: { const c = activeComponent; intStack[isp++] = c?.modelXOffset ?? 0; break; }
            case 1611: { const c = activeComponent; intStack[isp++] = c?.modelZOffset ?? 0; break; }
            case 1612: { const c = activeComponent; intStack[isp++] = c?.sprite ?? -1; break; }
            case 1700: { const c = activeComponent; intStack[isp++] = c?.objId ?? -1; break; }
            case 1701: {
                const c = activeComponent;
                intStack[isp++] = c?.objId === -1 ? 0 : (c?.objCount ?? 0);
                break;
            }
            case 1702: { const c = activeComponent; intStack[isp++] = (c as any)?.createdComponentId ?? -1; break; }
            case 1800: { const c = activeComponent; intStack[isp++] = (c as any)?.targetMask ?? 0; break; }
            case 1801: {
                const optIdx = intStack[--isp] - 1;
                const c = activeComponent;
                stringStack[ssp++] = optIdx >= 0 ? ((c as any)?.ops?.[optIdx] ?? (c as any)?.options?.[optIdx] ?? "") : "";
                break;
            }
            case 1802: { const c = activeComponent; stringStack[ssp++] = (c as any)?.optionBase ?? ""; break; }

            // Direct component getters (rt4 2500-2802 variants).
            case 2500: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c ? c.x : 0; break; }
            case 2501: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c ? c.y : 0; break; }
            case 2502: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c ? c.width : 0; break; }
            case 2503: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c ? c.height : 0; break; }
            case 2504: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.hidden ? 1 : 0; break; }
            case 2505: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.layer ?? 0; break; }
            case 2600: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.scrollPosX ?? 0; break; }
            case 2601: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.scrollPos ?? 0; break; }
            case 2602: { const c = hooks.getComponent?.(intStack[--isp]); stringStack[ssp++] = c?.text ?? ""; break; }
            case 2603: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.scrollMaxH ?? 0; break; }
            case 2604: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.scrollMaxV ?? 0; break; }
            case 2605: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.modelZoom ?? 0; break; }
            case 2606: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.modelXAngle ?? 0; break; }
            case 2607: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.modelYOffset ?? 0; break; }
            case 2608: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.modelYAngle ?? 0; break; }
            case 2609: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.alpha ?? 0; break; }
            case 2610: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.modelXOffset ?? 0; break; }
            case 2611: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.modelZOffset ?? 0; break; }
            case 2612: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.sprite ?? -1; break; }
            case 2700: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.objId ?? -1; break; }
            case 2701: {
                const c = hooks.getComponent?.(intStack[--isp]);
                intStack[isp++] = c?.objId === -1 ? 0 : (c?.objCount ?? 0);
                break;
            }
            case 2702: {
                const parentId = intStack[--isp];
                intStack[isp++] = hooks.hasOpenInterface?.(parentId) ? 1 : 0;
                break;
            }
            case 2703: {
                const c = hooks.getComponent?.(intStack[--isp]);
                const children = c?.createdComponents;
                if (!children) {
                    intStack[isp++] = 0;
                    break;
                }
                let next = children.length;
                for (let i = 0; i < children.length; i++) {
                    if (!children[i]) { next = i; break; }
                }
                intStack[isp++] = next | 0;
                break;
            }
            case 2704:
            case 2705: {
                const interfaceId = intStack[--isp];
                const parentId = intStack[--isp];
                intStack[isp++] = hooks.hasChildInterface?.(parentId, interfaceId) ? 1 : 0;
                break;
            }
            case 2800: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = (c as any)?.targetMask ?? 0; break; }
            case 2801: {
                const optIdx = intStack[--isp] - 1;
                const c = hooks.getComponent?.(intStack[--isp]);
                stringStack[ssp++] = optIdx >= 0 ? ((c as any)?.ops?.[optIdx] ?? (c as any)?.options?.[optIdx] ?? "") : "";
                break;
            }
            case 2802: { const c = hooks.getComponent?.(intStack[--isp]); stringStack[ssp++] = (c as any)?.optionBase ?? ""; break; }

            default:
                // Unsupported opcode — halt cleanly with diagnostics so the embedder can
                // see which script needs more of the rt4 ScriptRunner ported.
                return finalize("halt", `unsupported opcode ${opcode}`);
        }
    }
    return finalize("error", "cycle budget exhausted");

    function getSetterComponent(op: number): Cs2Component | null {
        return op >= 2000 ? hooks.getComponent?.(intStack[--isp]) ?? null : activeComponent;
    }

    function estimateVisibleWidth(text: string): number {
        return (text || "").replace(/<[^>]*>/g, "").length * 6;
    }

    function estimateLineCount(text: string, width: number): number {
        const maxWidth = Math.max(1, width | 0);
        const lineCapacity = Math.max(1, Math.floor(maxWidth / 6));
        const clean = (text || "").replace(/<br>/gi, "\n").replace(/<[^>]*>/g, "");
        let lines = 0;
        for (const line of clean.split("\n")) {
            lines += Math.max(1, Math.ceil(line.length / lineCapacity));
        }
        return lines | 0;
    }

    function estimateMaxLineWidth(text: string, width: number): number {
        const maxWidth = Math.max(0, width | 0);
        const clean = (text || "").replace(/<br>/gi, "\n").replace(/<[^>]*>/g, "");
        let measured = 0;
        for (const line of clean.split("\n")) measured = Math.max(measured, estimateVisibleWidth(line));
        return Math.min(measured, maxWidth) | 0;
    }

    function finalize(status: "ok" | "halt" | "error", reason: string | null): Cs2Result {
        return {
            status,
            intResult: isp > 0 ? intStack[isp - 1] : null,
            stringResult: ssp > 0 ? stringStack[ssp - 1] : null,
            cycles,
            lastOpcode,
            reason: reason ?? undefined,
        };
    }

    function newFrame(s: ClientScript530Data): CallFrame {
        return {
            script: s,
            pc: 0,
            intLocals: new Int32Array(s.intLocalCount),
            stringLocals: new Array(s.stringLocalCount).fill(""),
        };
    }
}
