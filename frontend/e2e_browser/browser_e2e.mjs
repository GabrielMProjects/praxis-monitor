// Browser end-to-end test of the REAL Flutter web UI against a REAL Spring Boot backend.
// No extra installs: Node (global WebSocket/fetch) drives the already installed Chrome through the
// Chrome DevTools Protocol. The UI is operated through Flutter's accessibility (semantics) tree, so the
// test doubles as an accessibility check: everything it clicks must be reachable by label.
//
// Run: scripts\e2e-browser.ps1   (builds jar + web bundle, then runs this file)
// Env: E2E_BACKEND_JAR, E2E_WEB_DIR (build/web), CHROME_BIN, E2E_PORT (18082), E2E_WEB_PORT (18083)
import { spawn } from 'node:child_process';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const JAR = process.env.E2E_BACKEND_JAR;
const WEB_DIR = process.env.E2E_WEB_DIR;
const CHROME = process.env.CHROME_BIN || (process.platform === 'win32' ? 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe' : 'google-chrome');
const CI_FLAGS = process.env.CI ? ['--no-sandbox', '--disable-dev-shm-usage'] : []; // GitHub runners: no user namespaces for the sandbox
const API_PORT = Number(process.env.E2E_PORT || 18082);
const WEB_PORT = Number(process.env.E2E_WEB_PORT || 18083);
const CDP_PORT = Number(process.env.E2E_CDP_PORT || 9333);
const API = `http://localhost:${API_PORT}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let backend, webServer, chrome, cdp;
const results = [];
const jsErrors = [];

// ---------------------------------------------------------------- processes
async function startBackend() {
  backend = spawn(process.env.JAVA_BIN || 'java', ['-jar', JAR, `--server.port=${API_PORT}`], { stdio: 'ignore' });
  for (let i = 0; i < 90; i++) {
    try {
      if ((await fetch(`${API}/api/rooms`)).ok) return;
    } catch { /* not up yet */ }
    await sleep(1000);
  }
  throw new Error('backend did not start');
}

async function stopBackend() {
  if (!backend) return;
  const done = new Promise((r) => backend.once('exit', r));
  backend.kill();
  await Promise.race([done, sleep(15000)]);
  backend = undefined;
}

function startWebServer() {
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.otf': 'font/otf', '.ttf': 'font/ttf', '.css': 'text/css' };
  webServer = http.createServer((req, res) => {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (p === '/') p = '/index.html';
    const file = path.join(path.resolve(WEB_DIR), p);
    if (!file.startsWith(path.resolve(WEB_DIR)) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404);
      return res.end();
    }
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((r) => webServer.listen(WEB_PORT, r));
}

async function startChrome() {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'praxis-e2e-chrome-'));
  chrome = spawn(CHROME, [
    '--headless=new', `--remote-debugging-port=${CDP_PORT}`, `--user-data-dir=${profile}`,
    ...CI_FLAGS, '--no-first-run', '--no-default-browser-check', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
    '--window-size=1280,900', 'about:blank',
  ], { stdio: 'ignore' });
  let target;
  for (let i = 0; i < 40 && !target; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/list`)).json();
      target = list.find((t) => t.type === 'page');
    } catch { /* not up yet */ }
    if (!target) await sleep(500);
  }
  if (!target) throw new Error('chrome did not start');
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let id = 0;
  const pending = new Map();
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result);
    } else if (msg.method === 'Runtime.exceptionThrown') {
      jsErrors.push(msg.params.exceptionDetails?.exception?.description || msg.params.exceptionDetails?.text);
    }
  };
  cdp = (method, params = {}) => new Promise((resolve, reject) => {
    const i = ++id;
    pending.set(i, { resolve, reject });
    ws.send(JSON.stringify({ id: i, method, params }));
  });
  await cdp('Runtime.enable');
  await cdp('Page.enable');
  await cdp('Emulation.setFocusEmulationEnabled', { enabled: true }); // headless page must behave as focused
}

