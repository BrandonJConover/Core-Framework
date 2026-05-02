import { Js5Cache } from "../../Js5Cache";
import { Component } from "./Component";

export class ComponentLoader {
    static async loadInterface(js5: Js5Cache, interfaceId: number): Promise<Component[]> {
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
            out.push(Component.decode((interfaceId << 16) | childId, bytes));
        }
        return out;
    }
}
