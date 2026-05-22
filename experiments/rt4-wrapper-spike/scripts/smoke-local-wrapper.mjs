import playwright from '../../../Deployment_Scripts/playwright/node_modules/playwright/index.js';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const { chromium } = playwright;
const url = process.env.RT4_WRAPPER_URL || 'http://127.0.0.1:8787/';
const username = process.env.RT4_SMOKE_USERNAME || `smoke${Date.now().toString().slice(-6)}`;
const password = process.env.RT4_SMOKE_PASSWORD || 'password';
const outDir = process.env.RT4_SMOKE_OUT || path.join(os.tmpdir(), `rt4-wrapper-smoke-${Date.now()}`);
const startupMs = Number(process.env.RT4_SMOKE_STARTUP_MS || 120000);
const postLoginMs = Number(process.env.RT4_SMOKE_POST_LOGIN_MS || 45000);

fs.mkdirSync(outDir, { recursive: true });

const importantLogs = [];

function recordImportant(kind, text) {
  if (
    text.includes('Browser error') ||
    text.includes('Unhandled rejection') ||
    text.includes('Exception') ||
    text.includes('Run main failed') ||
    text.includes('Auto launch failed')
  ) {
    importantLogs.push(`[${kind}] ${text}`);
  }
}

const browser = await chromium.launch({ headless: true });
let page;
try {
  page = await browser.newPage({ viewport: { width: 1024, height: 768 } });
  page.on('console', msg => recordImportant(msg.type(), msg.text()));
  page.on('pageerror', err => importantLogs.push(`[pageerror] ${err.message}`));

  const smokeUrl = `${url}${url.includes('?') ? '&' : '?'}v=smoke-${Date.now()}`;
  await page.goto(smokeUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(startupMs);
  await page.screenshot({ path: path.join(outDir, '01-login-screen.png'), fullPage: true });

  await page.mouse.click(512, 207);
  await page.waitForTimeout(1200);
  await page.mouse.click(512, 298);
  await page.keyboard.type(username);
  await page.keyboard.press('Tab');
  await page.keyboard.type(password);
  await page.mouse.click(512, 400);

  await page.waitForTimeout(postLoginMs);
  await page.screenshot({ path: path.join(outDir, '02-in-game.png'), fullPage: true });

  if (importantLogs.length > 0) {
    fs.writeFileSync(path.join(outDir, 'important.log'), importantLogs.join('\n') + '\n');
    throw new Error(`Important browser logs were emitted. See ${path.join(outDir, 'important.log')}`);
  }

  console.log(`RT4 wrapper smoke passed for ${username}`);
  console.log(`Artifacts: ${outDir}`);
} catch (err) {
  if (page) {
    try {
      await page.screenshot({ path: path.join(outDir, '99-failure.png'), fullPage: true });
    } catch {
      // Keep the original failure visible if screenshot capture also fails.
    }
  }
  console.error(`Artifacts: ${outDir}`);
  throw err;
} finally {
  await browser.close();
}
