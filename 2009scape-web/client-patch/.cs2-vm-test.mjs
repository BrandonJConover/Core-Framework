/**
 * CS2 VM trace harness. Hand-builds a few small scripts in-memory (no decode)
 * and exercises the VM. Verifies:
 *   - basic int arithmetic + push/pop
 *   - branch_eq / branch_ne / jump
 *   - varp + varbit hooks
 *   - return from script
 *   - string concat
 *   - call_script with args
 *
 * Output: .cs2-vm-trace.txt + exit 0 when all pass.
 */
import { readFileSync, writeFileSync } from "fs";
import { createRequire } from "module";

let loadedProductionVm = false;
const runClientScript = await loadProductionVm();

async function loadProductionVm() {
    try {
        const require = createRequire(new URL("../client/package.json", import.meta.url));
        const ts = require("typescript");
        const source = readFileSync(new URL("osrs/script/ClientScript530.ts", import.meta.url), "utf8");
        const js = ts.transpileModule(source, {
            compilerOptions: {
                module: ts.ModuleKind.ES2020,
                target: ts.ScriptTarget.ES2019,
            },
        }).outputText;
        const encoded = Buffer.from(js, "utf8").toString("base64");
        const mod = await import(`data:text/javascript;base64,${encoded}`);
        loadedProductionVm = true;
        return mod.runClientScript;
    } catch (err) {
        console.warn(`[CS2] production VM import failed, using inline mirror: ${err?.message ?? err}`);
        return runMirroredClientScript;
    }
}

// Inline-port the VM (mirrors ClientScript530.ts). Pure JS for offline use.
const INT_STACK_SIZE = 1000;
const STR_STACK_SIZE = 1000;
const MAX_CYCLES = 500_000;

function normalizeSocialName(name) {
    return (name || "").replace(/^@cr\d+@/i, "").replace(/^<img=\d+>/i, "").trim().toLowerCase();
}

