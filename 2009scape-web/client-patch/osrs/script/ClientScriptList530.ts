/**
 * ClientScriptList530 — caching loader for CS2 scripts from idx12 of the
 * rev-530 cache. Each script lives as a single file at idx12/groupId where
 * groupId == scriptId (one script per group, file 0). Bytes are passed
 * straight to decodeClientScript so the VM can execute them.
 *
 * Source of truth (read-only):
 *   reference/rt4-client/client/src/main/java/rt4/ClientScriptList.java
 *     get(scriptId) and decode() — lines ~30-110
 *
 * Cache is in-memory; missed scripts cache a null sentinel so we don't
 * re-fetch the same missing id. Sync API is provided for use inside the
 * VM's loadScript hook (the VM is synchronous); call preload(ids) ahead of
 * time when scripts are needed mid-tick.
 */

import { decodeClientScript, ClientScript530Data } from "./ClientScript530";

interface Js5LikeCache {
    /** Sync read: returns null if not yet loaded (caller must preload). */
    getFileBytesSync?(idxNum: number, groupId: number, fileId: number): Uint8Array | null;
    /** Async read: always available. */
    getFileBytes(idxNum: number, groupId: number, fileId: number): Promise<Uint8Array | null>;
}

const SCRIPT_INDEX = 12;

export class ClientScriptList530 {
    private static cache: Map<number, ClientScript530Data | null> = new Map();
    private static js5: Js5LikeCache | null = null;

    static attach(js5: Js5LikeCache): void {
        this.js5 = js5;
    }

    /** Sync get — returns null if the script isn't preloaded. */
    static get(scriptId: number): ClientScript530Data | null {
        if (this.cache.has(scriptId)) return this.cache.get(scriptId) ?? null;
        // Try a sync read if the cache exposes one (unlikely on web, but supported).
        const bytes = this.js5?.getFileBytesSync?.(SCRIPT_INDEX, scriptId, 0);
        if (!bytes) return null;
        const decoded = decodeClientScript(bytes);
        this.cache.set(scriptId, decoded);
        return decoded;
    }

    /** Async preload — call ahead of time so subsequent get() returns the script. */
    static async preload(scriptIds: number[]): Promise<void> {
        if (!this.js5) return;
        const work = scriptIds.filter(id => !this.cache.has(id));
        await Promise.all(work.map(async (id) => {
            try {
                const bytes = await this.js5!.getFileBytes(SCRIPT_INDEX, id, 0);
                if (!bytes) {
                    this.cache.set(id, null);
                    return;
                }
                this.cache.set(id, decodeClientScript(bytes));
            } catch (_) {
                this.cache.set(id, null);
            }
        }));
    }

    /** Drop the in-memory cache (for tests + cache invalidation). */
    static reset(): void {
        this.cache.clear();
    }
}
