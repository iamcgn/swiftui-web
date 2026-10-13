// A controllable local fixture server for the URLSession checks (pf-urlsession): GET /slow?ms=N
// sends the headers at once and the body after N ms (a timeout or a cancellation while the body
// is being read), GET /fixtures/<file> serves Examples/Launches/fixtures. Every response carries
// Access-Control-Allow-Origin: * so the page may call it from another port; nothing else is
// served, nothing leaves 127.0.0.1.
//   node fixture-server.mjs 8777
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const port = Number(process.argv[2] || 8777);
const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'Examples', 'Launches', 'fixtures');
createServer((req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', '*');
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }
  if (url.pathname === '/slow') {
    const ms = Number(url.searchParams.get('ms') || 1000);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.write('{"slow":');                      // the headers and the first bytes go now…
    const timer = setTimeout(() => { res.end('true}'); }, ms);   // …the rest after `ms`
    req.on('close', () => clearTimeout(timer));
    return;
  }
  if (url.pathname.startsWith('/fixtures/')) {
    try { const body = readFileSync(join(root, url.pathname.slice('/fixtures/'.length))); res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(body); }
    catch { res.writeHead(404, { 'Content-Type': 'text/plain' }); res.end('not found'); }
    return;
  }
  res.writeHead(404); res.end();
}).listen(port, '127.0.0.1', () => console.log(`fixture server on ${port}`));