function runMirroredClientScript(script, args, hooks = {}) {
    const intStack = new Int32Array(INT_STACK_SIZE);
    const stringStack = new Array(STR_STACK_SIZE);
    let isp = 0, ssp = 0;
    const callStack = [];
    let activeComponent1 = null;
    let activeComponent2 = null;
    let activeComponent = null;
    const arrays = new Map();
    let frame = newFrame(script);
    let intArgIdx = 0, strArgIdx = 0;
    for (const arg of args) {
        if (typeof arg === "string") {
            if (strArgIdx < script.stringArgCount) frame.stringLocals[strArgIdx++] = arg;
        } else {
            if (intArgIdx < script.intArgCount) frame.intLocals[intArgIdx++] = arg | 0;
        }
    }
    let cycles = 0, lastOpcode = -1;
    while (cycles < MAX_CYCLES) {
        cycles++;
        if (frame.pc >= frame.script.opcodes.length) return finalize("ok", null);
        const op = frame.script.opcodes[frame.pc];
        const ia = frame.script.intOperands[frame.pc];
        const sa = frame.script.stringOperands[frame.pc];
        lastOpcode = op;
        frame.pc++;
        activeComponent = ia === 1 ? activeComponent1 : activeComponent2;
        switch (op) {
            case 0:  intStack[isp++] = ia; break;
            case 3:  stringStack[ssp++] = sa ?? ""; break;
            case 33: intStack[isp++] = frame.intLocals[ia]; break;
            case 34: frame.intLocals[ia] = intStack[--isp]; break;
            case 35: stringStack[ssp++] = frame.stringLocals[ia] ?? ""; break;
            case 36: frame.stringLocals[ia] = stringStack[--ssp]; break;
            case 38: --isp; break;
            case 39: --ssp; break;
            case 6:  frame.pc += ia; break;
            case 7:  { const b = intStack[--isp]; const a = intStack[--isp]; if (a !== b) frame.pc += ia; break; }
            case 8:  { const b = intStack[--isp]; const a = intStack[--isp]; if (a === b) frame.pc += ia; break; }
            case 9:  { const b = intStack[--isp]; const a = intStack[--isp]; if (a < b)  frame.pc += ia; break; }
            case 10: { const b = intStack[--isp]; const a = intStack[--isp]; if (a > b)  frame.pc += ia; break; }
            case 31: { const b = intStack[--isp]; const a = intStack[--isp]; if (a >= b) frame.pc += ia; break; }
            case 32: { const b = intStack[--isp]; const a = intStack[--isp]; if (a <= b) frame.pc += ia; break; }
            case 1:  intStack[isp++] = (hooks.getVarp?.(ia) ?? 0) | 0; break;
            case 2:  hooks.setVarp?.(ia, intStack[--isp]); break;
            case 25: intStack[isp++] = (hooks.getVarbit?.(ia) ?? 0) | 0; break;
            case 27: hooks.setVarbit?.(ia, intStack[--isp]); break;
            case 21: { if (callStack.length === 0) return finalize("ok", null); frame = callStack.pop(); break; }
            case 40: {
                if (!hooks.loadScript) return finalize("halt", "loadScript hook missing");
                const sub = hooks.loadScript(ia);
                if (!sub) return finalize("halt", `script ${ia} not found`);
                callStack.push(frame);
                frame = newFrame(sub);
                for (let i = sub.intArgCount - 1; i >= 0; i--) frame.intLocals[i] = intStack[--isp];
                for (let i = sub.stringArgCount - 1; i >= 0; i--) frame.stringLocals[i] = stringStack[--ssp];
                break;
            }
            case 51: {
                const key = intStack[--isp];
                const tbl = frame.script.switchTables[ia];
                const delta = tbl ? tbl.get(key) : undefined;
                if (delta !== undefined) frame.pc += delta;
                break;
            }
            case 37: {
                const count = ia;
                let s = "";
                const base = ssp - count;
                for (let i = 0; i < count; i++) s += stringStack[base + i] ?? "";
                ssp = base;
                stringStack[ssp++] = s;
                break;
            }
            case 4000: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = (a + b) | 0; break; }
            case 4001: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = (a - b) | 0; break; }
            case 4002: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = Math.imul(a, b); break; }
            case 4003: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = b === 0 ? 0 : (a / b) | 0; break; }
            case 4006: { const x = intStack[--isp]; const x1 = intStack[--isp]; const x0 = intStack[--isp]; const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = x1 === x0 ? a : (((b - a) * (x - x0)) / (x1 - x0) + a) | 0; break; }
            case 4007: { const pct = intStack[--isp]; const base = intStack[--isp]; intStack[isp++] = ((base * pct) / 100 + base) | 0; break; }
            case 4008: { const bit = intStack[--isp]; const value = intStack[--isp]; intStack[isp++] = (value | (1 << bit)) | 0; break; }
            case 4009: { const bit = intStack[--isp]; const value = intStack[--isp]; intStack[isp++] = (value & ~(1 << bit)) | 0; break; }
            case 4010: { const bit = intStack[--isp]; const value = intStack[--isp]; intStack[isp++] = (value & (1 << bit)) === 0 ? 0 : 1; break; }
            case 4014: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = (a & b) | 0; break; }
            case 4015: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = (a | b) | 0; break; }
            case 4016: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = Math.min(a, b) | 0; break; }
            case 4017: { const b = intStack[--isp]; const a = intStack[--isp]; intStack[isp++] = Math.max(a, b) | 0; break; }
            case 4018: { const scale = intStack[--isp]; const divisor = intStack[--isp]; const value = intStack[--isp]; intStack[isp++] = divisor === 0 ? 0 : ((value * scale) / divisor) | 0; break; }
            // Strings 4100+
            case 4100: { const i = intStack[--isp]; const s = stringStack[--ssp] ?? ""; stringStack[ssp++] = s + String(i); break; }
            case 4101: { const b = stringStack[--ssp] ?? ""; const a = stringStack[--ssp] ?? ""; stringStack[ssp++] = a + b; break; }
            case 4103: { const s = stringStack[--ssp] ?? ""; stringStack[ssp++] = s.toLowerCase(); break; }
            case 4105: { const female = stringStack[--ssp] ?? ""; const male = stringStack[--ssp] ?? ""; stringStack[ssp++] = hooks.getPlayerGender?.() === 1 ? female : male; break; }
            case 4108: { const fontId = intStack[--isp]; const width = intStack[--isp]; const text = stringStack[--ssp] ?? ""; intStack[isp++] = hooks.measureTextLineCount?.(text, width, fontId) ?? Math.max(1, Math.ceil(text.replace(/<[^>]*>/g, "").length * 6 / Math.max(1, width))); break; }
            case 4109: { const fontId = intStack[--isp]; const width = intStack[--isp]; const text = stringStack[--ssp] ?? ""; intStack[isp++] = hooks.measureTextMaxLineWidth?.(text, width, fontId) ?? Math.min(text.replace(/<[^>]*>/g, "").length * 6, Math.max(0, width)); break; }
            case 4111: { const s = stringStack[--ssp] ?? ""; let out = ""; for (let i = 0; i < s.length; i++) { const ch = s.charAt(i); out += ch === "<" ? "<lt>" : ch === ">" ? "<gt>" : ch; } stringStack[ssp++] = out; break; }
            case 4117: { const s = stringStack[--ssp] ?? ""; intStack[isp++] = s.length; break; }
            case 4118: { const end = intStack[--isp]; const start = intStack[--isp]; const s = stringStack[--ssp] ?? ""; const a = Math.max(0, Math.min(s.length, start)); const b = Math.max(a, Math.min(s.length, end)); stringStack[ssp++] = s.substring(a, b); break; }
            case 4119: { const s = stringStack[--ssp] ?? ""; stringStack[ssp++] = s.replace(/<[^>]*>/g, ""); break; }
            case 4124: { const flag = intStack[--isp]; void flag; const value = intStack[--isp]; stringStack[ssp++] = String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ","); break; }
            // Items 4200+
            case 4200: { const id = intStack[--isp]; stringStack[ssp++] = hooks.getItem?.(id)?.name ?? ""; break; }
            case 4203: { const id = intStack[--isp]; intStack[isp++] = hooks.getItem?.(id)?.cost ?? 0; break; }
            case 4204: { const id = intStack[--isp]; intStack[isp++] = hooks.getItem?.(id)?.isStackable ? 1 : 0; break; }
            // Component getters 1500+
            case 1500: { const c = activeComponent; intStack[isp++] = c ? c.x : 0; break; }
            case 1502: { const c = activeComponent; intStack[isp++] = c ? c.width : 0; break; }
            case 1504: { const c = activeComponent; intStack[isp++] = c?.hidden ? 1 : 0; break; }
            case 1602: { const c = activeComponent; stringStack[ssp++] = c?.text ?? ""; break; }
            case 2500: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c ? c.x : 0; break; }
            case 2502: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c ? c.width : 0; break; }
            case 2602: { const c = hooks.getComponent?.(intStack[--isp]); stringStack[ssp++] = c?.text ?? ""; break; }
            case 2700: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.objId ?? -1; break; }
            case 2701: { const c = hooks.getComponent?.(intStack[--isp]); intStack[isp++] = c?.objId === -1 ? 0 : (c?.objCount ?? 0); break; }
            case 2702: { const parentId = intStack[--isp]; intStack[isp++] = hooks.hasOpenInterface?.(parentId) ? 1 : 0; break; }
            case 2703: { const c = hooks.getComponent?.(intStack[--isp]); const children = c?.createdComponents; if (!children) { intStack[isp++] = 0; break; } let next = children.length; for (let i = 0; i < children.length; i++) if (!children[i]) { next = i; break; } intStack[isp++] = next; break; }
            case 2704:
            case 2705: { const interfaceId = intStack[--isp]; const parentId = intStack[--isp]; intStack[isp++] = hooks.hasChildInterface?.(parentId, interfaceId) ? 1 : 0; break; }
            // Active-component setChild
            case 200: { const childId = intStack[--isp]; const ifId = intStack[--isp]; if (childId === -1) { activeComponent = null; if (ia === 1) activeComponent1 = null; else activeComponent2 = null; intStack[isp++] = 0; } else { const hash = (ifId << 16) | (childId & 0xFFFF); activeComponent = hooks.getComponent?.(hash) ?? null; if (ia === 1) activeComponent1 = activeComponent; else activeComponent2 = activeComponent; intStack[isp++] = activeComponent ? 1 : 0; } break; }
            case 201: { const hash = intStack[--isp]; activeComponent = hooks.getComponent?.(hash) ?? null; if (ia === 1) activeComponent1 = activeComponent; else activeComponent2 = activeComponent; intStack[isp++] = activeComponent ? 1 : 0; break; }
            // Component setters
            case 1003: { const v = intStack[--isp]; if (activeComponent) activeComponent.hidden = v !== 0; break; }
            case 1101: { const v = intStack[--isp]; if (activeComponent) activeComponent.colour = v | 0; break; }
            case 1112: { const t = stringStack[--ssp] ?? ""; if (activeComponent) activeComponent.text = t; break; }
            // Character design opcodes
            case 403: { const identikit = intStack[--isp]; const featureId = intStack[--isp]; hooks.setPlayerIdentikit?.(featureId, identikit); break; }
            case 404: { const color = intStack[--isp]; const slot = intStack[--isp]; hooks.setPlayerColor?.(slot, color); break; }
            case 410: { hooks.setPlayerGender?.(intStack[--isp] !== 0); break; }
            // Client action/media opcodes
            case 3100: { hooks.addGameMessage?.(stringStack[--ssp] ?? ""); break; }
            case 3101: { const delay = intStack[--isp]; const seqId = intStack[--isp]; hooks.animateSelf?.(seqId, delay); break; }
            case 3103: { hooks.closeWidgets?.(); break; }
            case 3104: { const s = stringStack[--ssp] ?? ""; hooks.resumeIntegerInput?.(/^[-+]?\d+$/.test(s) ? parseInt(s, 10) | 0 : 0); break; }
            case 3105: { hooks.resumeNameInput?.(stringStack[--ssp] ?? ""); break; }
            case 3106: { hooks.resumeStringInput?.(stringStack[--ssp] ?? ""); break; }
            case 3107: { const playerIndex = intStack[--isp]; const option = stringStack[--ssp] ?? ""; hooks.clickPlayerOption?.(option, playerIndex); break; }
            case 3108: { const componentHash = intStack[--isp]; const arg1 = intStack[--isp]; const arg0 = intStack[--isp]; hooks.runWidgetAction?.(arg0, arg1, hooks.getComponent?.(componentHash) ?? null); break; }
            case 3109: { const arg1 = intStack[--isp]; const arg0 = intStack[--isp]; hooks.runWidgetAction?.(arg0, arg1, activeComponent); break; }
            case 3110: { hooks.sendDialogAction?.(intStack[--isp]); break; }
            case 3200: { const delay = intStack[--isp]; const loops = intStack[--isp]; const soundId = intStack[--isp]; hooks.playSoundEffect?.(soundId, loops, delay); break; }
            case 3201: { hooks.playMusic?.(intStack[--isp]); break; }
            case 3202: { const delay = intStack[--isp]; const jingleId = intStack[--isp]; hooks.playMusicEffect?.(jingleId, delay); break; }
            // Skill query
            case 3300: { intStack[isp++] = hooks.getClientCycle?.() ?? cycles; break; }
            case 3301: { const slot = intStack[--isp]; const id = intStack[--isp]; const c = hooks.getContainer?.(id); intStack[isp++] = c && slot >= 0 && slot < c.items.length ? c.items[slot] : -1; break; }
            case 3302: { const slot = intStack[--isp]; const id = intStack[--isp]; const c = hooks.getContainer?.(id); intStack[isp++] = c && slot >= 0 && slot < c.amounts.length ? c.amounts[slot] : 0; break; }
            case 3305: { const id = intStack[--isp]; intStack[isp++] = hooks.getSkill?.(id)?.currentLevel ?? 0; break; }
            case 3307: { const id = intStack[--isp]; intStack[isp++] = hooks.getSkill?.(id)?.xp ?? 0; break; }
            case 3308: { intStack[isp++] = hooks.getMyLocation?.() ?? 0; break; }
            case 3309: { const coord = intStack[--isp]; intStack[isp++] = (coord >> 14) & 0x3FFF; break; }
            case 3310: { const coord = intStack[--isp]; intStack[isp++] = (coord >> 28) & 0x3; break; }
            case 3311: { const coord = intStack[--isp]; intStack[isp++] = coord & 0x3FFF; break; }
            case 3312: { intStack[isp++] = hooks.isMembers?.() ? 1 : 0; break; }
            case 3316: { intStack[isp++] = hooks.getClientRights?.() ?? 0; break; }
            case 3317: { intStack[isp++] = hooks.getSystemUpdateTimer?.() ?? 0; break; }
            case 3318: { intStack[isp++] = hooks.getWorldId?.() ?? 0; break; }
            case 3321: { intStack[isp++] = hooks.getRunEnergy?.() ?? 0; break; }
            case 3322: { intStack[isp++] = hooks.getPlayerWeight?.() ?? 0; break; }
            case 3326: { intStack[isp++] = hooks.getCombatLevel?.() ?? 0; break; }
            case 3327: { intStack[isp++] = hooks.getPlayerGender?.() === 1 ? 1 : 0; break; }
            case 3329: { intStack[isp++] = hooks.isMapQuickChat?.() ? 1 : 0; break; }
            // Container query
            case 3304: { const id = intStack[--isp]; intStack[isp++] = hooks.getContainer?.(id)?.capacity ?? 0; break; }
            case 3331: { const id = intStack[--isp]; const c = hooks.getContainer?.(id); if (!c) { intStack[isp++] = 0; break; } let n = 0; for (let i = 0; i < c.items.length; i++) if (c.items[i] >= 0 && (c.amounts[i] || 0) > 0) n++; intStack[isp++] = n; break; }
            case 3335: { intStack[isp++] = hooks.getLanguage?.() ?? 0; break; }
            case 3336: { const y = intStack[--isp]; const plane = intStack[--isp]; const x = intStack[--isp]; const base = intStack[--isp]; intStack[isp++] = (base + (x << 14) + (plane << 28) + y) | 0; break; }
            case 3337: { intStack[isp++] = hooks.getAffiliate?.() ?? 0; break; }
            // Social query
            case 3600: { const state = hooks.getFriendListState?.() ?? 2; intStack[isp++] = state === 0 ? -2 : state === 1 ? -1 : (hooks.getFriendCount?.() ?? 0); break; }
            case 3601: { const idx = intStack[--isp]; stringStack[ssp++] = hooks.getFriend?.(idx)?.name ?? ""; break; }
            case 3602: { const idx = intStack[--isp]; intStack[isp++] = hooks.getFriend?.(idx)?.world ?? 0; break; }
            case 3603: { const idx = intStack[--isp]; intStack[isp++] = hooks.getFriend?.(idx)?.rank ?? 0; break; }
            case 3609: { const name = normalizeSocialName(stringStack[--ssp] ?? ""); intStack[isp++] = hooks.isFriend?.(name) ? 1 : 0; break; }
            case 3610: { const idx = intStack[--isp]; stringStack[ssp++] = hooks.getFriend?.(idx)?.worldName ?? ""; break; }
            case 3611: { stringStack[ssp++] = hooks.getClan?.()?.name ?? ""; break; }
            case 3612: { const clan = hooks.getClan?.(); intStack[isp++] = clan ? clan.members.length : 0; break; }
            case 3613: { const idx = intStack[--isp]; stringStack[ssp++] = hooks.getClan?.()?.members[idx]?.name ?? ""; break; }
            case 3614: { const idx = intStack[--isp]; intStack[isp++] = hooks.getClan?.()?.members[idx]?.world ?? 0; break; }
            case 3615: { const idx = intStack[--isp]; intStack[isp++] = hooks.getClan?.()?.members[idx]?.rank ?? 0; break; }
            case 3616: { intStack[isp++] = hooks.getClan?.()?.minKick ?? 0; break; }
            case 3618: { intStack[isp++] = hooks.getClan?.()?.rank ?? 0; break; }
            case 3621: { const state = hooks.getFriendListState?.() ?? 2; intStack[isp++] = state === 0 ? -1 : (hooks.getIgnoreCount?.() ?? 0); break; }
            case 3622: { const idx = intStack[--isp]; stringStack[ssp++] = hooks.getIgnoreName?.(idx) ?? ""; break; }
            case 3623: { const name = normalizeSocialName(stringStack[--ssp] ?? ""); intStack[isp++] = hooks.isIgnored?.(name) ? 1 : 0; break; }
            case 3624: { const idx = intStack[--isp]; const member = hooks.getClan?.()?.members[idx]?.name ?? ""; intStack[isp++] = normalizeSocialName(member) === normalizeSocialName(hooks.getSelfName?.() ?? "") ? 1 : 0; break; }
            case 3625: { stringStack[ssp++] = hooks.getClan?.()?.owner ?? ""; break; }
            case 3626: { const idx = intStack[--isp]; stringStack[ssp++] = hooks.getClan?.()?.members[idx]?.worldName ?? ""; break; }
            case 3627: { const idx = intStack[--isp]; intStack[isp++] = hooks.getFriend?.(idx)?.sameGame ? 1 : 0; break; }
            case 3628: { const name = normalizeSocialName(stringStack[--ssp] ?? ""); intStack[isp++] = hooks.getFriendIndex?.(name) ?? -1; break; }
            case 3629: { intStack[isp++] = hooks.getCountry?.() ?? 0; break; }
            // Grand Exchange query
            case 3903: { const slot = intStack[--isp]; intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.type ?? 0; break; }
            case 3904: { const slot = intStack[--isp]; intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.item ?? -1; break; }
            case 3905: { const slot = intStack[--isp]; intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.price ?? 0; break; }
            case 3906: { const slot = intStack[--isp]; intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.count ?? 0; break; }
            case 3907: { const slot = intStack[--isp]; intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.completedCount ?? 0; break; }
            case 3908: { const slot = intStack[--isp]; intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.completedGold ?? 0; break; }
            case 3910: { const slot = intStack[--isp]; intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.status === 0 ? 1 : 0; break; }
            case 3911: { const slot = intStack[--isp]; intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.status === 2 ? 1 : 0; break; }
            case 3912: { const slot = intStack[--isp]; intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.status === 5 ? 1 : 0; break; }
            case 3913: { const slot = intStack[--isp]; intStack[isp++] = hooks.getGrandExchangeOffer?.(slot)?.status === 1 ? 1 : 0; break; }
            // Chat query/settings
            case 5000: { intStack[isp++] = hooks.getPublicChatSetting?.() ?? 0; break; }
            case 5001: { const trade = intStack[--isp]; const priv = intStack[--isp]; const pub = intStack[--isp]; hooks.setChatSettings?.(pub, priv, trade); break; }
            case 5002: { --ssp; isp -= 2; break; }
            case 5003: { const idx = intStack[--isp]; stringStack[ssp++] = hooks.getChatMessage?.(idx)?.message ?? ""; break; }
            case 5004: { const idx = intStack[--isp]; const msg = hooks.getChatMessage?.(idx); intStack[isp++] = msg && msg.message !== "" ? msg.type : -1; break; }
            case 5005: { intStack[isp++] = hooks.getPrivateChatSetting?.() ?? 0; break; }
            case 5008: { --ssp; break; }
            case 5009: { ssp -= 2; break; }
            case 5010: { const idx = intStack[--isp]; stringStack[ssp++] = hooks.getChatMessage?.(idx)?.name ?? ""; break; }
            case 5011: { const idx = intStack[--isp]; stringStack[ssp++] = hooks.getChatMessage?.(idx)?.clan ?? ""; break; }
            case 5012: { const idx = intStack[--isp]; intStack[isp++] = hooks.getChatMessage?.(idx)?.phraseId ?? -1; break; }
            case 5015: { stringStack[ssp++] = hooks.getSelfName?.() ?? ""; break; }
            case 5016: { intStack[isp++] = hooks.getTradeSetting?.() ?? 0; break; }
            case 5017: { intStack[isp++] = hooks.getChatSize?.() ?? 0; break; }
            // Keyboard/time
            case 5100: { intStack[isp++] = hooks.isKeyHeld?.("alt") ? 1 : 0; break; }
            case 5101: { intStack[isp++] = hooks.isKeyHeld?.("ctrl") ? 1 : 0; break; }
            case 5102: { intStack[isp++] = hooks.isKeyHeld?.("shift") ? 1 : 0; break; }
            case 5300: { const h = intStack[--isp]; const w = intStack[--isp]; intStack[isp++] = hooks.requestFullscreen?.(w, h) ? 1 : 0; break; }
            case 5301: { hooks.exitFullscreen?.(); break; }
            case 5302: { intStack[isp++] = hooks.getDisplayModeCount?.() ?? 0; break; }
            case 5303: { const idx = intStack[--isp]; const m = hooks.getDisplayMode?.(idx); intStack[isp++] = m?.width ?? 0; intStack[isp++] = m?.height ?? 0; break; }
            case 5305: { intStack[isp++] = hooks.getPreferredFullscreenMode?.() ?? -1; break; }
            case 5306: { intStack[isp++] = hooks.getWindowMode?.() ?? 0; break; }
            case 5307: { let mode = intStack[--isp]; if (mode < 0 || mode > 2) mode = 0; hooks.setWindowMode?.(mode); break; }
            case 5308: { intStack[isp++] = hooks.getPreferredWindowMode?.() ?? 0; break; }
            case 5309: { let mode = intStack[--isp]; if (mode < 0 || mode > 2) mode = 0; hooks.setPreferredWindowMode?.(mode); break; }
            case 5500: { const acc = intStack[--isp]; const speed = intStack[--isp]; const height = intStack[--isp]; const coord = intStack[--isp]; hooks.moveCameraTo?.(coord, height, speed, acc); break; }
            case 5501: { const acc = intStack[--isp]; const speed = intStack[--isp]; const height = intStack[--isp]; const coord = intStack[--isp]; hooks.pointCameraAt?.(coord, height, speed, acc); break; }
            case 5502: { const values = new Array(6); for (let i = 5; i >= 0; i--) values[i] = intStack[--isp]; hooks.setCameraPath?.(values); break; }
            case 5503: { hooks.unlockCamera?.(); break; }
            case 5504: { const yaw = intStack[--isp]; const pitch = intStack[--isp]; hooks.setCameraRotation?.(pitch, yaw); break; }
            case 5505: { intStack[isp++] = hooks.getCameraRotation?.().pitch ?? 0; break; }
            case 5506: { intStack[isp++] = hooks.getCameraRotation?.().yaw ?? 0; break; }
            case 5600: { const flags = intStack[--isp]; const password = stringStack[--ssp] ?? ""; const username = stringStack[--ssp] ?? ""; hooks.requestDirectLogin?.(username, password, flags); break; }
            case 5601: { hooks.skipLoginStage?.(); break; }
            case 5602: { hooks.resetLoginReply?.(); break; }
            case 5603: { const d = intStack[--isp]; const c = intStack[--isp]; const b = intStack[--isp]; const a = intStack[--isp]; hooks.checkAccountInfo?.(a, b, c, d); break; }
            case 5604: { const name = stringStack[--ssp] ?? ""; hooks.requestAccountName?.(name); break; }
            case 5605: { const d = intStack[--isp]; const c = intStack[--isp]; const b = intStack[--isp]; const a = intStack[--isp]; const password = stringStack[--ssp] ?? ""; const username = stringStack[--ssp] ?? ""; hooks.createAccount?.(username, password, a, b, c, d); break; }
            case 5606: { hooks.resetAccountCreateReply?.(); break; }
            case 5607: { intStack[isp++] = hooks.getGameLoginReply?.() ?? 0; break; }
            case 5608: { intStack[isp++] = hooks.getWorldSwitchTimer?.() ?? 0; break; }
            case 5609: { intStack[isp++] = hooks.getAccountCreateReply?.() ?? 0; break; }
            case 5610: { const names = hooks.getSuggestedAccountNames?.() ?? []; for (let i = 0; i < 5; i++) stringStack[ssp++] = names[i] ?? ""; hooks.clearSuggestedAccountNames?.(); break; }
            case 5611: { intStack[isp++] = hooks.getDetailedLoginReply?.() ?? 0; break; }
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
            case 6023: { let v = intStack[--isp]; if (v < 0) v = 0; if (v > 2) v = 2; const ok = hooks.setPreference?.("particleSetting", v); intStack[isp++] = ok === 0 ? 0 : 1; break; }
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
            case 6200: { let far = intStack[--isp]; if (far <= 0) far = 205; let near = intStack[--isp]; if (near <= 0) near = 256; hooks.setViewport?.("near", [near, far]); break; }
            case 6201: { let far = intStack[--isp]; if (far <= 0) far = 320; let near = intStack[--isp]; if (near <= 0) near = 256; hooks.setViewport?.("far", [near, far]); break; }
            case 6202: { let maxY = intStack[--isp]; if (maxY <= 0) maxY = 32767; let minY = intStack[--isp]; if (minY <= 0) minY = 1; let maxX = intStack[--isp]; if (maxX <= 0) maxX = 32767; let minX = intStack[--isp]; if (minX <= 0) minX = 1; if (minX > maxX) maxX = minX; if (maxY < minY) maxY = minY; hooks.setViewport?.("clamp", [minX, maxX, minY, maxY]); break; }
            case 6203: { const v = hooks.getViewport?.("size") ?? [0, 0]; intStack[isp++] = v[0] | 0; intStack[isp++] = v[1] | 0; break; }
            case 6204: { const v = hooks.getViewport?.("far") ?? [256, 320]; intStack[isp++] = v[0] | 0; intStack[isp++] = v[1] | 0; break; }
            case 6205: { const v = hooks.getViewport?.("near") ?? [256, 205]; intStack[isp++] = v[0] | 0; intStack[isp++] = v[1] | 0; break; }
            case 6300: { intStack[isp++] = ((hooks.getCurrentTimeMillis?.() ?? Date.now()) / 60000) | 0; break; }
            case 6301: { intStack[isp++] = (((hooks.getCurrentTimeMillis?.() ?? Date.now()) / 86400000) | 0) - 11745; break; }
            case 6302: { const year = intStack[--isp]; const month = intStack[--isp]; const day = intStack[--isp]; intStack[isp++] = ((Date.UTC(year, month, day, 12) / 86400000) | 0) - 11745; break; }
            case 6303: { intStack[isp++] = new Date(hooks.getCurrentTimeMillis?.() ?? Date.now()).getFullYear(); break; }
            case 6304: { const year = intStack[--isp]; let leap = true; if (year < 0) leap = (year + 1) % 4 === 0; else if (year < 1582) leap = year % 4 === 0; else if (year % 4 !== 0) leap = false; else if (year % 100 !== 0) leap = true; else if (year % 400 !== 0) leap = false; intStack[isp++] = leap ? 1 : 0; break; }
            case 6405: { intStack[isp++] = hooks.canShowVideoAd?.() ? 1 : 0; break; }
            case 6406: { intStack[isp++] = hooks.isShowingVideoAd?.() ? 1 : 0; break; }
            case 6500: { intStack[isp++] = hooks.fetchWorldList?.() ? 1 : 0; break; }
            case 6501: { const w = hooks.getFirstWorld?.() ?? null; if (!w) { intStack[isp++] = -1; intStack[isp++] = 0; stringStack[ssp++] = ""; intStack[isp++] = 0; stringStack[ssp++] = ""; intStack[isp++] = 0; } else { intStack[isp++] = w.id | 0; intStack[isp++] = w.flags | 0; stringStack[ssp++] = w.activity || ""; intStack[isp++] = w.countryFlag | 0; stringStack[ssp++] = w.countryName || ""; intStack[isp++] = w.players | 0; } break; }
            case 6502: { const w = hooks.getNextWorld?.() ?? null; if (!w) { intStack[isp++] = -1; intStack[isp++] = 0; stringStack[ssp++] = ""; intStack[isp++] = 0; stringStack[ssp++] = ""; intStack[isp++] = 0; } else { intStack[isp++] = w.id | 0; intStack[isp++] = w.flags | 0; stringStack[ssp++] = w.activity || ""; intStack[isp++] = w.countryFlag | 0; stringStack[ssp++] = w.countryName || ""; intStack[isp++] = w.players | 0; } break; }
            case 6503: { const worldId = intStack[--isp]; intStack[isp++] = hooks.hopWorld?.(worldId) ? 1 : 0; break; }
            case 6504: { hooks.setLastWorld?.(intStack[--isp]); break; }
            case 6505: { intStack[isp++] = hooks.getLastWorld?.() ?? 0; break; }
            case 6506: { const worldId = intStack[--isp]; const w = hooks.getWorldById?.(worldId) ?? null; if (!w) { intStack[isp++] = -1; stringStack[ssp++] = ""; intStack[isp++] = 0; stringStack[ssp++] = ""; intStack[isp++] = 0; } else { intStack[isp++] = w.flags | 0; stringStack[ssp++] = w.activity || ""; intStack[isp++] = w.countryFlag | 0; stringStack[ssp++] = w.countryName || ""; intStack[isp++] = w.players | 0; } break; }
            case 6507: { const secondaryAscending = intStack[--isp] === 1; const secondaryKey = intStack[--isp]; const primaryAscending = intStack[--isp] === 1; const primaryKey = intStack[--isp]; hooks.sortWorldList?.(primaryKey, primaryAscending, secondaryKey, secondaryAscending); break; }
            case 6600: { hooks.setSiteSettingsMembers?.(intStack[--isp] === 1); break; }
            case 6601: { intStack[isp++] = hooks.isSiteSettingsMembers?.() ? 1 : 0; break; }
            // Enum/datamap
            case 3400: { const key = intStack[--isp]; const enumId = intStack[--isp]; const e = hooks.getEnum?.(enumId); stringStack[ssp++] = e?.intToString?.get(key) ?? e?.defaultString ?? ""; break; }
            case 3408: { const key = intStack[--isp]; const enumId = intStack[--isp]; const valueType = intStack[--isp]; const keyType = intStack[--isp]; const e = hooks.getEnum?.(enumId); if (!e || e.keyType !== keyType || e.valueType !== valueType) { if (valueType === 115) stringStack[ssp++] = ""; else intStack[isp++] = 0; } else if (valueType === 115) stringStack[ssp++] = e.intToString?.get(key) ?? e.defaultString ?? ""; else intStack[isp++] = e.intToInt?.get(key) ?? e.defaultInt ?? 0; break; }
            case 3409: { const value = intStack[--isp]; const enumId = intStack[--isp]; const valueType = intStack[--isp]; const e = hooks.getEnum?.(enumId); let found = 0; if (e && e.valueType === valueType && valueType !== 115) e.intToInt?.forEach((v) => { if (v === value) found = 1; }); intStack[isp++] = found; break; }
            case 3410: { const enumId = intStack[--isp]; const value = stringStack[--ssp] ?? ""; const e = hooks.getEnum?.(enumId); let found = 0; if (e && e.valueType === 115) e.intToString?.forEach((v) => { if (v === value) found = 1; }); intStack[isp++] = found; break; }
            case 3411: { const enumId = intStack[--isp]; const e = hooks.getEnum?.(enumId); intStack[isp++] = e ? (e.intToString?.size ?? e.intToInt?.size ?? 0) : 0; break; }
            // Arrays
            case 44: { const length = intStack[--isp]; if (length < 0 || length > 5000) return finalize("error", `invalid array length ${length}`); const arr = new Int32Array(length); if ((ia & 0xFFFF) !== 105) arr.fill(-1); arrays.set((ia >>> 16) & 0xFFFF, arr); break; }
            case 45: { const idx = intStack[--isp]; const arr = arrays.get(ia); intStack[isp++] = (arr && idx >= 0 && idx < arr.length) ? arr[idx] : 0; break; }
            case 46: { const value = intStack[--isp]; const idx = intStack[--isp]; const arr = arrays.get(ia); if (arr && idx >= 0 && idx < arr.length) arr[idx] = value | 0; break; }
            // Component lifecycle
            case 100: { const childIndex = intStack[--isp]; const type = intStack[--isp]; const parentHash = intStack[--isp]; if (type === 0) return finalize("error", "cannot create component with type 0"); const parent = hooks.getComponent?.(parentHash) ?? null; if (!parent) return finalize("error", `component ${parentHash} not found`); if (!parent.createdComponents) parent.createdComponents = []; while (parent.createdComponents.length <= childIndex) parent.createdComponents.push(null); if (childIndex > 0 && !parent.createdComponents[childIndex - 1]) return finalize("error", `gap at child index ${childIndex - 1}`); const created = hooks.createComponent?.(parentHash, type, childIndex, parent) ?? { x: 0, y: 0, width: 0, height: 0, hidden: false, text: "", id: parentHash, overlayer: parentHash, parentId: parentHash, layer: parentHash, type, if3: true, createdComponentId: childIndex }; parent.createdComponents[childIndex] = created; activeComponent = created; if (ia === 1) activeComponent1 = created; else activeComponent2 = created; break; }
            case 101: { const selected = ia === 1 ? activeComponent1 : activeComponent2; if (!selected) return finalize("error", "no active component to delete"); const childIndex = selected.createdComponentId ?? -1; if (childIndex === -1) return finalize("error", "tried to delete a static active component"); const parentHash = selected.id ?? selected.parentId ?? selected.layer ?? 0; const parent = hooks.getComponent?.(parentHash) ?? null; if (parent?.createdComponents && childIndex >= 0 && childIndex < parent.createdComponents.length) parent.createdComponents[childIndex] = null; hooks.deleteComponent?.(selected, parent); if (ia === 1) activeComponent1 = null; else activeComponent2 = null; activeComponent = null; break; }
            case 102: { const parentHash = intStack[--isp]; const parent = hooks.getComponent?.(parentHash) ?? null; if (parent) { parent.createdComponents = undefined; hooks.deleteComponentChildren?.(parentHash, parent); } break; }
            // Item search
            case 4210: { const exact = intStack[--isp]; const q = stringStack[--ssp] ?? ""; intStack[isp++] = hooks.searchItem?.(q, exact) ?? 0; break; }
            case 4211: { intStack[isp++] = hooks.nextSearchResult?.() ?? -1; break; }
            case 4208: { const paramId = intStack[--isp]; const itemId = intStack[--isp]; const v = hooks.getItemAttribute?.(itemId, paramId); if (typeof v === "string") stringStack[ssp++] = v; else intStack[isp++] = (v ?? 0) | 0; break; }
            // Layout setters
            case 1000: { const yMode = intStack[--isp]; const xMode = intStack[--isp]; const y = intStack[--isp]; const x = intStack[--isp]; void xMode; void yMode; if (activeComponent) { activeComponent.x = x | 0; activeComponent.y = y | 0; } break; }
            case 1001: { const hMode = intStack[--isp]; const wMode = intStack[--isp]; const h = intStack[--isp]; const w = intStack[--isp]; void wMode; void hMode; if (activeComponent) { activeComponent.width = w | 0; activeComponent.height = h | 0; } break; }
            case 2000: { const c = hooks.getComponent?.(intStack[--isp]); const yMode = intStack[--isp]; const xMode = intStack[--isp]; const y = intStack[--isp]; const x = intStack[--isp]; void xMode; void yMode; if (c) { c.x = x | 0; c.y = y | 0; } break; }
            case 2003: { const c = hooks.getComponent?.(intStack[--isp]); const v = intStack[--isp]; if (c) c.hidden = v !== 0; break; }
            case 2101: { const c = hooks.getComponent?.(intStack[--isp]); const v = intStack[--isp]; if (c) c.colour = v | 0; break; }
            case 2112: { const c = hooks.getComponent?.(intStack[--isp]); const t = stringStack[--ssp] ?? ""; if (c) c.text = t; break; }
            case 2201: { const c = hooks.getComponent?.(intStack[--isp]); const npcId = intStack[--isp]; if (c) { c.modelType = 2; c.modelId = npcId | 0; } break; }
            // Interaction setters
            case 1300:
            case 2300: { const c = op >= 2000 ? hooks.getComponent?.(intStack[--isp]) : activeComponent; const idx = intStack[--isp] - 1; const option = stringStack[--ssp] ?? ""; if (c && idx >= 0 && idx <= 9) { if (!c.ops) c.ops = []; c.ops[idx] = option; } break; }
            case 1305:
            case 2305: { const c = op >= 2000 ? hooks.getComponent?.(intStack[--isp]) : activeComponent; const value = stringStack[--ssp] ?? ""; if (c) c.optionBase = value; break; }
            case 1306:
            case 2306: { const c = op >= 2000 ? hooks.getComponent?.(intStack[--isp]) : activeComponent; const value = stringStack[--ssp] ?? ""; if (c) c.targetVerb = value; break; }
            case 2309: { const c = hooks.getComponent?.(intStack[--isp]); const cursor = intStack[--isp]; const optionIndex = intStack[--isp]; if (c && optionIndex >= 1 && optionIndex <= 10) { if (!c.optionCursors) c.optionCursors = []; c.optionCursors[optionIndex - 1] = cursor | 0; } break; }
            // Param lookup
            case 4500: { const paramId = intStack[--isp]; const structId = intStack[--isp]; const v = hooks.getStructParam?.(structId, paramId); if (typeof v === "string") stringStack[ssp++] = v; else intStack[isp++] = (v ?? 0) | 0; break; }
            default: return finalize("halt", `unsupported opcode ${op}`);
        }
    }
    return finalize("error", "cycle budget exhausted");

    function finalize(status, reason) {
        return {
            status,
            intResult: isp > 0 ? intStack[isp - 1] : null,
            stringResult: ssp > 0 ? stringStack[ssp - 1] : null,
            cycles,
            lastOpcode,
            reason,
        };
    }
    function newFrame(s) {
        return { script: s, pc: 0, intLocals: new Int32Array(s.intLocalCount), stringLocals: new Array(s.stringLocalCount).fill("") };
    }
}

