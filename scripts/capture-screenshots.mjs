// Captures the README screenshots from the REAL application (release web build + real backend, synthetic data only).
// No extra installs: Node >= 22 drives the installed Chrome through the DevTools Protocol.
//
// Run: scripts\capture-screenshots.ps1   (builds jar + web bundle, then runs this file)
// Env: E2E_BACKEND_JAR, E2E_WEB_DIR (flutter build output), CHROME_BIN, SHOT_API_PORT (18082), SHOT_WEB_PORT (18083), SHOT_OUT (docs/screenshots)
import { spawn } from 'node:child_process';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const JAR = process.env.E2E_BACKEND_JAR;
const WEB_DIR = process.env.E2E_WEB_DIR;
const CHROME = process.env.CHROME_BIN || (process.platform === 'win32' ? 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe' : 'google-chrome');
const API_PORT = Number(process.env.SHOT_API_PORT || 18082);
const WEB_PORT = Number(process.env.SHOT_WEB_PORT || 18083);
const CDP_PORT = Number(process.env.SHOT_CDP_PORT || 9444);
const OUT = path.resolve(process.env.SHOT_OUT || 'docs/screenshots');
const API = `http://localhost:${API_PORT}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let backend, web, chrome, cdp;

async function startBackend() {
  backend = spawn(process.env.JAVA_BIN || 'java', ['-jar', JAR, `--server.port=${API_PORT}`], { stdio: 'ignore' });
  for (let i = 0; i < 90; i++) {
    try { if ((await fetch(`${API}/api/rooms`)).ok) return; } catch { /* starting */ }
    await sleep(1000);
  }
  throw new Error('backend did not start');
}

function startWeb() {
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.otf': 'font/otf', '.ttf': 'font/ttf' };
  web = http.createServer((req, res) => {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (p === '/') p = '/index.html';
    const file = path.join(path.resolve(WEB_DIR), p);
    if (!file.startsWith(path.resolve(WEB_DIR)) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((r) => web.listen(WEB_PORT, r));
}

async function startChrome() {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'praxis-shot-chrome-'));
  chrome = spawn(CHROME, ['--headless=new', `--remote-debugging-port=${CDP_PORT}`, `--user-data-dir=${profile}`, '--no-first-run',
    '--use-angle=swiftshader', '--enable-unsafe-swiftshader', ...(process.env.CI ? ['--no-sandbox'] : []), 'about:blank'], { stdio: 'ignore' });
  let target;
  for (let i = 0; i < 40 && !target; i++) {
    try { target = (await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/list`)).json()).find((t) => t.type === 'page'); } catch { /* starting */ }
    if (!target) await sleep(500);
  }
  if (!target) throw new Error('chrome did not start');
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let id = 0;
  const pending = new Map();
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (msg.id && pending.has(msg.id)) { const { resolve, reject } = pending.get(msg.id); pending.delete(msg.id); msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result); }
  };
  cdp = (method, params = {}) => new Promise((resolve, reject) => { const i = ++id; pending.set(i, { resolve, reject }); ws.send(JSON.stringify({ id: i, method, params })); });
  await cdp('Runtime.enable');
  await cdp('Page.enable');
  await cdp('Emulation.setFocusEmulationEnabled', { enabled: true });
}

// Embeds a value into evaluated page code as a URI-encoded literal: only [A-Za-z0-9%-_.!~*()] ends up in the code
// string (the single quote is escaped too), so test data can never break out of the literal.
const lit = (v) => `JSON.parse(decodeURIComponent('${encodeURIComponent(JSON.stringify(v)).replace(/'/g, '%27')}'))`;
const OWN = `const own=e=>([...e.childNodes].filter(n=>n.nodeType===3||(n.nodeType===1&&n.tagName.toLowerCase()!=='flt-semantics')).map(n=>n.textContent).join('')||e.getAttribute('aria-label')||'').replace(/\\s+/g,' ').trim();`;
const evalJs = async (expr) => (await cdp('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true })).result.value;

async function waitFor(fn, what, timeout = 30000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) { try { const v = await fn(); if (v) return v; } catch { /* retry */ } await sleep(200); }
  throw new Error(`timeout: ${what}`);
}
const texts = () => evalJs(`(()=>{${OWN} return [...document.querySelectorAll('flt-semantics')].map(own).filter(Boolean);})()`);
const waitText = (s) => waitFor(async () => (await texts()).some((t) => t.includes(s)), `text ${s}`);

async function click(sub, exact = false) {
  const r = await waitFor(() => evalJs(`(()=>{${OWN} const m=[...document.querySelectorAll('flt-semantics')].filter(e=>${exact ? 'true' : 'false'}?own(e)===${lit(sub)}:own(e).includes(${lit(sub)})); const e=m[0]; if(!e) return null; const r=e.getBoundingClientRect(); return r.width>0?{x:r.x+r.width/2,y:r.y+r.height/2}:null;})()`), `element ${sub}`);
  for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) {
    await cdp('Input.dispatchMouseEvent', { type, x: r.x, y: r.y, button: 'left', clickCount: 1 });
  }
}

