import { loginWithCanvas, runScenario } from '../lib/harness.mjs';

await runScenario('01-login', async session => {
  await session.goto();
  await loginWithCanvas(session);
});