// Helper to build a script. opcodes are written as [opcode, operand] pairs; switch tables array.
function makeScript(name, ops, intLocals, strLocals, intArgs, strArgs, switchTables = []) {
    return {
        name,
        opcodes: ops.map(([o]) => o),
        intOperands: ops.map(([, a]) => (typeof a === "number" ? a : 0)),
        stringOperands: ops.map(([, a]) => (typeof a === "string" ? a : null)),
        intLocalCount: intLocals,
        stringLocalCount: strLocals,
        intArgCount: intArgs,
        stringArgCount: strArgs,
        switchTables,
    };
}

// ── Test fixtures ─────────────────────────────────────────────────

const lines = [];
let failures = 0;
function assert(label, actual, expected) {
    const pass = actual === expected;
    if (!pass) {
        failures++;
        lines.push(`FAIL ${label}: expected=${JSON.stringify(expected)} actual=${JSON.stringify(actual)}`);
        console.error(`FAIL ${label}: expected=${JSON.stringify(expected)} actual=${JSON.stringify(actual)}`);
    }
    return pass;
}
function trace(msg) { lines.push(msg); console.log(msg); }

trace(`[CS2] vm=${loadedProductionVm ? "production" : "inline-mirror"}`);

// Game's CS2 hooks must expose the live packet-level container snapshots. Bank
// and inventory scripts often address container ids directly, before a decoded
// component/widget mirror exists.
{
    const gameSource = readFileSync(new URL("osrs/Game.ts", import.meta.url), "utf8");
    const ok = gameSource.includes("const liveItems = (game as any).containerItems?.[containerId];")
        && gameSource.includes("const liveAmounts = (game as any).containerAmounts?.[containerId];")
        && gameSource.includes("return { items: liveItems, amounts: liveAmounts, capacity: liveItems.length };");
    trace(`[CS2] game live container hook: ${ok ? "OK" : "MISSING"}`);
    assert("game live container hook", ok, true);
}

