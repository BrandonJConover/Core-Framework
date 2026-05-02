import { clickCanvasAt, loginWithCanvas, runScenario, waitForOutboundAfter } from '../lib/harness.mjs';

await runScenario('03-drop-item', async session => {
  await session.goto();
  await loginWithCanvas(session);

  // Open the inventory tab and use the first slot's context menu. The default
  // test account is expected to carry at least one disposable item.
  const sentBefore = session.events.filter(e => e.kind === 'WS_SEND').length;
  await clickCanvasAt(session, 720, 170);
  await session.page.waitForTimeout(500);
  await clickCanvasAt(session, 590, 232);
  await session.page.waitForTimeout(500);
  await clickCanvasAt(session, 590, 282);
  await waitForOutboundAfter(session, sentBefore, 15000);
  await session.screenshot('after-drop-attempt');
});
