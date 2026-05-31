import fs from 'node:fs/promises';
import path from 'node:path';

const base = process.env.EVEN_CODEX_SIMULATOR_BASE || 'http://127.0.0.1:9898';
const repoRoot = process.cwd();
const outputDir = path.join(repoRoot, 'even-hub', 'assets', 'screenshots');

await ensureSimulator();
await fs.mkdir(outputDir, { recursive: true });

await writeImage('/api/screenshot/glasses', 'glasses.png');
await writeImage('/api/screenshot/webview', 'webview.png');

console.log(`Captured Even Hub screenshots from evenhub-simulator automation-port at ${base}`);

async function ensureSimulator() {
  const response = await fetch(`${base}/api/ping`);
  if (!response.ok) {
    throw new Error(`Simulator ping failed: ${response.status}`);
  }
}

async function writeImage(endpoint, filename) {
  const response = await fetch(`${base}${endpoint}`);
  if (!response.ok) {
    throw new Error(`${endpoint} failed with status ${response.status}`);
  }

  const data = Buffer.from(await response.arrayBuffer());
  await fs.writeFile(path.join(outputDir, filename), data);
}
