#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PLAYER_FILE="${RT4_BANK_FIXTURE_PLAYER_FILE:-$REPO_ROOT/2009scape-web/2009scape/Server/data/players/rt4bankfx4.json}"
TEMPLATE_FILE="${RT4_BANK_FIXTURE_TEMPLATE_FILE:-$REPO_ROOT/2009scape-web/2009scape/Server/data/players/rt4bankfixture.json}"
LOGIN_ROUTE="${RT4_BANK_FIXTURE_LOGIN_ROUTE:-lobby}"
MODE="${1:-seed}"

node - "$PLAYER_FILE" "$TEMPLATE_FILE" "$LOGIN_ROUTE" "$MODE" <<'NODE'
const fs = require('fs');

const file = process.argv[2];
const templateFile = process.argv[3];
const loginRoute = process.argv[4];
const mode = process.argv[5];
const fixture = {
  bank: [],
  inventory: [
    { amount: "1", charge: "1000", slot: "0", id: "1351" },
    { amount: "1", charge: "1000", slot: "1", id: "590" },
    { amount: "50", charge: "1000", slot: "2", id: "995" },
  ],
};

function fail(message) {
  console.error(message);
  process.exit(1);
}

if (!fs.existsSync(file)) {
  if (mode === "--check") {
    fail(`missing RT4 bank fixture player save: ${file}`);
  }
  if (!fs.existsSync(templateFile)) {
    fail(`missing RT4 bank fixture player save and template: ${file}; ${templateFile}`);
  }
  fs.copyFileSync(templateFile, file);
}

const save = JSON.parse(fs.readFileSync(file, 'utf8'));
if (!save.core_data || typeof save.core_data !== 'object') {
  fail(`RT4 bank fixture has no core_data object: ${file}`);
}

function upsertAttribute(key, type, value) {
  if (!Array.isArray(save.attributes)) {
    save.attributes = [];
  }
  const existing = save.attributes.find((attr) => attr && attr.key === key);
  const attr = existing || { key };
  attr.type = type;
  attr.value = value;
  delete attr.expirable;
  delete attr['expiration-time'];
  if (!existing) {
    save.attributes.push(attr);
  }
}

function removeAttribute(key) {
  if (!Array.isArray(save.attributes)) {
    return;
  }
  save.attributes = save.attributes.filter((attr) => !attr || attr.key !== key);
}

const hasItems = (items) => Array.isArray(items) && items.some((item) => {
  const id = Number(item && item.id);
  const amount = Number(item && item.amount);
  return Number.isFinite(id) && id >= 0 && Number.isFinite(amount) && amount > 0;
});

if (mode === "--check") {
  if (!hasItems(save.core_data.inventory) && !hasItems(save.core_data.bank)) {
    fail(`RT4 bank fixture has no inventory or bank items: ${file}`);
  }
  console.log(`RT4 bank fixture already has item data: ${file}`);
  process.exit(0);
}

save.core_data.bank = fixture.bank;
save.core_data.inventory = fixture.inventory;
save.core_data.location = "3094,3107,0";
if (loginRoute === "direct") {
  removeAttribute("tutorial:complete");
  upsertAttribute("tutorial:stage", "int", "0");
} else {
  upsertAttribute("tutorial:complete", "bool", true);
  upsertAttribute("tutorial:stage", "int", "73");
}
upsertAttribute("rules:confirmed", "bool", true);
if (!Array.isArray(save.core_data.bankTabs) || save.core_data.bankTabs.length === 0) {
  save.core_data.bankTabs = Array.from({ length: 11 }, (_, index) => ({
    startSlot: "0",
    index: String(index),
  }));
}

fs.writeFileSync(file, JSON.stringify(save));
console.log(`Seeded RT4 bank fixture player save: ${file}`);
NODE
