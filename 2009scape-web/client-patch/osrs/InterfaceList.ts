import { Js5Cache } from "./Js5Cache";
import { Component } from "./cache/def/Component";
import { ComponentLoader } from "./cache/def/ComponentLoader";

export class InterfaceList {
    static byKey: Map<string, Component> = new Map<string, Component>();
    static loadedInterfaces: Set<number> = new Set<number>();
    static loadingInterfaces: Map<number, Promise<void>> = new Map<number, Promise<void>>();
    static openModalStack: { parentInterfaceId: number; rootCompId: number }[] = [];
    private static replayedRecorder: boolean = false;

    static componentKey(interfaceId: number, childId: number): string {
        return interfaceId + ":" + childId;
    }

    static get(interfaceId: number, childId: number): Component | null {
        return this.byKey.get(this.componentKey(interfaceId, childId)) || null;
    }

    static put(c: Component): void {
        const interfaceId = c.id >>> 16;
        const childId = c.id & 0xFFFF;
        this.byKey.set(this.componentKey(interfaceId, childId), c);
        this.loadedInterfaces.add(interfaceId);
    }

    static loadInterface(js5: Js5Cache | null, interfaceId: number): Promise<void> {
        if (!js5 || interfaceId < 0) return Promise.resolve();
        if (this.loadedInterfaces.has(interfaceId)) return Promise.resolve();
        const active = this.loadingInterfaces.get(interfaceId);
        if (active) return active;
        const promise = ComponentLoader.loadInterface(js5, interfaceId)
            .then((components) => {
                for (const c of components) this.put(c);
                this.loadedInterfaces.add(interfaceId);
            })
            .catch(() => {})
            .then(() => {
                this.loadingInterfaces.delete(interfaceId);
            });
        this.loadingInterfaces.set(interfaceId, promise);
        return promise;
    }

    static openModal(parentInterfaceId: number, rootCompId: number): void {
        this.openModalStack.push({ parentInterfaceId, rootCompId });
    }

    static closeAll(): void {
        this.openModalStack = [];
    }

    static applyUpdate(game: any, kind: string, compId: number, payload: any): void {
        const js5 = game ? (game.js5Cache || (globalThis as any).js5Cache || null) : null;
        const interfaceId = compId >>> 16;
        const childId = compId & 0xFFFF;
        this.loadInterface(js5, interfaceId).then(() => {
            this.applyLoaded(kind, interfaceId, childId, compId, payload);
            this.maybeReplayRecorder(game);
        });
    }

    static maybeReplayRecorder(game: any): void {
        if (this.replayedRecorder || !game || !game.interfaceUpdates) return;
        this.replayedRecorder = true;
        const copy = game.interfaceUpdates.slice(0);
        for (const u of copy) this.applyUpdate(game, u.kind, u.compId, u.payload);
    }

    private static applyLoaded(kind: string, interfaceId: number, childId: number, compId: number, payload: any): void {
        const c = this.get(interfaceId, childId);
        if (!c) return;
        c.tracknum = payload && payload.tracknum !== undefined ? payload.tracknum : c.tracknum;
        switch (kind) {
            case "IF_SETCOLOUR":
                c.colour = payload.color | 0;
                break;
            case "IF_SETSCROLLPOS":
                c.scrollPos = payload.pos | 0;
                break;
            case "IF_SETTEXT2":
            case "IF_SETTEXT3":
                c.text = String(payload.text || "");
                break;
            case "INTERFACE_ANIMATE_ROTATE":
                c.rotatePitchStep = payload.pitchStep | 0;
                c.rotateYawStep = payload.yawStep | 0;
                break;
            case "WIDGETSTRUCT_SETTING":
                c.structValue = payload.value | 0;
                c.structStart = payload.start | 0;
                c.structEnd = payload.end | 0;
                break;
            case "SWITCH_WIDGET":
                c.switchSource = payload.source | 0;
                break;
        }
    }
}
