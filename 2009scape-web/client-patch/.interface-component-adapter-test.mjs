import fs from "fs";

const tracePath = new URL("./.interface-component-adapter-trace.txt", import.meta.url);

function fromInterfaceComponent(data) {
    const c = {
        id: data.id,
        if3: data.ifVersion === 3,
        ifVersion: data.ifVersion,
        type: data.type,
        x: data.x,
        y: data.y,
        width: data.width,
        height: data.height,
        parentId: data.parentId,
        childIds: [],
        ops: data.ops ? data.ops.slice() : [],
        text: null,
        inventorySlotCount: 0,
        inventoryItems: [],
        inventoryItemAmounts: [],
        inventoryOptions: [],
    };
    if (data.container) {
        c.childIds = data.container.childIds.slice();
    }
    if (data.text) {
        c.text = data.text.text;
        c.font = data.text.font;
        c.colour = data.text.color;
    }
    if (data.inventory) {
        c.inventorySlotCount = data.inventory.slotCount;
        c.inventoryItems = data.inventory.items.slice();
        c.inventoryItemAmounts = data.inventory.itemAmounts.slice();
        c.inventoryOptions = data.inventory.options.slice();
        if (c.ops.length === 0) c.ops = data.inventory.options.slice();
    }
    return c;
}

const inventoryData = {
    id: (12 << 16) | 0,
    ifVersion: 3,
    type: 2,
    x: 12,
    y: 18,
    width: 7,
    height: 4,
    parentId: -1,
    ops: [],
    inventory: {
        slotCount: 28,
        items: new Array(28).fill(-1),
        itemAmounts: new Array(28).fill(0),
        options: ["Use", "Drop", "", "", ""],
    },
};

const textData = {
    id: (12 << 16) | 1,
    ifVersion: 3,
    type: 4,
    x: 3,
    y: 5,
    width: 120,
    height: 20,
    parentId: -1,
    ops: [],
    text: { text: "Hello 530", font: 494, color: 0xffcc00 },
};

const inventory = fromInterfaceComponent(inventoryData);
const text = fromInterfaceComponent(textData);

if (!inventory.if3 || inventory.inventorySlotCount !== 28 || inventory.inventoryItems.length !== 28) {
    throw new Error("inventory adapter projection failed");
}
if (!text.if3 || text.text !== "Hello 530" || text.font !== 494) {
    throw new Error("text adapter projection failed");
}

const lines = [
    `[InterfaceComponent530Adapter] component id=${inventory.id} type=${inventory.type} slots=${inventory.inventorySlotCount}`,
    `[InterfaceComponent530Adapter] component id=${text.id} type=${text.type} text=${text.text}`,
];
fs.writeFileSync(tracePath, lines.join("\n") + "\n");
console.log(lines.join("\n"));
