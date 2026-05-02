import { Component } from "./Component";
import { InterfaceComponent530 } from "./InterfaceComponent530";

export interface ComponentLoaderCache {
    getMeta(idxNum: number): Promise<{ groupSizes: number[]; fileIds: (number[] | null)[] } | null>;
    getFileBytes(idxNum: number, groupId: number, fileId: number): Promise<Uint8Array | null>;
}

export class ComponentLoader {
    static async loadInterface(js5: ComponentLoaderCache, interfaceId: number): Promise<Component[]> {
        const meta = await js5.getMeta(3);
        if (!meta || interfaceId < 0 || interfaceId >= meta.groupSizes.length) return [];
        const count = meta.groupSizes[interfaceId] || 0;
        if (count <= 0) return [];

        const ids = meta.fileIds[interfaceId];
        const out: Component[] = [];
        for (let dense = 0; dense < count; dense++) {
            const childId = ids ? ids[dense] : dense;
            const bytes = await js5.getFileBytes(3, interfaceId, childId);
            if (!bytes) continue;
            const id = (interfaceId << 16) | childId;
            try {
                out.push(Component.fromInterfaceComponent(InterfaceComponent530.decode(bytes, id)));
            } catch (_) {
                out.push(Component.decode(id, bytes));
            }
        }
        return out;
    }
}