async function shot(name, clip) {
  await sleep(700); // let animations settle
  const params = { format: 'png', captureBeyondViewport: false };
  if (clip) params.clip = { ...clip, scale: 1 };
  const { data } = await cdp('Page.captureScreenshot', params);
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, name), Buffer.from(data, 'base64'));
  console.log('  wrote', path.join('docs/screenshots', name));
}

const api = (method, p, body) => fetch(`${API}${p}`, { method, headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined }).then((r) => (r.status === 204 ? null : r.json()));
const viewport = (width, height) => cdp('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });

async function seed() {
  // synthetic demo data only
  await api('POST', '/api/patients', { name: 'Alex Beispiel', urgency: 'CRITICAL' });
  const robin = await api('POST', '/api/patients', { name: 'Robin Muster', urgency: 'HIGH' });
  await api('POST', '/api/patients', { name: 'Sam Testfall', urgency: 'HIGH' });
  await api('POST', '/api/patients', { name: 'Kim Probe', urgency: 'MEDIUM' });
  await api('POST', '/api/patients', { name: 'Noa Demo', urgency: 'LOW' });
  await api('POST', '/api/patients', { name: 'Eli Platzhalter', urgency: 'LOW' });
  await api('POST', '/api/rooms/room-2/assign', { patientId: robin.id });
  await api('POST', '/api/rooms/room-2/complete-treatment'); // -> CLEANING
  const jules = await api('POST', '/api/patients', { name: 'Jules Beispiel', urgency: 'MEDIUM' });
  await api('POST', '/api/rooms/room-1/assign', { patientId: jules.id }); // -> OCCUPIED (Alex stays CRITICAL in the queue)
}

async function openApp(w, h) {
  await viewport(w, h);
  await cdp('Page.navigate', { url: `http://localhost:${WEB_PORT}/` });
  await waitFor(async () => {
    await evalJs(`(()=>{const p=document.querySelector('flt-semantics-placeholder'); if(p) p.dispatchEvent(new MouseEvent('click',{bubbles:true}));})()`);
    return (await evalJs(`document.querySelectorAll('flt-semantics').length`)) > 0;
  }, 'semantics', 60000);
  await waitText('Live verbunden');
}

async function main() {
  if (!JAR || !WEB_DIR) throw new Error('set E2E_BACKEND_JAR and E2E_WEB_DIR (use scripts/capture-screenshots.ps1)');
  await startBackend();
  await startWeb();
  await startChrome();
  await seed();

  console.log('Capturing screenshots (wide) ...');
  await openApp(1280, 900);
  await waitText('Raum 2 Status: Reinigung');
  await shot('dashboard.png');
  await shot('queue-urgency-levels.png', { x: 0, y: 56, width: 770, height: 844 });
  await shot('rooms.png', { x: 770, y: 56, width: 510, height: 844 });

  await click('Aufrufen', false); // first queue entry (the CRITICAL patient)
  await waitText('Raum wählen');
  await shot('assign-room-dialog.png');
  await cdp('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 });
  await cdp('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 });

  console.log('Capturing screenshots (responsive) ...');
  await openApp(390, 844);
  await shot('responsive-mobile-queue.png');
  await click('Räume', true).catch(() => click('Räume'));
  await waitText('Raum 1 Status');
  await shot('responsive-mobile-rooms.png');

  console.log('Capturing screenshot (connection lost) ...');
  await openApp(1280, 800);
  backend.kill();
  await waitText('Echtzeit-Verbindung: Getrennt');
  await shot('connection-lost.png', { x: 0, y: 0, width: 1280, height: 330 });
}

let code = 0;
try { await main(); } catch (e) { console.error('Screenshot run failed:', e.message); code = 1; }
finally {
  try { await cdp?.('Browser.close'); } catch { /* ignore */ }
  chrome?.kill();
  web?.close();
  backend?.kill();
}
process.exit(code);
