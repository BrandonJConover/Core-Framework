import { clickCanvasAt, loginWithCanvas, runScenario, waitForOutboundAfter } from '../lib/harness.mjs';

await runScenario('02-walk', async session => {
  await session.goto();
  await loginWithCanvas(session);

  const sentBefore = session.events.filter(e => e.kind === 'WS_SEND').length;
  await clickCanvasAt(session, 382, 252);
  await waitForOutboundAfter(session, sentBefore, 15000);
  await session.screenshot('after-walk-click');
});
