// A wasm file's size without its custom sections (names, DWARF): the Linux builds here run no
// wasm-opt, so their raw files carry debug sections the shipped bundle does not. Prints raw,
// stripped, and stripped brotli (quality 11), the measure of the decision 0006 budget.
//   node wasm-size.mjs <file.wasm>...
import { readFileSync } from 'node:fs';
import { brotliCompressSync, constants } from 'node:zlib';
for (const path of process.argv.slice(2)) {
  const b = readFileSync(path);
  const parts = [b.subarray(0, 8)];
  let i = 8;
  const leb = () => { let r = 0, s = 0, x; do { x = b[i++]; r |= (x & 0x7f) << s; s += 7; } while (x & 0x80); return r >>> 0; };
  while (i < b.length) {
    const start = i, id = b[i++], size = leb(), end = i + size;
    if (id !== 0) parts.push(b.subarray(start, end));
    i = end;
  }
  const stripped = Buffer.concat(parts);
  const br = brotliCompressSync(stripped, { params: { [constants.BROTLI_PARAM_QUALITY]: 11, [constants.BROTLI_PARAM_SIZE_HINT]: stripped.length } }).length;
  console.log(`${path.split('/')[1] || path}: raw ${b.length}, without custom sections ${stripped.length}, brotli ${br}`);
}
