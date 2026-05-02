import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const scenarioDir = path.join(root, 'scenarios');
const files = fs
  .readdirSync(scenarioDir)
  .filter(file => /^\d+.*\.mjs$/.test(file))
  .sort();

if (process.argv.includes('--list')) {
  for (const file of files) console.log(file);
  process.exit(0);
}

if (files.length === 0) {
  console.error('No scenarios found in', scenarioDir);
  process.exit(1);
}

for (const file of files) {
  console.log(`\n=== running ${file} ===`);
  const result = spawnSync(process.execPath, [path.join(scenarioDir, file)], {
    stdio: 'inherit',
    env: process.env,
  });
  if (result.status !== 0) {
    console.error(`\nFAIL: ${file}`);
    process.exit(result.status || 1);
  }
}

console.log(`\nALL ${files.length} SCENARIOS PASS`);
