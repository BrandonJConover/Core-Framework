import { Component } from "./cache/def/Component";
import { InterfaceList } from "./InterfaceList";
import { PacketHandler530 } from "./PacketHandler530";

function resetInterfaces() {
    InterfaceList.byKey.clear();
    InterfaceList.loadedInterfaces.clear();
    InterfaceList.loadingInterfaces.clear();
    InterfaceList.openModalStack = [];
    InterfaceList.serverActiveProperties.clear();
}

function packet(bytes: number[]): any {
    return { buffer: Int8Array.from(bytes), currentPosition: 0 };
}

function component(id: number, slots: number): Component {
    const c = new Component();
    c.id = id;
    c.inventoryItems = new Array(slots).fill(-1);
    c.inventoryItemAmounts = new Array(slots).fill(0);
    InterfaceList.put(c);
    return c;
}

describe("PacketHandler530 inventory containers", () => {
    beforeEach(resetInterfaces);

    test("full container updates are applied to loaded components and container maps", () => {
        const componentHash = (12 << 16) | 34;
        const c = component(componentHash, 4);
        c.inventoryItems[3] = 999;
        c.inventoryItemAmounts[3] = 1;
        const game: any = {
            legacyInventoryMirrors: {},
            syncLegacyInventoryWidget(componentId: number, comp: Component) {
                this.legacyInventoryMirrors[componentId] = {
                    items: comp.inventoryItems.map((itemId) => itemId >= 0 ? itemId + 1 : 0),
                    amounts: comp.inventoryItemAmounts.slice(),
                };
            },
            getComponent: (id: number) => InterfaceList.get(id >>> 16, id & 0xffff),
        };

        const bytes = [
            0x00, 0x0c, 0x00, 0x22, // component hash
            0x00, 0x5d,             // container id
            0x00, 0x03,             // total slots
            0x7b, 0x00, 0x65,       // count 5, item 100
            0x80, 0x00, 0x00,       // empty
            0x7f, 0x00, 0xca,       // count 1, item 201
        ];

        expect(PacketHandler530.handleUpdateInvFull(packet(bytes), bytes.length, game)).toBe(true);

        expect(c.inventoryItems.slice(0, 4)).toEqual([100, -1, 201, -1]);
        expect(c.inventoryItemAmounts.slice(0, 4)).toEqual([5, 0, 1, 0]);
        expect(game.containerComponents[0x5d]).toBe(componentHash);
        expect(game.containerItems[0x5d]).toEqual([100, -1, 201]);
        expect(game.containerAmounts[0x5d]).toEqual([5, 0, 1]);
        expect(game.legacyInventoryMirrors[componentHash].items.slice(0, 4)).toEqual([101, 0, 202, 0]);
        expect(game.legacyInventoryMirrors[componentHash].amounts.slice(0, 4)).toEqual([5, 0, 1, 0]);
    });

    test("clear container updates reset component, legacy widget slots, and mapped container id", () => {
        const componentHash = (12 << 16) | 34;
        const c = component(componentHash, 3);
        c.inventoryItems = [100, 200, 300];
        c.inventoryItemAmounts = [1, 2, 3];
        const game: any = {
            containerComponents: { 0x5d: componentHash },
            containerItems: { 0x5d: [100, 200, 300] },
            containerAmounts: { 0x5d: [1, 2, 3] },
            legacyInventoryMirrors: {},
            syncLegacyInventoryWidget(componentId: number, comp: Component) {
                this.legacyInventoryMirrors[componentId] = {
                    items: comp.inventoryItems.map((itemId) => itemId >= 0 ? itemId + 1 : 0),
                    amounts: comp.inventoryItemAmounts.slice(),
                };
            },
            getComponent: (id: number) => InterfaceList.get(id >>> 16, id & 0xffff),
        };

        const bytes = [
            0x00, 0x0c, 0x00, 0x22, // component hash
        ];

        expect(PacketHandler530.handleUpdateInvClear(packet(bytes), game)).toBe(true);

        expect(c.inventoryItems).toEqual([-1, -1, -1]);
        expect(c.inventoryItemAmounts).toEqual([0, 0, 0]);
        expect(game.legacyInventoryMirrors[componentHash].items).toEqual([0, 0, 0]);
        expect(game.legacyInventoryMirrors[componentHash].amounts).toEqual([0, 0, 0]);
        expect(game.containerItems[0x5d]).toEqual([]);
        expect(game.containerAmounts[0x5d]).toEqual([]);
        expect(game.containerItems[componentHash]).toBeUndefined();
        expect(game.containerAmounts[componentHash]).toBeUndefined();
    });

    test("partial updates replay when the component appears after the packet", async () => {
        const componentHash = (15 << 16) | 7;
        const game: any = {
            legacyInventoryMirrors: {},
            syncLegacyInventoryWidget(componentId: number, comp: Component) {
                this.legacyInventoryMirrors[componentId] = {
                    items: comp.inventoryItems.map((itemId) => itemId >= 0 ? itemId + 1 : 0),
                    amounts: comp.inventoryItemAmounts.slice(),
                };
            },
            getComponent: (id: number) => InterfaceList.get(id >>> 16, id & 0xffff),
        };
        const bytes = [
            0x00, 0x0f, 0x00, 0x07, // component hash
            0x00, 0x5e,             // container id
            0x02,                   // slot 2
            0x01, 0x2d,             // item 300
            0x04,                   // count 4
        ];

        expect(PacketHandler530.handleUpdateInvPartial(packet(bytes), bytes.length, game)).toBe(true);
        const c = component(componentHash, 3);
        await Promise.resolve();

        expect(c.inventoryItems).toEqual([-1, -1, 300]);
        expect(c.inventoryItemAmounts).toEqual([0, 0, 4]);
        expect(game.legacyInventoryMirrors[componentHash].items).toEqual([0, 0, 301]);
        expect(game.legacyInventoryMirrors[componentHash].amounts).toEqual([0, 0, 4]);
        expect(game.containerComponents[0x5e]).toBe(componentHash);
    });

    test("negative component hashes use the high-bank container id without touching widgets", () => {
        const game: any = {};
        const bytes = [
            0xff, 0xfe, 0xee, 0x8f, // negative component sentinel below -70000
            0x00, 0x02,             // raw container id -> 32770
            0x00, 0x01,             // total slots
            0x7d, 0x00, 0x33,       // count 3, item 50
        ];

        expect(PacketHandler530.handleUpdateInvFull(packet(bytes), bytes.length, game)).toBe(true);

        expect(game.containerComponents[32770]).toBe(0xfffeee8f);
        expect(game.containerItems[32770]).toEqual([50]);
        expect(game.containerAmounts[32770]).toEqual([3]);
    });

    test("open-top packets queue a legacy widget bridge for the opened 530 interface", async () => {
        const interfaceId = 762;
        const childA = new Component();
        childA.id = (interfaceId << 16) | 3;
        const childB = new Component();
        childB.id = (interfaceId << 16) | 1;
        InterfaceList.put(childA);
        InterfaceList.put(childB);
        const bridged: any[] = [];
        const game: any = {
            syncLegacyInterfaceWidgets(openedInterfaceId: number, rootWidgetId: number) {
                bridged.push({ openedInterfaceId, rootWidgetId });
            },
        };
        const bytes = [
            0x00,                   // type
            0x00, 0x00, 0x00, 0x00, // pointer
            0x00, 0x80,             // tracknum 0, g2add
            0x02, 0xfa,             // component/interface 762
        ];

        expect(PacketHandler530.handleIfOpenTop(packet(bytes), game)).toBe(true);
        await Promise.resolve();

        expect(game.topInterface).toEqual({ type: 0, pointer: 0, component: interfaceId, tracknum: 0 });
        expect(InterfaceList.openModalStack).toEqual([{ parentInterfaceId: interfaceId, rootCompId: 0 }]);
        expect(InterfaceList.componentsForInterface(interfaceId).map((c) => c.id & 0xffff)).toEqual([1, 3]);
        expect(bridged).toEqual([{ openedInterfaceId: interfaceId, rootWidgetId: interfaceId }]);
    });
});
