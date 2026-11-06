// Gesture probe: drags, long-presses and double-clicks the gesture fixture, then pinches the
// pinch fixture (served from Examples/Gallery on 8767) and checks the labels through the
// semantics overlay.
//   node gesture-probe.mjs http://127.0.0.1:8767/index.html
import { chromium } from 'playwright';

const url = process.argv[2] || 'http://127.0.0.1:8767/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 2, hasTouch: true });
page.on('pageerror', e => console.error('page error', e));
await page.goto(`${url}?fixture=${encodeURIComponent('gesture/basic')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);
const labels = () => page.evaluate(() => window.__swiftuiwebDebug.semantics().map(n => n.label));
const canvas = await page.locator('canvas').first().boundingBox();
const probe = async (name) => {
  const frames = await page.evaluate(() => window.__swiftuiwebProbes || null);
  return frames && frames[name];
};
let failures = 0;
// Polls until the semantics hold `label` (a CI runner can take more than one frame to update).
const hasMatch = (source, ms = 3000) => page.waitForFunction(r => window.__swiftuiwebDebug.semantics().some(n => new RegExp(r).test(n.label)), source, { timeout: ms, polling: 50 }).then(() => true, () => false);
const hasLabel = (label, ms = 3000) => page.waitForFunction(l => window.__swiftuiwebDebug.semantics().some(n => n.label === l), label, { timeout: ms, polling: 50 }).then(() => true, () => false);
const check = async (name, ok) => { console.log((ok ? 'PASS ' : 'FAIL ') + name); if (!ok) { failures++; console.log('  labels:', (await labels()).join(' | ')); } };
// Boxes are laid out below their labels: use the label's overlay element to find each box.
const below = async (label, dy) => { const b = await page.locator(`[aria-label="${label}"]`).boundingBox(); return { x: b.x + b.width / 2, y: b.y + b.height + dy }; };

const drag = await below('Drag the box', 14 + 25);
await page.mouse.move(drag.x, drag.y);
await page.mouse.down();
await page.mouse.move(drag.x + 30, drag.y + 10, { steps: 5 });
await page.waitForTimeout(100);
await check('drag reports its translation', await hasMatch('^Dragging 3\\d, 1\\d$'));
await page.mouse.up();
await page.waitForTimeout(100);
await check('drag ends', await hasLabel('Drag the box'));

const press = await below('Long presses: 0', 14 + 20);
await page.mouse.move(press.x, press.y);
await page.mouse.down();
await page.waitForTimeout(150);
await check('pressing reported', await hasLabel('Pressing', 400));
await page.waitForTimeout(700);
await page.mouse.up();
await page.waitForTimeout(100);
await check('long press fires after the duration', await hasLabel('Long presses: 1'));

const tap = await below('Double taps: 0', 14 + 20);
await page.mouse.click(tap.x, tap.y, { clickCount: 1 });
await page.waitForTimeout(50);
await page.mouse.click(tap.x, tap.y, { clickCount: 2 });
await page.waitForTimeout(100);
await check('double tap counts', await hasLabel('Double taps: 1'));

const held = await below('Idle', 14 + 20);
await page.mouse.move(held.x, held.y);
await page.mouse.down();
// Held lasts until the long press succeeds at 0.3 s, which ends the gesture and resets the state.
await check('gesture state set while held', await hasLabel('Held', 280));
await check('gesture state resets when the press succeeds', await hasLabel('Idle'));
await page.mouse.up();

// Pinches (gesture/pinch): a control-wheel pinch (Chromium and Firefox), Safari-style gesture
// events, and two touches through the Chrome DevTools Protocol.
await page.goto(`${url}?fixture=${encodeURIComponent('gesture/pinch')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);
const pinchBox = await below('Scale 1.00, 0°', 14 + 35);
const canvasBox = await page.locator('canvas').first().boundingBox();
const wheelPinch = async (deltaY) => page.evaluate(([x, y, deltaY]) => {
  const canvas = document.querySelector('canvas');
  canvas.dispatchEvent(new WheelEvent('wheel', { deltaY, ctrlKey: true, clientX: x, clientY: y, bubbles: true, cancelable: true }));
}, [pinchBox.x, pinchBox.y, deltaY]);
for (let i = 0; i < 3; i++) { await wheelPinch(-20); await page.waitForTimeout(30); }
// Three steps of e^0.2 compound to 1.82 (until the pinch ends after a pause).
await check('control-wheel pinch magnifies', await hasLabel('Scale 1.82, 0°', 300));
await check('the wheel pinch ends after a pause', await hasLabel('Scale 1.00, 0°'));

const gestureEvent = async (type, scale, rotation) => page.evaluate(([type, x, y, scale, rotation]) => {
  const canvas = document.querySelector('canvas');
  const event = new Event(type, { bubbles: true, cancelable: true });
  Object.assign(event, { scale, rotation, clientX: x, clientY: y });
  canvas.dispatchEvent(event);
}, [type, pinchBox.x, pinchBox.y, scale, rotation]);
await gestureEvent('gesturestart', 1, 0);
await gestureEvent('gesturechange', 1.5, 30);
await page.waitForTimeout(100);
await check('gesture events scale and rotate', await hasLabel('Scale 1.50, 30°'));
await gestureEvent('gestureend', 1.5, 30);
await page.waitForFunction(() => window.__swiftuiwebDebug.semantics().some(n => n.label === 'Scale 1.00, 0°'), null, { timeout: 1000 }).catch(() => {});
await check('gesture end resets', (await labels()).includes('Scale 1.00, 0°'));

const stateBox = await below('Rest', 14 + 20);
const touch = await page.context().newCDPSession(page);
const touchPoints = (spread) => [{ x: stateBox.x - spread, y: stateBox.y }, { x: stateBox.x + spread, y: stateBox.y }];
await touch.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: touchPoints(20) });
await touch.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: touchPoints(30) });
await page.waitForTimeout(100);
await check('two touches pinch and set the gesture state', await hasLabel('Pinching'));
await touch.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
await page.waitForTimeout(100);
await check('lifting the touches resets the gesture state', await hasLabel('Rest'));
await browser.close();
console.log(failures === 0 ? 'gesture probe: all passed' : `gesture probe: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