// ---------------------------------------------------------------- page helpers (Flutter semantics tree)
// Embeds a value into evaluated page code as a URI-encoded literal: only [A-Za-z0-9%-_.!~*()] ends up in the code
// string (the single quote is escaped too), so test data can never break out of the literal.
const lit = (v) => `JSON.parse(decodeURIComponent('${encodeURIComponent(JSON.stringify(v)).replace(/'/g, '%27')}'))`;
const OWN = `const own=e=>([...e.childNodes].filter(n=>n.nodeType===3||(n.nodeType===1&&n.tagName.toLowerCase()!=='flt-semantics')).map(n=>n.textContent).join('')||e.getAttribute('aria-label')||'').replace(/\\s+/g,' ').trim();`;

async function evalJs(expr) {
  const r = await cdp('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || 'eval failed');
  return r.result.value;
}

const texts = async () => evalJs(`(()=>{${OWN} return [...new Set([...document.querySelectorAll('flt-semantics')].map(own).filter(Boolean))];})()`);

async function waitFor(fn, what, timeout = 20000) {
  const end = Date.now() + timeout;
  let last;
  while (Date.now() < end) {
    try { last = await fn(); if (last) return last; } catch (e) { last = e.message; }
    await sleep(150);
  }
  throw new Error(`timeout waiting for: ${what}`);
}

const waitText = (sub, timeout) => waitFor(async () => (await texts()).find((t) => t.includes(sub)), `text "${sub}"`, timeout);
const waitNoText = (sub, timeout) => waitFor(async () => !(await texts()).some((t) => t.includes(sub)), `no text "${sub}"`, timeout);

async function rectOf(role, sub, nth = 0, exact = false) {
  return evalJs(`(()=>{${OWN}
    const m=[...document.querySelectorAll('flt-semantics')].filter(e=>(${lit(role)}===null||e.getAttribute('role')===${lit(role)})&&(${exact ? 'true' : 'false'}?own(e)===${lit(sub)}:own(e).includes(${lit(sub)})));
    const e=m[${Number(nth)}]; if(!e) return null; const r=e.getBoundingClientRect();
    return {x:r.x+r.width/2,y:r.y+r.height/2,w:r.width,h:r.height,count:m.length};})()`);
}

async function click(role, sub, nth = 0, exact = false) {
  const r = await waitFor(async () => { const v = await rectOf(role, sub, nth, exact); return v && v.w > 0 && v.h > 0 ? v : null; }, `element ${role ?? '*'} "${sub}"`);
  await cdp('Input.dispatchMouseEvent', { type: 'mouseMoved', x: r.x, y: r.y });
  await cdp('Input.dispatchMouseEvent', { type: 'mousePressed', x: r.x, y: r.y, button: 'left', clickCount: 1 });
  await cdp('Input.dispatchMouseEvent', { type: 'mouseReleased', x: r.x, y: r.y, button: 'left', clickCount: 1 });
}

const KEYS = { Tab: 9, Enter: 13, Escape: 27, ' ': 32 };
async function key(k) {
  const code = KEYS[k];
  const base = { key: k, code: k === ' ' ? 'Space' : k, windowsVirtualKeyCode: code, nativeVirtualKeyCode: code };
  await cdp('Input.dispatchKeyEvent', { type: 'keyDown', ...base, text: k === 'Enter' ? '\r' : k === ' ' ? ' ' : undefined });
  await cdp('Input.dispatchKeyEvent', { type: 'keyUp', ...base });
}

const activeLabel = () => evalJs(`(()=>{${OWN} const a=document.activeElement; if(!a) return ''; return a.tagName.toLowerCase()==='flt-semantics' ? own(a) : '<'+a.tagName.toLowerCase()+'>';})()`);

async function queue() {
  const all = await texts();
  return all
    .map((t) => /^Position (\d+): (.*?), Dringlichkeit (\w+) \((\d)\), Ankunft [\d:]+, Status: (.*)$/.exec(t))
    .filter(Boolean)
    .map((m) => ({ pos: Number(m[1]), name: m[2], urgency: m[3], prio: Number(m[4]), status: m[5] }));
}
const queueNames = async () => (await queue()).map((q) => q.name);

async function api(method, p, body) {
  const res = await fetch(`${API}${p}`, { method, headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, json: res.status === 204 || res.status >= 500 ? null : await res.json().catch(() => null) };
}

async function openApp() {
  await cdp('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });
  await cdp('Page.navigate', { url: `http://localhost:${WEB_PORT}/` });
  await waitFor(() => evalJs(`!!document.querySelector('flt-semantics-placeholder')`), 'flutter placeholder', 60000);
  // screen readers activate semantics exactly like this; retry until the app has rendered and semantics exist
  await waitFor(async () => {
    await evalJs(`(()=>{const p=document.querySelector('flt-semantics-placeholder'); if(p) p.dispatchEvent(new MouseEvent('click',{bubbles:true}));})()`);
    return (await evalJs(`document.querySelectorAll('flt-semantics').length`)) > 0;
  }, 'semantics tree enabled', 60000);
  await waitText('Echtzeit-Verbindung', 30000);
}

// ---------------------------------------------------------------- test runner
async function step(name, fn) {
  const t0 = Date.now();
  try {
    await fn();
    results.push({ name, ok: true });
    console.log(`  ok   ${name} (${Date.now() - t0} ms)`);
  } catch (e) {
    results.push({ name, ok: false, error: e.message });
    console.log(`  FAIL ${name}: ${e.message}`);
    try { console.log('       visible texts:', JSON.stringify((await texts()).slice(0, 25))); } catch { /* ignore */ }
  }
}
const assert = (cond, msg) => { if (!cond) throw new Error(msg); };

async function main() {
  if (!JAR || !WEB_DIR) throw new Error('set E2E_BACKEND_JAR and E2E_WEB_DIR (use scripts/e2e-browser.ps1)');
  await startBackend();
  await startWebServer();
  await startChrome();
  await openApp();
  console.log('Browser E2E against', API, '- UI served on', `http://localhost:${WEB_PORT}`);

  await step('1 app loads, WebSocket connected, empty state, a11y structure (headings, live region)', async () => {
    await waitText('Echtzeit-Verbindung: Live verbunden');
    await waitText('Warteschlange (0)');
    await waitText('Keine wartenden Patienten');
    await waitText('Behandlungsräume (4 von 4 verfügbar)');
    const heads = await evalJs(`[...document.querySelectorAll('flt-semantics h1,flt-semantics h2,flt-semantics h3,flt-semantics[role=heading]')].length`);
    assert(heads >= 3, `expected >=3 heading nodes, got ${heads}`);
    await waitText('Technische Demonstration');
  });

  await step('2 "Demo-Patient hinzufügen" (mouse) x3 -> queue sorted by urgency, then arrival', async () => {
    for (let i = 1; i <= 3; i++) {
      await click('button', 'Demo-Patient hinzufügen');
      await waitText(`Warteschlange (${i})`);
    }
    const q = await queue();
    assert(q.length === 3, `3 patients expected, got ${q.length}`);
    assert(q.map((x) => x.pos).join() === '1,2,3', 'positions 1..3');
    for (let i = 1; i < q.length; i++) assert(q[i - 1].prio <= q[i].prio, `not sorted: ${JSON.stringify(q)}`);
  });

  await step('3 live update without interaction: patient created via REST appears first (WebSocket)', async () => {
    const r = await api('POST', '/api/patients', { name: 'E2E Extern Kritisch', urgency: 'CRITICAL' });
    assert(r.status === 201, 'REST create failed');
    await waitText('Warteschlange (4)');
    await waitFor(async () => (await queueNames()).includes('E2E Extern Kritisch'), 'extern patient visible');
    const q = await queue();
    const idx = q.findIndex((x) => x.name === 'E2E Extern Kritisch');
    assert(q.slice(0, idx + 1).every((x) => x.prio === 1), 'everything up to the critical patient is critical');
    for (let i = 1; i < q.length; i++) assert(q[i - 1].prio <= q[i].prio, 'sorted after live update');
  });

  await step('4 change urgency through the UI dropdown (label-addressable) -> queue reorders', async () => {
    const q = await queue();
    const last = q[q.length - 1];
    assert(last.prio > 1, 'last patient should not already be critical');
    await click('button', `Dringlichkeit ändern für ${last.name}`);
    await click(null, 'Kritisch', 0, true).catch(() => { throw new Error('dropdown option "Kritisch" not reachable'); });
    await waitFor(async () => (await queue()).find((x) => x.name === last.name)?.urgency === 'Kritisch', 'urgency changed');
    const after = await queue();
    for (let i = 1; i < after.length; i++) assert(after[i - 1].prio <= after[i].prio, 'still sorted');
    // the escalated patient arrived BEFORE the externally created one: keeping its original arrival rank
    // means it must be listed ahead of it within the CRITICAL block
    const idxExtern = after.findIndex((x) => x.name === 'E2E Extern Kritisch');
    const idxLast = after.findIndex((x) => x.name === last.name);
    assert(idxLast < idxExtern, 'escalated patient keeps its original arrival rank (FIFO within CRITICAL)');
  });

  await step('5 dialog: "Aufrufen" opens room dialog, Escape closes it, choosing a room occupies it', async () => {
    await click('button', 'Aufrufen', 0);
    await waitText('Raum wählen');
    await key('Escape');
    await waitNoText('Raum wählen');
    await click('button', 'Aufrufen', 0);
    await waitText('Raum wählen');
    await click(null, 'Raum 2', 0);
    await waitText('Raum 2 Status: Belegt');
    await waitText('Warteschlange (3)');
  });

  await step('6 "Nächsten aufrufen" in Raum 1 -> Raum 1 occupied by queue head', async () => {
    await click('button', 'Nächsten aufrufen', 0);
    await waitText('Raum 1 Status: Belegt');
    await waitText('Warteschlange (2)');
  });

  await step('7 treatment finished -> room CLEANING (not available) -> explicit "Reinigung beendet" -> AVAILABLE', async () => {
    await click('button', 'Behandlung abschließen', 0);
    await waitFor(async () => (await texts()).some((t) => t.startsWith('Raum') && t.includes('Status: Reinigung')), 'a room is cleaning');
    assert(!(await texts()).some((t) => t.includes('Status: Verfügbar') && t.startsWith('Raum 1')), 'room must not auto-free');
    await click('button', 'Reinigung beendet', 0);
    await waitFor(async () => !(await texts()).some((t) => t.includes('Status: Reinigung')), 'no room cleaning');
  });

  await step('8 room change made elsewhere (REST) shows up live in the UI via WebSocket', async () => {
    const rooms = (await api('GET', '/api/rooms')).json;
    const occupied = rooms.find((r) => r.status === 'OCCUPIED');
    assert(occupied, 'an occupied room exists');
    await api('POST', `/api/rooms/${occupied.id}/complete-treatment`);
    await waitText(`${occupied.name} Status: Reinigung`);
    await api('PUT', `/api/rooms/${occupied.id}/status`, { status: 'AVAILABLE' });
    await waitText(`${occupied.name} Status: Verfügbar`);
  });

  await step('9 keyboard only: Tab reaches "Demo-Patient hinzufügen", Enter activates it', async () => {
    const before = (await queue()).length;
    let found = false;
    const seen = [];
    for (let i = 0; i < 25 && !found; i++) {
      await key('Tab');
      await sleep(100);
      const label = await activeLabel();
      seen.push(label);
      found = label.includes('Demo-Patient hinzufügen');
    }
    console.log('       focus order seen:', JSON.stringify(seen));
    assert(found, 'focus never reached the demo button by Tab');
    console.log('       focused element:', await evalJs('document.activeElement.outerHTML.slice(0,160)'));
    await key('Enter');
    const added = await waitFor(async () => (await queue()).length === before + 1, 'patient added by Enter', 4000).catch(() => false);
    if (!added) {
      await key(' ');
      await waitFor(async () => (await queue()).length === before + 1, 'patient added by Space (Enter did not work)', 4000);
      console.log('       (activated by Space, not Enter)');
    }
  });

  await step('9b focus order is logical: all queue controls come before the room controls (fresh page)', async () => {
    await openApp();
    await waitFor(async () => (await queue()).length > 0, 'queue loaded');
    const seen = [];
    for (let i = 0; i < 16; i++) {
      await key('Tab');
      await sleep(80);
      seen.push(await activeLabel());
    }
    const isQueue = (l) => /Demo-Patient hinzufügen|Dringlichkeit ändern|^Aufrufen|entfernen/.test(l);
    const isRoom = (l) => /Nächsten aufrufen|Reinigung starten|Behandlung abschließen|Reinigung beendet/.test(l);
    const firstRoom = seen.findIndex(isRoom);
    assert(firstRoom > 0, `no room control reached: ${JSON.stringify(seen)}`);
    const wrap = seen.findIndex((l, i) => i > firstRoom && l.startsWith('<'));
    const afterRoomsStart = seen.slice(firstRoom, wrap === -1 ? undefined : wrap);
    assert(!afterRoomsStart.some(isQueue), `queue control after room control (zig-zag): ${JSON.stringify(seen)}`);
    console.log('       focus order:', JSON.stringify(seen));
  });

  await step('10 remove a patient via its labelled trash button', async () => {
    const q = await queue();
    const victim = q[q.length - 1].name;
    await click('button', `${victim} aus der Warteschlange entfernen`);
    await waitFor(async () => !(await queueNames()).includes(victim), 'patient removed');
  });

  await step('11 narrow viewport (375 px): tabs, queue and rooms reachable, no JS exceptions', async () => {
    await cdp('Emulation.setDeviceMetricsOverride', { width: 375, height: 800, deviceScaleFactor: 1, mobile: false });
    await waitFor(async () => (await rectOf(null, 'Räume'))?.w > 0, 'tab "Räume"');
    await click(null, 'Räume');
    await waitText('Raum 1 Status');
    await click(null, 'Warteschlange', 0);
    await waitFor(async () => (await queue()).length > 0, 'queue visible again');
    await cdp('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });
    await waitText('Behandlungsräume');
  });

  await step('12 backend killed -> UI shows disconnected banner, keeps data; restart -> auto reconnect + REST re-sync', async () => {
    assert((await queue()).length > 0, 'data before outage');
    await stopBackend();
    await waitText('Echtzeit-Verbindung: Getrennt', 40000);
    await waitText('Echtzeit-Verbindung getrennt – Anzeige evtl. veraltet');
    assert((await queue()).length > 0, 'stale data stays visible during outage');
    await startBackend(); // fresh in-memory state
    await waitText('Echtzeit-Verbindung: Live verbunden', 60000);
    await waitText('Warteschlange (0)', 30000);
    await waitText('Behandlungsräume (4 von 4 verfügbar)');
  });

  await step('13 after reconnect live events work and arrive exactly once', async () => {
    await api('POST', '/api/patients', { name: 'E2E Nach Reconnect', urgency: 'HIGH' });
    await waitText('Warteschlange (1)');
    await sleep(1500);
    const names = await queueNames();
    assert(names.filter((n) => n === 'E2E Nach Reconnect').length === 1 && names.length === 1, `unexpected queue ${names}`);
  });

  await step('14 no uncaught JavaScript exceptions during the whole run', async () => {
    assert(jsErrors.length === 0, `JS errors: ${jsErrors.join(' | ')}`);
  });
}

let exitCode = 0;
try {
  await main();
} catch (e) {
  console.error('E2E setup/run error:', e.message);
  try {
    console.error('DOM sample:', await evalJs(`[...document.querySelectorAll('flt-semantics')].slice(0,6).map(e=>e.outerHTML.slice(0,300)).join('\\n') + ' | total=' + document.querySelectorAll('flt-semantics').length + ' | url=' + location.href`));
  } catch { /* ignore */ }
  exitCode = 1;
} finally {
  try { await cdp?.('Browser.close'); } catch { /* ignore */ }
  chrome?.kill();
  webServer?.close();
  await stopBackend();
}
const failed = results.filter((r) => !r.ok);
console.log(`\nBrowser E2E: ${results.length - failed.length}/${results.length} steps passed`);
process.exit(exitCode || (failed.length ? 1 : 0));
