let playwright;
try {
  playwright = require('playwright');
} catch (err) {
  playwright = require('../../Deployment_Scripts/playwright/node_modules/playwright');
}
const { chromium } = playwright;
const fs = require('fs');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 900, height: 700 },
  });
  const page = await context.newPage();

  const logs = [];
  const pageErrors = [];

  const assertFirstPlayable = process.env.ASSERT_FIRST_PLAYABLE === '1';
  const assertFirstPlayableExtended = process.env.ASSERT_FIRST_PLAYABLE_EXTENDED === '1';
  const targetUrl = process.env.CLIENT_URL || 'http://10.8.0.1:8500/';
  const username = process.env.CLIENT_USERNAME || (assertFirstPlayable ? 'rt4bankfx4' : 'playtest2');
  const password = process.env.CLIENT_PASSWORD || username;
  const relogUsername = process.env.CLIENT_RELOG_USERNAME || (username.length < 12 ? `${username}r` : `${username.slice(0, 11)}r`);
  const relogPassword = process.env.CLIENT_RELOG_PASSWORD || 'password';
  const captureScreenshots = process.env.CAPTURE_SCREENSHOTS !== '0';
  const sendCommand = process.env.SEND_COMMAND !== '0' && !assertFirstPlayable;
  const assertCommand = process.env.ASSERT_COMMAND === '1';
  const assertWalk = process.env.ASSERT_WALK === '1' || assertFirstPlayable;
  const assertMinimapWalk = process.env.ASSERT_MINIMAP_WALK === '1' || assertFirstPlayable;
  const assertActionProbes = process.env.ASSERT_ACTION_PROBES === '1';
  const assertGroundItemActionProbes = process.env.ASSERT_GROUND_ITEM_ACTION_PROBES === '1';
  const assertGroundItemMenuProbe = process.env.ASSERT_GROUND_ITEM_MENU_PROBE === '1' || assertFirstPlayable;
  const assertDialogueContinueProbe = process.env.ASSERT_DIALOGUE_CONTINUE_PROBE === '1';
  const assertDialogueActionProbe = process.env.ASSERT_DIALOGUE_ACTION_PROBE === '1';
  const assertRenderedActionMenu = process.env.ASSERT_RENDERED_ACTION_MENU === '1';
  const assertRenderedNpcMenu = process.env.ASSERT_RENDERED_NPC_MENU === '1';
  const assertRenderedLocMenu = process.env.ASSERT_RENDERED_LOC_MENU === '1';
  const assertCombatTargetProbe = process.env.ASSERT_COMBAT_TARGET_PROBE === '1';
  const assertCombatContactSmoke = process.env.ASSERT_COMBAT_CONTACT_SMOKE === '1' || assertFirstPlayable;
  const assertDropTakeSmoke = process.env.ASSERT_DROP_TAKE_SMOKE === '1' || assertFirstPlayable;
  const assertKeepalive = process.env.ASSERT_KEEPALIVE === '1' || assertFirstPlayable;
  const assertNpcDialogueSmoke = process.env.ASSERT_NPC_DIALOGUE_SMOKE === '1' || assertFirstPlayable;
  const assertBankInventoryProbe = process.env.ASSERT_BANK_INVENTORY_PROBE === '1' || assertFirstPlayable;
  const assertBankActionProbe = process.env.ASSERT_BANK_ACTION_PROBE === '1' || assertFirstPlayable;
  const autoEnterWorld = process.env.AUTO_ENTER_WORLD === '1';
  const requirePlayerInfoProbe = process.env.REQUIRE_PLAYER_INFO_PROBE === '1';
  const allowInvisibleLocalPlayer = process.env.ALLOW_INVISIBLE_LOCAL_PLAYER === '1'
    || assertBankInventoryProbe
    || assertBankActionProbe
    || autoEnterWorld;
  const bankFixtureCommand = process.env.BANK_FIXTURE_COMMAND || (assertFirstPlayable ? '::bank' : '');
  const bankFixtureNativeCommand = process.env.BANK_FIXTURE_NATIVE_COMMAND !== '0';
  const bankFixtureCommands = bankFixtureCommand
    .split(/\s*;\s*|\r?\n/)
    .map((command) => command.trim())
    .filter((command) => command.length > 0);
  const bankFixtureWaitMs = process.env.BANK_FIXTURE_WAIT_MS ? Number(process.env.BANK_FIXTURE_WAIT_MS) : 12000;
  const postEnterWorldWaitMs = process.env.POST_ENTER_WORLD_WAIT_MS ? Number(process.env.POST_ENTER_WORLD_WAIT_MS) : 1500;
  const assertLogoutRelog = process.env.ASSERT_LOGOUT_RELOG === '1' || assertFirstPlayableExtended;
  const assertServerRestartReconnect = process.env.ASSERT_SERVER_RESTART_RECONNECT === '1' || assertFirstPlayableExtended;
  const bankInventoryContainerIds = (process.env.BANK_INVENTORY_CONTAINER_IDS || (assertFirstPlayable ? '93,95' : ''))
    .split(',')
    .map((id) => id.trim())
    .filter((id) => id.length > 0)
    .map((id) => Number(id))
    .filter((id) => Number.isFinite(id));
  const bankInventoryRequireOpen = process.env.BANK_INVENTORY_REQUIRE_OPEN === '1' || assertFirstPlayable;
  const bankInventoryRequireItem = process.env.BANK_INVENTORY_REQUIRE_ITEM === '1' || assertFirstPlayable;
  const bankActionContainerId = process.env.BANK_ACTION_CONTAINER_ID ? Number(process.env.BANK_ACTION_CONTAINER_ID) : (assertFirstPlayable ? 93 : undefined);
  const bankActionOption = process.env.BANK_ACTION_OPTION ? Number(process.env.BANK_ACTION_OPTION) : 1;
  const bankActionMode = process.env.BANK_ACTION_MODE || 'if';
  const bankActionMutationWaitMs = process.env.BANK_ACTION_MUTATION_WAIT_MS ? Number(process.env.BANK_ACTION_MUTATION_WAIT_MS) : 5000;
  const npcDialogueTargetId = process.env.NPC_DIALOGUE_TARGET_ID ? Number(process.env.NPC_DIALOGUE_TARGET_ID) : 945;
  const npcDialogueFixtureCommand = process.env.NPC_DIALOGUE_FIXTURE_COMMAND || '';
  const npcDialogueWaitMs = process.env.NPC_DIALOGUE_WAIT_MS ? Number(process.env.NPC_DIALOGUE_WAIT_MS) : 8000;
  const dropTakeFixtureCommand = process.env.DROP_TAKE_FIXTURE_COMMAND || '';
  const dropTakeContainerId = process.env.DROP_TAKE_CONTAINER_ID ? Number(process.env.DROP_TAKE_CONTAINER_ID) : 93;
  const dropTakeWaitMs = process.env.DROP_TAKE_WAIT_MS ? Number(process.env.DROP_TAKE_WAIT_MS) : 10000;
  const dropTakeTakeMode = process.env.DROP_TAKE_TAKE_MODE || (assertFirstPlayable ? 'menu' : 'direct');
  const combatContactWaitMs = process.env.COMBAT_CONTACT_WAIT_MS ? Number(process.env.COMBAT_CONTACT_WAIT_MS) : 12000;
  const autoLogin = process.env.AUTO_LOGIN === '1';
  const serverHost = process.env.CLIENT_SERVER_HOST;
  const serverPort = process.env.CLIENT_SERVER_PORT ? Number(process.env.CLIENT_SERVER_PORT) : undefined;
  const serverDialect = process.env.CLIENT_SERVER_DIALECT;
  const stabilityMs = process.env.STABILITY_MS ? Number(process.env.STABILITY_MS) : (assertFirstPlayable ? 60000 : 45000);
  const effectiveSmokeConfig = {
    assertFirstPlayable,
    assertFirstPlayableExtended,
    targetUrl,
    username,
    captureScreenshots,
    sendCommand,
    autoLogin,
    serverHost,
    serverPort,
    serverDialect,
    stabilityMs,
    gates: {
      assertWalk,
      assertMinimapWalk,
      assertActionProbes,
      assertGroundItemActionProbes,
      assertGroundItemMenuProbe,
      assertDialogueContinueProbe,
      assertDialogueActionProbe,
      assertRenderedActionMenu,
      assertRenderedNpcMenu,
      assertRenderedLocMenu,
      assertCombatTargetProbe,
      assertCombatContactSmoke,
      assertDropTakeSmoke,
      assertKeepalive,
      assertNpcDialogueSmoke,
      assertBankInventoryProbe,
      assertBankActionProbe,
      assertLogoutRelog,
      assertServerRestartReconnect,
    },
    bank: {
      bankFixtureCommands,
      bankFixtureNativeCommand,
      bankFixtureWaitMs,
      bankInventoryContainerIds,
      bankInventoryRequireOpen,
      bankInventoryRequireItem,
      bankActionContainerId,
      bankActionOption,
      bankActionMode,
      bankActionMutationWaitMs,
    },
    npcDialogue: {
      npcDialogueTargetId,
      npcDialogueFixtureCommand,
      npcDialogueWaitMs,
    },
    dropTake: {
      dropTakeFixtureCommand,
      dropTakeContainerId,
      dropTakeWaitMs,
      dropTakeTakeMode,
    },
    combat: {
      combatContactWaitMs,
    },
  };
  console.log('>>> Effective smoke config: ' + JSON.stringify(effectiveSmokeConfig));
  const runSmokeGate = async (label, fn) => {
    if (!assertFirstPlayable) return fn();
    console.log('>>> First playable gate start: ' + label);
    try {
      const result = await fn();
      console.log('>>> First playable gate pass: ' + label);
      return result;
    } catch (err) {
      console.log('>>> First playable gate fail: ' + label + ': ' + String(err?.message || err));
      throw err;
    }
  };
  const shot = async (path) => {
    if (!captureScreenshots) return;
    const dataUrl = await page.evaluate(() => document.querySelector('canvas')?.toDataURL('image/png') || '');
    if (dataUrl) fs.writeFileSync(path, Buffer.from(dataUrl.split(',')[1], 'base64'));
  };
  const waitForInGame = async () => {
    try {
      await page.waitForFunction((allowInvisibleLocalPlayer) => {
        const g = window.__webscapeGame;
        const p = g?.constructor.localPlayer;
        return !!g?.loggedIn && g.loadingStage === 2 && (allowInvisibleLocalPlayer || !!p?.visible);
      }, allowInvisibleLocalPlayer, { timeout: 90000 });
    } catch (err) {
      const diagnostics = await page.evaluate(() => {
        const g = window.__webscapeGame;
        const p = g?.constructor.localPlayer;
        return {
          loggedIn: !!g?.loggedIn,
          loadingStage: g?.loadingStage ?? null,
          loginScreenState: g?.loginScreenState ?? null,
          statusLineOne: g?.statusLineOne || '',
          statusLineTwo: g?.statusLineTwo || '',
          opcode: g?.opcode ?? null,
          packetSize: g?.packetSize ?? null,
          timeoutCounter: g?.timeoutCounter ?? null,
          lastDropClientReason: g?.lastDropClientReason || '',
          rt4KeepaliveSendCount: g?.rt4KeepaliveSendCount ?? null,
          lastRt4KeepaliveAt: g?.lastRt4KeepaliveAt ?? null,
          lastRt4KeepaliveReason: g?.lastRt4KeepaliveReason || '',
          lastRt4KeepaliveError: g?.lastRt4KeepaliveError || '',
          rt4KeepaliveActive: g?.rt4KeepaliveActive ?? null,
          lastFlushOutgoingAt: g?.lastFlushOutgoingAt ?? null,
          lastFlushOutgoingError: g?.lastFlushOutgoingError || '',
          lastFlushOutgoingOpcodeCount: g?.lastFlushOutgoingOpcodeCount ?? null,
          lastIncomingOpcode530: g?.lastIncomingOpcode530 ?? null,
          lastIncomingPacketSize: g?.lastIncomingPacketSize ?? null,
          lastIncomingAvailable: g?.lastIncomingAvailable ?? null,
          partialPacketWaitCount: g?.partialPacketWaitCount ?? null,
          lastPartialPacketReason: g?.lastPartialPacketReason || '',
          lastPartialPacketOpcode530: g?.lastPartialPacketOpcode530 ?? null,
          lastPartialPacketExpected: g?.lastPartialPacketExpected ?? null,
          lastPartialPacketAvailable: g?.lastPartialPacketAvailable ?? null,
          lastIncomingPacketAt: g?.lastIncomingPacketAt ?? null,
          localPlayer: p ? {
            visible: !!p.visible,
            worldX: p.worldX,
            worldY: p.worldY,
            pathX0: p.pathX?.[0],
            pathY0: p.pathY?.[0],
          } : null,
          wsEvents: (window.__webscapeWsEvents || []).slice(-20),
          sentPackets: (window.__webscapeSentPackets || []).slice(-20),
        };
      }).catch((diagnosticErr) => ({ error: String(diagnosticErr?.message || diagnosticErr) }));
      throw new Error('timed out waiting for in-game state: ' + JSON.stringify(diagnostics) + '; cause=' + String(err?.message || err));
    }
  };

  page.on('console', (msg) => logs.push(`[${msg.type()}] ${msg.text()}`));
  page.on('pageerror', (err) => pageErrors.push(`${err.name}: ${err.message}`));
  await page.addInitScript(({ username, password, autoLogin, serverHost, serverPort, serverDialect }) => {
    window.__webscapeCredentials = { username, password, autoLogin };
    if (serverHost && Number.isFinite(serverPort)) {
      window.__webscapeServer = { host: serverHost, port: serverPort, dialect: serverDialect };
    }
    window.__webscapeWsOpenCount = 0;
    window.__webscapeWsCloseCount = 0;
    window.__webscapeWsSendCount = 0;
    window.__webscapeWsSendSeq = 0;
    window.__webscapeWsSocketSeq = 0;
    window.__webscapeSentPackets = [];
    window.__webscapeWsEvents = [];
    window.DEBUG_PACKETS_530 = true;
    const describePacket = (bytes) => {
      const opcode = bytes[0];
      const labels = {
        14: 'handshake-530',
        16: 'login-new-530',
        18: 'login-reconnect-530',
        44: 'command-530',
      };
      const description = {
        opcode,
        label: labels[opcode] || 'opcode-' + opcode,
      };
      if (opcode === 44) {
        const declaredLength = bytes[1] ?? null;
        const body = bytes.slice(2, declaredLength == null ? undefined : 2 + declaredLength);
        description.declaredLength = declaredLength;
        description.command = String.fromCharCode(...body.filter((byte) => byte > 0));
      } else if (opcode === 16 || opcode === 18) {
        description.loginLength = bytes.length >= 3 ? ((bytes[1] & 0xff) << 8) | (bytes[2] & 0xff) : null;
      } else if (opcode === 14) {
        description.nameHash = bytes[1] ?? null;
      }
      return description;
    };
    const pushWsEvent = (event) => {
      window.__webscapeWsEvents.push({ seq: window.__webscapeWsEvents.length + 1, ...event });
      if (window.__webscapeWsEvents.length > 100) window.__webscapeWsEvents.shift();
    };
    const NativeWebSocket = window.WebSocket;
    window.WebSocket = class WebscapeTrackedWebSocket extends NativeWebSocket {
      constructor(...args) {
        super(...args);
        this.__webscapeSocketId = ++window.__webscapeWsSocketSeq;
        window.__webscapeWsOpenCount++;
        pushWsEvent({ type: 'construct', socketId: this.__webscapeSocketId, url: String(args[0] || '') });
        this.addEventListener('open', () => {
          pushWsEvent({ type: 'open', socketId: this.__webscapeSocketId });
        });
        this.addEventListener('close', (event) => {
          window.__webscapeWsCloseCount++;
          pushWsEvent({ type: 'close', socketId: this.__webscapeSocketId, code: event.code, reason: event.reason, wasClean: event.wasClean });
        });
        this.addEventListener('error', () => {
          pushWsEvent({ type: 'error', socketId: this.__webscapeSocketId });
        });
      }

      send(data) {
        window.__webscapeWsSendCount++;
        window.__webscapeWsSendSeq++;
        const bytes = ArrayBuffer.isView(data)
          ? Array.from(new Uint8Array(data.buffer, data.byteOffset, data.byteLength))
          : data instanceof ArrayBuffer
            ? Array.from(new Uint8Array(data))
            : [];
        const packet = {
          seq: window.__webscapeWsSendSeq,
          socketId: this.__webscapeSocketId,
          len: bytes.length,
          bytes: bytes.slice(0, 48),
          decoded: describePacket(bytes),
        };
        window.__webscapeSentPackets.push(packet);
        if (window.__webscapeSentPackets.length > 100) window.__webscapeSentPackets.shift();
        pushWsEvent({ type: 'send', socketId: this.__webscapeSocketId, packet });
        return super.send(data);
      }
    };
  }, { username, password, autoLogin, serverHost, serverPort, serverDialect });

  console.log('>>> Navigating to ' + targetUrl + '...');
  await page.goto(targetUrl, { waitUntil: 'networkidle', timeout: 30000 });
  await page.waitForSelector('canvas', { timeout: 15000 });
  await page.waitForTimeout(6000);

  const canvas = await page.$('canvas');
  const box = await canvas.boundingBox();
  const scaleX = box.width / 765;
  const scaleY = box.height / 503;
  const canvasClick = async (cx, cy) => {
    await page.mouse.move(box.x + cx * scaleX, box.y + cy * scaleY);
    await page.mouse.down();
    await page.waitForTimeout(80);
    await page.mouse.up();
  };
  const canvasRightClick = async (cx, cy) => {
    await page.mouse.move(box.x + cx * scaleX, box.y + cy * scaleY);
    await page.mouse.click(box.x + cx * scaleX, box.y + cy * scaleY, { button: 'right' });
  };
  const readMenuRows = async () => page.evaluate(() => {
    const g = window.__webscapeGame;
    if (!g) return [];
    const rows = [];
    for (let i = 0; i < (g.menuActionRow || 0); i++) {
      rows.push({
        index: i,
        text: g.menuActionTexts?.[i] || '',
        action: g.menuActionTypes?.[i] || 0,
        first: g.firstMenuOperand?.[i] || 0,
        second: g.secondMenuOperand?.[i] || 0,
        selected: g.selectedMenuActions?.[i] || 0,
      });
    }
    return rows;
  });
  const packetOpcodes = async (limit = 20) => page.evaluate((limit) => {
    return (window.__webscapeSemanticPackets || [])
      .slice(-limit)
      .map((packet) => packet.semantic?.opcode)
      .filter((opcode) => Number.isFinite(opcode));
  }, limit);
  const assertOpcodeSince = async (label, beforeCount, opcodes) => {
    const packets = await page.evaluate(({ beforeCount }) => {
      return (window.__webscapeSemanticPackets || []).filter((packet) => (packet.seq || 0) > beforeCount);
    }, { beforeCount });
    const hasOpcode = (packet, opcode) => packet.semantic?.opcode === opcode
      || (packet.semantics || []).some((semantic) => semantic?.opcode === opcode)
      || (packet.bytes || []).some((byte) => (byte & 0xff) === opcode);
    const missing = opcodes.filter((opcode) => !packets.some((packet) => hasOpcode(packet, opcode)));
    if (missing.length > 0) {
      throw new Error(label + ' did not emit expected opcode; expected=' + opcodes.join(',')
        + ' missing=' + missing.join(',')
        + ' packets=' + JSON.stringify(packets.slice(-12)));
    }
    console.log('>>> ' + label + ' emitted opcode(s): ' + packets
      .flatMap((p) => [p.semantic, ...(p.semantics || [])].map((semantic) => semantic?.opcode))
      .filter(Boolean)
      .join(','));
  };
  const semanticSeq = async () => page.evaluate(() => window.__webscapeSemanticPacketSeq || 0);
  const runtimeEvidenceFields = [
    'rt4KeepaliveSendCount',
    'lastRt4KeepaliveAt',
    'lastRt4KeepaliveReason',
    'lastRt4KeepaliveError',
    'rt4KeepaliveActive',
    'lastFlushOutgoingAt',
    'lastFlushOutgoingError',
    'lastFlushOutgoingOpcodeCount',
    'lastIncomingOpcode530',
    'lastIncomingPacketSize',
    'lastIncomingAvailable',
    'partialPacketWaitCount',
    'lastPartialPacketReason',
    'lastPartialPacketOpcode530',
    'lastPartialPacketExpected',
    'lastPartialPacketAvailable',
    'lastIncomingPacketAt',
    'lastDropClientReason',
  ];
  const readBankInventorySnapshot = async ({ expectedIds, requireOpen, requireItem }) => page.evaluate(({ expectedIds, requireOpen, requireItem, runtimeEvidenceFields }) => {
    const g = window.__webscapeGame;
    const readRuntimeEvidence = () => {
      const evidence = {};
      if (!g) return evidence;
      for (const field of runtimeEvidenceFields) {
        if (field in g) evidence[field] = g[field] ?? null;
      }
      return evidence;
    };
    const toSigned32 = (value) => value | 0;
    const toUnsigned32 = (value) => value >>> 0;
    const decodeComponentHash = (componentHash) => {
      if (!Number.isFinite(componentHash)) return null;
      const unsigned = toUnsigned32(componentHash);
      return {
        raw: toSigned32(componentHash),
        unsigned,
        hex: '0x' + unsigned.toString(16).padStart(8, '0'),
        interfaceId: unsigned >>> 16,
        childId: unsigned & 0xffff,
      };
    };
    const summarizeInterface = (name, id) => {
      const normalizedId = Number.isFinite(id) ? id : -1;
      if (normalizedId === -1) return { name, id: -1, open: false };
      let component = null;
      try {
        component = g?.getComponent ? g.getComponent(normalizedId) : null;
      } catch (err) {
        component = null;
      }
      return {
        name,
        id: normalizedId,
        open: true,
        hasComponent: !!component,
        parentId: component?.parentId ?? null,
        type: component?.type ?? null,
        contentType: component?.contentType ?? null,
        width: component?.width ?? null,
        height: component?.height ?? null,
        children: Array.isArray(component?.children) ? component.children.length : null,
      };
    };
    const componentSummary = (componentHash) => {
      const decoded = decodeComponentHash(componentHash);
      if (!decoded || decoded.raw < 0) return { decoded, hasComponent: false };
      let component = null;
      try {
        component = g?.getComponent ? g.getComponent(decoded.raw) : null;
      } catch (err) {
        component = null;
      }
      return {
        decoded,
        hasComponent: !!component,
        parentId: component?.parentId ?? null,
        type: component?.type ?? null,
        contentType: component?.contentType ?? null,
        inventorySlotCount: component?.inventorySlotCount ?? null,
        inventoryItemsLength: Array.isArray(component?.inventoryItems) ? component.inventoryItems.length : null,
        inventoryAmountsLength: Array.isArray(component?.inventoryItemAmounts) ? component.inventoryItemAmounts.length : null,
        width: component?.width ?? null,
        height: component?.height ?? null,
      };
    };
    const itemsByContainer = g?.containerItems || {};
    const amountsByContainer = g?.containerAmounts || {};
    const componentsByContainer = g?.containerComponents || {};
    const rt4Diagnostics = g?.rt4InterfaceDiagnostics ? g.rt4InterfaceDiagnostics() : {
      topInterface: g?.topInterface || null,
      openModalStack: [],
      loadedInterfaces: [],
      recentPackets530: g?.packetTrace530 || [],
    };
    const runtimeEvidence = readRuntimeEvidence();
    const chatRecent = [];
    const chatMessages = g?.chatMessages || [];
    for (let i = 0; i < Math.min(10, chatMessages.length); i++) {
      if (chatMessages[i]) chatRecent.push({
        type: g.chatTypes?.[i],
        name: g.chatPlayerNames?.[i] || '',
        message: chatMessages[i] || '',
      });
    }
    const openInterfaces = [
      summarizeInterface('modal', g?.openInterfaceId),
      summarizeInterface('tab', g?.anInt1089),
      summarizeInterface('chatBack', g?.backDialogueId),
      summarizeInterface('dialogue', g?.dialogueId),
    ];
    const openInterfaceIds = openInterfaces
      .filter((entry) => entry.open)
      .map((entry) => entry.id);
    const ids = Array.from(new Set([
      ...Object.keys(itemsByContainer),
      ...Object.keys(amountsByContainer),
      ...Object.keys(componentsByContainer),
    ])).map((id) => Number(id)).filter((id) => Number.isFinite(id)).sort((a, b) => a - b);
    const containers = ids.map((id) => {
      const items = Array.isArray(itemsByContainer[id]) ? itemsByContainer[id] : [];
      const amounts = Array.isArray(amountsByContainer[id]) ? amountsByContainer[id] : [];
      const componentHash = componentsByContainer[id] ?? null;
      const component = componentSummary(componentHash);
      const nonEmptySlots = items.reduce((count, itemId, slot) => {
        const amount = amounts[slot] || 0;
        return count + (Number.isFinite(itemId) && itemId >= 0 && amount > 0 ? 1 : 0);
      }, 0);
      const lengthMismatches = [];
      for (let slot = 0; slot < Math.max(items.length, amounts.length); slot++) {
        const itemId = items[slot];
        const amount = amounts[slot];
        if ((Number.isFinite(itemId) && itemId >= 0) !== (Number.isFinite(amount) && amount > 0)) {
          lengthMismatches.push({ slot, itemId: itemId ?? null, amount: amount ?? null });
        }
        if (lengthMismatches.length >= 5) break;
      }
      return {
        id,
        idHex: '0x' + (id >>> 0).toString(16),
        componentHash,
        component,
        attachedOpenInterface: component.decoded
          ? openInterfaceIds.includes(component.decoded.interfaceId) || openInterfaceIds.includes(component.decoded.raw)
          : false,
        itemsLength: items.length,
        amountsLength: amounts.length,
        nonEmptySlots,
        firstSlots: items.slice(0, 10).map((itemId, slot) => ({ slot, itemId, amount: amounts[slot] || 0 })),
        sample: items.map((itemId, slot) => ({ slot, itemId, amount: amounts[slot] || 0 }))
          .filter((slot) => slot.itemId >= 0 || slot.amount > 0)
          .slice(0, 8),
        valueMismatches: lengthMismatches,
      };
    });
    const missingExpectedIds = expectedIds.filter((expectedId) => !containers.some((container) => container.id === expectedId));
    const problems = [];
    if (!g?.loggedIn || g?.loadingStage !== 2) problems.push('client is not in playable state');
    for (const container of containers) {
      if (container.itemsLength !== container.amountsLength) {
        problems.push(`container ${container.id} item/amount length mismatch ${container.itemsLength}/${container.amountsLength}`);
      }
      if (container.valueMismatches.length > 0) {
        problems.push(`container ${container.id} has item/amount value mismatches ${JSON.stringify(container.valueMismatches)}`);
      }
    }
    if (containers.length === 0) problems.push('no server container snapshots have been decoded');
    for (const expectedId of missingExpectedIds) {
      problems.push(`expected container ${expectedId} was not decoded`);
    }
    if (requireOpen && openInterfaceIds.length === 0) problems.push('no modal/tab/dialogue interface is open');
    if (requireItem && !containers.some((container) => container.nonEmptySlots > 0)) {
      problems.push('no non-empty container slots were observed');
    }
    return {
      loggedIn: !!g?.loggedIn,
      loadingStage: g?.loadingStage,
      openInterfaces,
      expectedIds,
      missingExpectedIds,
      requireOpen,
      requireItem,
      containerIds: containers.map((container) => container.id),
      containers,
      rt4Diagnostics,
      runtimeEvidence,
      chatRecent,
      problems,
    };
  }, { expectedIds, requireOpen, requireItem, runtimeEvidenceFields });
  const classifyBankSmokeFailure = (snapshot) => {
    const evidence = snapshot.runtimeEvidence || {};
    if (Object.keys(evidence).length === 0) return '';
    const classifications = [];
    if (evidence.lastDropClientReason) {
      classifications.push('server-close/drop evidence: lastDropClientReason=' + JSON.stringify(evidence.lastDropClientReason));
    }
    if (evidence.lastRt4KeepaliveError) {
      classifications.push('keepalive send error: lastRt4KeepaliveError=' + JSON.stringify(evidence.lastRt4KeepaliveError));
    } else if (evidence.rt4KeepaliveActive === false) {
      classifications.push('keepalive inactive: rt4KeepaliveActive=false');
    }
    if (evidence.lastFlushOutgoingError) {
      classifications.push('outgoing flush error: lastFlushOutgoingError=' + JSON.stringify(evidence.lastFlushOutgoingError));
    }
    if (Number.isFinite(evidence.partialPacketWaitCount) && evidence.partialPacketWaitCount > 0) {
      classifications.push('parser waited on partial packets: partialPacketWaitCount=' + evidence.partialPacketWaitCount
        + ' reason=' + JSON.stringify(evidence.lastPartialPacketReason || '')
        + ' opcode=' + JSON.stringify(evidence.lastPartialPacketOpcode530)
        + ' expected=' + JSON.stringify(evidence.lastPartialPacketExpected)
        + ' available=' + JSON.stringify(evidence.lastPartialPacketAvailable)
        + ' lastIncomingOpcode530=' + JSON.stringify(evidence.lastIncomingOpcode530)
        + ' lastIncomingPacketSize=' + JSON.stringify(evidence.lastIncomingPacketSize)
        + ' lastIncomingAvailable=' + JSON.stringify(evidence.lastIncomingAvailable));
    }
    if (classifications.length === 0) {
      classifications.push('runtime transport/parser evidence present without a classified error');
    }
    return ' classification=' + classifications.join(' | ');
  };
  const formatBankInventoryDiagnostics = (snapshot) => [
    'expectedIds=' + JSON.stringify(snapshot.expectedIds),
    'decodedIds=' + JSON.stringify(snapshot.containerIds),
    'missingExpectedIds=' + JSON.stringify(snapshot.missingExpectedIds),
    'openInterfaces=' + JSON.stringify(snapshot.openInterfaces),
    'rt4Diagnostics=' + JSON.stringify(snapshot.rt4Diagnostics),
    'runtimeEvidence=' + JSON.stringify(snapshot.runtimeEvidence || {}),
    'chatRecent=' + JSON.stringify(snapshot.chatRecent),
    'containers=' + JSON.stringify(snapshot.containers),
  ].join('; ');
  const formatBankInventoryAdvice = (snapshot) => {
    const advice = [];
    const sawSillyCommandDenial = (snapshot.chatRecent || [])
      .some((entry) => String(entry.message || '').includes('tried to do something very silly'));
    if (snapshot.missingExpectedIds.length > 0) {
      advice.push('check BANK_INVENTORY_CONTAINER_IDS against the fixture output');
    }
    if (sawSillyCommandDenial) {
      advice.push('the bank fixture command reached the server but was denied; run the local server with dev/admin/noauth-default-admin enabled');
    }
    if (snapshot.requireOpen && snapshot.openInterfaces.every((entry) => !entry.open)) {
      advice.push('open the bank fixture before asserting, or set BANK_FIXTURE_COMMAND to a server-side command that opens it');
    }
    if (snapshot.requireItem && !snapshot.containers.some((container) => container.nonEmptySlots > 0)) {
      advice.push('seed the fixture with at least one inventory or bank item, or unset BANK_INVENTORY_REQUIRE_ITEM');
    }
    if (snapshot.containers.length === 0) {
      advice.push('confirm the login reached a world that sends container snapshots before enabling the bank lane');
    }
    if (!bankFixtureCommand) {
      advice.push('optional: set BANK_FIXTURE_COMMAND to print/open the deterministic bank fixture and include its chat output in this failure');
    }
    return advice.length > 0 ? ' advice=' + advice.join(' | ') : '';
  };
  const runBankComponentItemActionProbe = async ({ expectedIds, preferredContainerId, option }) => {
    const optionToAction = {
      1: { action: 9, opcode: 81, label: 'item component option 1' },
      2: { action: 225, opcode: 206, label: 'item component option 2' },
      3: { action: 444, opcode: 154, label: 'item component option 3' },
      4: { action: 564, opcode: 85, label: 'item component option 4' },
      5: { action: 894, opcode: 6, label: 'item component option 5' },
    };
    const selectedOption = optionToAction[option] || optionToAction[1];
    const before = await semanticSeq();
    const result = await page.evaluate(({ expectedIds, preferredContainerId, selectedOption }) => {
      const g = window.__webscapeGame;
      if (!g) return { ok: false, reason: 'missing game' };
      const itemsByContainer = g.containerItems || {};
      const amountsByContainer = g.containerAmounts || {};
      const componentsByContainer = g.containerComponents || {};
      const ids = Array.from(new Set([
        ...(Number.isFinite(preferredContainerId) ? [preferredContainerId] : []),
        ...expectedIds,
        95,
        ...Object.keys(itemsByContainer).map((id) => Number(id)),
      ])).filter((id) => Number.isFinite(id));
      let chosen = null;
      for (const id of ids) {
        const items = Array.isArray(itemsByContainer[id]) ? itemsByContainer[id] : [];
        const amounts = Array.isArray(amountsByContainer[id]) ? amountsByContainer[id] : [];
        const componentHash = componentsByContainer[id];
        if (!Number.isFinite(componentHash) || componentHash < 0) continue;
        const slot = items.findIndex((itemId, index) => Number.isFinite(itemId) && itemId >= 0 && (amounts[index] || 0) > 0);
        if (slot < 0) continue;
        chosen = {
          containerId: id,
          componentHash: componentHash | 0,
          slot,
          itemId: items[slot] | 0,
          amount: amounts[slot] || 0,
        };
        break;
      }
      if (!chosen) {
        return {
          ok: false,
          reason: 'no non-empty component-backed bank/container slot',
          containerIds: Object.keys(itemsByContainer),
          componentsByContainer,
        };
      }
      g.menuActionTypes[0] = selectedOption.action;
      g.firstMenuOperand[0] = chosen.slot;
      g.secondMenuOperand[0] = chosen.componentHash;
      g.selectedMenuActions[0] = chosen.itemId;
      g.processMenuActions(0);
      g.flushOutgoingPackets?.();
      return { ok: true, selectedOption, chosen };
    }, { expectedIds, preferredContainerId, selectedOption });
    if (!result.ok) {
      throw new Error('bank action probe failed: ' + JSON.stringify(result));
    }
    await assertOpcodeSince('bank ' + selectedOption.label + ' probe', before, [selectedOption.opcode]);
    console.log('>>> Bank action probe selected: ' + JSON.stringify(result.chosen)
      + ' action=' + selectedOption.action + ' opcode=' + selectedOption.opcode);
  };
  const runBankIfActionProbe = async ({ expectedIds, preferredContainerId, option, mutationWaitMs }) => {
    const optionToAction = {
      1: { opcode: 155, label: 'IF action 1' },
      2: { opcode: 196, label: 'IF action 2' },
      3: { opcode: 124, label: 'IF action 3' },
      4: { opcode: 199, label: 'IF action 4' },
      5: { opcode: 234, label: 'IF action 5' },
      6: { opcode: 168, label: 'IF action 6' },
      7: { opcode: 166, label: 'IF action 7' },
    };
    const selectedOption = optionToAction[option] || optionToAction[1];
    const before = await semanticSeq();
    const result = await page.evaluate(async ({ expectedIds, preferredContainerId, selectedOption, option }) => {
      const g = window.__webscapeGame;
      if (!g?.outBuffer) return { ok: false, reason: 'game/outBuffer unavailable' };
      if (typeof g.sendNativeIfButtonAction !== 'function') {
        return { ok: false, reason: 'missing sendNativeIfButtonAction helper' };
      }
      const itemsByContainer = g.containerItems || {};
      const amountsByContainer = g.containerAmounts || {};
      const ids = Array.from(new Set([
        ...(Number.isFinite(preferredContainerId) ? [preferredContainerId] : []),
        93,
        95,
        ...expectedIds,
      ])).filter((id) => id === 93 || id === 95);
      const totalFor = (containerId, itemId) => {
        const items = Array.isArray(itemsByContainer[containerId]) ? itemsByContainer[containerId] : [];
        const amounts = Array.isArray(amountsByContainer[containerId]) ? amountsByContainer[containerId] : [];
        return items.reduce((total, id, slot) => total + (id === itemId ? (amounts[slot] || 0) : 0), 0);
      };
      let chosen = null;
      for (const id of ids) {
        const items = Array.isArray(itemsByContainer[id]) ? itemsByContainer[id] : [];
        const amounts = Array.isArray(amountsByContainer[id]) ? amountsByContainer[id] : [];
        const slot = items.findIndex((itemId, index) => Number.isFinite(itemId) && itemId >= 0 && (amounts[index] || 0) > 0);
        if (slot < 0) continue;
        const componentId = id === 93 ? ((763 << 16) | 0) : ((762 << 16) | 73);
        chosen = {
          containerId: id,
          direction: id === 93 ? 'deposit' : 'withdraw',
          componentId,
          slot,
          itemId: items[slot] | 0,
          amount: amounts[slot] || 0,
        };
        chosen.sourceTotalBefore = totalFor(id, chosen.itemId);
        chosen.targetContainerId = id === 93 ? 95 : 93;
        chosen.targetTotalBefore = totalFor(chosen.targetContainerId, chosen.itemId);
        break;
      }
      if (!chosen) {
        return {
          ok: false,
          reason: 'no non-empty bank IF source slot in containers 93/95',
          expectedIds,
          preferredContainerId,
          containerIds: Object.keys(itemsByContainer),
        };
      }
      const sent = await g.sendNativeIfButtonAction(option, chosen.componentId, chosen.slot);
      if (!sent) return { ok: false, reason: 'sendNativeIfButtonAction returned false', selectedOption, chosen };
      return { ok: true, selectedOption, chosen };
    }, { expectedIds, preferredContainerId, selectedOption, option });
    if (!result.ok) {
      throw new Error('bank IF action probe failed: ' + JSON.stringify(result));
    }
    await assertOpcodeSince('bank ' + selectedOption.label + ' probe', before, [selectedOption.opcode]);
    const mutationResult = await page.waitForFunction(({ chosen }) => {
      const g = window.__webscapeGame;
      const itemsByContainer = g?.containerItems || {};
      const amountsByContainer = g?.containerAmounts || {};
      const totalFor = (containerId, itemId) => {
        const items = Array.isArray(itemsByContainer[containerId]) ? itemsByContainer[containerId] : [];
        const amounts = Array.isArray(amountsByContainer[containerId]) ? amountsByContainer[containerId] : [];
        return items.reduce((total, id, slot) => total + (id === itemId ? (amounts[slot] || 0) : 0), 0);
      };
      const sourceTotal = totalFor(chosen.containerId, chosen.itemId);
      const targetTotal = totalFor(chosen.targetContainerId, chosen.itemId);
      if (sourceTotal < chosen.sourceTotalBefore || targetTotal > chosen.targetTotalBefore) {
        return { ok: true, sourceTotal, targetTotal };
      }
      return false;
    }, { chosen: result.chosen }, { timeout: mutationWaitMs }).then((handle) => handle.jsonValue()).catch(async () => {
      const after = await readBankInventorySnapshot({ expectedIds, requireOpen: false, requireItem: false });
      return { ok: false, after };
    });
    if (!mutationResult.ok) {
      throw new Error('bank IF action did not mutate containers after ' + mutationWaitMs + 'ms: '
        + JSON.stringify({ selected: result.chosen, after: mutationResult.after }));
    }
    console.log('>>> Bank IF action probe selected: ' + JSON.stringify(result.chosen)
      + ' opcode=' + selectedOption.opcode + ' mutation=' + JSON.stringify(mutationResult));
  };
  const runBankActionProbe = async ({ expectedIds, preferredContainerId, option, mode, mutationWaitMs }) => {
    if (mode === 'component-item') {
      return runBankComponentItemActionProbe({ expectedIds, preferredContainerId, option });
    }
    return runBankIfActionProbe({ expectedIds, preferredContainerId, option, mutationWaitMs });
  };
  const readNpcDialogueTargets = async ({ targetId }) => page.evaluate(({ targetId }) => {
    const g = window.__webscapeGame;
    if (!g) return { ok: false, reason: 'missing game', targets: [], npcs: [] };
    const npcs = [];
    for (let i = 0; i < (g.anInt1133 || 0); i++) {
      const index = g.anIntArray1134?.[i];
      const npc = g.npcs?.[index];
      const def = npc?.npcDefinition;
      const id = def?.id ?? def?.npcId ?? def?.type ?? -1;
      if (!npc || !def) continue;
      npcs.push({
        index,
        id,
        name: def.name || '',
        actions: Array.isArray(def.actions) ? def.actions.slice(0, 5) : [],
        clickable: !!def.clickable,
        pathX0: npc.pathX?.[0] ?? null,
        pathY0: npc.pathY?.[0] ?? null,
        worldX: npc.worldX ?? null,
        worldY: npc.worldY ?? null,
      });
    }
    return {
      ok: true,
      targetId,
      count: g.anInt1133 || 0,
      localPlayer: g.constructor.localPlayer ? {
        pathX0: g.constructor.localPlayer.pathX?.[0],
        pathY0: g.constructor.localPlayer.pathY?.[0],
        worldX: g.constructor.localPlayer.worldX,
        worldY: g.constructor.localPlayer.worldY,
      } : null,
      targets: npcs.filter((npc) => npc.id === targetId),
      npcs: npcs.slice(0, 20),
    };
  }, { targetId });
  const waitForNpcDialogueTarget = async ({ targetId, timeoutMs }) => {
    try {
      await page.waitForFunction(({ targetId }) => {
        const g = window.__webscapeGame;
        if (!g?.loggedIn || g.loadingStage !== 2) return false;
        for (let i = 0; i < (g.anInt1133 || 0); i++) {
          const index = g.anIntArray1134?.[i];
          const npc = g.npcs?.[index];
          const def = npc?.npcDefinition;
          const id = def?.id ?? def?.npcId ?? def?.type ?? -1;
          if (id === targetId) return true;
        }
        return false;
      }, { targetId }, { timeout: Number.isFinite(timeoutMs) ? timeoutMs : 8000 });
    } catch (err) {
      const targets = await readNpcDialogueTargets({ targetId });
      throw new Error('NPC dialogue target was not visible: ' + JSON.stringify(targets)
        + '; cause=' + String(err?.message || err).split('\n')[0]);
    }
    return readNpcDialogueTargets({ targetId });
  };
  const classifyNpcDialogueOpenFailure = (runtime) => {
    const updates = runtime?.interfaceUpdates || [];
    const packets = runtime?.packetTrace530Interesting || [];
    const ifOpenUpdates = updates.filter((update) => update.kind === 'IF_OPENTOP');
    const incomingOpenPackets = packets.filter((packet) => packet.opcode === 155 || packet.opcode === 145 || packet.opcodeName === 'IF_OPENTOP');
    if (incomingOpenPackets.length === 0 && ifOpenUpdates.length === 0) {
      return 'NPC action was sent, but no incoming interface-open packet/update was observed';
    }
    if (incomingOpenPackets.length > 0 && ifOpenUpdates.length === 0) {
      return 'incoming interface-open packet was observed, but PacketHandler530 did not record IF_OPENTOP';
    }
    const lastIfOpen = ifOpenUpdates[ifOpenUpdates.length - 1];
    const payload = lastIfOpen?.payload || {};
    if (payload.parentInterfaceId !== undefined && payload.parentInterfaceId !== 752) {
      return 'IF_OPENTOP targeted parent ' + payload.parentInterfaceId + ' instead of CHATTOP_752';
    }
    if (payload.parentInterfaceId === 752 && payload.childId === 12 && !(runtime?.dialogueId >= 0)) {
      return 'CHATTOP_752 dialogue child opened, but dialogueId was not mirrored';
    }
    if ((runtime?.dialogueId >= 0 || runtime?.backDialogueId >= 0)
      && runtime?.dialogueWidget?.open
      && runtime?.dialogueWidget?.hasComponent === false) {
      return 'dialogue state opened, but the legacy widget/component bridge is missing';
    }
    return 'dialogue open evidence was present, but no open dialogue state was observed';
  };
  const runNpcDialogueSmoke = async () => {
    console.log('>>> Run NPC dialogue smoke target=' + npcDialogueTargetId);
    let fixture = null;
    if (npcDialogueFixtureCommand) {
      const beforeRuntime = await readRuntimeDiagnostics();
      const submit = await sendNativeCommand(npcDialogueFixtureCommand);
      await page.waitForTimeout(2500);
      const afterRuntime = await readRuntimeDiagnostics();
      fixture = { command: npcDialogueFixtureCommand, submit, beforeRuntime, afterRuntime };
      console.log('>>> NPC dialogue fixture: ' + JSON.stringify(fixture));
    }
    const targetSnapshot = await waitForNpcDialogueTarget({
      targetId: npcDialogueTargetId,
      timeoutMs: npcDialogueWaitMs,
    });
    console.log('>>> NPC dialogue target snapshot: ' + JSON.stringify(targetSnapshot));
    const preActionFlush = await page.evaluate(async () => {
      const g = window.__webscapeGame;
      const pending = g?.outBuffer?.currentPosition || 0;
      if (pending > 0) await g.flushOutgoingPackets?.();
      return { pending };
    });
    if (preActionFlush.pending > 0) {
      console.log('>>> NPC dialogue pre-action flush cleared bytes: ' + JSON.stringify(preActionFlush));
      await page.waitForTimeout(150);
    }
    const npcOpcodeByAction = new Map([
      [318, 78],
      [921, 3],
      [118, 148],
      [553, 30],
      [432, 218],
    ]);
    const beforeTalk = await semanticSeq();
    const talkResult = await page.evaluate(({ targetId }) => {
      const g = window.__webscapeGame;
      if (!g) return { ok: false, reason: 'missing game' };
      let target = null;
      for (let i = 0; i < (g.anInt1133 || 0); i++) {
        const index = g.anIntArray1134?.[i];
        const npc = g.npcs?.[index];
        const def = npc?.npcDefinition;
        const id = def?.id ?? def?.npcId ?? def?.type ?? -1;
        if (id === targetId) {
          target = {
            index,
            id,
            name: def.name || '',
            actions: Array.isArray(def.actions) ? def.actions.slice(0, 5) : [],
            pathX0: npc.pathX?.[0] ?? null,
            pathY0: npc.pathY?.[0] ?? null,
            npc,
            def,
          };
          break;
        }
      }
      if (!target) return { ok: false, reason: 'target missing' };
      const npcActions = [318, 921, 118, 553, 432];
      const previousRows = g.menuActionRow || 0;
      g.menuActionRow = 0;
      g.method82(target.def, target.pathY0, target.pathX0, target.index, -76);
      const rows = [];
      const expectedOpcodeByAction = {
        318: 78,
        921: 3,
        118: 148,
        553: 30,
        432: 218,
      };
      for (let row = 0; row < (g.menuActionRow || 0); row++) {
        const text = g.menuActionTexts?.[row] || '';
        const action = g.menuActionTypes?.[row] || 0;
        rows.push({
          index: row,
          text,
          strippedText: String(text).replace(/@[a-z0-9]{3}@/gi, '').trim(),
          action,
          expectedOpcode: expectedOpcodeByAction[action] || null,
          first: g.firstMenuOperand?.[row] || 0,
          second: g.secondMenuOperand?.[row] || 0,
          selected: g.selectedMenuActions?.[row] || 0,
        });
      }
      const chosen = rows.find((row) => row.selected === target.index
        && npcActions.includes(row.action)
        && /^(talk-to|talk)\b/i.test(row.strippedText));
      if (!chosen) {
        g.menuActionRow = previousRows;
        return {
          ok: false,
          reason: 'no generated Talk-to/Talk row for target',
          target: {
            index: target.index,
            id: target.id,
            name: target.name,
            actions: target.actions,
            pathX0: target.pathX0,
            pathY0: target.pathY0,
          },
          rows,
        };
      }
      try {
        g.processMenuActions(chosen.index);
        g.flushOutgoingPackets?.();
      } finally {
        g.menuActionRow = previousRows;
      }
      return {
        ok: true,
        target: {
          index: target.index,
          id: target.id,
          name: target.name,
          actions: target.actions,
          pathX0: target.pathX0,
          pathY0: target.pathY0,
        },
        chosen,
        selectionSource: 'method82-direct',
        rows,
      };
    }, { targetId: npcDialogueTargetId });
    if (!talkResult.ok) {
      throw new Error('NPC dialogue talk action failed: ' + JSON.stringify(talkResult)
        + '; targets=' + JSON.stringify(targetSnapshot) + (fixture ? '; fixture=' + JSON.stringify(fixture) : ''));
    }
    const expectedTalkOpcode = npcOpcodeByAction.get(talkResult.chosen?.action);
    if (!expectedTalkOpcode) throw new Error('NPC dialogue talk action has no expected native opcode: ' + JSON.stringify(talkResult));
    await assertOpcodeSince('NPC dialogue talk-to', beforeTalk, [expectedTalkOpcode]);
    let openedDialogue = null;
    try {
      await page.waitForFunction(() => {
        const g = window.__webscapeGame;
        return !!g?.loggedIn && g.loadingStage === 2 && (g.backDialogueId >= 0 || g.dialogueId >= 0);
      }, null, { timeout: Number.isFinite(npcDialogueWaitMs) ? npcDialogueWaitMs : 8000 });
      openedDialogue = await readRuntimeDiagnostics();
    } catch (err) {
      const runtime = await readRuntimeDiagnostics();
      throw new Error('NPC dialogue did not open after talk-to: talk=' + JSON.stringify(talkResult)
        + '; runtime=' + JSON.stringify(runtime)
        + '; classification=' + classifyNpcDialogueOpenFailure(runtime)
        + (fixture ? '; fixture=' + JSON.stringify(fixture) : '')
        + '; cause=' + String(err?.message || err).split('\n')[0]);
    }
    console.log('>>> NPC dialogue opened: ' + JSON.stringify(openedDialogue));
    const beforeContinue = await semanticSeq();
    const continueResult = await page.evaluate(() => {
      const g = window.__webscapeGame;
      if (!g) return { ok: false, reason: 'missing game' };
      const interfaceId = Number.isFinite(g.backDialogueId) && g.backDialogueId >= 0
        ? g.backDialogueId
        : g.dialogueId;
      if (!Number.isFinite(interfaceId) || interfaceId < 0) {
        return { ok: false, reason: 'no open dialogue interface', backDialogueId: g.backDialogueId, dialogueId: g.dialogueId };
      }
      const component = g.getComponent?.((interfaceId << 16) | 0) || g.getComponent?.(interfaceId) || null;
      const previousBoolean = g.aBoolean1239;
      try {
        g.aBoolean1239 = false;
        g.menuActionTypes[0] = 575;
        g.firstMenuOperand[0] = 0;
        g.secondMenuOperand[0] = (interfaceId << 16) | 0;
        g.selectedMenuActions[0] = 0;
        g.processMenuActions(0);
        g.flushOutgoingPackets?.();
        return {
          ok: true,
          interfaceId,
          componentId: (interfaceId << 16) | 0,
          componentSummary: component ? {
            id: component.id ?? null,
            parentId: component.parentId ?? null,
            type: component.type ?? null,
            width: component.width ?? null,
            height: component.height ?? null,
            children: Array.isArray(component.children) ? component.children.length : null,
          } : null,
        };
      } finally {
        g.aBoolean1239 = previousBoolean;
      }
    });
    if (!continueResult.ok) {
      throw new Error('NPC dialogue continue failed: ' + JSON.stringify(continueResult)
        + '; opened=' + JSON.stringify(openedDialogue));
    }
    try {
      await assertOpcodeSince('NPC dialogue continue', beforeContinue, [132]);
    } catch (err) {
      const runtime = await readRuntimeDiagnostics();
      throw new Error('NPC dialogue continue opcode missing: continue=' + JSON.stringify(continueResult)
        + '; runtime=' + JSON.stringify(runtime)
        + '; cause=' + String(err?.message || err).split('\n')[0]);
    }
    await page.waitForTimeout(750);
    const afterContinue = await readRuntimeDiagnostics();
    console.log('>>> NPC dialogue after continue: ' + JSON.stringify(afterContinue));
  };
  const runCombatTargetProbe = async () => {
    console.log('>>> Run combat target probe');
    const npcOpcodeByAction = new Map([
      [318, 78],
      [921, 3],
      [118, 148],
      [553, 30],
      [432, 218],
    ]);
    const beforeCombat = await semanticSeq();
    const result = await page.evaluate(() => {
      const g = window.__webscapeGame;
      if (!g) return { ok: false, reason: 'missing game' };
      const npcActions = [318, 921, 118, 553, 432, 2318, 2921, 2118, 2553, 2432];
      const expectedOpcodeByBaseAction = {
        318: 78,
        921: 3,
        118: 148,
        553: 30,
        432: 218,
      };
      const candidates = [];
      const previousRows = g.menuActionRow || 0;
      for (let i = 0; i < (g.anInt1133 || 0); i++) {
        const index = g.anIntArray1134?.[i];
        const npc = g.npcs?.[index];
        const def = npc?.npcDefinition;
        const id = def?.id ?? def?.npcId ?? def?.type ?? -1;
        if (!npc || !def || !def.clickable || !Array.isArray(def.actions)) continue;
        g.menuActionRow = 0;
        g.method82(def, npc.pathY?.[0] ?? 0, npc.pathX?.[0] ?? 0, index, -76);
        const rows = [];
        for (let row = 0; row < (g.menuActionRow || 0); row++) {
          const rawAction = g.menuActionTypes?.[row] || 0;
          const baseAction = rawAction >= 2000 ? rawAction - 2000 : rawAction;
          const text = g.menuActionTexts?.[row] || '';
          rows.push({
            index: row,
            text,
            strippedText: String(text).replace(/@[a-z0-9]{3}@/gi, '').trim(),
            action: rawAction,
            baseAction,
            expectedOpcode: expectedOpcodeByBaseAction[baseAction] || null,
            first: g.firstMenuOperand?.[row] || 0,
            second: g.secondMenuOperand?.[row] || 0,
            selected: g.selectedMenuActions?.[row] || 0,
          });
        }
        const attack = rows.find((row) => row.selected === index
          && npcActions.includes(row.action)
          && /^attack\b/i.test(row.strippedText));
        candidates.push({
          index,
          id,
          name: def.name || '',
          combatLevel: def.combatLevel ?? 0,
          actions: def.actions.slice(0, 5),
          pathX0: npc.pathX?.[0] ?? null,
          pathY0: npc.pathY?.[0] ?? null,
          rows,
          attack,
        });
        if (attack) {
          try {
            g.processMenuActions(attack.index);
            g.flushOutgoingPackets?.();
          } finally {
            g.menuActionRow = previousRows;
          }
          return {
            ok: true,
            selectionSource: 'method82-direct',
            target: candidates[candidates.length - 1],
            chosen: attack,
          };
        }
      }
      g.menuActionRow = previousRows;
      return {
        ok: false,
        reason: 'no visible NPC attack row',
        candidates: candidates.slice(0, 12),
      };
    });
    if (!result.ok) throw new Error('combat target probe failed: ' + JSON.stringify(result));
    const expectedOpcode = npcOpcodeByAction.get(result.chosen?.baseAction);
    if (!expectedOpcode) throw new Error('combat target probe has no expected opcode: ' + JSON.stringify(result));
    await assertOpcodeSince('combat target probe', beforeCombat, [expectedOpcode]);
    console.log('>>> Combat target probe selected: ' + JSON.stringify({
      target: result.target,
      chosen: result.chosen,
      expectedOpcode,
    }));
    return { ...result, expectedOpcode };
  };
  const runCombatContactSmoke = async () => {
    console.log('>>> Run combat contact smoke');
    const beforeTraceCount = await page.evaluate(() => (window.__webscapeGame?.combatTrace530 || []).length);
    const targetResult = await runCombatTargetProbe();
    const contact = await page.waitForFunction(({ beforeTraceCount, targetIndex }) => {
      const g = window.__webscapeGame;
      const trace = g?.combatTrace530 || [];
      const after = trace.filter((entry, index) => index >= beforeTraceCount);
      const feedbackKinds = new Set([
        "npcHit",
        "npcSecondaryHit",
        "npcAnimation",
        "npcTarget",
        "npcSpotAnim",
        "playerHit",
        "playerSecondaryHit",
        "playerAnimation",
        "playerTarget",
        "playerSpotAnim",
      ]);
      const relevant = after.filter((entry) => feedbackKinds.has(entry.kind)
        && (!Number.isFinite(targetIndex) || entry.id === targetIndex || String(entry.target) === String(targetIndex)));
      const npc = Number.isFinite(targetIndex) ? g?.npcs?.[targetIndex] : null;
      const liveNpcEvidence = npc ? {
        anInt1609: npc.anInt1609,
        emoteAnimation: npc.emoteAnimation,
        graphic: npc.graphic,
        currentAnimation: npc.currentAnimation,
        hitDamages: Array.isArray(npc.hitDamages) ? npc.hitDamages.slice() : [],
        hitTypes: Array.isArray(npc.hitTypes) ? npc.hitTypes.slice() : [],
        hitCycles: Array.isArray(npc.hitCycles) ? npc.hitCycles.slice() : [],
      } : null;
      const liveHit = liveNpcEvidence?.hitCycles?.some((cycle) => cycle > (g?.constructor?.pulseCycle || 0));
      const liveAnimation = liveNpcEvidence && (liveNpcEvidence.emoteAnimation >= 0 || liveNpcEvidence.graphic >= 0);
      if (relevant.length > 0 || liveHit || liveAnimation) {
        return { ok: true, relevant, recent: after.slice(-20), liveNpcEvidence };
      }
      return false;
    }, {
      beforeTraceCount,
      targetIndex: targetResult.target?.index,
    }, { timeout: combatContactWaitMs })
      .then((handle) => handle.jsonValue())
      .catch(async (err) => {
        const errorMessage = String(err?.message || err).split('\n')[0];
        const diagnostics = await page.evaluate(({ beforeTraceCount, targetIndex, errorMessage }) => {
          const g = window.__webscapeGame;
          const npc = Number.isFinite(targetIndex) ? g?.npcs?.[targetIndex] : null;
          return {
            error: errorMessage,
            combatTrace: (g?.combatTrace530 || []).slice(Math.max(0, beforeTraceCount - 5)),
            targetIndex,
            targetNpc: npc ? {
              anInt1609: npc.anInt1609,
              emoteAnimation: npc.emoteAnimation,
              graphic: npc.graphic,
              currentAnimation: npc.currentAnimation,
              hitDamages: Array.isArray(npc.hitDamages) ? npc.hitDamages.slice() : [],
              hitTypes: Array.isArray(npc.hitTypes) ? npc.hitTypes.slice() : [],
              hitCycles: Array.isArray(npc.hitCycles) ? npc.hitCycles.slice() : [],
            } : null,
            recentPackets: (window.__webscapeSemanticPackets || []).slice(-12),
            runtime: {
              lastIncomingOpcode530: g?.lastIncomingOpcode530 ?? null,
              lastIncomingPacketSize: g?.lastIncomingPacketSize ?? null,
              partialPacketWaitCount: g?.partialPacketWaitCount ?? null,
              lastDropClientReason: g?.lastDropClientReason || '',
            },
          };
        }, { beforeTraceCount, targetIndex: targetResult.target?.index, errorMessage });
        return { ok: false, diagnostics };
      });
    if (!contact.ok) {
      throw new Error('combat contact smoke did not observe server feedback after '
        + combatContactWaitMs + 'ms: ' + JSON.stringify({ targetResult, contact }));
    }
    console.log('>>> Combat contact smoke passed: ' + JSON.stringify({ targetResult, contact }));
  };
  const readDropTakeSnapshot = async ({ containerId, itemId = null } = {}) => page.evaluate(({ containerId, itemId }) => {
    const g = window.__webscapeGame;
    const p = g?.constructor.localPlayer;
    const itemsByContainer = g?.containerItems || {};
    const amountsByContainer = g?.containerAmounts || {};
    const items = Array.isArray(itemsByContainer[containerId]) ? itemsByContainer[containerId] : [];
    const amounts = Array.isArray(amountsByContainer[containerId]) ? amountsByContainer[containerId] : [];
    const inventory = items
      .map((id, slot) => ({ slot, itemId: id, amount: amounts[slot] || 0 }))
      .filter((entry) => Number.isFinite(entry.itemId) && entry.itemId >= 0 && entry.amount > 0);
    const totalFor = (id) => inventory.reduce((total, entry) => total + (entry.itemId === id ? entry.amount : 0), 0);
    const plane = Number.isFinite(g?.plane) ? g.plane : 0;
    const localX = p?.pathX?.[0] ?? null;
    const localY = p?.pathY?.[0] ?? null;
    const ground = [];
    const pushGround = (entry) => {
      if (!entry || !Number.isFinite(entry.itemId) || entry.itemId < 0) return;
      if (itemId !== null && entry.itemId !== itemId) return;
      ground.push(entry);
    };
    if (Number.isFinite(localX) && Number.isFinite(localY)) {
      const nativeStack = g?.groundObjects?.[plane]?.[localX]?.[localY] || [];
      for (const obj of nativeStack) {
        pushGround({
          source: 'groundObjects',
          plane,
          localX,
          localY,
          sceneX: localX + (g.nextTopLeftTileX || 0),
          sceneY: localY + (g.nextTopRightTileY || 0),
          itemId: obj?.type ?? -1,
          amount: obj?.amount ?? 0,
        });
      }
      const legacyList = g?.groundItems?.[plane]?.[localX]?.[localY] || null;
      if (legacyList) {
        for (let item = legacyList.last(); item != null; item = legacyList.previous()) {
          pushGround({
            source: 'groundItems',
            plane,
            localX,
            localY,
            sceneX: localX + (g.nextTopLeftTileX || 0),
            sceneY: localY + (g.nextTopRightTileY || 0),
            itemId: item.itemId ?? -1,
            amount: item.itemCount ?? 0,
          });
        }
      }
    }
    return {
      loggedIn: !!g?.loggedIn,
      loadingStage: g?.loadingStage ?? null,
      containerId,
      containerIds: Object.keys(itemsByContainer).map((id) => Number(id)).filter(Number.isFinite).sort((a, b) => a - b),
      inventory,
      inventoryTotalForItem: itemId === null ? null : totalFor(itemId),
      localPlayer: p ? {
        visible: !!p.visible,
        pathX0: localX,
        pathY0: localY,
        worldX: p.worldX ?? null,
        worldY: p.worldY ?? null,
      } : null,
      plane,
      baseX: g?.nextTopLeftTileX ?? null,
      baseY: g?.nextTopRightTileY ?? null,
      ground,
      recentPackets: (window.__webscapeSemanticPackets || []).slice(-12),
      runtime: {
        lastIncomingOpcode530: g?.lastIncomingOpcode530 ?? null,
        partialPacketWaitCount: g?.partialPacketWaitCount ?? null,
        lastDropClientReason: g?.lastDropClientReason || '',
      },
    };
  }, { containerId, itemId });
  const runDropTakeSmoke = async () => {
    console.log('>>> Run drop/take smoke');
    if (dropTakeFixtureCommand) {
      console.log('>>> Run drop/take fixture command: ' + dropTakeFixtureCommand);
      const fixture = await sendNativeCommand(dropTakeFixtureCommand);
      console.log('>>> Drop/take fixture command result: ' + JSON.stringify(fixture.submitWsDiagnostics));
      await page.waitForTimeout(1000);
    }
    const beforeDropSeq = await semanticSeq();
    const dropResult = await page.evaluate(async ({ containerId }) => {
      const g = window.__webscapeGame;
      const p = g?.constructor.localPlayer;
      if (!g?.outBuffer || !p) return { ok: false, reason: 'game/outBuffer/local player unavailable' };
      const items = Array.isArray(g.containerItems?.[containerId]) ? g.containerItems[containerId] : [];
      const amounts = Array.isArray(g.containerAmounts?.[containerId]) ? g.containerAmounts[containerId] : [];
      const slot = items.findIndex((id, index) => Number.isFinite(id) && id >= 0 && (amounts[index] || 0) > 0);
      if (slot < 0) {
        return {
          ok: false,
          reason: 'no non-empty inventory slot to drop',
          containerId,
          containerIds: Object.keys(g.containerItems || {}),
        };
      }
      const itemId = items[slot] | 0;
      const amountBefore = amounts[slot] || 0;
      const componentId = (149 << 16) | 0;
      const mp4 = (value) => {
        g.outBuffer.putByte((value >> 8) & 0xff);
        g.outBuffer.putByte(value & 0xff);
        g.outBuffer.putByte((value >> 24) & 0xff);
        g.outBuffer.putByte((value >> 16) & 0xff);
      };
      g.outBuffer.putOpcode530(135);
      g.outBuffer.putShortAdded(itemId);
      g.outBuffer.putShortAdded(slot);
      mp4(componentId);
      if (typeof g.flushOutgoingPackets === 'function') {
        await g.flushOutgoingPackets();
      } else if (g.gameConnection && g.outBuffer.currentPosition > 0) {
        g.gameConnection.write(g.outBuffer.currentPosition, 0, g.outBuffer.buffer);
        g.outBuffer.currentPosition = 0;
      }
      return {
        ok: true,
        containerId,
        slot,
        itemId,
        amountBefore,
        componentId,
        localX: p.pathX?.[0] ?? null,
        localY: p.pathY?.[0] ?? null,
        sceneX: (p.pathX?.[0] ?? 0) + (g.nextTopLeftTileX || 0),
        sceneY: (p.pathY?.[0] ?? 0) + (g.nextTopRightTileY || 0),
      };
    }, { containerId: dropTakeContainerId });
    if (!dropResult.ok) {
      const snapshot = await readDropTakeSnapshot({ containerId: dropTakeContainerId });
      throw new Error('drop/take smoke could not drop an item: ' + JSON.stringify(dropResult)
        + '; snapshot=' + JSON.stringify(snapshot));
    }
    await assertOpcodeSince('drop item smoke', beforeDropSeq, [135]);
    const dropped = await page.waitForFunction(({ dropResult, containerId }) => {
      const g = window.__webscapeGame;
      const items = Array.isArray(g?.containerItems?.[containerId]) ? g.containerItems[containerId] : [];
      const amounts = Array.isArray(g?.containerAmounts?.[containerId]) ? g.containerAmounts[containerId] : [];
      const inventoryTotal = items.reduce((total, id, slot) => total + (id === dropResult.itemId ? (amounts[slot] || 0) : 0), 0);
      const groundObjects = g?.groundObjects?.[g.plane || 0]?.[dropResult.localX]?.[dropResult.localY] || [];
      const nativeGround = groundObjects.some((obj) => obj?.type === dropResult.itemId && (obj.amount || 0) > 0);
      const legacyList = g?.groundItems?.[g.plane || 0]?.[dropResult.localX]?.[dropResult.localY] || null;
      let legacyGround = false;
      if (legacyList) {
        for (let item = legacyList.last(); item != null; item = legacyList.previous()) {
          if (item.itemId === dropResult.itemId && (item.itemCount || 0) > 0) {
            legacyGround = true;
            break;
          }
        }
      }
      if (inventoryTotal < dropResult.amountBefore || nativeGround || legacyGround) {
        return { ok: true, inventoryTotal, nativeGround, legacyGround };
      }
      return false;
    }, { dropResult, containerId: dropTakeContainerId }, { timeout: dropTakeWaitMs })
      .then((handle) => handle.jsonValue())
      .catch(async (err) => ({
        ok: false,
        error: String(err?.message || err).split('\n')[0],
        snapshot: await readDropTakeSnapshot({ containerId: dropTakeContainerId, itemId: dropResult.itemId }),
      }));
    if (!dropped.ok) {
      throw new Error('drop/take smoke did not observe dropped ground item after ' + dropTakeWaitMs + 'ms: '
        + JSON.stringify({ dropResult, dropped }));
    }
    const beforeTakeSeq = await semanticSeq();
    const takeResult = await page.evaluate(async ({ dropResult, takeMode }) => {
      const g = window.__webscapeGame;
      if (!g?.outBuffer) return { ok: false, reason: 'game/outBuffer unavailable' };
      if (takeMode === 'menu') {
        if (typeof g.addSceneGroundItemMenuRows !== 'function') {
          return { ok: false, reason: 'missing addSceneGroundItemMenuRows helper' };
        }
        const previousRows = g.menuActionRow || 0;
        const previousItemSelected = g.itemSelected;
        const previousWidgetSelected = g.widgetSelected;
        try {
          g.menuActionRow = 0;
          g.itemSelected = 0;
          g.widgetSelected = 0;
          g.addSceneGroundItemMenuRows(dropResult.localX, dropResult.localY);
          const rows = [];
          for (let row = 0; row < (g.menuActionRow || 0); row++) {
            rows.push({
              index: row,
              text: g.menuActionTexts?.[row] || '',
              action: g.menuActionTypes?.[row] || 0,
              first: g.firstMenuOperand?.[row] || 0,
              second: g.secondMenuOperand?.[row] || 0,
              selected: g.selectedMenuActions?.[row] || 0,
            });
          }
          const take = rows.find((row) => row.action === 684
            && row.selected === dropResult.itemId
            && row.first === dropResult.localX
            && row.second === dropResult.localY);
          if (!take) {
            return { ok: false, reason: 'missing Take row for dropped item', rows, mode: takeMode };
          }
          g.processMenuActions(take.index);
          if (typeof g.flushOutgoingPackets === 'function') {
            await g.flushOutgoingPackets();
          } else if (g.gameConnection && g.outBuffer.currentPosition > 0) {
            g.gameConnection.write(g.outBuffer.currentPosition, 0, g.outBuffer.buffer);
            g.outBuffer.currentPosition = 0;
          }
          return { ok: true, mode: takeMode, itemId: dropResult.itemId, row: take, rows };
        } finally {
          g.menuActionRow = previousRows;
          g.itemSelected = previousItemSelected;
          g.widgetSelected = previousWidgetSelected;
        }
      }
      if (takeMode !== 'direct') {
        return { ok: false, reason: 'unknown DROP_TAKE_TAKE_MODE', mode: takeMode };
      }
      g.outBuffer.putOpcode530(66);
      g.outBuffer.putLEShort(dropResult.sceneX);
      g.outBuffer.putShort(dropResult.itemId);
      g.outBuffer.putLEShortAdded(dropResult.sceneY);
      if (typeof g.flushOutgoingPackets === 'function') {
        await g.flushOutgoingPackets();
      } else if (g.gameConnection && g.outBuffer.currentPosition > 0) {
        g.gameConnection.write(g.outBuffer.currentPosition, 0, g.outBuffer.buffer);
        g.outBuffer.currentPosition = 0;
      }
      return { ok: true, mode: takeMode, itemId: dropResult.itemId, sceneX: dropResult.sceneX, sceneY: dropResult.sceneY };
    }, { dropResult, takeMode: dropTakeTakeMode });
    if (!takeResult.ok) {
      throw new Error('drop/take smoke could not send take action: ' + JSON.stringify(takeResult));
    }
    await assertOpcodeSince('take ground item smoke', beforeTakeSeq, [66]);
    const taken = await page.waitForFunction(({ dropResult, containerId }) => {
      const g = window.__webscapeGame;
      const items = Array.isArray(g?.containerItems?.[containerId]) ? g.containerItems[containerId] : [];
      const amounts = Array.isArray(g?.containerAmounts?.[containerId]) ? g.containerAmounts[containerId] : [];
      const inventoryTotal = items.reduce((total, id, slot) => total + (id === dropResult.itemId ? (amounts[slot] || 0) : 0), 0);
      const groundObjects = g?.groundObjects?.[g.plane || 0]?.[dropResult.localX]?.[dropResult.localY] || [];
      const nativeGround = groundObjects.some((obj) => obj?.type === dropResult.itemId && (obj.amount || 0) > 0);
      if (inventoryTotal >= dropResult.amountBefore || !nativeGround) {
        return { ok: true, inventoryTotal, nativeGround };
      }
      return false;
    }, { dropResult, containerId: dropTakeContainerId }, { timeout: dropTakeWaitMs })
      .then((handle) => handle.jsonValue())
      .catch(async (err) => ({
        ok: false,
        error: String(err?.message || err).split('\n')[0],
        snapshot: await readDropTakeSnapshot({ containerId: dropTakeContainerId, itemId: dropResult.itemId }),
      }));
    if (!taken.ok) {
      throw new Error('drop/take smoke did not observe take completion after ' + dropTakeWaitMs + 'ms: '
        + JSON.stringify({ dropResult, dropped, taken }));
    }
    console.log('>>> Drop/take smoke passed: ' + JSON.stringify({ dropResult, dropped, takeResult, taken }));
  };
  const readWsDiagnostics = async ({ sinceSeq = 0 } = {}) => page.evaluate(({ sinceSeq }) => {
    const sentPackets = (window.__webscapeSentPackets || [])
      .filter((packet) => (packet.seq || 0) > sinceSeq);
    return {
      wsOpenCount: window.__webscapeWsOpenCount || 0,
      wsCloseCount: window.__webscapeWsCloseCount || 0,
      wsSendCount: window.__webscapeWsSendCount || 0,
      wsSendSeq: window.__webscapeWsSendSeq || 0,
      events: (window.__webscapeWsEvents || []).slice(-20),
      sentPackets: sentPackets.slice(-20),
      commandPackets: sentPackets.filter((packet) => packet.decoded?.opcode === 44).slice(-10),
      loginPackets: sentPackets.filter((packet) => packet.decoded?.opcode === 16 || packet.decoded?.opcode === 18).slice(-10),
    };
  }, { sinceSeq }).catch(() => ({
    wsOpenCount: 0,
    wsCloseCount: 0,
    wsSendCount: 0,
    wsSendSeq: 0,
    events: [],
    sentPackets: [],
    commandPackets: [],
    loginPackets: [],
  }));
  const readRuntimeDiagnostics = async () => page.evaluate((runtimeEvidenceFields) => {
    const g = window.__webscapeGame;
    const p = g?.constructor.localPlayer;
    const summarizeWidget = (name, id) => {
      const normalizedId = Number.isFinite(id) ? id : -1;
      if (normalizedId < 0) return { name, id: -1, open: false };
      let root = null;
      let firstChild = null;
      try {
        root = g?.getComponent?.(normalizedId) || null;
        firstChild = g?.getComponent?.((normalizedId << 16) | 0) || null;
      } catch (_) {
        root = null;
        firstChild = null;
      }
      const component = root || firstChild;
      return {
        name,
        id: normalizedId,
        open: true,
        hasComponent: !!component,
        rootComponent: root ? {
          id: root.id ?? null,
          parentId: root.parentId ?? null,
          type: root.type ?? null,
          children: Array.isArray(root.children) ? root.children.length : null,
          width: root.width ?? null,
          height: root.height ?? null,
        } : null,
        firstChild: firstChild ? {
          id: firstChild.id ?? null,
          parentId: firstChild.parentId ?? null,
          type: firstChild.type ?? null,
          children: Array.isArray(firstChild.children) ? firstChild.children.length : null,
          width: firstChild.width ?? null,
          height: firstChild.height ?? null,
        } : null,
      };
    };
    const runtimeEvidence = {};
    if (g) {
      for (const field of runtimeEvidenceFields) {
        if (field in g) runtimeEvidence[field] = g[field] ?? null;
      }
    }
    const containerIds = Array.from(new Set([
      ...Object.keys(g?.containerItems || {}),
      ...Object.keys(g?.containerAmounts || {}),
      ...Object.keys(g?.containerComponents || {}),
    ])).map((id) => Number(id)).filter((id) => Number.isFinite(id)).sort((a, b) => a - b);
    const openInterfaceIds = [
      g?.openInterfaceId,
      g?.anInt1089,
      g?.backDialogueId,
      g?.dialogueId,
    ].filter((id) => Number.isFinite(id) && id >= 0);
    return {
      loggedIn: !!g?.loggedIn,
      loadingStage: g?.loadingStage ?? null,
      loginScreenState: g?.loginScreenState ?? null,
      statusLineOne: g?.statusLineOne || '',
      statusLineTwo: g?.statusLineTwo || '',
      opcode: g?.opcode ?? null,
      packetSize: g?.packetSize ?? null,
      topInterface: g?.topInterface || null,
      chatboxInterfaceOpen: g?.chatboxInterfaceOpen || null,
      interfaceUpdates: (g?.interfaceUpdates || []).slice(-20),
      rt4InterfaceDiagnostics: g?.rt4InterfaceDiagnostics ? g.rt4InterfaceDiagnostics() : null,
      packetTrace530Interesting: (g?.packetTrace530 || [])
        .filter((packet) => [145, 155, 225].includes(packet.opcode) || packet.kind === 'IF_OPENTOP')
        .slice(-20),
      backDialogueId: g?.backDialogueId ?? null,
      dialogueId: g?.dialogueId ?? null,
      backDialogueWidget: summarizeWidget('backDialogue', g?.backDialogueId),
      dialogueWidget: summarizeWidget('dialogue', g?.dialogueId),
      timeoutCounter: g?.timeoutCounter ?? null,
      lastDropClientReason: g?.lastDropClientReason || '',
      ...runtimeEvidence,
      runtimeEvidence,
      lastDropClientTimeoutCounter: g?.lastDropClientTimeoutCounter ?? null,
      localPlayer: p ? {
        visible: !!p.visible,
        worldX: p.worldX,
        worldY: p.worldY,
        pathX0: p.pathX?.[0],
        pathY0: p.pathY?.[0],
      } : null,
      containerIds,
      openInterfaceIds,
      wsOpenCount: window.__webscapeWsOpenCount || 0,
      wsCloseCount: window.__webscapeWsCloseCount || 0,
      wsSendSeq: window.__webscapeWsSendSeq || 0,
      wsEvents: (window.__webscapeWsEvents || []).slice(-8),
      semanticPackets: (window.__webscapeSemanticPackets || []).slice(-8),
      sentPackets: (window.__webscapeSentPackets || []).slice(-8),
    };
  }, runtimeEvidenceFields).catch((err) => ({ error: String(err?.message || err) }));
  const assertSessionKeepaliveAdvanced = async (before, after, observedMs) => {
    if (!after.loggedIn || after.loadingStage !== 2) {
      throw new Error('keepalive stability probe lost playable state after ' + observedMs + 'ms: before='
        + JSON.stringify(before) + ' after=' + JSON.stringify(after));
    }
    const beforeCount = before.rt4KeepaliveSendCount;
    const afterCount = after.rt4KeepaliveSendCount;
    if (!Number.isFinite(beforeCount) || !Number.isFinite(afterCount)) {
      throw new Error('keepalive stability probe missing counters: before='
        + JSON.stringify(before) + ' after=' + JSON.stringify(after));
    }
    if (afterCount <= beforeCount) {
      throw new Error('keepalive stability probe did not advance after ' + observedMs + 'ms: before='
        + JSON.stringify(before) + ' after=' + JSON.stringify(after));
    }
    if (after.lastRt4KeepaliveError || after.lastFlushOutgoingError || after.lastDropClientReason) {
      throw new Error('keepalive stability probe saw transport/drop evidence after ' + observedMs + 'ms: before='
        + JSON.stringify(before) + ' after=' + JSON.stringify(after));
    }
    console.log('>>> Keepalive stability advanced: ' + beforeCount + ' -> ' + afterCount
      + ' in ' + observedMs + 'ms');
  };
  const enterWorldFromLobby = async () => {
    const before = await semanticSeq();
    const result = await page.evaluate(async () => {
      const g = window.__webscapeGame;
      if (!g?.outBuffer) return { sent: false, reason: 'game/outBuffer unavailable' };
      const openInterfaceIds = [
        g.openInterfaceId,
        g.anInt1089,
        g.backDialogueId,
        g.dialogueId,
      ].filter((id) => Number.isFinite(id) && id >= 0);
      const componentId = (378 << 16) | 140;
      g.outBuffer.putOpcode530(155);
      g.outBuffer.putInt(componentId);
      g.outBuffer.putShort(0);
      if (typeof g.flushOutgoingPackets === 'function') {
        await g.flushOutgoingPackets();
      } else if (g.gameConnection && g.outBuffer.currentPosition > 0) {
        g.gameConnection.write(g.outBuffer.currentPosition, 0, g.outBuffer.buffer);
        g.outBuffer.currentPosition = 0;
      }
      return {
        sent: true,
        componentId,
        openInterfaceIds,
        loadedInterface378: !!g.getComponent?.(378),
        recentPackets530: (g.packetTrace530 || []).slice(-12),
      };
    });
    console.log('>>> Enter-world button probe: ' + JSON.stringify(result));
    if (result.sent) {
      await assertOpcodeSince('welcome play button', before, [155]);
    }
    return result;
  };
  const waitForPlayerInfo = async (timeoutMs = 15000) => {
    try {
      await page.waitForFunction(() => {
        const g = window.__webscapeGame;
        const p = g?.constructor.localPlayer;
        const sawPlayerInfo = (g?.packetTrace530 || []).some((packet) => packet?.opcode === 225);
        return !!p?.visible || sawPlayerInfo;
      }, null, { timeout: timeoutMs });
    } catch (err) {
      const runtime = await readRuntimeDiagnostics();
      if (runtime.localPlayer?.visible || runtime.lastIncomingOpcode530 === 225) {
        return runtime;
      }
      throw err;
    }
    return readRuntimeDiagnostics();
  };
  const waitForBankFixtureContainers = async (timeoutMs) => {
    if (bankInventoryContainerIds.length === 0) {
      await page.waitForTimeout(Number.isFinite(timeoutMs) ? timeoutMs : 3000);
      return { matched: false, reason: 'no expected bank container ids configured' };
    }
    try {
      await page.waitForFunction((expectedIds) => {
        const g = window.__webscapeGame;
        if (!g?.loggedIn || g.loadingStage !== 2) return false;
        const ids = new Set([
          ...Object.keys(g.containerItems || {}),
          ...Object.keys(g.containerAmounts || {}),
          ...Object.keys(g.containerComponents || {}),
        ].map((id) => Number(id)).filter((id) => Number.isFinite(id)));
        return expectedIds.every((id) => ids.has(id));
      }, bankInventoryContainerIds, { timeout: Number.isFinite(timeoutMs) ? timeoutMs : 3000 });
      return { matched: true, expectedIds: bankInventoryContainerIds };
    } catch (err) {
      return {
        matched: false,
        expectedIds: bankInventoryContainerIds,
        reason: String(err?.message || err).split('\n')[0],
      };
    }
  };
  const readChatState = async () => page.evaluate(() => {
    const g = window.__webscapeGame;
    if (!g) return { count: 0, input: '', wsSendCount: window.__webscapeWsSendCount || 0, recent: [] };
    const recent = [];
    for (let i = 0; i < Math.min(10, g.chatMessages.length); i++) {
      if (g.chatMessages[i]) recent.push({
        type: g.chatTypes[i],
        name: g.chatPlayerNames[i] || '',
        message: g.chatMessages[i] || '',
      });
    }
    return {
      count: g.chatMessages.filter(Boolean).length,
      input: g.chatboxInput,
      wsSendCount: window.__webscapeWsSendCount || 0,
      wsSendSeq: window.__webscapeWsSendSeq || 0,
      semanticPackets: (window.__webscapeSemanticPackets || []).slice(-12),
      sentPackets: (window.__webscapeSentPackets || []).slice(-12),
      wsEvents: (window.__webscapeWsEvents || []).slice(-12),
      recent,
    };
  }).catch(() => ({ count: 0, input: '', wsSendCount: 0, wsSendSeq: 0, semanticPackets: [], sentPackets: [], wsEvents: [], recent: [] }));
  const sendChatLine = async (line) => {
    const before = await readChatState();
    await canvas.focus();
    await page.keyboard.type(line, { delay: 40 });
    await page.waitForFunction((expected) => window.__webscapeGame?.chatboxInput === expected, line, { timeout: 5000 }).catch(async () => {
      const inputState = await page.evaluate(() => {
        const g = window.__webscapeGame;
        return {
          activeElement: document.activeElement?.tagName,
          activeClass: document.activeElement?.className,
          loggedIn: !!g?.loggedIn,
          loadingStage: g?.loadingStage,
          loginScreenState: g?.loginScreenState,
          chatboxInput: g?.chatboxInput,
          readIndex: g?.readIndex,
          writeIndex: g?.writeIndex,
          wsSendCount: window.__webscapeWsSendCount || 0,
        };
      });
      if (inputState.chatboxInput === line) return;
      if (inputState.loggedIn && inputState.loadingStage === 2) {
        await page.evaluate((expected) => {
          const g = window.__webscapeGame;
          if (g) g.chatboxInput = expected;
        }, line);
        return;
      }
      throw new Error(line + ' was not captured in chatboxInput: ' + JSON.stringify(inputState));
    });
    await page.waitForTimeout(300);
    await page.keyboard.press('Enter');
    await page.waitForTimeout(300);
    if (await page.evaluate((expected) => window.__webscapeGame?.chatboxInput === expected, line)) {
      await page.evaluate(() => {
        const canvas = document.querySelector('canvas');
        canvas?.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
        canvas?.dispatchEvent(new KeyboardEvent('keyup', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
      });
      await page.waitForTimeout(300);
    }
    const after = await readChatState();
    const wsDiagnostics = await readWsDiagnostics({ sinceSeq: before.wsSendSeq || 0 });
    return { ...before, afterSubmit: after, submitWsDiagnostics: wsDiagnostics };
  };
  const sendNativeCommand = async (line) => {
    const before = await readChatState();
    const result = await page.evaluate(async (line) => {
      const g = window.__webscapeGame;
      if (!g?.outBuffer) return { ok: false, reason: 'game/outBuffer unavailable' };
      const command = line.startsWith('::') ? line.slice(2) : line;
      g.outBuffer.putOpcode530(44);
      g.outBuffer.putByte(command.length + 1);
      g.outBuffer.putString(command);
      if (typeof g.flushOutgoingPackets === 'function') {
        await g.flushOutgoingPackets();
      } else if (g.gameConnection && g.outBuffer.currentPosition > 0) {
        g.gameConnection.write(g.outBuffer.currentPosition, 0, g.outBuffer.buffer);
        g.outBuffer.currentPosition = 0;
      }
      return { ok: true, command };
    }, line);
    if (!result.ok) throw new Error('native command failed: ' + JSON.stringify(result));
    const after = await readChatState();
    const wsDiagnostics = await readWsDiagnostics({ sinceSeq: before.wsSendSeq || 0 });
    return { ...before, nativeCommand: result, afterSubmit: after, submitWsDiagnostics: wsDiagnostics };
  };
  const runGroundItemMenuProbe = async () => {
    console.log('>>> Run ground-item menu generation probe');
    const beforeGroundMenu = await semanticSeq();
    const result = await page.evaluate(() => {
      const g = window.__webscapeGame;
      const p = g?.constructor.localPlayer;
      if (!g || !p) return { ok: false, reason: 'missing game/local player' };
      if (typeof g.addSceneGroundItemMenuRows !== 'function') {
        return { ok: false, reason: 'missing addSceneGroundItemMenuRows helper' };
      }
      const plane = Number.isFinite(g.plane) ? g.plane : 0;
      const x = p.pathX?.[0] ?? (p.worldX >> 7);
      const y = p.pathY?.[0] ?? (p.worldY >> 7);
      if (!g.groundItems?.[plane]?.[x]) return { ok: false, reason: 'groundItems tile array unavailable', plane, x, y };
      const original = g.groundItems[plane][x][y];
      const item = { itemId: 995, itemCount: 1 };
      const list = {
        used: false,
        last() {
          this.used = true;
          return item;
        },
        previous() {
          return null;
        },
      };
      const previousRows = g.menuActionRow || 0;
      const previousItemSelected = g.itemSelected;
      const previousWidgetSelected = g.widgetSelected;
      try {
        g.groundItems[plane][x][y] = list;
        g.menuActionRow = 0;
        g.itemSelected = 0;
        g.widgetSelected = 0;
        g.addSceneGroundItemMenuRows(x, y);
        const rows = [];
        for (let row = 0; row < (g.menuActionRow || 0); row++) {
          rows.push({
            index: row,
            text: g.menuActionTexts?.[row] || '',
            action: g.menuActionTypes?.[row] || 0,
            first: g.firstMenuOperand?.[row] || 0,
            second: g.secondMenuOperand?.[row] || 0,
            selected: g.selectedMenuActions?.[row] || 0,
          });
        }
        const take = rows.find((row) => row.action === 684 && row.selected === item.itemId && row.first === x && row.second === y);
        if (!take) return { ok: false, reason: 'missing Take row', rows, plane, x, y };
        g.processMenuActions(take.index);
        g.flushOutgoingPackets?.();
        return { ok: true, rows, chosen: take, plane, x, y, itemId: item.itemId };
      } finally {
        g.groundItems[plane][x][y] = original;
        g.menuActionRow = previousRows;
        g.itemSelected = previousItemSelected;
        g.widgetSelected = previousWidgetSelected;
      }
    });
    if (!result.ok) throw new Error('ground-item menu probe failed: ' + JSON.stringify(result));
    await assertOpcodeSince('ground-item menu take probe', beforeGroundMenu, [66]);
    console.log('>>> Ground-item menu probe selected: ' + JSON.stringify(result));
  };
  const assertRenderedSceneMenu = async ({ kind = 'any' } = {}) => {
    console.log('>>> Search rendered scene menu rows' + (kind === 'any' ? '' : ' (' + kind + ' only)'));
    const locActions = [35, 389, 888, 892, 1280];
    const npcActions = [318, 921, 118, 553, 432];
    const allowedActions = kind === 'loc'
      ? locActions
      : kind === 'npc'
        ? npcActions
        : locActions.concat(npcActions);
    const samples = [
      [256, 168], [330, 168], [410, 168],
      [220, 220], [300, 220], [380, 220], [460, 220],
      [220, 275], [300, 275], [380, 275], [460, 275],
      [256, 315], [360, 315], [470, 315],
    ];
    let match = null;
    for (const [x, y] of samples) {
      await canvasRightClick(x, y);
      await page.waitForTimeout(250);
      const rows = await readMenuRows();
      const row = rows.find((r) => allowedActions.includes(r.action));
      if (row) {
        const menu = await page.evaluate(() => {
          const g = window.__webscapeGame;
          return {
            open: !!g?.menuOpen,
            x: g?.menuClickX || 0,
            y: g?.menuClickY || 0,
            width: g?.anInt1307 || 0,
            height: g?.anInt1308 || 0,
            rows: g?.menuActionRow || 0,
            area: g?.anInt1304 || 0,
          };
        });
        match = { x, y, row, rows, menu };
        break;
      }
    }
    if (!match) {
      throw new Error('no rendered ' + (kind === 'any' ? 'loc/NPC' : kind) + ' menu rows found; sampled=' + JSON.stringify(samples)
        + ' recentOpcodes=' + (await packetOpcodes()).join(','));
    }
    console.log('>>> Rendered menu match: ' + JSON.stringify(match));
    const beforeRenderedDispatch = await semanticSeq();
    const menuOffset = match.menu.area === 1
      ? { x: 553, y: 205 }
      : match.menu.area === 2
        ? { x: 17, y: 357 }
        : { x: 4, y: 4 };
    const rowNativeX = menuOffset.x + match.menu.x + Math.min(Math.max(8, match.menu.width / 2), Math.max(8, match.menu.width - 8));
    const rowNativeY = menuOffset.y + match.menu.y + 31 + (match.menu.rows - 1 - match.row.index) * 15 - 5;
    console.log('>>> Click rendered menu row at native canvas: ' + JSON.stringify({ x: rowNativeX, y: rowNativeY }));
    await canvasClick(rowNativeX, rowNativeY);
    await page.waitForTimeout(1000);
    const locOpcodeByAction = new Map([
      [35, 254],
      [389, 194],
      [888, 84],
      [892, 247],
      [1280, 170],
    ]);
    const npcOpcodeByAction = new Map([
      [318, 78],
      [921, 3],
      [118, 148],
      [553, 30],
      [432, 218],
    ]);
    const expectedOpcode = locOpcodeByAction.get(match.row.action) || npcOpcodeByAction.get(match.row.action);
    await assertOpcodeSince('rendered scene menu action', beforeRenderedDispatch, [expectedOpcode]);
    return match;
  };
  let renderedActionMenuAsserted = false;

  if (!autoLogin) {
    // State 0: click "Existing User" at canvas (462, 291) — bounds 387-537 x 271-311
    console.log('>>> Click Existing User');
    await canvasClick(462, 291);
    await page.waitForTimeout(1000);
    await shot('/tmp/playwright-2009scape/01-login-form.png');

    await page.waitForTimeout(300);
    await shot('/tmp/playwright-2009scape/02-creds-entered.png');

    // Click Login button — center (302, 321), bounds 227-377 x 301-341
    console.log('>>> Click Login button');
    await canvasClick(302, 321);
  } else {
    console.log('>>> Auto-login enabled');
  }
  console.log('>>> Waiting for in-game state...');
  await waitForInGame();
  await page.evaluate(() => {
    const g = window.__webscapeGame;
    const bufferProto = g?.outBuffer?.constructor?.prototype;
    const connProto = g?.gameConnection?.constructor?.prototype;
    if (!g || !bufferProto || !connProto || window.__webscapePacketTraceInstalled) return;
    window.__webscapePacketTraceInstalled = true;
    window.__webscapeSemanticPackets = [];
    window.__webscapeSemanticPacketSeq = 0;
    const originalPutOpcode = bufferProto.putOpcode;
    const originalPutOpcode530 = bufferProto.putOpcode530;
    const originalWrite = connProto.write;
    window.__webscapePendingSemanticOpcodes = [];
    bufferProto.putOpcode = function(opcode) {
      window.__webscapeLastSemanticOpcode = { kind: 'legacy', opcode };
      window.__webscapePendingSemanticOpcodes.push(window.__webscapeLastSemanticOpcode);
      return originalPutOpcode.call(this, opcode);
    };
    bufferProto.putOpcode530 = function(opcode) {
      window.__webscapeLastSemanticOpcode = { kind: 'native', opcode };
      window.__webscapePendingSemanticOpcodes.push(window.__webscapeLastSemanticOpcode);
      return originalPutOpcode530.call(this, opcode);
    };
    connProto.write = function(length, offset, src) {
      const bytes = Array.from(src.slice(offset, offset + length));
      const semantics = (window.__webscapePendingSemanticOpcodes || []).slice();
      window.__webscapeSemanticPackets.push({
        seq: ++window.__webscapeSemanticPacketSeq,
        semantic: window.__webscapeLastSemanticOpcode || null,
        semantics,
        len: length,
        bytes: bytes.slice(0, 24),
      });
      if (window.__webscapeSemanticPackets.length > 100) window.__webscapeSemanticPackets.shift();
      window.__webscapeLastSemanticOpcode = null;
      window.__webscapePendingSemanticOpcodes = [];
      return originalWrite.call(this, length, offset, src);
    };
  });
  if (autoEnterWorld) {
    await enterWorldFromLobby();
    try {
      const playerInfoRuntime = await waitForPlayerInfo();
      console.log('>>> Player-info/world-entry runtime: ' + JSON.stringify(playerInfoRuntime));
    } catch (err) {
      const runtime = await readRuntimeDiagnostics();
      const message = 'player-info/world-entry probe failed: ' + String(err?.message || err)
        + '; runtime=' + JSON.stringify(runtime);
      if (requirePlayerInfoProbe) throw new Error(message);
      console.log('>>> ' + message);
    }
    if (postEnterWorldWaitMs > 0) {
      console.log('>>> Wait after world entry: ' + postEnterWorldWaitMs + 'ms');
      await page.waitForTimeout(postEnterWorldWaitMs);
    }
  }
  await page.waitForTimeout(1000);
  await shot('/tmp/playwright-2009scape/03-in-game.png');

  if (sendCommand) {
    // Try a cheat command
    console.log('>>> Type ::players');
    const beforeChat = await sendChatLine('::players');
    await page.waitForTimeout(3000);
    const afterCommand = await readChatState();
    console.log('>>> Chat count before/after command: ' + beforeChat.count + '/' + afterCommand.count);
    console.log('>>> WS sends before/after command: ' + beforeChat.wsSendCount + '/' + afterCommand.wsSendCount);
    console.log('>>> Command submit WS diagnostics: ' + JSON.stringify(beforeChat.submitWsDiagnostics));
    const commandPacket = afterCommand.semanticPackets.some((packet) => {
      const opcodes = [packet.semantic, ...(packet.semantics || [])].map((semantic) => semantic?.opcode);
      const bytes = packet.bytes || [];
      return opcodes.some((opcode) => opcode === 56 || opcode === 38 || opcode === 44)
        || bytes.some((byte) => [56, 38, 44].includes(byte & 0xff));
    }) || (beforeChat.submitWsDiagnostics?.commandPackets || []).some((packet) => packet.decoded?.opcode === 44);
    if (assertCommand && afterCommand.input === '::players' && afterCommand.count <= beforeChat.count && afterCommand.wsSendCount <= beforeChat.wsSendCount && !commandPacket) {
      throw new Error('::players was not consumed by chat input or sent; submit=' + JSON.stringify(beforeChat.submitWsDiagnostics));
    }
    await shot('/tmp/playwright-2009scape/04-after-cmd.png');
  }

  if (assertRenderedNpcMenu) {
    await assertRenderedSceneMenu({ kind: 'npc' });
  }
  if (assertRenderedLocMenu) {
    await assertRenderedSceneMenu({ kind: 'loc' });
  }
  if (assertRenderedNpcMenu || assertRenderedLocMenu) {
    renderedActionMenuAsserted = true;
  }
  if (assertRenderedActionMenu && !assertRenderedNpcMenu && !assertRenderedLocMenu) {
    await assertRenderedSceneMenu();
    renderedActionMenuAsserted = true;
  }

  if (assertWalk) {
    const beforeWalk = await page.evaluate(() => {
      const g = window.__webscapeGame;
      const p = g?.constructor.localPlayer;
      return {
        wsSendCount: window.__webscapeWsSendCount || 0,
        destinationX: g?.destinationX,
        destinationY: g?.destinationY,
        worldX: p?.worldX,
        worldY: p?.worldY,
        pathX0: p?.pathX?.[0],
        pathY0: p?.pathY?.[0],
        semanticCount: window.__webscapeSemanticPackets?.length || 0,
      };
    });
    console.log('>>> Click scene for walk');
    await canvasClick(410, 220);
    await page.waitForTimeout(8000);
    const afterWalk = await page.evaluate(() => {
      const g = window.__webscapeGame;
      const p = g?.constructor.localPlayer;
      return {
        wsSendCount: window.__webscapeWsSendCount || 0,
        destinationX: g?.destinationX,
        destinationY: g?.destinationY,
        worldX: p?.worldX,
        worldY: p?.worldY,
        pathX0: p?.pathX?.[0],
        pathY0: p?.pathY?.[0],
        semanticPackets: (window.__webscapeSemanticPackets || []).slice(-12),
      };
    });
    console.log('>>> Walk before: ' + JSON.stringify(beforeWalk));
    console.log('>>> Walk after: ' + JSON.stringify(afterWalk));
    const moved = afterWalk.worldX !== beforeWalk.worldX
      || afterWalk.worldY !== beforeWalk.worldY
      || afterWalk.pathX0 !== beforeWalk.pathX0
      || afterWalk.pathY0 !== beforeWalk.pathY0;
    const walkPacket = afterWalk.semanticPackets.some((packet) => {
      const opcodes = [packet.semantic, ...(packet.semantics || [])].map((semantic) => semantic?.opcode);
      const bytes = packet.bytes || [];
      return opcodes.some((opcode) => opcode === 187 || opcode === 215 || opcode === 39 || opcode === 77)
        || bytes.some((byte) => [187, 215, 39, 77].includes(byte & 0xff));
    });
    if (!moved) throw new Error('scene click did not move the local player; walkPacket=' + walkPacket);
  }

  if (assertMinimapWalk) {
    const beforeMinimap = await page.evaluate(() => {
      const g = window.__webscapeGame;
      const p = g?.constructor.localPlayer;
      return {
        destinationX: g?.destinationX,
        destinationY: g?.destinationY,
        worldX: p?.worldX,
        worldY: p?.worldY,
        pathX0: p?.pathX?.[0],
        pathY0: p?.pathY?.[0],
        semanticCount: window.__webscapeSemanticPackets?.length || 0,
      };
    });
    console.log('>>> Click minimap for walk');
    await canvasClick(630, 84);
    await page.waitForTimeout(8000);
    const afterMinimap = await page.evaluate(() => {
      const g = window.__webscapeGame;
      const p = g?.constructor.localPlayer;
      return {
        destinationX: g?.destinationX,
        destinationY: g?.destinationY,
        worldX: p?.worldX,
        worldY: p?.worldY,
        pathX0: p?.pathX?.[0],
        pathY0: p?.pathY?.[0],
        semanticPackets: (window.__webscapeSemanticPackets || []).slice(-12),
      };
    });
    console.log('>>> Minimap walk before: ' + JSON.stringify(beforeMinimap));
    console.log('>>> Minimap walk after: ' + JSON.stringify(afterMinimap));
    const moved = afterMinimap.worldX !== beforeMinimap.worldX
      || afterMinimap.worldY !== beforeMinimap.worldY
      || afterMinimap.pathX0 !== beforeMinimap.pathX0
      || afterMinimap.pathY0 !== beforeMinimap.pathY0
      || afterMinimap.destinationX !== beforeMinimap.destinationX
      || afterMinimap.destinationY !== beforeMinimap.destinationY;
    const minimapPacket = afterMinimap.semanticPackets.some((packet) => {
      const opcodes = [packet.semantic, ...(packet.semantics || [])].map((semantic) => semantic?.opcode);
      const bytes = packet.bytes || [];
      return opcodes.some((opcode) => opcode === 39 || opcode === 187)
        || bytes.some((byte) => [39, 187].includes(byte & 0xff));
    });
    if (!moved || !minimapPacket) {
      throw new Error('minimap click did not move or emit minimap walk; moved=' + moved
        + ' packets=' + JSON.stringify(afterMinimap.semanticPackets));
    }
  }

  if (assertActionProbes) {
    console.log('>>> Run live action packet probes');
    const beforeProbeCount = await semanticSeq();
    const probeResult = await page.evaluate(() => {
      const g = window.__webscapeGame;
      const p = g?.constructor.localPlayer;
      if (!g || !p) return { ok: false, reason: 'missing game/local player' };
      const result = { ok: true, npcIndex: -1, locProbe: false };
      const oldClickX = g.clickX;
      const oldClickY = g.clickY;
      try {
        g.clickX = 410;
        g.clickY = 220;
        const ids = Array.from(g.anIntArray1134 || []);
        const npcIndex = ids.find((id) => Number.isFinite(id) && g.npcs?.[id]);
        if (Number.isFinite(npcIndex)) {
          result.npcIndex = npcIndex;
          g.menuActionTypes[0] = 318;
          g.firstMenuOperand[0] = 0;
          g.secondMenuOperand[0] = 0;
          g.selectedMenuActions[0] = npcIndex;
          g.processMenuActions(0);
          g.flushOutgoingPackets?.();
        }
        g.menuActionTypes[0] = 35;
        g.firstMenuOperand[0] = p.pathX?.[0] || 0;
        g.secondMenuOperand[0] = p.pathY?.[0] || 0;
        g.selectedMenuActions[0] = 0;
        g.processMenuActions(0);
        result.locProbe = true;
        g.flushOutgoingPackets?.();
      } finally {
        g.clickX = oldClickX;
        g.clickY = oldClickY;
      }
      return result;
    });
    if (!probeResult.ok) throw new Error('action probes failed: ' + JSON.stringify(probeResult));
    const expected = [254];
    if (probeResult.npcIndex >= 0) expected.push(78);
    await assertOpcodeSince('live action probes', beforeProbeCount, expected);
    console.log('>>> Synthetic loc action probe passed; npcIndex=' + probeResult.npcIndex + ' recent opcodes: ' + (await packetOpcodes()).join(','));
  }

  if (assertGroundItemActionProbes) {
    console.log('>>> Run ground-item action packet probes');
    const beforeGroundItemProbe = await semanticSeq();
    const probeResult = await page.evaluate(() => {
      const g = window.__webscapeGame;
      const p = g?.constructor.localPlayer;
      if (!g || !p) return { ok: false, reason: 'missing game/local player' };
      const oldClickX = g.clickX;
      const oldClickY = g.clickY;
      const first = p.pathX?.[0] || 0;
      const second = p.pathY?.[0] || 0;
      try {
        g.clickX = 410;
        g.clickY = 220;
        for (const action of [684, 930, 270]) {
          g.menuActionTypes[0] = action;
          g.firstMenuOperand[0] = first;
          g.secondMenuOperand[0] = second;
          g.selectedMenuActions[0] = 0x0789;
          g.processMenuActions(0);
          g.flushOutgoingPackets?.();
        }
      } finally {
        g.clickX = oldClickX;
        g.clickY = oldClickY;
      }
      return { ok: true };
    });
    if (!probeResult.ok) throw new Error('ground-item action probes failed: ' + JSON.stringify(probeResult));
    await assertOpcodeSince('ground-item action probes', beforeGroundItemProbe, [66, 33, 48]);
  }

  if (assertGroundItemMenuProbe) {
    await runSmokeGate('ground-item menu', () => runGroundItemMenuProbe());
  }

  if (assertDialogueContinueProbe) {
    console.log('>>> Run dialogue continue packet probe');
    const beforeDialogueContinue = await semanticSeq();
    const probeResult = await page.evaluate(() => {
      const g = window.__webscapeGame;
      if (!g) return { ok: false, reason: 'missing game' };
      const previousBoolean = g.aBoolean1239;
      try {
        g.aBoolean1239 = false;
        g.menuActionTypes[0] = 575;
        g.firstMenuOperand[0] = 0x0123;
        g.secondMenuOperand[0] = 0x00040056;
        g.selectedMenuActions[0] = 0;
        g.processMenuActions(0);
        g.flushOutgoingPackets?.();
        return { ok: true };
      } finally {
        g.aBoolean1239 = previousBoolean;
      }
    });
    if (!probeResult.ok) throw new Error('dialogue continue probe failed: ' + JSON.stringify(probeResult));
    await assertOpcodeSince('dialogue continue probe', beforeDialogueContinue, [132]);
  }

  if (assertDialogueActionProbe) {
    console.log('>>> Run CS2 dialogue action packet probe');
    const beforeDialogueAction = await semanticSeq();
    const probeResult = await page.evaluate(() => {
      const g = window.__webscapeGame;
      if (!g) return { ok: false, reason: 'missing game' };
      if (!g.cs2Hooks?.sendDialogAction) return { ok: false, reason: 'missing cs2 sendDialogAction hook' };
      g.cs2Hooks.sendDialogAction(0x1234);
      g.flushOutgoingPackets?.();
      return { ok: g.cs2DialogAction === 0x1234, action: g.cs2DialogAction };
    });
    if (!probeResult.ok) throw new Error('dialogue action probe failed: ' + JSON.stringify(probeResult));
    await assertOpcodeSince('dialogue action probe', beforeDialogueAction, [111]);
  }

  if (assertNpcDialogueSmoke) {
    await runSmokeGate('NPC dialogue', () => runNpcDialogueSmoke());
  }

  if (assertCombatContactSmoke) {
    await runSmokeGate('combat contact', () => runCombatContactSmoke());
  } else if (assertCombatTargetProbe) {
    await runSmokeGate('combat target', () => runCombatTargetProbe());
  }

  if (assertDropTakeSmoke) {
    await runSmokeGate('drop/take', () => runDropTakeSmoke());
  }

  if (assertBankInventoryProbe || assertBankActionProbe) {
    await runSmokeGate('bank inventory/action', async () => {
      let bankFixtureResult = null;
      if (bankFixtureCommands.length > 0) {
        console.log('>>> Run bank fixture command(s): ' + bankFixtureCommands.join('; '));
        const steps = [];
        for (const command of bankFixtureCommands) {
          const beforeRuntime = await readRuntimeDiagnostics();
          const beforeFixture = bankFixtureNativeCommand
            ? await sendNativeCommand(command)
            : await sendChatLine(command);
          const waitResult = await waitForBankFixtureContainers(bankFixtureWaitMs);
          const afterFixture = await readChatState();
          const afterRuntime = await readRuntimeDiagnostics();
          steps.push({
            command,
            beforeRuntime,
            submit: beforeFixture,
            waitResult,
            after: afterFixture,
            afterRuntime,
          });
          console.log('>>> Bank fixture command "' + command + '" WS diagnostics: ' + JSON.stringify(beforeFixture.submitWsDiagnostics));
          console.log('>>> Bank fixture command "' + command + '" runtime before/after: '
            + JSON.stringify({ beforeRuntime, waitResult, afterRuntime }));
        }
        bankFixtureResult = { commands: bankFixtureCommands, waitMs: bankFixtureWaitMs, steps };
        console.log('>>> Bank fixture command result: ' + JSON.stringify(bankFixtureResult));
      }
      console.log('>>> Inspect bank/inventory container state');
      const snapshot = await readBankInventorySnapshot({
        expectedIds: bankInventoryContainerIds,
        requireOpen: bankInventoryRequireOpen,
        requireItem: bankInventoryRequireItem,
      });
      console.log('>>> Bank/inventory snapshot: ' + JSON.stringify(snapshot));
      if (assertBankInventoryProbe && snapshot.problems.length > 0) {
        const classification = classifyBankSmokeFailure(snapshot);
        throw new Error('bank/inventory probe failed: ' + snapshot.problems.join('; ')
          + '; ' + formatBankInventoryDiagnostics(snapshot)
          + (bankFixtureResult ? '; fixture=' + JSON.stringify(bankFixtureResult) : '')
          + (classification ? ';' + classification : '')
          + ';' + formatBankInventoryAdvice(snapshot));
      }
      if (assertBankActionProbe) {
        if (snapshot.problems.length > 0) {
          const classification = classifyBankSmokeFailure(snapshot);
          throw new Error('bank action probe preflight failed: ' + snapshot.problems.join('; ')
            + '; ' + formatBankInventoryDiagnostics(snapshot)
            + (bankFixtureResult ? '; fixture=' + JSON.stringify(bankFixtureResult) : '')
            + (classification ? ';' + classification : '')
            + ';' + formatBankInventoryAdvice(snapshot));
        }
        await runBankActionProbe({
          expectedIds: bankInventoryContainerIds,
          preferredContainerId: bankActionContainerId,
          option: bankActionOption,
          mode: bankActionMode,
          mutationWaitMs: bankActionMutationWaitMs,
        });
      }
    });
  }

  if (assertRenderedActionMenu && !renderedActionMenuAsserted) {
    await assertRenderedSceneMenu();
  }

  if (assertLogoutRelog) {
    console.log('>>> Logout and relog as ' + relogUsername);
    const beforeLogoutRelog = await page.evaluate(() => {
      const g = window.__webscapeGame;
      return {
        loggedIn: !!g?.loggedIn,
        wsSendCount: window.__webscapeWsSendCount || 0,
        semanticCount: window.__webscapeSemanticPackets?.length || 0,
      };
    });
    if (!beforeLogoutRelog.loggedIn) throw new Error('cannot logout/relog: client is not logged in');
    await page.evaluate(async ({ username, password }) => {
      const g = window.__webscapeGame;
      if (!g) throw new Error('missing game');
      g.logout();
      if (g.loggedIn) throw new Error('logout did not clear loggedIn');
      await g.login(username, password, false);
    }, { username: relogUsername, password: relogPassword });
    try {
      await waitForInGame();
    } catch (err) {
      const relogFailure = await page.evaluate(() => {
        const g = window.__webscapeGame;
        const p = g?.constructor.localPlayer;
        return {
          hasGame: !!g,
          loggedIn: !!g?.loggedIn,
          loadingStage: g?.loadingStage,
          loginScreenState: g?.loginScreenState,
          statusLineOne: g?.statusLineOne,
          statusLineTwo: g?.statusLineTwo,
          opcode: g?.opcode,
          packetSize: g?.packetSize,
          localPlayer: p ? { visible: !!p.visible, worldX: p.worldX, worldY: p.worldY, pathX0: p.pathX?.[0], pathY0: p.pathY?.[0] } : null,
          wsSendCount: window.__webscapeWsSendCount || 0,
          recentPackets: (window.__webscapeSemanticPackets || []).slice(-12),
        };
      });
      throw new Error('logout/relog did not reach in-game state: ' + JSON.stringify(relogFailure));
    }
    await page.waitForTimeout(1000);
    const afterLogoutRelog = await page.evaluate(() => {
      const g = window.__webscapeGame;
      const p = g?.constructor.localPlayer;
      return {
        loggedIn: !!g?.loggedIn,
        loadingStage: g?.loadingStage,
        wsSendCount: window.__webscapeWsSendCount || 0,
        semanticPackets: (window.__webscapeSemanticPackets || []).slice(-12),
        localPlayer: p ? {
          visible: !!p.visible,
          worldX: p.worldX,
          worldY: p.worldY,
          pathX0: p.pathX?.[0],
          pathY0: p.pathY?.[0],
        } : null,
      };
    });
    console.log('>>> Logout/relog before: ' + JSON.stringify(beforeLogoutRelog));
    console.log('>>> Logout/relog after: ' + JSON.stringify(afterLogoutRelog));
    if (!afterLogoutRelog.loggedIn || afterLogoutRelog.loadingStage !== 2 || !afterLogoutRelog.localPlayer?.visible) {
      throw new Error('logout/relog did not return to playable state: ' + JSON.stringify(afterLogoutRelog));
    }
  }

  if (assertServerRestartReconnect) {
    console.log('>>> Simulate server restart websocket close and require reconnect');
    const beforeReconnect = await page.evaluate(() => {
      const g = window.__webscapeGame;
      const p = g?.constructor.localPlayer;
      return {
        loggedIn: !!g?.loggedIn,
        loadingStage: g?.loadingStage,
        localPlayer: p ? { visible: !!p.visible, worldX: p.worldX, worldY: p.worldY } : null,
        wsOpenCount: window.__webscapeWsOpenCount || 0,
        wsCloseCount: window.__webscapeWsCloseCount || 0,
        wsSendSeq: window.__webscapeWsSendSeq || 0,
      };
    });
    if (!beforeReconnect.loggedIn) throw new Error('cannot reconnect: client is not logged in');
    await page.evaluate(() => {
      const g = window.__webscapeGame;
      const ws = g?.gameConnection?.socket?.client?._socket;
      if (!ws) throw new Error('missing live websocket');
      ws.close(1012, 'smoke server restart reconnect');
    });
    try {
      await page.waitForFunction(({ beforeOpenCount, beforeCloseCount }) => {
        const g = window.__webscapeGame;
        const p = g?.constructor.localPlayer;
        return !!g?.loggedIn
          && g.loadingStage === 2
          && !!p?.visible
          && (window.__webscapeWsOpenCount || 0) > beforeOpenCount
          && (window.__webscapeWsCloseCount || 0) > beforeCloseCount;
      }, {
        beforeOpenCount: beforeReconnect.wsOpenCount,
        beforeCloseCount: beforeReconnect.wsCloseCount,
      }, { timeout: 90000 });
    } catch (err) {
      const reconnectFailure = await page.evaluate(() => {
        const g = window.__webscapeGame;
        const p = g?.constructor.localPlayer;
        return {
          loggedIn: !!g?.loggedIn,
          loadingStage: g?.loadingStage,
          loginScreenState: g?.loginScreenState,
          statusLineOne: g?.statusLineOne,
          statusLineTwo: g?.statusLineTwo,
          opcode: g?.opcode,
          packetSize: g?.packetSize,
          wsOpenCount: window.__webscapeWsOpenCount || 0,
          wsCloseCount: window.__webscapeWsCloseCount || 0,
          sentPackets: (window.__webscapeSentPackets || []).slice(-12),
          localPlayer: p ? { visible: !!p.visible, worldX: p.worldX, worldY: p.worldY } : null,
        };
      });
      throw new Error('server restart reconnect did not reach playable state: ' + JSON.stringify(reconnectFailure));
    }
    await page.waitForTimeout(1000);
    const afterReconnect = await page.evaluate(({ beforeSeq }) => {
      const g = window.__webscapeGame;
      const p = g?.constructor.localPlayer;
      const reconnectLoginPackets = (window.__webscapeSentPackets || [])
        .filter((packet) => packet.seq > beforeSeq && packet.decoded?.opcode === 18);
      const newLoginPackets = (window.__webscapeSentPackets || [])
        .filter((packet) => packet.seq > beforeSeq && packet.decoded?.opcode === 16);
      return {
        loggedIn: !!g?.loggedIn,
        loadingStage: g?.loadingStage,
        wsOpenCount: window.__webscapeWsOpenCount || 0,
        wsCloseCount: window.__webscapeWsCloseCount || 0,
        reconnectLoginPackets,
        newLoginPackets,
        recentWsEvents: (window.__webscapeWsEvents || []).slice(-20),
        sentPackets: (window.__webscapeSentPackets || []).filter((packet) => packet.seq > beforeSeq).slice(-20),
        localPlayer: p ? { visible: !!p.visible, worldX: p.worldX, worldY: p.worldY } : null,
      };
    }, { beforeSeq: beforeReconnect.wsSendSeq });
    console.log('>>> Server restart reconnect before: ' + JSON.stringify(beforeReconnect));
    console.log('>>> Server restart reconnect after: ' + JSON.stringify(afterReconnect));
    if (!afterReconnect.loggedIn || afterReconnect.loadingStage !== 2 || !afterReconnect.localPlayer?.visible) {
      throw new Error('server restart reconnect did not return to playable state: ' + JSON.stringify(afterReconnect));
    }
    if (afterReconnect.wsOpenCount <= beforeReconnect.wsOpenCount || afterReconnect.wsCloseCount <= beforeReconnect.wsCloseCount) {
      throw new Error('server restart reconnect did not cycle websocket: ' + JSON.stringify(afterReconnect));
    }
    if (afterReconnect.reconnectLoginPackets.length === 0) {
      throw new Error('server restart reconnect did not send reconnect login opcode 18: ' + JSON.stringify(afterReconnect));
    }
  }

  // Stability observation
  console.log('>>> Observing ' + stabilityMs + 'ms for stability...');
  const beforeStability = assertKeepalive ? await readRuntimeDiagnostics() : null;
  if (stabilityMs > 0) await page.waitForTimeout(stabilityMs);
  if (assertKeepalive) {
    const afterStability = await readRuntimeDiagnostics();
    await assertSessionKeepaliveAdvanced(beforeStability, afterStability, stabilityMs);
  }
  await shot('/tmp/playwright-2009scape/05-final.png');

  const stateSnapshot = await Promise.race([
    page.evaluate(() => {
      const g = window.__webscapeGame;
      if (!g) return { hasGame: false };
      return {
        hasGame: true,
        loggedIn: !!g.loggedIn,
        loginScreenState: g.loginScreenState,
        statusLineOne: g.statusLineOne,
        statusLineTwo: g.statusLineTwo,
        loadingStage: g.loadingStage,
        localPlayerCount: g.localPlayerCount,
        npcCount: g.anInt1133,
        plane: g.plane,
        topLeftTileX: g.topLeftTileX,
        topLeftTileY: g.topLeftTileY,
        localPlayer: g.constructor.localPlayer ? {
          worldX: g.constructor.localPlayer.worldX,
          worldY: g.constructor.localPlayer.worldY,
          pathX0: g.constructor.localPlayer.pathX?.[0],
          pathY0: g.constructor.localPlayer.pathY?.[0],
          visible: g.constructor.localPlayer.visible,
        } : null,
        recentChat: g.chatMessages.slice(0, 5).map((message, i) => message ? {
          type: g.chatTypes[i],
          name: g.chatPlayerNames[i] || '',
          message,
        } : null).filter(Boolean),
      };
    }),
    new Promise((resolve) => setTimeout(() => resolve({ timedOut: true }), 20000)),
  ]);

  console.log('\n===== CONSOLE (' + logs.length + ') =====');
  for (const l of logs) console.log(l);
  console.log('\n===== STATE =====');
  console.log(JSON.stringify(stateSnapshot, null, 2));
  console.log('\n===== PAGE ERRORS (' + pageErrors.length + ') =====');
  for (const e of pageErrors) console.log(e);

  if (pageErrors.length > 0) throw new Error('page errors seen: ' + pageErrors.join('; '));
  if (!stateSnapshot.hasGame || !stateSnapshot.loggedIn) throw new Error('client did not reach logged-in state');
  if (stateSnapshot.loadingStage !== 2) throw new Error('client did not finish scene load');
  if (!allowInvisibleLocalPlayer && (!stateSnapshot.localPlayer || !stateSnapshot.localPlayer.visible)) {
    throw new Error('local player is not visible');
  }

  await browser.close();
})().catch((err) => {
  console.error('FATAL:', err);
  process.exit(1);
});
