// Compares two directories of screenshots of the same renders (Tier B's, or a probe's): the
// Canvas2D painter's and the WebGL painter's. For each PNG in both, the share of pixels whose
// channels differ by more than 32 (Tier B's test) and the mean channel difference; the worst
// renders get a side-by-side (2D | WebGL | difference) in the output directory.
//   node diff.mjs <2d dir> <webgl dir> [--out dir] [--worst 12] [--json summary.json]
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync } from 'node:fs';
import { join, basename } from 'node:path';
import { PNG } from 'pngjs';
const args = process.argv.slice(2);
const [a, b] = args.filter(x => !x.startsWith('--'));
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const out = opt('--out', null), worstN = Number(opt('--worst', 12)), jsonPath = opt('--json', null);
const walk = (dir, pre = '') => readdirSync(join(dir, pre), { withFileTypes: true }).flatMap(e => e.isDirectory() ? walk(dir, join(pre, e.name)) : (e.name.endsWith('.png') && !e.name.endsWith('.diff.png') ? [join(pre, e.name)] : []));
const rows = [];
for (const file of walk(a)) {
  if (!existsSync(join(b, file))) { rows.push({ file, missing: true }); continue; }
  const p = PNG.sync.read(readFileSync(join(a, file))), q = PNG.sync.read(readFileSync(join(b, file)));
  if (p.width !== q.width || p.height !== q.height) { rows.push({ file, size: `${p.width}x${p.height} vs ${q.width}x${q.height}`, share: 1, mean: 255 }); continue; }
  let over = 0, sum = 0, max = 0;
  const d = new PNG({ width: p.width, height: p.height });
  for (let i = 0; i < p.data.length; i += 4) {
    let m = 0;
    for (let c = 0; c < 4; c++) { const v = Math.abs(p.data[i + c] - q.data[i + c]); sum += v; if (v > m) m = v; }
    if (m > max) max = m;
    if (m > 32) over++;
    const g = Math.min(255, m * 4);
    d.data[i] = g; d.data[i + 1] = m > 32 ? 0 : g; d.data[i + 2] = m > 32 ? 0 : g; d.data[i + 3] = 255;
  }
  rows.push({ file, share: over / (p.width * p.height), mean: sum / p.data.length, max, w: p.width, h: p.height, p, q, d });
}
const ok = rows.filter(r => !r.missing);
ok.sort((x, y) => y.share - x.share);
const pct = v => (v * 100).toFixed(2) + '%';
const within = t => ok.filter(r => r.share <= t).length;
console.log(`${ok.length} renders compared (${rows.length - ok.length} missing in the WebGL run)`);
console.log(`identical: ${ok.filter(r => r.max === 0).length}; within 0.5%: ${within(0.005)}; within 3% (Tier B's tolerance): ${within(0.03)}; over 3%: ${ok.length - within(0.03)}`);
const means = ok.map(r => r.share).sort((x, y) => x - y);
if (means.length) console.log(`differing pixels: median ${pct(means[Math.floor(means.length / 2)])}, p90 ${pct(means[Math.floor(means.length * 0.9)])}, worst ${pct(means[means.length - 1])}`);
console.log('worst renders:');
for (const r of ok.slice(0, worstN)) console.log(`  ${pct(r.share).padStart(7)}  mean ${r.mean.toFixed(2)}  max ${r.max}  ${r.file}${r.size ? ' size ' + r.size : ''}`);
for (const r of rows.filter(r => r.missing)) console.log(`  missing ${r.file}`);
if (out) {
  mkdirSync(out, { recursive: true });
  for (const r of ok.slice(0, worstN)) {
    if (!r.p) continue;
    const s = new PNG({ width: r.w * 3, height: r.h });
    for (let y = 0; y < r.h; y++) for (const [k, img] of [r.p, r.q, r.d].entries()) {
      img.data.copy(s.data, (y * r.w * 3 + k * r.w) * 4, y * r.w * 4, (y + 1) * r.w * 4);
    }
    writeFileSync(join(out, basename(r.file).replace(/\.png$/, '') + '.side.png'), PNG.sync.write(s));
  }
}
if (jsonPath) writeFileSync(jsonPath, JSON.stringify(rows.map(({ p, q, d, ...r }) => r), null, 2));
