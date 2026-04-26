const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 900, height: 700 },
  });
  const page = await context.newPage();

  const logs = [];
  const pageErrors = [];

  page.on('console', (msg) => logs.push(`[${msg.type()}] ${msg.text()}`));
  page.on('pageerror', (err) => pageErrors.push(`${err.name}: ${err.message}`));

  console.log('>>> Navigating...');
  await page.goto('http://10.8.0.1:8500/', { waitUntil: 'networkidle', timeout: 30000 });
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

  // State 0: click "Existing User" at canvas (462, 291) — bounds 387-537 x 271-311
  console.log('>>> Click Existing User');
  await canvasClick(462, 291);
  await page.waitForTimeout(1000);
  await page.screenshot({ path: '/tmp/playwright-2009scape/01-login-form.png' });

  // State 2: default anInt977=0 (username active). Type directly.
  // Canvas needs focus for keyboard events.
  await canvas.focus();
  await page.keyboard.type('playtest2', { delay: 60 });
  await page.waitForTimeout(300);
  // Enter advances to password field (anInt977=1)
  await page.keyboard.press('Enter');
  await page.waitForTimeout(300);
  await page.keyboard.type('playtest2', { delay: 60 });
  await page.waitForTimeout(300);
  await page.screenshot({ path: '/tmp/playwright-2009scape/02-creds-entered.png' });

  // Click Login button — center (302, 321), bounds 227-377 x 301-341
  console.log('>>> Click Login button');
  await canvasClick(302, 321);
  console.log('>>> Waiting 15s for handshake...');
  await page.waitForTimeout(15000);
  await page.screenshot({ path: '/tmp/playwright-2009scape/03-in-game.png' });

  // Try a cheat command
  console.log('>>> Type ::players');
  await canvas.focus();
  await page.keyboard.type('::players', { delay: 40 });
  await page.waitForTimeout(300);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(3000);
  await page.screenshot({ path: '/tmp/playwright-2009scape/04-after-cmd.png' });

  // Stability observation
  console.log('>>> Observing 45s for stability...');
  await page.waitForTimeout(45000);
  await page.screenshot({ path: '/tmp/playwright-2009scape/05-final.png' });

  console.log('\n===== CONSOLE (' + logs.length + ') =====');
  for (const l of logs) console.log(l);
  console.log('\n===== PAGE ERRORS (' + pageErrors.length + ') =====');
  for (const e of pageErrors) console.log(e);

  await browser.close();
})().catch((err) => {
  console.error('FATAL:', err);
  process.exit(1);
});
