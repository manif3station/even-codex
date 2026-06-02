import fs from 'node:fs/promises';
import path from 'node:path';

const repoRoot = process.cwd();
const distAssets = path.join(repoRoot, 'dist', 'assets');
const jsSource = path.join(distAssets, 'even-hub-app.js');
const cssSource = path.join(distAssets, 'even-hub-app.css');
const jsDest = path.join(repoRoot, 'dashboards', 'public', 'js', 'even-hub-app.js');
const cssDest = path.join(repoRoot, 'dashboards', 'public', 'css', 'even-hub-app.css');

await fs.mkdir(path.dirname(jsDest), { recursive: true });
await fs.mkdir(path.dirname(cssDest), { recursive: true });
await fs.copyFile(jsSource, jsDest);
await fs.copyFile(cssSource, cssDest);
