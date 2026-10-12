// UIKit drag and drop probe (uk-dragdrop), on uikit/events/dragdrop served from Examples/Gallery
// on 8767: a mouse press and 4 pt of travel on the card lift its `UIDragInteraction` items; the
// well's `UIDropInteraction` turns green while the session is over it and shows the dropped
// text; the same session crosses the app boundary through the browser's DragEvents (the
// DataTransfer carries text/plain "Drag me"), and a drag from outside drops the same way.
//   node uikit-dragdrop-probe.mjs http://127.0.0.1:8767/index.html
import { chromium } from 'playwright';

const url = process.argv[2] || 'http://127.0.0.1:8767/index.html';
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 2 });
const page = await context.newPage();
page.on('pageerror', e => console.error('page error', e));
await page.goto(`${url}?fixture=${encodeURIComponent('uikit/events/dragdrop')}`);
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
const wellIsGreen = async () => (await list()).some(c => c.startsWith('fillRRect(20, 120, 280, 120)') && c.includes('#34C759'));
const wellIsBlue = async () => (await list()).some(c => c.startsWith('fillRRect(20, 120, 280, 120)') && c.includes('#0088FF'));
const statusText = async () => (await list()).filter(c => c.startsWith('drawText(')).map(c => c.slice(10, c.indexOf('"', 10))).find(t => t.startsWith('Dropped') || t.startsWith('Nothing'));
const drag = (type, x, y, transferName) => page.evaluate(({ type, x, y, transferName }) => {
  const canvas = document.querySelector('canvas');
  window.__transfers = window.__transfers || {};
  if (!window.__transfers[transferName]) window.__transfers[transferName] = new DataTransfer();
  const event = new DragEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, dataTransfer: window.__transfers[transferName] });
  return !canvas.dispatchEvent(event);
}, { type, x, y, transferName });
const transferData = (transferName, type) => page.evaluate(({ transferName, type }) => window.__transfers[transferName].getData(type), { transferName, type });
const setTransfer = (transferName, type, text) => page.evaluate(({ transferName, type, text }) => {
  window.__transfers = window.__transfers || {};
  window.__transfers[transferName] = new DataTransfer();
  window.__transfers[transferName].setData(type, text);
}, { transferName, type, text });

check('the well starts blue', await wellIsBlue());
check('the status says nothing was dropped', (await statusText()) === 'Nothing dropped');
// 1. A mouse drag from the card to the well.
await page.mouse.move(sourceX, sourceY);
await page.mouse.down();
await page.mouse.move(sourceX + 6, sourceY, { steps: 2 });
await page.waitForTimeout(50);
check('a press on the card makes the canvas draggable', await page.evaluate(() => document.querySelector('canvas').draggable));
await page.mouse.move(targetX, targetY, { steps: 4 });
await page.waitForTimeout(100);
check('the well turns green while the drag is over it', await wellIsGreen());
// (Chromium starts its own drag from the draggable canvas, so the scene paints no preview of
// its own here; the pointer-driven preview is covered by HostedDragDropTests natively.)
await page.mouse.up();
await page.waitForTimeout(100);
check('the drop shows the text', (await statusText()) === 'Dropped: Drag me');
check('the well is blue again', await wellIsBlue());
// 2. The same through the browser's system drag.
await page.mouse.move(sourceX, sourceY);
await page.mouse.down();
await page.mouse.move(sourceX + 2, sourceY);
const startPrevented = await drag('dragstart', sourceX + 2, sourceY, 'own');
check('dragstart is not prevented (the scene has items)', !startPrevented);
check('the DataTransfer carries the text', (await transferData('own', 'text/plain')) === 'Drag me');
check('dragover over the well is accepted', await drag('dragover', targetX, targetY, 'own'));
await page.waitForTimeout(50);
check('the well turns green for the system drag', await wellIsGreen());
await drag('drop', targetX, targetY, 'own');
await drag('dragend', targetX, targetY, 'own');
await page.mouse.up();
await page.waitForTimeout(100);
check('the system drop delivers the text', (await statusText()) === 'Dropped: Drag me');
check('the canvas is no longer draggable', !(await page.evaluate(() => document.querySelector('canvas').draggable)));
// 3. A drag from outside the page, and one of a type the well refuses.
await setTransfer('outside', 'text/plain', 'From outside');
check('an outside dragover is accepted', await drag('dragover', targetX, targetY, 'outside'));
await page.waitForTimeout(50);
check('the well turns green for it', await wellIsGreen());
await drag('drop', targetX, targetY, 'outside');
await page.waitForTimeout(100);
check('its text is dropped', (await statusText()) === 'Dropped: From outside');
await setTransfer('png', 'image/png', 'iVBORw0KGgo=');
check('a PNG drag is refused over the well', !(await drag('dragover', targetX, targetY, 'png')));
await drag('dragleave', targetX, targetY, 'png');
await browser.close();
console.log(failures === 0 ? 'uikit dragdrop probe: all passed' : `uikit dragdrop probe: ${failures} failure(s)`);
process.exit(failures === 0 ? 0 : 1);
