// Drives the mudclient through to the login form and confirms WS connects.
// Captures a Playwright trace + screenshots so we can see the full sequence.
import { webkit } from 'playwright';
import fs from 'node:fs';

const URL = process.argv[2] || 'http://10.8.0.1:8080/mudclient.html';
const OUTDIR = '/tmp/mudclient-playwright/login-' + Date.now();
fs.mkdirSync(OUTDIR, { recursive: true });

const t0 = Date.now();
const stamp = () => ((Date.now() - t0) / 1000).toFixed(1) + 's';
const log = (tag, extra = '') => console.log(`[${stamp()}] ${tag} ${extra}`);

const browser = await webkit.launch({ headless: true });
const ctx = await browser.newContext({ viewport: { width: 1024, height: 768 } });
const page = await ctx.newPage();

const consoleLines = [];
page.on('console', msg => {
  const line = `[${stamp()}] console.${msg.type()}: ${msg.text()}`;
  consoleLines.push(line);
  if (msg.text().includes('INFO') || msg.type() === 'error') {
    console.log(line);
  }
});
page.on('pageerror', err => log('PAGE_ERR', err.message));
page.on('requestfailed', req => log('REQ_FAIL', `${req.url()} ${req.failure()?.errorText}`));

// Track WS frames — this is the gold for understanding server interaction
const wsEvents = [];
page.on('websocket', ws => {
  log('WS_OPEN', ws.url());
  wsEvents.push({ t: stamp(), kind: 'open', url: ws.url() });
  ws.on('framesent', f => {
    const len = f.payload?.length || 0;
    wsEvents.push({ t: stamp(), kind: 'send', bytes: len, hex: f.payload?.slice(0, 64).toString('hex') });
    if (wsEvents.filter(e => e.kind === 'send').length <= 5) log('WS_SEND', `${len} bytes`);
  });
  ws.on('framereceived', f => {
    const len = f.payload?.length || 0;
    wsEvents.push({ t: stamp(), kind: 'recv', bytes: len, hex: f.payload?.slice(0, 64).toString('hex') });
    if (wsEvents.filter(e => e.kind === 'recv').length <= 5) log('WS_RECV', `${len} bytes`);
  });
  ws.on('close', () => { log('WS_CLOSE'); wsEvents.push({ t: stamp(), kind: 'close' }); });
  ws.on('socketerror', e => { log('WS_ERR', e); wsEvents.push({ t: stamp(), kind: 'error', err: String(e) }); });
});

await page.goto(URL, { waitUntil: 'commit' });
log('PAGE_NAVIGATED');

// Wait for the login UI to render (takes ~15s for the full cache load)
log('WAITING for login UI...');
await page.waitForFunction(
  () => {
    const c = document.getElementById('canvas');
    return c && c.width >= 1024;
  },
  { timeout: 30000 }
);
log('LOGIN_UI_READY');
await page.screenshot({ path: `${OUTDIR}/01-login-ui.png` });

// The game canvas is interactive. "Click here to login" text is at roughly (512, 620)
// based on the previous screenshot at viewport 1024x768. We click the canvas at that spot.
const canvas = page.locator('#canvas');
const box = await canvas.boundingBox();
log('CANVAS_BOX', JSON.stringify(box));

// Click "Click here to login" — it's the button in the middle
const clickX = box.x + box.width / 2;
const clickY = box.y + box.height * 0.81; // roughly where the button is
log('CLICKING', `at (${clickX}, ${clickY})`);
await page.mouse.click(clickX, clickY);
await page.waitForTimeout(2000);
await page.screenshot({ path: `${OUTDIR}/02-after-click.png` });

// Wait another 10s to see any WS activity
await page.waitForTimeout(10000);
await page.screenshot({ path: `${OUTDIR}/03-final.png` });

// Final summary
console.log('\n=== SUMMARY ===');
console.log(`Console lines:      ${consoleLines.length}`);
console.log(`WS events:          ${wsEvents.length}`);
console.log(`WS opens:           ${wsEvents.filter(e => e.kind === 'open').length}`);
console.log(`WS frames sent:     ${wsEvents.filter(e => e.kind === 'send').length}`);
console.log(`WS frames received: ${wsEvents.filter(e => e.kind === 'recv').length}`);
console.log(`WS closes:          ${wsEvents.filter(e => e.kind === 'close').length}`);
console.log(`WS errors:          ${wsEvents.filter(e => e.kind === 'error').length}`);
console.log(`Output dir:         ${OUTDIR}`);

fs.writeFileSync(`${OUTDIR}/console.log`, consoleLines.join('\n'));
fs.writeFileSync(`${OUTDIR}/ws-events.json`, JSON.stringify(wsEvents, null, 2));
await browser.close();