// 1. Arithmetic: 5 + 7 = 12, then return.
{
    const s = makeScript("add", [
        [0, 5],     // push 5
        [0, 7],     // push 7
        [4000, 0],  // add
        [21, 0],    // return
    ], 0, 0, 0, 0);
    const r = runClientScript(s, []);
    trace(`[CS2] add: status=${r.status} intResult=${r.intResult} cycles=${r.cycles}`);
    assert("add status", r.status, "ok");
    assert("add result", r.intResult, 12);
}

// 2. Branch: if 10 == 10, push 1; else push 0.
{
    const s = makeScript("eq_branch", [
        [0, 10],    // push 10
        [0, 10],    // push 10
        [8, 2],     // branch_eq +2 (skip past the "push 0" path)
        [0, 0],     // push 0
        [6, 1],     // jump +1 (skip past "push 1")
        [0, 1],     // push 1   ← branch lands here
        [21, 0],    // return
    ], 0, 0, 0, 0);
    const r = runClientScript(s, []);
    trace(`[CS2] branch_eq: status=${r.status} intResult=${r.intResult}`);
    assert("branch_eq status", r.status, "ok");
    assert("branch_eq result", r.intResult, 1);
}

// 3. Varp hook: get varp 100, multiply by 2, set varp 101 to result.
{
    const varps = { 100: 21 };
    const s = makeScript("varp_double", [
        [1, 100],   // push_varp 100
        [0, 2],     // push 2
        [4002, 0],  // mul
        [2, 101],   // set_varp 101
        [21, 0],    // return
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], {
        getVarp: (id) => varps[id] ?? 0,
        setVarp: (id, v) => { varps[id] = v; },
    });
    trace(`[CS2] varp_double: status=${r.status} varp[101]=${varps[101]}`);
    assert("varp_double status", r.status, "ok");
    assert("varp[101] after", varps[101], 42);
}

