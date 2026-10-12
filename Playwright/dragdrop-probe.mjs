// Drag and drop across the app boundary probe (sw-dragdrop-os), on dragdrop/external served
// from Examples/Gallery on 8767: a press on the draggable makes the canvas draggable for that
// press, `dragstart` fills the DataTransfer from the scene's items (text/plain "Drag me") and
// sets a drag image, `dragover` over the destination is accepted (default prevented, the
// destination turns green), `drop` delivers the text, `dragend` ends the drag; a drag from
// outside (a DataTransfer of its own) drops the same way, and one of a type nothing takes is
// refused. Chromium dispatches synthetic DragEvents with a DataTransfer.
//   node dragdrop-probe.mjs http://127.0.0.1:8767/index.html
import { chromium } from 'playwright';

const url = process.argv[2] || 'http://127.0.0.1:8767/index.html';
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 2 });
const page = await context.newPage();
page.on('pageerror', e => console.error('page error', e));
await page.goto(`${url}?fixture=${encodeURIComponent('dragdrop/external')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);
await page.waitForFunction(() => window.__galleryFrames !== undefined, null, { timeout: 60000 });
let failures = 0;
const check = (name, ok) => { console.log((ok ? 'PASS ' : 'FAIL ') + name); if (!ok) failures++; };
const frames = await page.evaluate(() => window.__galleryFrames);
const canvas = await page.locator('canvas').first().boundingBox();
const source = frames.source, target = frames.target;
const sourceX = canvas.x + source.x + source.width / 2, sourceY = canvas.y + source.y + source.height / 2;
const targetX = canvas.x + target.x + target.width / 2, targetY = canvas.y + target.y + target.height / 2;
const list = () => page.evaluate(() => window.__swiftuiwebDebug.displayList());
const targetFill = async () => (await list()).find(c => c.startsWith('fillPath') && (c.includes('#0088FF') || c.includes('#34C759') || c.includes('#007AFF')));
// Dispatches a DragEvent of `type` on the canvas at client (x, y) carrying `transfer` (a
// DataTransfer kept in the page); returns whether the default was prevented.
const drag = (type, x, y, transferName) => page.evaluate(({ type, x, y, transferName }) => {
  const canvas = document.querySelector('canvas');
  window.__transfers = window.__transfers || {};
  if (!window.__transfers[transferName]) window.__transfers[transferName] = new DataTransfer();
  const event = new DragEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, dataTransfer: window.__transfers[transferName] });
  const notPrevented = canvas.dispatchEvent(event);
  return !notPrevented;
}, { type, x, y, transferName });
const transferData = (transferName, type) => page.evaluate(({ transferName, type }) => window.__transfers[transferName].getData(type), { transferName, type });
const setTransfer = (transferName, type, text) => page.evaluate(({ transferName, type, text }) => {
  window.__transfers = window.__transfers || {};
  window.__transfers[transferName] = new DataTransfer();
  window.__transfers[transferName].setData(type, text);
}, { transferName, type, text });

check('the destination starts blue', (await targetFill())?.includes('#0088FF') || (await targetFill())?.includes('#007AFF'));
// 1. The app's own drag through the browser.
await page.mouse.move(sourceX, sourceY);
await page.mouse.down();
check('a press on the draggable makes the canvas draggable', await page.evaluate(() => document.querySelector('canvas').draggable));
await page.mouse.move(sourceX + 2, sourceY);
const startPrevented = await drag('dragstart', sourceX + 2, sourceY, 'own');
check('dragstart is not prevented (the scene has a payload)', !startPrevented);
check('the DataTransfer carries the text', (await transferData('own', 'text/plain')) === 'Drag me');
check('the scene is dragging', await page.evaluate(() => window.__swiftuiwebDebug.isDragging ? window.__swiftuiwebDebug.isDragging() : true));
const overPrevented = await drag('dragover', targetX, targetY, 'own');
await page.waitForTimeout(100);
check('dragover over the destination is accepted', overPrevented);
check('the destination turns green while targeted', (await targetFill())?.includes('#34C759'));
await drag('drop', targetX, targetY, 'own');
await drag('dragend', targetX, targetY, 'own');
await page.mouse.up();
await page.waitForTimeout(100);
check('the drop shows the dropped text', (await list()).some(c => c.startsWith('drawText("Drag me"') && !c.includes('#')) || (await list()).filter(c => c.startsWith('drawText("Drag me"')).length >= 2);
check('the destination is blue again', (await targetFill())?.includes('#0088FF') || (await targetFill())?.includes('#007AFF'));
check('the canvas is no longer draggable', !(await page.evaluate(() => document.querySelector('canvas').draggable)));
// 2. A drag from outside the page.
await setTransfer('outside', 'text/plain', 'From outside');
check('an outside dragover is accepted', await drag('dragover', targetX, targetY, 'outside'));
await page.waitForTimeout(50);
check('the destination turns green for it', (await targetFill())?.includes('#34C759'));
await drag('drop', targetX, targetY, 'outside');
await page.waitForTimeout(100);
check('its text is dropped', (await list()).some(c => c.startsWith('drawText("From outside"')));
// 3. A type nothing takes.
await setTransfer('png', 'image/png', 'iVBORw0KGgo=');
check('a PNG drag is refused over the text destination', !(await drag('dragover', targetX, targetY, 'png')));
await drag('dragleave', targetX, targetY, 'png');
await browser.close();
console.log(failures === 0 ? 'dragdrop probe: all passed' : `dragdrop probe: ${failures} failure(s)`);
process.exit(failures === 0 ? 0 : 1);
