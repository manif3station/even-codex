import fs from 'node:fs/promises';
import path from 'node:path';

const repoRoot = process.cwd();
const sourceManifestPath = path.join(repoRoot, 'app.json');
const generatedDir = path.join(repoRoot, '.even-hub-build');
const generatedManifestPath = path.join(generatedDir, 'app.json');
const bridgeOrigin = normalizeOrigin(
  process.env.EVEN_CODEX_HUB_ORIGIN || 'https://192.168.1.20:7890/ajax/even-codex',
);

const manifest = JSON.parse(await fs.readFile(sourceManifestPath, 'utf8'));
manifest.permissions = (manifest.permissions || []).map((permission) => {
  if (permission.name !== 'network') {
    return permission;
  }

  return {
    ...permission,
    whitelist: [bridgeOrigin],
  };
});

await fs.rm(generatedDir, { recursive: true, force: true });
await fs.mkdir(generatedDir, { recursive: true });
await fs.writeFile(generatedManifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

function normalizeOrigin(value) {
  let parsed;

  try {
    parsed = new URL(value);
  } catch (error) {
    throw new Error(`EVEN_CODEX_HUB_ORIGIN must be a full http or https origin: ${value}`);
  }

  if (!/^https?:$/.test(parsed.protocol)) {
    throw new Error(`EVEN_CODEX_HUB_ORIGIN must use http or https: ${value}`);
  }

  return parsed.origin;
}
