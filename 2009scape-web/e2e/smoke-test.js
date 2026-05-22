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

  const targetUrl = process.env.CLIENT_URL || 'http://10.8.0.1:8500/';
  const username = process.env.CLIENT_USERNAME || 'playtest2';
  const password = process.env.CLIENT_PASSWORD || username;
  const relogUsername = process.env.CLIENT_RELOG_USERNAME || (username.length < 12 ? `${username}r` : `${username.slice(0, 11)}r`);
  const relogPassword = process.env.CLIENT_RELOG_PASSWORD || 'password';
  const captureScreenshots = process.env.CAPTURE_SCREENSHOTS !== '0';
  const sendCommand = process.env.SEND_COMMAND !== '0';
  const assertCommand = process.env.ASSERT_COMMAND === '1';
  const assertWalk = process.env.ASSERT_WALK === '1';
  const assertMinimapWalk = process.env.ASSERT_MINIMAP_WALK === '1';
  const assertActionProbes = process.env.ASSERT_ACTION_PROBES === '1';
  const assertGroundItemActionProbes = process.env.ASSERT_GROUND_ITEM_ACTION_PROBES === '1';
  const assertDialogueContinueProbe = process.env.ASSERT_DIALOGUE_CONTINUE_PROBE === '1';
  const assertDialogueActionProbe = process.env.ASSERT_DIALOGUE_ACTION_PROBE === '1';
  const assertRenderedActionMenu = process.env.ASSERT_RENDERED_ACTION_MENU === '1';
  const assertRenderedNpcMenu = process.env.ASSERT_RENDERED_NPC_MENU === '1';
  const assertRenderedLocMenu = process.env.ASSERT_RENDERED_LOC_MENU === '1';
  const assertBankInventoryProbe = process.env.ASSERT_BANK_INVENTORY_PROBE === '1';
  const bankFixtureCommand = process.env.BANK_FIXTURE_COMMAND || '';
  const bankFixtureWaitMs = process.env.BANK_FIXTURE_WAIT_MS ? Number(process.env.BANK_FIXTURE_WAIT_MS) : 3000;
  const assertLogoutRelog = process.env.ASSERT_LOGOUT_RELOG === '1';
  const assertServerRestartReconnect = process.env.ASSERT_SERVER_RESTART_RECONNECT === '1';
  const bankInventoryContainerIds = (process.env.BANK_INVENTORY_CONTAINER_IDS || '')
    .split(',')
    .map((id) => id.trim())
    .filter((id) => id.length > 0)
    .map((id) => Number(id))
    .filter((id) => Number.isFinite(id));
  const bankInventoryRequireOpen = process.env.BANK_INVENTORY_REQUIRE_OPEN === '1';
  const bankInventoryRequireItem = process.env.BANK_INVENTORY_REQUIRE_ITEM === '1';
  const autoLogin = process.env.AUTO_LOGIN === '1';
  const serverHost = process.env.CLIENT_SERVER_HOST;
  const serverPort = process.env.CLIENT_SERVER_PORT ? Number(process.env.CLIENT_SERVER_PORT) : undefined;
  const serverDialect = process.env.CLIENT_SERVER_DIALECT;
  const stabilityMs = process.env.STABILITY_MS ? Number(process.env.STABILITY_MS) : 45000;
  const shot = async (path) => {
    if (!captureScreenshots) return;
    const dataUrl = await page.evaluate(() => document.querySelector('canvas')?.toDataURL('image/png') || '');
    if (dataUrl) fs.writeFileSync(path, Buffer.from(dataUrl.split(',')[1], 'base64'));
  };
  const waitForInGame = async () => {
    await page.waitForFunction(() => {
      const g = window.__webscapeGame;
      const p = g?.constructor.localPlayer;
      return !!g?.loggedIn && g.loadingStage === 2 && !!p?.visible;
    }, undefined, { timeout: 90000 });
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
    window.__webscapeSentPackets = [];
    window.DEBUG_PACKETS_530 = true;
    const NativeWebSocket = window.WebSocket;
    window.WebSocket = class WebscapeTrackedWebSocket extends NativeWebSocket {
      constructor(...args) {
        super(...args);
        window.__webscapeWsOpenCount++;
        this.addEventListener('close', () => {
          window.__webscapeWsCloseCount++;
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
        window.__webscapeSentPackets.push({ seq: window.__webscapeWsSendSeq, len: bytes.length, bytes: bytes.slice(0, 24) });
        if (window.__webscapeSentPackets.length > 100) window.__webscapeSentPackets.shift();
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
  const readBankInventorySnapshot = async ({ expectedIds, requireOpen, requireItem }) => page.evaluate(({ expectedIds, requireOpen, requireItem }) => {
    const g = window.__webscapeGame;
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
      chatRecent,
      problems,
    };
  }, { expectedIds, requireOpen, requireItem });
  const formatBankInventoryDiagnostics = (snapshot) => [
    'expectedIds=' + JSON.stringify(snapshot.expectedIds),
    'decodedIds=' + JSON.stringify(snapshot.containerIds),
    'missingExpectedIds=' + JSON.stringify(snapshot.missingExpectedIds),
    'openInterfaces=' + JSON.stringify(snapshot.openInterfaces),
    'rt4Diagnostics=' + JSON.stringify(snapshot.rt4Diagnostics),
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
      semanticPackets: (window.__webscapeSemanticPackets || []).slice(-12),
      recent,
    };
  }).catch(() => ({ count: 0, input: '', wsSendCount: 0, semanticPackets: [], recent: [] }));
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
    }
    return before;
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
    const commandPacket = afterCommand.semanticPackets.some((packet) => {
      const opcodes = [packet.semantic, ...(packet.semantics || [])].map((semantic) => semantic?.opcode);
      const bytes = packet.bytes || [];
      return opcodes.some((opcode) => opcode === 56 || opcode === 38 || opcode === 44)
        || bytes.some((byte) => [56, 38, 44].includes(byte & 0xff));
    });
    if (assertCommand && afterCommand.input === '::players' && afterCommand.count <= beforeChat.count && afterCommand.wsSendCount <= beforeChat.wsSendCount && !commandPacket) {
      throw new Error('::players was not consumed by chat input or sent');
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
          g.firstMenuOperand[0] = npcIndex;
          g.secondMenuOperand[0] = 0;
          g.selectedMenuActions[0] = 0;
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

  if (assertBankInventoryProbe) {
    let bankFixtureResult = null;
    if (bankFixtureCommand) {
      console.log('>>> Run bank fixture command: ' + bankFixtureCommand);
      const beforeFixture = await sendChatLine(bankFixtureCommand);
      await page.waitForTimeout(Number.isFinite(bankFixtureWaitMs) ? bankFixtureWaitMs : 3000);
      const afterFixture = await readChatState();
      bankFixtureResult = { command: bankFixtureCommand, waitMs: bankFixtureWaitMs, before: beforeFixture, after: afterFixture };
      console.log('>>> Bank fixture command result: ' + JSON.stringify(bankFixtureResult));
    }
    console.log('>>> Inspect bank/inventory container state');
    const snapshot = await readBankInventorySnapshot({
      expectedIds: bankInventoryContainerIds,
      requireOpen: bankInventoryRequireOpen,
      requireItem: bankInventoryRequireItem,
    });
    console.log('>>> Bank/inventory snapshot: ' + JSON.stringify(snapshot));
    if (snapshot.problems.length > 0) {
      throw new Error('bank/inventory probe failed: ' + snapshot.problems.join('; ')
        + '; ' + formatBankInventoryDiagnostics(snapshot)
        + (bankFixtureResult ? '; fixture=' + JSON.stringify(bankFixtureResult) : '')
        + ';' + formatBankInventoryAdvice(snapshot));
    }
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
        .filter((packet) => packet.seq > beforeSeq && packet.bytes?.[0] === 18);
      return {
        loggedIn: !!g?.loggedIn,
        loadingStage: g?.loadingStage,
        wsOpenCount: window.__webscapeWsOpenCount || 0,
        wsCloseCount: window.__webscapeWsCloseCount || 0,
        reconnectLoginPackets,
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
  if (stabilityMs > 0) await page.waitForTimeout(stabilityMs);
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
  if (!stateSnapshot.localPlayer || !stateSnapshot.localPlayer.visible) throw new Error('local player is not visible');

  await browser.close();
})().catch((err) => {
  console.error('FATAL:', err);
  process.exit(1);
});
