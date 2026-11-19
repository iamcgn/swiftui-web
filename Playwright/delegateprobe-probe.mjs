// Scratch probe (not for merging): loads DelegateProbe and prints what its main printed.
import { chromium } from 'playwright';
const url = process.argv[2];
const browser = await chromium.launch();
const page = await browser.newPage();
const lines = [];
page.on('console', message => lines.push(`${message.type()}: ${message.text()}`));
page.on('pageerror', error => lines.push(`pageerror: ${error.message}`));
await page.goto(url);
const deadline = Date.now() + 60000;
while (Date.now() < deadline && !lines.some(l => l.includes('probe done') || l.startsWith('pageerror'))) await page.waitForTimeout(500);
console.log(lines.join('\n'));
await browser.close();
process.exit(lines.some(l => l.includes('probe done')) ? 0 : 1);
