#!/usr/bin/env node

import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { chromium, devices } from "playwright";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, "..");
const publicDir = path.join(rootDir, "public");
const artifactDir = path.join(rootDir, "test-artifacts");

const tests = [];

function test(name, fn) {
  tests.push({ name, fn });
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function contentTypeFor(filePath) {
  if (filePath.endsWith(".html")) return "text/html; charset=utf-8";
  if (filePath.endsWith(".js")) return "text/javascript; charset=utf-8";
  if (filePath.endsWith(".json")) return "application/json; charset=utf-8";
  if (filePath.endsWith(".jar")) return "application/java-archive";
  return "application/octet-stream";
}

function resolvePublicPath(urlPath) {
  const withoutAppPrefix = urlPath.startsWith("/app/") ? urlPath.slice(4) : urlPath;
  const decoded = decodeURIComponent(withoutAppPrefix);
  const normalized = path.normalize(decoded).replace(/^(\.\.(\/|\\|$))+/, "");
  const relative = normalized === "/" ? "index.html" : normalized.replace(/^\/+/, "");
  const fullPath = path.resolve(publicDir, relative);
  if (!fullPath.startsWith(publicDir + path.sep) && fullPath !== publicDir) {
    return null;
  }
  return fullPath;
}

function serveRangeFile(req, res, filePath) {
  const stat = fs.statSync(filePath);
  const headers = {
    "Accept-Ranges": "bytes",
    "Cross-Origin-Embedder-Policy": "require-corp",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Resource-Policy": "cross-origin",
    "Content-Type": contentTypeFor(filePath),
  };
  const range = req.headers.range;
  if (range) {
    const match = /^bytes=(\d*)-(\d*)$/.exec(range);
    if (!match) {
      res.writeHead(416, headers);
      res.end();
      return;
    }
    const start = match[1] ? Number(match[1]) : 0;
    const end = match[2] ? Number(match[2]) : stat.size - 1;
    const safeStart = Math.max(0, Math.min(start, stat.size - 1));
    const safeEnd = Math.max(safeStart, Math.min(end, stat.size - 1));
    res.writeHead(206, {
      ...headers,
      "Content-Length": safeEnd - safeStart + 1,
      "Content-Range": `bytes ${safeStart}-${safeEnd}/${stat.size}`,
    });
    if (req.method === "HEAD") {
      res.end();
      return;
    }
    fs.createReadStream(filePath, { start: safeStart, end: safeEnd }).pipe(res);
    return;
  }

  res.writeHead(200, {
    ...headers,
    "Content-Length": stat.size,
  });
  if (req.method === "HEAD") {
    res.end();
    return;
  }
  fs.createReadStream(filePath).pipe(res);
}

async function startServer() {
  const server = http.createServer((req, res) => {
    try {
      const url = new URL(req.url || "/", "http://127.0.0.1");
      const filePath = resolvePublicPath(url.pathname);
      if (!filePath || !fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
        res.writeHead(404, {
          "Cross-Origin-Embedder-Policy": "require-corp",
          "Cross-Origin-Opener-Policy": "same-origin",
        });
        res.end("Not found");
        return;
      }
      serveRangeFile(req, res, filePath);
    } catch (error) {
      res.writeHead(500);
      res.end(String(error && error.stack ? error.stack : error));
    }
  });

  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  return {
    server,
    baseUrl: `http://127.0.0.1:${address.port}/`,
  };
}

function readWrapperConfig() {
  const script = fs.readFileSync(path.join(publicDir, "wrapper-config.js"), "utf8");
  const match = /window\.RT4_WRAPPER_CONFIG\s*=\s*(\{[\s\S]*?\});?\s*$/.exec(script.trim());
  assert(match, "wrapper-config.js must assign window.RT4_WRAPPER_CONFIG");
  return Function(`"use strict"; const window = {}; ${script}; return window.RT4_WRAPPER_CONFIG;`)();
}

function jarContains(jarName, entryName) {
  const data = fs.readFileSync(path.join(publicDir, jarName));
  return data.includes(Buffer.from(entryName, "utf8"));
}

function javapContains(jarName, className, text) {
  const result = spawnSync("javap", [
    "-classpath",
    path.join(publicDir, jarName),
    "-c",
    "-p",
    className,
  ], { encoding: "utf8" });
  assert(result.status === 0, `javap failed for ${jarName} ${className}: ${result.stderr || result.stdout}`);
  return result.stdout.includes(text);
}

function assertBrowserAudioPatched(jarName, label) {
  assert(jarContains(jarName, "rt4/BrowserAudioNative.class"), `${label} client jar is missing BrowserAudioNative`);
  assert(jarContains(jarName, "rt4/BrowserAudioChannel.class"), `${label} client jar is missing BrowserAudioChannel`);
  assert(jarContains(jarName, "rt4/BrowserAudioChannel"), `${label} AudioChannel is not patched to reference BrowserAudioChannel`);
  assert(javapContains(jarName, "rt4.AudioChannel", "rt4.browser.websocket"), `${label} AudioChannel is missing the browser websocket/audio feature flag`);
}

async function withPage(browser, baseUrl, query, options, fn) {
  const context = await browser.newContext(options);
  await context.route("https://cjrtnc.leaningtech.com/4.3/loader.js", route => {
    route.fulfill({
      contentType: "text/javascript",
      body: `
        window.cheerpjInit = async function () {};
        window.cheerpjCreateDisplay = function (_w, _h, parent) {
          if (document.getElementById("cheerpjDisplay")) return;
          const display = document.createElement("div");
          display.id = "cheerpjDisplay";
          display.style.width = "100%";
          display.style.height = "100%";
          const win = document.createElement("div");
          win.className = "cjWindow";
          win.style.width = "100%";
          win.style.height = "100%";
          const canvas = document.createElement("canvas");
          canvas.width = 765;
          canvas.height = 503;
          canvas.style.width = "100%";
          canvas.style.height = "100%";
          win.appendChild(canvas);
          display.appendChild(win);
          parent.appendChild(display);
        };
        window.cheerpjRunMain = async function () { return 0; };
        window.cheerpjRunJar = async function () { return 0; };
      `,
    });
  });
  const page = await context.newPage();
  const consoleMessages = [];
  page.on("console", msg => consoleMessages.push(`${msg.type()}: ${msg.text()}`));
  try {
    await page.goto(baseUrl + query, { waitUntil: "domcontentloaded" });
    await page.waitForSelector("#cheerpjDisplay", { timeout: 5000 });
    await fn(page, consoleMessages);
  } finally {
    await context.close();
  }
}

async function screenshot(page, name) {
  fs.mkdirSync(artifactDir, { recursive: true });
  await page.screenshot({ path: path.join(artifactDir, name), fullPage: true });
}

test("static config and assets are internally consistent", async ({ baseUrl }) => {
  const config = readWrapperConfig();
  assert(config.clientJar, "clientJar is missing");
  assert(config.launcherJar, "launcherJar is missing");
  const configuredAssets = [
    config.clientJar,
    config.launcherJar,
    config.desktopClientJar,
    config.desktopLauncherJar,
    config.mobileClientJar,
    config.mobileLauncherJar,
  ].filter(Boolean);
  for (const asset of configuredAssets) {
    assert(fs.existsSync(path.join(publicDir, asset)), `Missing ${asset}`);
  }
  assert(config.desktopClientJar === "client-1.0.0-mobile19.jar", "Desktop should keep the click-safe mobile19 client jar");
  assert(config.mobileClientJar === "client-1.0.0-mobile17-audio1.jar", "Mobile should use the compact audio-patched mobile17 client jar");
  assert(config.mobileClientJar && config.mobileClientJar.includes("mobile"), "Mobile client jar should be explicit");
  assertBrowserAudioPatched(config.desktopClientJar, "Desktop");
  assertBrowserAudioPatched(config.mobileClientJar, "Mobile");
  assert(javapContains(config.mobileLauncherJar, "spike.Rt4SpikeLauncher", "rt4.browser.websocket"), "Launcher jar must enable the browser websocket/audio feature flag");
  assert(config.desktopLauncherJar === config.mobileLauncherJar, "Desktop and mobile should use the same boot-safe launcher jar on the dev wrapper");
  assert(config.websocketUrl === "ws://192.168.0.30:43601", "Dev wrapper should target the Pi websocket");

  const appConfig = JSON.parse(fs.readFileSync(path.join(publicDir, "config.json"), "utf8"));
  assert(appConfig.ip_address === "192.168.0.30", "config.json ip_address should target the Pi");
  assert(appConfig.ip_management === "192.168.0.30", "config.json ip_management should target the Pi");
  assert(Number(appConfig.server_port) === 43600, "config.json server_port should be 43600");

  for (const jar of [config.desktopClientJar, config.mobileClientJar]) {
    const jarUrl = new URL(`/app/${jar}`, baseUrl);
    const response = await fetch(jarUrl, { headers: { Range: "bytes=0-7" } });
    assert(response.status === 206, `Range request for ${jar} returned ${response.status}, expected 206`);
    assert(response.headers.get("content-range"), `Range response for ${jar} is missing Content-Range`);
  }
});

test("desktop and mobile choose different runtime jars", async ({ browser, baseUrl }) => {
  await withPage(browser, baseUrl, "?v=regression-desktop-jar", {
    viewport: { width: 1280, height: 720 },
    deviceScaleFactor: 1,
    hasTouch: false,
    isMobile: false,
  }, async page => {
    const selected = await page.evaluate(() => window.__rt4SelectedJars);
    assert(selected.mobile === false, `Desktop selected mobile jar mode: ${JSON.stringify(selected)}`);
    assert(selected.clientJar === "client-1.0.0-mobile19.jar", `Desktop selected wrong client jar: ${JSON.stringify(selected)}`);
    assert(selected.launcherJar === "rt4-spike-launcher-mobile18.jar", `Desktop selected wrong launcher jar: ${JSON.stringify(selected)}`);
  });

  await withPage(browser, baseUrl, "?v=regression-mobile-jar&forcetouch=1", {
    ...devices["iPhone 15 Pro"],
  }, async page => {
    const selected = await page.evaluate(() => window.__rt4SelectedJars);
    assert(selected.mobile === true, `Mobile selected desktop jar mode: ${JSON.stringify(selected)}`);
    assert(selected.clientJar === "client-1.0.0-mobile17-audio1.jar", `Mobile selected wrong client jar: ${JSON.stringify(selected)}`);
    assert(selected.launcherJar === "rt4-spike-launcher-mobile18.jar", `Mobile selected wrong launcher jar: ${JSON.stringify(selected)}`);
  });
});

test("audio diagnostics are available before Java audio starts", async ({ browser, baseUrl }) => {
  await withPage(browser, baseUrl, "?v=regression-audio-startup&forcetouch=1", {
    ...devices["iPhone 15 Pro"],
  }, async page => {
    const state = await page.evaluate(() => window.__rt4AudioState);
    assert(state?.reason === "startup", `Startup audio diagnostics are missing: ${JSON.stringify(state)}`);
    assert(state.contextState === "none", `Startup audio context should not be created yet: ${JSON.stringify(state)}`);
    const helpers = await page.evaluate(() => ({
      unlock: typeof window.__rt4UnlockAudio,
      reset: typeof window.__rt4ResetAudioContext,
      testTone: typeof window.__rt4PlayAudioTestTone,
    }));
    assert(helpers.unlock === "function", `Audio unlock helper is missing: ${JSON.stringify(helpers)}`);
    assert(helpers.reset === "function", `Audio reset helper is missing: ${JSON.stringify(helpers)}`);
    assert(helpers.testTone === "function", `Audio test tone helper is missing: ${JSON.stringify(helpers)}`);
  });
});

test("desktop native mouse path is available when direct bridge is disabled", async ({ browser, baseUrl }) => {
  await withPage(browser, baseUrl, "?v=regression-desktop-native&desktopDirectMouse=0", {
    viewport: { width: 1280, height: 720 },
    deviceScaleFactor: 1,
    hasTouch: false,
    isMobile: false,
  }, async page => {
    const before = await page.evaluate(() => {
      const display = document.getElementById("display");
      const rect = display.getBoundingClientRect();
      const x = Math.round(rect.left + rect.width * 0.5);
      const y = Math.round(rect.top + rect.height * 0.5);
      window.__rt4DomMouseEvents = [];
      ["mousedown", "mouseup", "click"].forEach(type => {
        display.addEventListener(type, event => {
          window.__rt4DomMouseEvents.push({
            type,
            defaultPrevented: event.defaultPrevented,
            targetId: event.target && event.target.id,
            button: event.button,
            buttons: event.buttons,
          });
        }, false);
      });
      return {
        x,
        y,
        harness: window.shouldUseTouchHarness(),
        desktopBridge: window.shouldUseDesktopMouseBridge(),
        elementAtPoint: document.elementFromPoint(x, y)?.id || document.elementFromPoint(x, y)?.tagName || "",
        bodyClass: document.body.className,
      };
    });
    assert(before.harness === false, "Desktop should not use the mobile touch harness");
    assert(before.desktopBridge === false, "desktopDirectMouse=0 should disable the desktop bridge");
    assert(before.elementAtPoint !== "touch-capture-layer", "Mobile capture layer is intercepting desktop clicks");
    await page.mouse.click(before.x, before.y);
    const after = await page.evaluate(() => ({
      events: window.__rt4DomMouseEvents || [],
      queueLength: (window.__rt4MouseQueue || []).length,
      lastDesktopMouse: window.__rt4LastDesktopMouse || null,
    }));
    assert(after.events.map(event => event.type).join(",") === "mousedown,mouseup,click", `Desktop native click did not pass through cleanly: ${JSON.stringify(after.events)}`);
    assert(after.events.every(event => event.defaultPrevented === false), `Desktop native click was prevented: ${JSON.stringify(after.events)}`);
    assert(after.queueLength === 0, "Native desktop path should not enqueue direct bridge mouse events");
  });
});

test("desktop direct mouse bridge queues exactly one primary and one secondary click", async ({ browser, baseUrl }) => {
  await withPage(browser, baseUrl, "?v=regression-desktop-direct", {
    viewport: { width: 1280, height: 720 },
    deviceScaleFactor: 1,
    hasTouch: false,
    isMobile: false,
  }, async page => {
    const point = await page.evaluate(() => {
      const rect = document.getElementById("display").getBoundingClientRect();
      return {
        x: Math.round(rect.left + rect.width * 0.5),
        y: Math.round(rect.top + rect.height * 0.5),
        harness: window.shouldUseTouchHarness(),
        desktopBridge: window.shouldUseDesktopMouseBridge(),
      };
    });
    assert(point.harness === false, "Desktop direct bridge test unexpectedly used touch harness");
    assert(point.desktopBridge === true, "Default desktop direct mouse bridge is not enabled");

    await page.mouse.click(point.x, point.y);
    const primary = await page.evaluate(() => {
      const out = [];
      for (let i = 0; i < 4; i++) {
        const type = window.Java_rt4_BrowserInputNative_pollMouseEventType();
        if (!type) break;
        out.push({
          type,
          x: window.Java_rt4_BrowserInputNative_pollMouseX(),
          y: window.Java_rt4_BrowserInputNative_pollMouseY(),
          button: window.Java_rt4_BrowserInputNative_pollMouseButton(),
        });
      }
      return out;
    });
    assert(primary.filter(event => event.type === 2).length === 1, `Primary click queued wrong down count: ${JSON.stringify(primary)}`);
    assert(primary.filter(event => event.type === 3).length === 1, `Primary click queued wrong up count: ${JSON.stringify(primary)}`);
    assert(primary.every(event => event.type === 1 || event.type === 2 || event.type === 3), `Primary click queued unexpected event: ${JSON.stringify(primary)}`);
    assert(primary.every(event => event.button === 1), `Primary click queued wrong button: ${JSON.stringify(primary)}`);

    await page.mouse.click(point.x + 20, point.y + 10, { button: "right" });
    const secondary = await page.evaluate(() => {
      const out = [];
      for (let i = 0; i < 6; i++) {
        const type = window.Java_rt4_BrowserInputNative_pollMouseEventType();
        if (!type) break;
        out.push({
          type,
          x: window.Java_rt4_BrowserInputNative_pollMouseX(),
          y: window.Java_rt4_BrowserInputNative_pollMouseY(),
          button: window.Java_rt4_BrowserInputNative_pollMouseButton(),
        });
      }
      return out;
    });
    assert(secondary.filter(event => event.type === 2).length === 1, `Secondary click queued wrong down count: ${JSON.stringify(secondary)}`);
    assert(secondary.filter(event => event.type === 3).length === 1, `Secondary click queued wrong up count: ${JSON.stringify(secondary)}`);
    assert(secondary.every(event => event.type === 1 || event.type === 2 || event.type === 3), `Secondary click queued unexpected event: ${JSON.stringify(secondary)}`);
    assert(secondary.filter(event => event.type === 2 || event.type === 3).every(event => event.button === 2), `Secondary click queued wrong button: ${JSON.stringify(secondary)}`);
  });
});

test("mobile chat keyboard focus and text queue survive input changes", async ({ browser, baseUrl }) => {
  await withPage(browser, baseUrl, "?v=regression-mobile-keyboard&forcetouch=1", {
    ...devices["iPhone 15 Pro"],
  }, async page => {
    await page.evaluate(() => {
      window.Java_rt4_BrowserInputNative_beginInputFrame(null, 30, 765, 503);
      window.Java_rt4_BrowserInputNative_setGameState(null, 30);
      window.__rt4RequestLayoutSync();
    });
    await page.waitForFunction(() => window.__rt4LayoutState && window.__rt4LayoutState.width >= 765);
    const target = await page.evaluate(() => {
      const height = Math.max(window.__rt4InputFrame?.canvasHeight || 0, window.__rt4LayoutState?.height || 0, 503);
      const width = Math.max(window.__rt4InputFrame?.canvasWidth || 0, window.__rt4LayoutState?.width || 0, 765);
      const field = { id: -2001, x: 0, y: Math.max(0, height - 56), width: Math.min(535, Math.round(width * 0.72)), height: 56 };
      const rect = document.getElementById("display").getBoundingClientRect();
      const layout = window.__rt4LayoutState || {};
      const scaleX = rect.width / Math.max(1, layout.width || 765);
      const scaleY = rect.height / Math.max(1, layout.height || 503);
      return {
        x: Math.round(rect.left + Math.min(40, field.width * 0.18) * scaleX),
        y: Math.round(rect.top + ((field?.y ?? 486) + (field?.height ?? 17) / 2) * scaleY),
        field,
      };
    });
    assert(target.field, "Chat fallback field was not registered");
    assert(target.x >= 0 && target.x <= 393, `Chat fallback target is out of mobile viewport: ${JSON.stringify(target)}`);
    assert(target.y >= 0 && target.y <= 659, `Chat fallback target is out of mobile viewport: ${JSON.stringify(target)}`);
    const hit = await page.evaluate(({ x, y }) => window.__rt4FieldAtClientPoint(x, y), { x: target.x, y: target.y });
    assert(hit.field?.name === "chat", `Chat target did not hit chat fallback: ${JSON.stringify({ target, hit })}`);
    const promptTarget = await page.evaluate(() => {
      const height = Math.max(window.__rt4InputFrame?.canvasHeight || 0, window.__rt4LayoutState?.height || 0, 503);
      const width = Math.max(window.__rt4InputFrame?.canvasWidth || 0, window.__rt4LayoutState?.width || 0, 765);
      const promptHeight = Math.min(126, Math.max(88, Math.round(height * 0.22)));
      const field = {
        id: -2002,
        x: 0,
        y: Math.max(0, height - promptHeight - 28),
        width: Math.min(560, Math.round(width * 0.78)),
        height: promptHeight,
      };
      const rect = document.getElementById("display").getBoundingClientRect();
      const layout = window.__rt4LayoutState || {};
      const scaleX = rect.width / Math.max(1, layout.width || 765);
      const scaleY = rect.height / Math.max(1, layout.height || 503);
      return {
        x: Math.round(rect.left + 120 * scaleX),
        y: Math.round(rect.top + (field.y + field.height * 0.35) * scaleY),
        field,
      };
    });
    const promptHit = await page.evaluate(({ x, y }) => window.__rt4FieldAtClientPoint(x, y), { x: promptTarget.x, y: promptTarget.y });
    assert(promptHit.field?.name === "chat-prompt", `Friend/add-name prompt target did not hit prompt fallback: ${JSON.stringify({ promptTarget, promptHit })}`);
    await page.evaluate(({ x, y }) => window.__rt4OpenKeyboardForClientPoint(x, y), { x: target.x, y: target.y });
    await page.evaluate(() => document.getElementById("keyboard-proxy")?.focus());
    const focused = await page.evaluate(() => ({
      activeId: document.activeElement && document.activeElement.id,
      lastTap: window.__rt4LastTap || null,
      activeField: window.__rt4KeyboardActiveField || null,
    }));
    assert(focused.activeField?.name === "chat", `Chat tap did not hit chat fallback: ${JSON.stringify(focused)}`);

    await page.evaluate(() => {
      const proxy = document.getElementById("keyboard-proxy");
      for (const char of "test1") {
        proxy.dispatchEvent(new InputEvent("beforeinput", {
          bubbles: true,
          cancelable: true,
          inputType: "insertText",
          data: char,
        }));
      }
    });
    const chars = await page.evaluate(() => {
      const out = [];
      for (let i = 0; i < 10; i++) {
        const code = window.Java_rt4_BrowserInputNative_pollKeyChar();
        if (code < 0) break;
        out.push(String.fromCharCode(code));
      }
      return out.join("");
    });
    assert(chars === "test1", `Printable keyboard queue changed: ${JSON.stringify(chars)}`);
  });
});

test("mobile portrait gameplay framing keeps both left chat tabs and right menu inside view", async ({ browser, baseUrl }) => {
  await withPage(browser, baseUrl, "?v=regression-portrait-frame&forcetouch=1", {
    ...devices["iPhone 15 Pro"],
  }, async page => {
    await page.evaluate(() => {
      window.Java_rt4_BrowserInputNative_beginInputFrame(null, 30, 765, 503);
      window.Java_rt4_BrowserInputNative_setGameState(null, 30);
      window.__rt4RequestLayoutSync();
    });
    await page.waitForFunction(() => window.__rt4LayoutState && window.__rt4LayoutState.width >= 765);
    await screenshot(page, "portrait-framing.png");
    const frame = await page.evaluate(() => {
      const rect = document.getElementById("display").getBoundingClientRect();
      const layout = window.__rt4LayoutState || {};
      const renderedScale = Math.max(0.001, layout.totalScaleX || layout.totalScale || layout.fitScale || 1);
      const visibleLeft = Math.max(0, Math.round((0 - rect.left) / renderedScale));
      const visibleRight = Math.min(layout.width || 765, Math.round((window.innerWidth - rect.left) / renderedScale));
      return {
        innerWidth: window.innerWidth,
        display: { left: Math.round(rect.left), width: Math.round(rect.width) },
        layout,
        visibleLeft,
        visibleRight,
      };
    });
    assert(frame.visibleLeft <= 12, `Portrait framing cuts too much off the left edge: ${JSON.stringify(frame)}`);
    assert(frame.visibleRight >= 758, `Portrait framing cuts too much off the right edge: ${JSON.stringify(frame)}`);
  });
});

test("mobile portrait pre-game layout uses the available height without stretching", async ({ browser, baseUrl }) => {
  await withPage(browser, baseUrl, "?v=regression-portrait-height&forcetouch=1", {
    ...devices["iPhone 15 Pro"],
  }, async page => {
    await page.waitForFunction(() => window.__rt4LayoutState && window.__rt4LayoutState.width >= 765);
    const frame = await page.evaluate(() => {
      const display = document.getElementById("display").getBoundingClientRect();
      const layout = window.__rt4LayoutState || {};
      return {
        innerWidth: window.innerWidth,
        innerHeight: window.innerHeight,
        display: {
          left: Math.round(display.left),
          top: Math.round(display.top),
          width: Math.round(display.width),
          height: Math.round(display.height),
        },
        layout,
      };
    });
    assert(frame.display.height >= frame.innerHeight * 0.9, `Portrait layout is still too short: ${JSON.stringify(frame)}`);
    assert(Math.abs((frame.layout.totalScaleX || 1) - (frame.layout.totalScaleY || 1)) < 0.001, `Portrait layout should preserve aspect ratio: ${JSON.stringify(frame)}`);
  });
});

test("mobile landscape pre-game layout fits without vertical cropping", async ({ browser, baseUrl }) => {
  await withPage(browser, baseUrl, "?v=regression-landscape-fit&forcetouch=1", {
    ...devices["iPhone 15 Pro landscape"],
  }, async page => {
    await page.waitForFunction(() => window.__rt4LayoutState && window.__rt4LayoutState.width >= 765);
    const frame = await page.evaluate(() => {
      const display = document.getElementById("display").getBoundingClientRect();
      const layout = window.__rt4LayoutState || {};
      return {
        innerWidth: window.innerWidth,
        innerHeight: window.innerHeight,
        display: {
          left: Math.round(display.left),
          top: Math.round(display.top),
          width: Math.round(display.width),
          height: Math.round(display.height),
        },
        layout,
      };
    });
    assert(frame.display.top >= -2, `Landscape layout is cropped above the viewport: ${JSON.stringify(frame)}`);
    assert(frame.display.top + frame.display.height <= frame.innerHeight + 2, `Landscape layout is cropped below the viewport: ${JSON.stringify(frame)}`);
    assert(frame.display.width >= frame.innerWidth * 0.9, `Landscape layout is not using enough width: ${JSON.stringify(frame)}`);
    assert(frame.display.height >= frame.innerHeight * 0.9, `Landscape layout is not using enough height: ${JSON.stringify(frame)}`);
    assert(Math.abs((frame.layout.totalScaleX || 1) - (frame.layout.totalScaleY || 1)) < 0.001, `Landscape layout should preserve aspect ratio: ${JSON.stringify(frame)}`);
  });
});

test("mobile landscape gameplay can draw a larger world while filling the display", async ({ browser, baseUrl }) => {
  await withPage(browser, baseUrl, "?v=regression-landscape-world&forcetouch=1", {
    ...devices["iPhone 15 Pro landscape"],
  }, async page => {
    await page.evaluate(() => {
      window.Java_rt4_BrowserInputNative_beginInputFrame(null, 30, 765, 503);
      window.Java_rt4_BrowserInputNative_setGameState(null, 30);
      window.__rt4RequestLayoutSync();
    });
    await page.waitForFunction(() => window.__rt4LayoutState && window.__rt4LayoutState.width >= 1180);
    const frame = await page.evaluate(() => {
      const display = document.getElementById("display").getBoundingClientRect();
      const layout = window.__rt4LayoutState || {};
      return {
        innerWidth: window.innerWidth,
        innerHeight: window.innerHeight,
        display: {
          left: Math.round(display.left),
          top: Math.round(display.top),
          width: Math.round(display.width),
          height: Math.round(display.height),
        },
        layout,
      };
    });
    assert(frame.layout.width >= 1180, `Landscape gameplay did not enlarge the draw surface: ${JSON.stringify(frame)}`);
    assert(frame.display.width >= frame.innerWidth * 0.9, `Landscape gameplay is not using enough width: ${JSON.stringify(frame)}`);
    assert(frame.display.height >= frame.innerHeight * 0.9, `Landscape gameplay is not using enough height: ${JSON.stringify(frame)}`);
    assert(Math.abs((frame.layout.totalScaleX || 1) - (frame.layout.totalScaleY || 1)) < 0.001, `Landscape gameplay should preserve aspect ratio: ${JSON.stringify(frame)}`);
  });
});

test("mobile swipe and pinch queue camera movement", async ({ browser, baseUrl }) => {
  await withPage(browser, baseUrl, "?v=regression-mobile-gestures&forcetouch=1", {
    ...devices["iPhone 15 Pro"],
  }, async page => {
    await page.evaluate(() => {
      window.Java_rt4_BrowserInputNative_beginInputFrame(null, 30, 765, 503);
      window.Java_rt4_BrowserInputNative_setGameState(null, 30);
      window.__rt4RequestLayoutSync();
    });
    await page.waitForFunction(() => window.__rt4LayoutState && window.__rt4LayoutState.width >= 765);

    const gestureResult = await page.evaluate(async () => {
      const target = document.getElementById("touch-capture-layer");
      const rect = target.getBoundingClientRect();
      const cx = rect.left + rect.width * 0.28;
      const cy = rect.top + rect.height * 0.55;
      const makeTouch = (identifier, x, y) => new Touch({
        identifier,
        target,
        clientX: x,
        clientY: y,
        screenX: x,
        screenY: y,
        pageX: x,
        pageY: y,
      });

      let one = makeTouch(1, cx, cy);
      document.dispatchEvent(new TouchEvent("touchstart", {
        bubbles: true,
        cancelable: true,
        touches: [one],
        targetTouches: [one],
        changedTouches: [one],
      }));
      for (let i = 1; i <= 5; i++) {
        one = makeTouch(1, cx + (60 * i / 5), cy);
        document.dispatchEvent(new TouchEvent("touchmove", {
          bubbles: true,
          cancelable: true,
          touches: [one],
          targetTouches: [one],
          changedTouches: [one],
        }));
        await new Promise(resolve => setTimeout(resolve, 16));
      }
      document.dispatchEvent(new TouchEvent("touchend", {
        bubbles: true,
        cancelable: true,
        touches: [],
        targetTouches: [],
        changedTouches: [one],
      }));
      await new Promise(resolve => setTimeout(resolve, 40));
      const yaw = window.Java_rt4_BrowserInputNative_pollCameraYaw();

      let left = makeTouch(1, cx - 30, cy);
      let right = makeTouch(2, cx + 30, cy);
      document.dispatchEvent(new TouchEvent("touchstart", {
        bubbles: true,
        cancelable: true,
        touches: [left, right],
        targetTouches: [left, right],
        changedTouches: [left, right],
      }));
      for (let i = 1; i <= 5; i++) {
        left = makeTouch(1, cx - 30 - i * 8, cy);
        right = makeTouch(2, cx + 30 + i * 8, cy);
        document.dispatchEvent(new TouchEvent("touchmove", {
          bubbles: true,
          cancelable: true,
          touches: [left, right],
          targetTouches: [left, right],
          changedTouches: [left, right],
        }));
        await new Promise(resolve => setTimeout(resolve, 16));
      }
      document.dispatchEvent(new TouchEvent("touchend", {
        bubbles: true,
        cancelable: true,
        touches: [],
        targetTouches: [],
        changedTouches: [left, right],
      }));
      await new Promise(resolve => setTimeout(resolve, 40));
      const zoom = window.Java_rt4_BrowserInputNative_pollCameraZoom();
      return { yaw, zoom };
    });

    assert(Math.abs(gestureResult.yaw) > 0, `Swipe did not queue camera yaw: ${JSON.stringify(gestureResult)}`);
    assert(Math.abs(gestureResult.zoom) > 0, `Pinch did not queue camera zoom: ${JSON.stringify(gestureResult)}`);
  });
});

test("mobile vertical swipe over interface panel scrolls instead of moving camera", async ({ browser, baseUrl }) => {
  await withPage(browser, baseUrl, "?v=regression-mobile-interface-scroll&forcetouch=1", {
    ...devices["iPhone 15 Pro"],
  }, async page => {
    await page.evaluate(() => {
      window.Java_rt4_BrowserInputNative_beginInputFrame(null, 30, 765, 503);
      window.Java_rt4_BrowserInputNative_setGameState(null, 30);
      window.__rt4RequestLayoutSync();
    });
    await page.waitForFunction(() => window.__rt4LayoutState && window.__rt4LayoutState.width >= 765);

    const result = await page.evaluate(async () => {
      const target = document.getElementById("touch-capture-layer");
      const rect = target.getBoundingClientRect();
      const cx = rect.left + rect.width * 0.64;
      const cy = rect.top + rect.height * 0.45;
      const makeTouch = (identifier, x, y) => new Touch({
        identifier,
        target,
        clientX: x,
        clientY: y,
        screenX: x,
        screenY: y,
        pageX: x,
        pageY: y,
      });

      let one = makeTouch(1, cx, cy);
      document.dispatchEvent(new TouchEvent("touchstart", {
        bubbles: true,
        cancelable: true,
        touches: [one],
        targetTouches: [one],
        changedTouches: [one],
      }));
      for (let i = 1; i <= 5; i++) {
        one = makeTouch(1, cx, cy - (80 * i / 5));
        document.dispatchEvent(new TouchEvent("touchmove", {
          bubbles: true,
          cancelable: true,
          touches: [one],
          targetTouches: [one],
          changedTouches: [one],
        }));
        await new Promise(resolve => setTimeout(resolve, 16));
      }
      document.dispatchEvent(new TouchEvent("touchend", {
        bubbles: true,
        cancelable: true,
        touches: [],
        targetTouches: [],
        changedTouches: [one],
      }));
      await new Promise(resolve => setTimeout(resolve, 40));
      return {
        yaw: window.Java_rt4_BrowserInputNative_pollCameraYaw(),
        pitch: window.Java_rt4_BrowserInputNative_pollCameraPitch(),
        wheel: window.Java_rt4_BrowserInputNative_pollWheelRotation(),
        gesture: window.__rt4LastGesture || null,
      };
    });

    assert(result.wheel !== 0, `Interface swipe did not queue scrollbar wheel: ${JSON.stringify(result)}`);
    assert(result.yaw === 0 && result.pitch === 0, `Interface swipe also moved camera: ${JSON.stringify(result)}`);
  });
});

test("mobile pointer fallback queues camera movement", async ({ browser, baseUrl }) => {
  await withPage(browser, baseUrl, "?v=regression-mobile-pointer-gestures&forcetouch=1", {
    ...devices["iPhone 15 Pro"],
  }, async page => {
    await page.evaluate(() => {
      window.Java_rt4_BrowserInputNative_beginInputFrame(null, 30, 765, 503);
      window.Java_rt4_BrowserInputNative_setGameState(null, 30);
      window.__rt4RequestLayoutSync();
    });
    await page.waitForFunction(() => window.__rt4LayoutState && window.__rt4LayoutState.width >= 765);

    const gestureResult = await page.evaluate(async () => {
      const target = document.getElementById("touch-capture-layer");
      const rect = target.getBoundingClientRect();
      const cx = rect.left + rect.width * 0.28;
      const cy = rect.top + rect.height * 0.55;
      const firePointer = (type, id, x, y) => {
        const event = new PointerEvent(type, {
          bubbles: true,
          cancelable: true,
          pointerId: id,
          pointerType: "touch",
          isPrimary: id === 1,
          clientX: x,
          clientY: y,
          screenX: x,
          screenY: y,
        });
        document.dispatchEvent(event);
      };

      firePointer("pointerdown", 1, cx, cy);
      for (let i = 1; i <= 5; i++) {
        firePointer("pointermove", 1, cx + (60 * i / 5), cy);
        await new Promise(resolve => setTimeout(resolve, 16));
      }
      firePointer("pointerup", 1, cx + 60, cy);
      await new Promise(resolve => setTimeout(resolve, 40));
      const yaw = window.Java_rt4_BrowserInputNative_pollCameraYaw();

      firePointer("pointerdown", 1, cx - 30, cy);
      firePointer("pointerdown", 2, cx + 30, cy);
      for (let i = 1; i <= 5; i++) {
        firePointer("pointermove", 1, cx - 30 - i * 8, cy);
        firePointer("pointermove", 2, cx + 30 + i * 8, cy);
        await new Promise(resolve => setTimeout(resolve, 16));
      }
      firePointer("pointerup", 1, cx - 70, cy);
      firePointer("pointerup", 2, cx + 70, cy);
      await new Promise(resolve => setTimeout(resolve, 40));
      const zoom = window.Java_rt4_BrowserInputNative_pollCameraZoom();
      return { yaw, zoom };
    });

    assert(Math.abs(gestureResult.yaw) > 0, `Pointer swipe did not queue camera yaw: ${JSON.stringify(gestureResult)}`);
    assert(Math.abs(gestureResult.zoom) > 0, `Pointer pinch did not queue camera zoom: ${JSON.stringify(gestureResult)}`);
  });
});

test("browser audio output can be unlocked and schedule a test tone", async ({ browser, baseUrl }) => {
  await withPage(browser, baseUrl, "?v=regression-audio-tone&forcetouch=1", {
    ...devices["iPhone 15 Pro"],
  }, async page => {
    await page.touchscreen.tap(12, 12);
    const state = await page.evaluate(async () => {
      await window.__rt4UnlockAudio("regression-tone-unlock");
      window.__rt4PlayAudioTestTone("regression-tone");
      return window.__rt4AudioState;
    });
    assert(state?.supported === true, `Audio output is not supported: ${JSON.stringify(state)}`);
    assert(state.unlocked === true, `Audio output did not unlock: ${JSON.stringify(state)}`);
    assert(state.contextState === "running", `Audio context is not running after test tone: ${JSON.stringify(state)}`);
    assert(state.gain === 1, `Audio output gain node is not connected at normal gain: ${JSON.stringify(state)}`);
    assert(state.lastTestToneAt > 0, `Audio test tone was not scheduled: ${JSON.stringify(state)}`);
  });
});

test("browser audio bridge unlocks and queues without runaway buffering", async ({ browser, baseUrl }) => {
  await withPage(browser, baseUrl, "?v=regression-audio&forcetouch=1", {
    ...devices["iPhone 15 Pro"],
  }, async page => {
    await page.touchscreen.tap(12, 12);
    await page.evaluate(async () => {
      await window.__rt4UnlockAudio("regression");
      window.__rt4ResetAudioContext("regression-reset");
      await window.__rt4UnlockAudio("regression-after-reset");
      window.Java_rt4_BrowserAudioNative_init(null, 22050, false);
      const samples = new Int32Array(512);
      for (let i = 0; i < samples.length; i++) samples[i] = Math.sin(i / 8) * 1200000;
      for (let i = 0; i < 6; i++) {
        window.Java_rt4_BrowserAudioNative_write(null, 0, samples, samples.length);
      }
    });
    const state = await page.evaluate(() => ({
      contextState: window.__rt4AudioState?.contextState,
      writes: window.__rt4AudioState?.writes,
      dropped: window.__rt4AudioState?.dropped,
      queuedSeconds: window.__rt4AudioState?.channels?.[0]?.queuedSeconds,
      lastPeakRaw: window.__rt4AudioState?.lastPeakRaw,
      lastPeakFloat: window.__rt4AudioState?.lastPeakFloat,
      lastRmsFloat: window.__rt4AudioState?.lastRmsFloat,
      lastNonZeroSamples: window.__rt4AudioState?.lastNonZeroSamples,
      nonSilentWrites: window.__rt4AudioState?.nonSilentWrites,
      maxPeakRaw: window.__rt4AudioState?.maxPeakRaw,
      maxPeakFloat: window.__rt4AudioState?.maxPeakFloat,
      maxRmsFloat: window.__rt4AudioState?.maxRmsFloat,
    }));
    assert(state.contextState === "running", `Audio context did not unlock: ${JSON.stringify(state)}`);
    assert(state.writes >= 5, `Audio writes did not register: ${JSON.stringify(state)}`);
    assert(state.dropped === 0, `Audio bridge dropped synthetic writes: ${JSON.stringify(state)}`);
    assert(state.queuedSeconds < 0.25, `Audio bridge queued too much audio: ${JSON.stringify(state)}`);
    assert(state.lastPeakRaw > 0, `Audio peak diagnostics did not capture samples: ${JSON.stringify(state)}`);
    assert(state.lastPeakFloat > 0, `Audio float peak diagnostics did not capture samples: ${JSON.stringify(state)}`);
    assert(state.lastRmsFloat > 0, `Audio RMS diagnostics did not capture samples: ${JSON.stringify(state)}`);
    assert(state.lastNonZeroSamples > 0, `Audio non-zero diagnostics did not capture samples: ${JSON.stringify(state)}`);
    assert(state.nonSilentWrites > 0, `Audio non-silent counter did not update: ${JSON.stringify(state)}`);
    assert(state.maxPeakRaw > 0, `Audio max raw peak did not update: ${JSON.stringify(state)}`);
    assert(state.maxPeakFloat > 0, `Audio max float peak did not update: ${JSON.stringify(state)}`);
    assert(state.maxRmsFloat > 0, `Audio max RMS did not update: ${JSON.stringify(state)}`);
  });
});

async function main() {
  const { server, baseUrl } = await startServer();
  const browser = await chromium.launch();
  let failed = 0;
  try {
    for (const item of tests) {
      const started = Date.now();
      try {
        await item.fn({ browser, baseUrl });
        console.log(`PASS ${item.name} (${Date.now() - started}ms)`);
      } catch (error) {
        failed += 1;
        console.error(`FAIL ${item.name}`);
        console.error(error && error.stack ? error.stack : String(error));
      }
    }
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }

  if (failed > 0) {
    console.error(`${failed} regression test${failed === 1 ? "" : "s"} failed.`);
    process.exit(1);
  }
  console.log(`All ${tests.length} RT4 wrapper regression tests passed.`);
}

main().catch(error => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