// 4. Locals: stash 99 in local 0, retrieve, add 1, return.
{
    const s = makeScript("local_inc", [
        [0, 99],    // push 99
        [34, 0],    // set_int_local 0
        [33, 0],    // push_int_local 0
        [0, 1],     // push 1
        [4000, 0],  // add
        [21, 0],    // return
    ], 1, 0, 0, 0);
    const r = runClientScript(s, []);
    trace(`[CS2] local_inc: status=${r.status} intResult=${r.intResult}`);
    assert("local_inc status", r.status, "ok");
    assert("local_inc result", r.intResult, 100);
}

// 5. String concat: "hello " + "world" → "hello world".
{
    const s = makeScript("strcat", [
        [3, "hello "],
        [3, "world"],
        [37, 2],    // concat 2 strings
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, []);
    trace(`[CS2] strcat: status=${r.status} stringResult="${r.stringResult}"`);
    assert("strcat status", r.status, "ok");
    assert("strcat result", r.stringResult, "hello world");
}

// 6. call_script: caller pushes 4, callee returns its arg + 10.
{
    const callee = makeScript("addTen", [
        [33, 0],    // push_int_local 0 (the arg)
        [0, 10],    // push 10
        [4000, 0],  // add
        [21, 0],    // return
    ], 1, 0, 1, 0);
    const caller = makeScript("caller", [
        [0, 4],     // push 4 (arg for callee)
        [40, 999],  // call_script 999
        [21, 0],    // return
    ], 0, 0, 0, 0);
    const r = runClientScript(caller, [], {
        loadScript: (id) => (id === 999 ? callee : null),
    });
    trace(`[CS2] call_script: status=${r.status} intResult=${r.intResult}`);
    assert("call_script status", r.status, "ok");
    assert("call_script result", r.intResult, 14);
}

// 7. Args: int arg 7, string arg "Bob", returns 7 in arg-local 0.
{
    const s = makeScript("argEcho", [
        [33, 0],    // push_int_local 0
        [21, 0],
    ], 1, 1, 1, 1);
    const r = runClientScript(s, [7, "Bob"]);
    trace(`[CS2] args: intArg passed=7 result=${r.intResult}`);
    assert("args result", r.intResult, 7);
}

// 8. String length: "OpenRSC" → 7
{
    const s = makeScript("strlen", [
        [3, "OpenRSC"],
        [4117, 0],  // LENGTH
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, []);
    trace(`[CS2] strlen: status=${r.status} intResult=${r.intResult}`);
    assert("strlen result", r.intResult, 7);
}

// 9. Substring: "Hello World".substring(6, 11) = "World"
{
    const s = makeScript("substr", [
        [3, "Hello World"],
        [0, 6],     // start
        [0, 11],    // end
        [4118, 0],  // SUBSTR
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, []);
    trace(`[CS2] substr: status=${r.status} stringResult="${r.stringResult}"`);
    assert("substr result", r.stringResult, "World");
}

// 10. Remove tags: "<col=ff0000>red</col>" → "red"
{
    const s = makeScript("remove_tags", [
        [3, "<col=ff0000>red</col>"],
        [4119, 0],  // REMOVE_TAGS
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, []);
    trace(`[CS2] remove_tags: stringResult="${r.stringResult}"`);
    assert("remove_tags result", r.stringResult, "red");
}

// 11. Format number: 1234567 → "1,234,567"
{
    const s = makeScript("fmt", [
        [0, 1234567],
        [0, 0],     // flag
        [4124, 0],  // FORMAT_NUMBER
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, []);
    trace(`[CS2] format: stringResult="${r.stringResult}"`);
    assert("format result", r.stringResult, "1,234,567");
}

// 12. Item lookup: id 4151 → "Abyssal whip", cost 100000
{
    const items = { 4151: { name: "Abyssal whip", cost: 100000, isStackable: false } };
    const s = makeScript("item", [
        [0, 4151],
        [4200, 0],  // GET_ITEM_NAME
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], { getItem: (id) => items[id] });
    trace(`[CS2] item_name: stringResult="${r.stringResult}"`);
    assert("item_name result", r.stringResult, "Abyssal whip");
}

// 13. Active component getter: read width without consuming a hash.
{
    const components = { [0xC0001]: { x: 5, y: 10, width: 200, height: 50, hidden: false, text: "Hi" } };
    const s = makeScript("comp_width", [
        [0, 0xC0001],
        [201, 0],   // set slot 2 active component
        [38, 0],
        [1502, 0],  // GET_WIDTH
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], { getComponent: (h) => components[h] });
    trace(`[CS2] comp_width: intResult=${r.intResult}`);
    assert("comp_width result", r.intResult, 200);
}

// 14. Active component getter: read text of same component → "Hi"
{
    const components = { [0xC0001]: { x: 5, y: 10, width: 200, height: 50, hidden: false, text: "Hi" } };
    const s = makeScript("comp_text", [
        [0, 0xC0001],
        [201, 0],
        [38, 0],
        [1602, 0],  // GET_TEXT
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], { getComponent: (h) => components[h] });
    trace(`[CS2] comp_text: stringResult="${r.stringResult}"`);
    assert("comp_text result", r.stringResult, "Hi");
}

// 15. Concat string + int: "Level " + 99 → "Level 99"
{
    const s = makeScript("concat_int", [
        [3, "Level "],
        [0, 99],
        [4100, 0],  // CONCAT_INT
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, []);
    trace(`[CS2] concat_int: stringResult="${r.stringResult}"`);
    assert("concat_int result", r.stringResult, "Level 99");
}

// 16. Set text on active component.
{
    const components = { [0xC0001]: { x: 0, y: 0, width: 100, height: 20, hidden: false, text: "Old" } };
    const s = makeScript("setText", [
        [0, 0xC0001],
        [201, 0],          // setChild2 → activate
        [38, 0],           // pop the success-flag the setter pushed
        [3, "New!"],
        [1112, 0],         // SET_TEXT
        [21, 0],
    ], 0, 0, 0, 0);
    runClientScript(s, [], { getComponent: (h) => components[h] });
    trace(`[CS2] setText: text="${components[0xC0001].text}"`);
    assert("setText result", components[0xC0001].text, "New!");
}

// 17. Toggle hidden.
{
    const components = { [0xC0002]: { x: 0, y: 0, width: 0, height: 0, hidden: false, text: "" } };
    const s = makeScript("hide", [
        [0, 0xC0002],
        [201, 0],
        [38, 0],
        [0, 1],
        [1003, 0],         // SET_HIDDEN
        [21, 0],
    ], 0, 0, 0, 0);
    runClientScript(s, [], { getComponent: (h) => components[h] });
    trace(`[CS2] setHidden: hidden=${components[0xC0002].hidden}`);
    assert("setHidden result", components[0xC0002].hidden, true);
}

// 18. Skill XP lookup.
{
    const skills = { 6: { currentLevel: 75, actualLevel: 75, xp: 1209022 } };
    const s = makeScript("skillXp", [
        [0, 6],
        [3307, 0],         // GET_SKILL_XP
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], { getSkill: (id) => skills[id] });
    trace(`[CS2] skillXp: intResult=${r.intResult}`);
    assert("skillXp result", r.intResult, 1209022);
}

// 19. Container occupancy.
{
    const containers = { 93: { items: [4151, -1, 4153, 4151], amounts: [1, 0, 1, 1], capacity: 4 } };
    const s = makeScript("invFill", [
        [0, 93],
        [3331, 0],         // distinct slots used
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], { getContainer: (id) => containers[id] });
    trace(`[CS2] invFill: intResult=${r.intResult}`);
    assert("invFill result", r.intResult, 3);
}

// 20. Arrays: init array of 5, write at index 2, read it back.
{
    const s = makeScript("array_rw", [
        [0, 5],         // length
        [44, 105],      // INIT_ARRAY id=0, default type=105
        [0, 2],         // index
        [0, 99],        // value
        [46, 0],        // WRITE_ARRAY 0, [2] = 99
        [0, 2],         // index
        [45, 0],        // READ_ARRAY 0, [2]
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, []);
    trace(`[CS2] array_rw: intResult=${r.intResult}`);
    assert("array_rw result", r.intResult, 99);
}

// 20b. RT4 array init: high 16 bits select array id; default type 105 fills 0, others fill -1.
{
    const s = makeScript("array_default", [
        [0, 2],
        [44, (3 << 16) | 115], // id=3, non-int default type -> -1
        [0, 0],
        [45, 3],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, []);
    trace(`[CS2] array_default: intResult=${r.intResult}`);
    assert("array_default result", r.intResult, -1);
}

// 20c. Dual active components: byte operand chooses slot 1 vs slot 2.
{
    const aHash = 0xC0005;
    const bHash = 0xC0006;
    const components = {
        [aHash]: { x: 0, y: 0, width: 111, height: 20, hidden: false, text: "A" },
        [bHash]: { x: 0, y: 0, width: 222, height: 20, hidden: false, text: "B" },
    };
    const s = makeScript("dual_active", [
        [0, aHash], [201, 0], [38, 0], // slot 2
        [0, bHash], [201, 1], [38, 0], // slot 1
        [3, "slot2"], [1112, 0],
        [3, "slot1"], [1112, 1],
        [1502, 0],
        [1502, 1],
        [4000, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], { getComponent: (h) => components[h] ?? null });
    trace(`[CS2] dual_active: intResult=${r.intResult} a="${components[aHash].text}" b="${components[bHash].text}"`);
    assert("dual_active result", r.intResult, 333);
    assert("dual_active slot2 text", components[aHash].text, "slot2");
    assert("dual_active slot1 text", components[bHash].text, "slot1");
}

// 20d. Direct component getter variants still consume an explicit hash.
{
    const hash = 0xC0007;
    const components = { [hash]: { x: 0, y: 0, width: 321, height: 20, hidden: false } };
    const s = makeScript("direct_comp_width", [
        [0, hash],
        [2502, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], { getComponent: (h) => components[h] ?? null });
    trace(`[CS2] direct_comp_width: intResult=${r.intResult}`);
    assert("direct_comp_width result", r.intResult, 321);
}

// 20e. IF3 lifecycle: create an active child, delete it, then clear children.
{
    const parentHash = 0xC0008;
    const parent = { x: 0, y: 0, width: 200, height: 100, hidden: false, text: "parent" };
    const components = { [parentHash]: parent };
    const created = [];
    const deleted = [];
    const hooks = {
        getComponent: (h) => components[h] ?? null,
        createComponent: (hash, type, childIndex) => {
            const child = { x: 0, y: 0, width: 0, height: 0, hidden: false, text: "", id: hash, layer: hash, type, if3: true, createdComponentId: childIndex };
            created.push(child);
            return child;
        },
        deleteComponent: (child) => { deleted.push(child); },
    };
    const s = makeScript("component_lifecycle", [
        [0, parentHash], [0, 4], [0, 0], [100, 0],
        [3, "child"], [1112, 0],
        [101, 0],
        [0, parentHash], [0, 5], [0, 0], [100, 0],
        [0, parentHash], [102, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], hooks);
    trace(`[CS2] component_lifecycle: status=${r.status} created=${created.length} deleted=${deleted.length}`);
    assert("component_lifecycle status", r.status, "ok");
    assert("component_lifecycle created count", created.length, 2);
    assert("component_lifecycle deleted text", deleted[0]?.text, "child");
    assert("component_lifecycle children cleared", parent.createdComponents, undefined);
}

// 20f. Direct component setters consume an explicit hash and mutate without activation.
{
    const hash = 0xC0009;
    const component = { x: 0, y: 0, width: 100, height: 20, hidden: false, text: "" };
    const components = { [hash]: component };
    const s = makeScript("direct_setters", [
        [0, 50], [0, 75], [0, 0], [0, 0], [0, hash], [2000, 0],
        [0, 0x123456], [0, hash], [2101, 0],
        [3, "direct"], [0, hash], [2112, 0],
        [0, 42], [0, hash], [2201, 0],
        [0, 2], [0, 777], [0, hash], [2309, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], { getComponent: (h) => components[h] ?? null });
    trace(`[CS2] direct_setters: status=${r.status} x=${component.x} y=${component.y} text="${component.text}"`);
    assert("direct_setters status", r.status, "ok");
    assert("direct_setters x", component.x, 50);
    assert("direct_setters y", component.y, 75);
    assert("direct_setters colour", component.colour, 0x123456);
    assert("direct_setters text", component.text, "direct");
    assert("direct_setters modelType", component.modelType, 2);
    assert("direct_setters modelId", component.modelId, 42);
    assert("direct_setters option cursor", (component.optionCursors ?? component.anIntArray39)?.[1], 777);
}

// 21. SET_POSITION: move active component to (50, 75).
{
    const components = { [0xC0003]: { x: 0, y: 0, width: 0, height: 0, hidden: false } };
    const s = makeScript("setPos", [
        [0, 0xC0003],
        [201, 0],          // setChild2
        [38, 0],           // pop success
        [0, 50],           // x
        [0, 75],           // y
        [0, 0],            // xMode
        [0, 0],            // yMode
        [1000, 0],         // SET_POSITION
        [21, 0],
    ], 0, 0, 0, 0);
    runClientScript(s, [], { getComponent: (h) => components[h] });
    trace(`[CS2] setPos: x=${components[0xC0003].x} y=${components[0xC0003].y}`);
    assert("setPos x", components[0xC0003].x, 50);
    assert("setPos y", components[0xC0003].y, 75);
}

// 22. Item search: find first matching item.
{
    const queue = [4151, 4152];
    const s = makeScript("itemSearch", [
        [3, "whip"],
        [0, 0],            // exact = 0 (substring)
        [4210, 0],         // SEARCH_ITEM
        [38, 0],           // pop count
        [4211, 0],         // NEXT_SEARCH_RESULT
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], {
        searchItem: () => queue.length,
        nextSearchResult: () => queue.shift() ?? -1,
    });
    trace(`[CS2] itemSearch: intResult=${r.intResult}`);
    assert("itemSearch first hit", r.intResult, 4151);
}

// 23. Struct param: pop paramId, structId → push value.
{
    const params = { 9001: { 5: "VIP" } };
    const s = makeScript("structParam", [
        [0, 9001],         // structId
        [0, 5],             // paramId
        [4500, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], {
        getStructParam: (sid, pid) => params[sid]?.[pid] ?? null,
    });
    trace(`[CS2] structParam: stringResult="${r.stringResult}"`);
    assert("structParam result", r.stringResult, "VIP");
}

// 24. Item param: pop paramId, itemId → push value.
{
    const s = makeScript("itemParam", [
        [0, 4151],
        [0, 7],
        [4208, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], {
        getItemAttribute: (itemId, paramId) => itemId === 4151 && paramId === 7 ? "Abyssal" : null,
    });
    trace(`[CS2] itemParam: stringResult="${r.stringResult}"`);
    assert("itemParam result", r.stringResult, "Abyssal");
}

// 25. Math utilities: interpolation, percent add, bit flags, multiply/divide.
{
    const s = makeScript("math_utils", [
        [0, 10],
        [0, 20],
        [0, 0],
        [0, 100],
        [0, 25],
        [4006, 0],         // 12
        [0, 25],
        [4007, 0],         // 15
        [0, 1],
        [4008, 0],         // flag bit 1 -> 15
        [0, 2],
        [4009, 0],         // clear bit 2 -> 11
        [0, 1],
        [4010, 0],         // bit 1 set -> 1
        [0, 12],
        [0, 3],
        [0, 2],
        [4018, 0],         // 12 * 2 / 3 = 8
        [4000, 0],         // 1 + 8 = 9
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, []);
    trace(`[CS2] math_utils: intResult=${r.intResult}`);
    assert("math_utils result", r.intResult, 9);
}

// 26. String utilities: gender choice + escape.
{
    const s = makeScript("string_utils", [
        [3, "Sir <A>"],
        [3, "Ma'am <B>"],
        [4105, 0],
        [4111, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], { getPlayerGender: () => 1 });
    trace(`[CS2] string_utils: stringResult="${r.stringResult}"`);
    assert("string_utils result", r.stringResult, "Ma'am <lt>B<gt>");
}

// 27. Component interaction setters: option text, base, and target verb.
{
    const c = { x: 0, y: 0, width: 1, height: 1, hidden: false, ops: [] };
    const hash = 0xC0004;
    const s = makeScript("component_interact", [
        [3, "Inspect"],
        [0, 2],
        [0, hash],
        [2300, 0],
        [3, "Choose"],
        [0, hash],
        [2305, 0],
        [3, "Use"],
        [0, hash],
        [2306, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], { getComponent: (h) => h === hash ? c : null });
    trace(`[CS2] component_interact: option="${c.ops[1]}" base="${c.optionBase}" verb="${c.targetVerb}"`);
    assert("component_interact status", r.status, "ok");
    assert("component option", c.ops[1], "Inspect");
    assert("component optionBase", c.optionBase, "Choose");
    assert("component targetVerb", c.targetVerb, "Use");
}

// 28. Client query opcodes: slot reads, packed coords, and player flags.
{
    const coord = (2 << 28) | (3200 << 14) | 3210;
    const s = makeScript("client_queries", [
        [0, 93],
        [0, 1],
        [3301, 0],         // item id slot -> 100
        [0, 93],
        [0, 1],
        [3302, 0],         // item amt slot -> 50
        [4000, 0],         // 150
        [3308, 0],         // coord
        [3309, 0],         // x -> 3200
        [4000, 0],         // 3350
        [3308, 0],
        [3310, 0],         // plane -> 2
        [4000, 0],         // 3352
        [3308, 0],
        [3311, 0],         // y -> 3210
        [4000, 0],         // 6562
        [3312, 0],         // members -> 1
        [4000, 0],         // 6563
        [3316, 0],         // rights -> 2
        [4000, 0],         // 6565
        [3326, 0],         // combat -> 99
        [4000, 0],         // 6664
        [3327, 0],         // female -> 1
        [4000, 0],         // 6665
        [3329, 0],         // quickchat -> 1
        [4000, 0],         // 6666
        [3335, 0],         // language -> 0
        [4000, 0],         // 6666
        [3337, 0],         // affiliate -> 4
        [4000, 0],         // 6670
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], {
        getContainer: (id) => id === 93 ? { items: [-1, 100], amounts: [0, 50], capacity: 2 } : null,
        getMyLocation: () => coord,
        isMembers: () => true,
        getClientRights: () => 2,
        getCombatLevel: () => 99,
        getPlayerGender: () => 1,
        isMapQuickChat: () => true,
        getLanguage: () => 0,
        getAffiliate: () => 4,
    });
    trace(`[CS2] client_queries: intResult=${r.intResult}`);
    assert("client_queries result", r.intResult, 6670);
}

// 29. MOVE_COORD packs fields into rt4 coord format.
{
    const s = makeScript("move_coord", [
        [0, 0],
        [0, 3200],
        [0, 2],
        [0, 3210],
        [3336, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, []);
    trace(`[CS2] move_coord: intResult=${r.intResult}`);
    assert("move_coord result", r.intResult, (2 << 28) | (3200 << 14) | 3210);
}

// 30. Enum/datamap lookups: string/int values, contains, size.
{
    const enums = new Map();
    enums.set(10, {
        keyType: 105,
        valueType: 115,
        defaultString: "Unknown",
        defaultInt: 0,
        intToString: new Map([[1, "Attack"], [2, "Defend"]]),
        intToInt: null,
    });
    enums.set(11, {
        keyType: 105,
        valueType: 105,
        defaultString: "null",
        defaultInt: -1,
        intToString: null,
        intToInt: new Map([[3, 99], [4, 42]]),
    });
    const s = makeScript("enum_datamap", [
        [0, 10],
        [0, 1],
        [3400, 0],         // "Attack"
        [3, "-"],
        [4101, 0],
        [0, 105],
        [0, 105],
        [0, 11],
        [0, 3],
        [3408, 0],         // 99
        [4100, 0],         // "Attack-99"
        [0, 105],
        [0, 11],
        [0, 42],
        [3409, 0],         // contains int 42 -> 1
        [4100, 0],         // "Attack-991"
        [3, "Defend"],
        [0, 10],
        [3410, 0],         // contains string Defend -> 1
        [4100, 0],         // "Attack-9911"
        [0, 10],
        [3411, 0],         // size -> 2
        [4100, 0],         // "Attack-99112"
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], { getEnum: (id) => enums.get(id) ?? null });
    trace(`[CS2] enum_datamap: stringResult="${r.stringResult}"`);
    assert("enum_datamap result", r.stringResult, "Attack-99112");
}

// 31. Friend / ignore / clan social query opcodes.
{
    const friend = { name: "Alice", world: 301, rank: 5, worldName: "World 301", sameGame: true };
    const clan = {
        name: "Raiders",
        owner: "Owner",
        rank: 3,
        minKick: 1,
        members: [{ name: "Alice", world: 301, rank: 5, worldName: "World 301" }],
    };
    const hooks = {
        getFriendListState: () => 2,
        getFriendCount: () => 1,
        getFriend: (idx) => idx === 0 ? friend : null,
        getFriendIndex: (name) => normalizeSocialName(name) === "alice" ? 0 : -1,
        isFriend: (name) => normalizeSocialName(name) === "alice",
        getIgnoreCount: () => 1,
        getIgnoreName: (idx) => idx === 0 ? "Bob" : "",
        isIgnored: (name) => normalizeSocialName(name) === "bob",
        getClan: () => clan,
        getSelfName: () => "Alice",
        getCountry: () => 840,
    };
    const ints = makeScript("social_ints", [
        [3600, 0],
        [0, 0], [3602, 0], [4000, 0],
        [0, 0], [3603, 0], [4000, 0],
        [3, "Alice"], [3609, 0], [4000, 0],
        [3612, 0], [4000, 0],
        [0, 0], [3614, 0], [4000, 0],
        [0, 0], [3615, 0], [4000, 0],
        [3621, 0], [4000, 0],
        [3, "Bob"], [3623, 0], [4000, 0],
        [0, 0], [3624, 0], [4000, 0],
        [0, 0], [3627, 0], [4000, 0],
        [3, "Alice"], [3628, 0], [4000, 0],
        [3629, 0], [4000, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const ri = runClientScript(ints, [], hooks);
    trace(`[CS2] social_ints: intResult=${ri.intResult}`);
    assert("social_ints result", ri.intResult, 1459);

    const strings = makeScript("social_strings", [
        [0, 0], [3601, 0],
        [3, "-"], [4101, 0],
        [0, 0], [3610, 0], [4101, 0],
        [3, "-"], [4101, 0],
        [3611, 0], [4101, 0],
        [3, "-"], [4101, 0],
        [0, 0], [3613, 0], [4101, 0],
        [3, "-"], [4101, 0],
        [0, 0], [3622, 0], [4101, 0],
        [3, "-"], [4101, 0],
        [3625, 0], [4101, 0],
        [3, "-"], [4101, 0],
        [0, 0], [3626, 0], [4101, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const rs = runClientScript(strings, [], hooks);
    trace(`[CS2] social_strings: stringResult="${rs.stringResult}"`);
    assert("social_strings result", rs.stringResult, "Alice-World 301-Raiders-Alice-Bob-Owner-World 301");
}

// 32. Grand Exchange offer query opcodes.
{
    const offer = {
        type: 1,
        status: 5,
        item: 4151,
        price: 1200000,
        count: 2,
        completedCount: 1,
        completedGold: 600000,
    };
    const s = makeScript("ge_offer", [
        [0, 0], [3903, 0],
        [0, 0], [3904, 0], [4000, 0],
        [0, 0], [3905, 0], [4000, 0],
        [0, 0], [3906, 0], [4000, 0],
        [0, 0], [3907, 0], [4000, 0],
        [0, 0], [3908, 0], [4000, 0],
        [0, 0], [3910, 0], [4000, 0],
        [0, 0], [3911, 0], [4000, 0],
        [0, 0], [3912, 0], [4000, 0],
        [0, 0], [3913, 0], [4000, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], { getGrandExchangeOffer: (slot) => slot === 0 ? offer : null });
    trace(`[CS2] ge_offer: intResult=${r.intResult}`);
    assert("ge_offer result", r.intResult, 1804156);
}

// 33. Chat history and filter query opcodes.
{
    let settings = { pub: 1, priv: 2, trade: 0 };
    const messages = [
        { type: 2, name: "Alice", message: "Selling whip", clan: "Raiders", phraseId: 77 },
        { type: 0, name: "", message: "Welcome", clan: "", phraseId: -1 },
    ];
    const hooks = {
        getPublicChatSetting: () => settings.pub,
        getPrivateChatSetting: () => settings.priv,
        getTradeSetting: () => settings.trade,
        setChatSettings: (pub, priv, trade) => { settings = { pub, priv, trade }; },
        getChatMessage: (idx) => messages[idx] ?? null,
        getChatSize: () => messages.length,
        getSelfName: () => "Brandon",
    };
    const ints = makeScript("chat_ints", [
        [5000, 0],
        [5005, 0], [4000, 0],
        [5016, 0], [4000, 0],
        [5017, 0], [4000, 0],
        [0, 0], [5004, 0], [4000, 0],
        [0, 0], [5012, 0], [4000, 0],
        [0, 3], [0, 1], [0, 2], [5001, 0],
        [5000, 0], [4000, 0],
        [5005, 0], [4000, 0],
        [5016, 0], [4000, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const ri = runClientScript(ints, [], hooks);
    trace(`[CS2] chat_ints: intResult=${ri.intResult}`);
    assert("chat_ints result", ri.intResult, 90);

    const strings = makeScript("chat_strings", [
        [0, 0], [5010, 0],
        [3, ":"], [4101, 0],
        [0, 0], [5003, 0], [4101, 0],
        [3, ":"], [4101, 0],
        [0, 0], [5011, 0], [4101, 0],
        [3, ":"], [4101, 0],
        [5015, 0], [4101, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const rs = runClientScript(strings, [], hooks);
    trace(`[CS2] chat_strings: stringResult="${rs.stringResult}"`);
    assert("chat_strings result", rs.stringResult, "Alice:Selling whip:Raiders:Brandon");
}

// 34. Keyboard modifier and calendar/time opcodes.
{
    const now = Date.UTC(2024, 0, 1, 0, 0, 0, 0);
    const s = makeScript("keyboard_time", [
        [5100, 0],
        [5101, 0], [4000, 0],
        [5102, 0], [4000, 0],
        [6300, 0], [4000, 0],
        [6301, 0], [4000, 0],
        [6303, 0], [4000, 0],
        [0, 1], [0, 0], [0, 2002], [6302, 0], [4000, 0],
        [0, 2024], [6304, 0], [4000, 0],
        [0, 1900], [6304, 0], [4000, 0],
        [0, 2000], [6304, 0], [4000, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], {
        isKeyHeld: (key) => key === "alt" || key === "shift",
        getCurrentTimeMillis: () => now,
    });
    trace(`[CS2] keyboard_time: intResult=${r.intResult}`);
    assert("keyboard_time result", r.intResult, 28411068);
}

// 35. Display/window mode opcodes.
{
    let windowMode = 2;
    let preferredWindowMode = 1;
    let fullscreenRequested = false;
    const displayModes = [{ width: 800, height: 600 }, { width: 1280, height: 720 }];
    const hooks = {
        getDisplayModeCount: () => displayModes.length,
        getDisplayMode: (idx) => displayModes[idx] ?? null,
        getPreferredFullscreenMode: () => 1,
        requestFullscreen: (w, h) => {
            fullscreenRequested = w === 1280 && h === 720;
            return fullscreenRequested;
        },
        exitFullscreen: () => { fullscreenRequested = false; },
        getWindowMode: () => windowMode,
        setWindowMode: (mode) => { windowMode = mode; },
        getPreferredWindowMode: () => preferredWindowMode,
        setPreferredWindowMode: (mode) => { preferredWindowMode = mode; },
    };
    const s = makeScript("display_modes", [
        [5302, 0],
        [0, 0], [5303, 0], [4000, 0], [4000, 0],
        [5305, 0], [4000, 0],
        [5306, 0], [4000, 0],
        [5308, 0], [4000, 0],
        [0, 2], [5309, 0],
        [5308, 0], [4000, 0],
        [0, 1], [5307, 0],
        [5306, 0], [4000, 0],
        [0, 1280], [0, 720], [5300, 0], [4000, 0],
        [5301, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], hooks);
    trace(`[CS2] display_modes: intResult=${r.intResult} fullscreen=${fullscreenRequested}`);
    assert("display_modes result", r.intResult, 1410);
    assert("display_modes fullscreen reset", fullscreenRequested, false);
}

// 36. Preferences and viewport/FOV opcodes.
{
    const prefs = new Map();
    const viewport = new Map([
        ["size", [765, 503]],
        ["near", [256, 205]],
        ["far", [256, 320]],
    ]);
    const hooks = {
        setPreference: (k, v) => { prefs.set(k, v); return 1; },
        getPreference: (k) => prefs.get(k) ?? 0,
        setViewport: (k, v) => { viewport.set(k, v); },
        getViewport: (k) => viewport.get(k) ?? [0, 0],
    };
    const s = makeScript("preferences_viewport", [
        [0, 9], [6001, 0], [6101, 0],
        [0, 3], [6011, 0], [6111, 0], [4000, 0],
        [0, 200], [6018, 0], [6118, 0], [4000, 0],
        [0, 300], [6019, 0], [6119, 0], [4000, 0],
        [0, 1], [6023, 0], [4000, 0],
        [6123, 0], [4000, 0],
        [0, 3], [6024, 0], [6124, 0], [4000, 0],
        [0, 0], [0, 0], [6200, 0],
        [6205, 0], [4000, 0], [4000, 0],
        [0, 640], [0, 480], [6201, 0],
        [6204, 0], [4000, 0], [4000, 0],
        [6203, 0], [4000, 0], [4000, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], hooks);
    trace(`[CS2] preferences_viewport: intResult=${r.intResult}`);
    assert("preferences_viewport result", r.intResult, 3237);
}

// 37. Camera control/query opcodes.
{
    const coord = (3200 << 14) | 3210;
    let rotation = { pitch: 128, yaw: 0 };
    let move = null;
    let point = null;
    let path = null;
    let unlocks = 0;
    const hooks = {
        moveCameraTo: (coord, height, speed, acceleration) => { move = { coord, height, speed, acceleration }; },
        pointCameraAt: (coord, height, speed, acceleration) => { point = { coord, height, speed, acceleration }; },
        setCameraPath: (values) => { path = values; },
        unlockCamera: () => { unlocks++; },
        setCameraRotation: (pitch, yaw) => { rotation = { pitch, yaw }; },
        getCameraRotation: () => rotation,
    };
    const s = makeScript("camera_ops", [
        [0, coord], [0, 80], [0, 6], [0, 7], [5500, 0],
        [0, coord], [0, 90], [0, 8], [0, 9], [5501, 0],
        [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [5502, 0],
        [0, 300], [0, 1024], [5504, 0],
        [5505, 0],
        [5506, 0], [4000, 0],
        [5503, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], hooks);
    trace(`[CS2] camera_ops: intResult=${r.intResult} moveHeight=${move?.height} pointHeight=${point?.height} pathLast=${path?.[5]} unlocks=${unlocks}`);
    assert("camera_ops result", r.intResult, 1324);
    assert("camera_ops move", move?.height, 80);
    assert("camera_ops point", point?.height, 90);
    assert("camera_ops path", path?.join(","), "1,2,3,4,5,6");
    assert("camera_ops unlocks", unlocks, 1);
}

// 38. Login/account-create opcodes.
{
    let loginReply = 3;
    let accountReply = 4;
    let direct = null;
    let info = null;
    let requestedName = "";
    let created = null;
    let skipped = 0;
    let suggested = ["One", "Two"];
    const hooks = {
        requestDirectLogin: (username, password, flags) => { direct = { username, password, flags }; },
        skipLoginStage: () => { skipped++; },
        resetLoginReply: () => { loginReply = -2; },
        checkAccountInfo: (a, b, c, d) => { info = { a, b, c, d }; },
        requestAccountName: (name) => { requestedName = name; },
        createAccount: (username, password, a, b, c, d) => { created = { username, password, a, b, c, d }; },
        resetAccountCreateReply: () => { accountReply = -2; },
        getGameLoginReply: () => loginReply,
        getWorldSwitchTimer: () => 12,
        getAccountCreateReply: () => accountReply,
        getSuggestedAccountNames: () => suggested,
        clearSuggestedAccountNames: () => { suggested = []; },
        getDetailedLoginReply: () => 9,
    };
    const s = makeScript("login_account", [
        [3, "user"], [3, "pass"], [0, 7], [5600, 0],
        [5601, 0], [5602, 0],
        [0, 1], [0, 2], [0, 3], [0, 4], [5603, 0],
        [3, "NewUser"], [5604, 0],
        [3, "CreateUser"], [3, "CreatePass"], [0, 5], [0, 6], [0, 7], [0, 8], [5605, 0],
        [5606, 0],
        [5607, 0], [5608, 0], [4000, 0],
        [5609, 0], [4000, 0],
        [5611, 0], [4000, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], hooks);
    trace(`[CS2] login_account: intResult=${r.intResult} direct=${direct?.username} created=${created?.username} skipped=${skipped}`);
    assert("login_account result", r.intResult, 17);
    assert("login_account direct", `${direct?.username}/${direct?.password}/${direct?.flags}`, "user/pass/7");
    assert("login_account info", `${info?.a},${info?.b},${info?.c},${info?.d}`, "1,2,3,4");
    assert("login_account name", requestedName, "NewUser");
    assert("login_account create", `${created?.username}/${created?.password}/${created?.a},${created?.b},${created?.c},${created?.d}`, "CreateUser/CreatePass/5,6,7,8");
    assert("login_account skipped", skipped, 1);

    suggested = ["One", "Two"];
    const namesScript = makeScript("login_names", [
        [5610, 0],
        [37, 5],
        [21, 0],
    ], 0, 0, 0, 0);
    const namesResult = runClientScript(namesScript, [], hooks);
    trace(`[CS2] login_names: stringResult="${namesResult.stringResult}" remaining=${suggested.length}`);
    assert("login_names string", namesResult.stringResult, "OneTwo");
    assert("login_names cleared", suggested.length, 0);
}

// 39. Ads/world-list/site-settings opcodes.
{
    let cursor = 0;
    let lastWorld = 0;
    let siteMembers = false;
    let hop = 0;
    let sorted = "";
    const worlds = [
        { id: 301, flags: 5, activity: "Trade", countryFlag: 1, countryName: "US", players: 100 },
        { id: 302, flags: 7, activity: "Skill", countryFlag: 2, countryName: "UK", players: 55 },
    ];
    const hooks = {
        canShowVideoAd: () => true,
        isShowingVideoAd: () => false,
        fetchWorldList: () => true,
        getFirstWorld: () => { cursor = 1; return worlds[0] ?? null; },
        getNextWorld: () => worlds[cursor++] ?? null,
        hopWorld: (worldId) => { hop = worldId; return worlds.some((w) => w.id === worldId); },
        setLastWorld: (worldId) => { lastWorld = worldId; },
        getLastWorld: () => lastWorld,
        getWorldById: (worldId) => worlds.find((w) => w.id === worldId) ?? null,
        sortWorldList: (primaryKey, primaryAscending, secondaryKey, secondaryAscending) => {
            sorted = `${primaryKey}/${primaryAscending}/${secondaryKey}/${secondaryAscending}`;
        },
        setSiteSettingsMembers: (members) => { siteMembers = members; },
        isSiteSettingsMembers: () => siteMembers,
    };
    const s = makeScript("world_ops", [
        [6405, 0], [6406, 0], [4000, 0],
        [6500, 0], [4000, 0],
        [0, 302], [6503, 0], [4000, 0],
        [0, 302], [6504, 0], [6505, 0], [4000, 0],
        [0, 1], [6600, 0], [6601, 0], [4000, 0],
        [0, 4], [0, 0], [0, 1], [0, 1], [6507, 0],
        [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], hooks);
    trace(`[CS2] world_ops: intResult=${r.intResult} hop=${hop} last=${lastWorld} sorted=${sorted}`);
    assert("world_ops result", r.intResult, 306);
    assert("world_ops hop", hop, 302);
    assert("world_ops sorted", sorted, "4/false/1/true");

    cursor = 0;
    const strings = makeScript("world_strings", [
        [6501, 0], [6502, 0], [0, 999], [6506, 0], [37, 6], [21, 0],
    ], 0, 0, 0, 0);
    const sr = runClientScript(strings, [], hooks);
    trace(`[CS2] world_strings: stringResult="${sr.stringResult}"`);
    assert("world_strings result", sr.stringResult, "TradeUSSkillUK");
}

// 40. Character design, interface-child, and text-measure opcodes.
{
    const calls = [];
    const parent = {
        x: 0, y: 0, width: 100, height: 20, hidden: false, id: 0x12340000,
        createdComponents: [
            { x: 1, y: 1, width: 1, height: 1, hidden: false, id: 0x12340000, createdComponentId: 0 },
            null,
            { x: 2, y: 2, width: 1, height: 1, hidden: false, id: 0x12340000, createdComponentId: 2 },
        ],
    };
    const hooks = {
        getComponent: (hash) => hash === 0x12340000 ? parent : null,
        setPlayerIdentikit: (featureId, identikit) => calls.push(`idkit:${featureId}/${identikit}`),
        setPlayerColor: (slot, color) => calls.push(`color:${slot}/${color}`),
        setPlayerGender: (female) => calls.push(`gender:${female ? 1 : 0}`),
        hasOpenInterface: (parentId) => parentId === 55,
        hasChildInterface: (parentId, interfaceId) => parentId === 55 && interfaceId === 66,
        measureTextLineCount: (text, width, fontId) => Math.ceil(text.length / 4) + width + fontId,
        measureTextMaxLineWidth: (text, width, fontId) => text.length + width + fontId,
    };
    const s = makeScript("appearance_child_text", [
        [0, 3], [0, 777], [403, 0],
        [0, 2], [0, 9], [404, 0],
        [0, 1], [410, 0],
        [0, 55], [2702, 0],
        [0, 0x12340000], [2703, 0],
        [0, 55], [0, 66], [2704, 0],
        [0, 55], [0, 67], [2705, 0],
        [3, "abcdefgh"], [0, 10], [0, 5], [4108, 0],
        [3, "abcd"], [0, 10], [0, 5], [4109, 0],
        [4000, 0], [4000, 0], [4000, 0], [4000, 0], [4000, 0], [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], hooks);
    trace(`[CS2] appearance_child_text: calls="${calls.join("|")}" intResult=${r.intResult}`);
    assert("appearance_child_text status", r.status, "ok");
    assert("appearance_child_text calls", calls.join("|"), "idkit:3/777|color:2/9|gender:1");
    assert("appearance_child_text result", r.intResult, 39);
}

// 41. Client action/media opcodes.
{
    const calls = [];
    const comp = { x: 1, y: 2, width: 3, height: 4, hidden: false, id: 0x12340005 };
    const hooks = {
        getComponent: (hash) => hash === 0x12340005 ? comp : null,
        addGameMessage: (message) => calls.push(`msg:${message}`),
        animateSelf: (seqId, delay) => calls.push(`anim:${seqId}/${delay}`),
        closeWidgets: () => calls.push("close"),
        resumeIntegerInput: (value) => calls.push(`int:${value}`),
        resumeNameInput: (name) => calls.push(`name:${name}`),
        resumeStringInput: (value) => calls.push(`str:${value}`),
        clickPlayerOption: (option, playerIndex) => calls.push(`player:${option}/${playerIndex}`),
        runWidgetAction: (a, b, component) => calls.push(`widget:${a}/${b}/${component?.id ?? -1}`),
        sendDialogAction: (componentId) => calls.push(`dialog:${componentId}`),
        playSoundEffect: (soundId, loops, delay) => calls.push(`sound:${soundId}/${loops}/${delay}`),
        playMusic: (songId) => calls.push(`music:${songId}`),
        playMusicEffect: (jingleId, delay) => calls.push(`jingle:${jingleId}/${delay}`),
    };
    const s = makeScript("client_actions", [
        [3, "Hello"], [3100, 0],
        [0, 100], [0, 3], [3101, 0],
        [3103, 0],
        [3, "42"], [3104, 0],
        [3, "Brandon"], [3105, 0],
        [3, "typed"], [3106, 0],
        [3, "Trade"], [0, 7], [3107, 0],
        [0, 5], [0, 6], [0, 0x12340005], [3108, 0],
        [0, 0x12340005], [201, 0],
        [0, 8], [0, 9], [3109, 0],
        [0, 0x12340005], [3110, 0],
        [0, 200], [0, 2], [0, 4], [3200, 0],
        [0, 300], [3201, 0],
        [0, 400], [0, 5], [3202, 0],
        [0, calls.length], [21, 0],
    ], 0, 0, 0, 0);
    const r = runClientScript(s, [], hooks);
    trace(`[CS2] client_actions: calls=${calls.length} intResult=${r.intResult}`);
    assert("client_actions status", r.status, "ok");
    assert("client_actions call count", calls.length, 13);
    assert("client_actions calls", calls.join("|"), "msg:Hello|anim:100/3|close|int:42|name:Brandon|str:typed|player:Trade/7|widget:5/6/305397765|widget:8/9/305397765|dialog:305397765|sound:200/2/4|music:300|jingle:400/5");
}

// 41. Unsupported opcode → halt cleanly.
{
    const s = makeScript("halt", [
        [9999, 0],  // unsupported
    ], 0, 0, 0, 0);
    const r = runClientScript(s, []);
    trace(`[CS2] halt: status=${r.status} reason="${r.reason}"`);
    assert("halt status", r.status, "halt");
}

// ── Summary ──
if (failures === 0) trace("[CS2] all tests passed");
else trace(`[CS2] ${failures} test(s) FAILED`);

writeFileSync(new URL(".cs2-vm-trace.txt", import.meta.url), lines.join("\n") + "\n");
if (failures > 0) process.exit(1);
