############################################
# app/src/server.js — Minimal dashboard API/UI
# Purpose: Express app with metrics, SSE logs, demo actions, inline UI
############################################

const express = require('express');
const os = require('os');

const app = express();
const PORT = Number(process.env.PORT || 80);

app.use(express.json());

const startedAt = Date.now();

const INFO = {
  appName: process.env.APP_NAME || 'Ruslan AWS 🚀',
  env: process.env.APP_ENV || 'prod',
  version: process.env.APP_VERSION || '1.0.0',
  gitSha: process.env.GIT_SHA || process.env.IMAGE_SHA || process.env.GITHUB_SHA || 'unknown',
};

const STATE = {
  deploys: 0,
  scaled: 1,
  cacheClears: 0,
  keyRotations: 0,
  lastAction: null,
};

const LOGS = [];
const MAX_LOGS = 500;
const clients = new Set();

function pushLog(level, msg, extra = {}) {
  const entry = { ts: new Date().toISOString(), level, msg, ...extra };
  LOGS.push(entry);
  if (LOGS.length > MAX_LOGS) LOGS.shift();
  const data = `event: log\ndata: ${JSON.stringify(entry)}\n\n`;
  for (const res of clients) {
    try { res.write(data); } catch (_) {}
  }
}

function getEcsMetaEnvHint() {
  return process.env.AWS_EXECUTION_ENV ? 'running on AWS (Fargate/ECS)' : 'local/docker';
}

function getLocalMetrics() {
  const mem = process.memoryUsage();
  return {
    hostname: os.hostname(),
    platform: `${os.type()} ${os.release()}`,
    arch: process.arch,
    uptimeSec: Math.round((Date.now() - startedAt) / 1000),
    cpuCount: os.cpus()?.length || 1,
    loadAvg: os.loadavg(),
    rssMB: Math.round(mem.rss / 1024 / 1024),
    heapUsedMB: Math.round(mem.heapUsed / 1024 / 1024),
    externalIpHint: getEcsMetaEnvHint(),
  };
}

setInterval(() => {
  const m = getLocalMetrics();
  pushLog('info', 'heartbeat', { uptimeSec: m.uptimeSec, rssMB: m.rssMB, heapMB: m.heapUsedMB, load: m.loadAvg });
}, 15000);

async function getEcsMetadata() {
  try {
    const base = process.env.ECS_CONTAINER_METADATA_URI_V4 || process.env.ECS_CONTAINER_METADATA_URI;
    if (!base) return null;
    const [task, container] = await Promise.all([
      fetch(`${base}/task`).then(r => r.ok ? r.json() : null).catch(() => null),
      fetch(base).then(r => r.ok ? r.json() : null).catch(() => null),
    ]);
    return { task, container };
  } catch (_) {
    return null;
  }
}

app.get('/health', (_req, res) => res.status(200).send('OK'));

app.get('/api/metrics', async (_req, res) => {
  const ecs = await getEcsMetadata();
  res.json({
    info: INFO,
    state: STATE,
    system: getLocalMetrics(),
    ecs: ecs ? {
      cluster: ecs.task?.Cluster,
      taskArn: ecs.task?.TaskARN,
      family: ecs.task?.Family,
      rev: ecs.task?.Revision,
      containerName: ecs.container?.Name,
    } : null,
    now: new Date().toISOString(),
  });
});

app.get('/api/logs', (_req, res) => {
  res.json(LOGS.slice(-200));
});

app.get('/api/logs/stream', (req, res) => {
  res.set({
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache, no-transform',
    'Connection': 'keep-alive',
  });
  res.flushHeaders();
  clients.add(res);
  const snapshot = LOGS.slice(-100);
  res.write(`event: snapshot\ndata: ${JSON.stringify(snapshot)}\n\n`);
  const hb = setInterval(() => res.write(': ping\n\n'), 10000);
  req.on('close', () => {
    clearInterval(hb);
    clients.delete(res);
  });
});

app.post('/action', (req, res) => {
  const a = (req.body?.action || '').toLowerCase();
  switch (a) {
    case 'deploy':
      STATE.deploys += 1;
      STATE.lastAction = 'Deploy started';
      pushLog('action', 'deploy');
      return res.json({ ok: true, msg: 'Deploy started (demo)' });
    case 'scale_up':
      STATE.scaled += 1;
      STATE.lastAction = 'Scaled +1';
      pushLog('action', 'scale_up', { replicas: STATE.scaled });
      return res.json({ ok: true, msg: `Scaled up to ${STATE.scaled}` });
    case 'scale_down':
      STATE.scaled = Math.max(1, STATE.scaled - 1);
      STATE.lastAction = 'Scaled -1';
      pushLog('action', 'scale_down', { replicas: STATE.scaled });
      return res.json({ ok: true, msg: `Scaled down to ${STATE.scaled}` });
    case 'clear_cache':
      STATE.cacheClears += 1;
      STATE.lastAction = 'Cache cleared';
      pushLog('action', 'clear_cache');
      return res.json({ ok: true, msg: 'Cache cleared (demo)' });
    case 'rotate_keys':
      STATE.keyRotations += 1;
      STATE.lastAction = 'Keys rotated';
      pushLog('action', 'rotate_keys');
      return res.json({ ok: true, msg: 'Keys rotation triggered (demo)' });
    case 'p95_report':
      STATE.lastAction = 'P95 report generated';
      pushLog('action', 'p95_report');
      return res.json({ ok: true, msg: 'P95 latency report ready (demo)' });
    default:
      return res.status(400).json({ ok: false, msg: 'Unknown action' });
  }
});

const LOGO_SVG = `
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="g" x1="0" x2="1" y1="0" y2="1">
      <stop offset="0" stop-color="#ff00ea"/><stop offset="0.5" stop-color="#00e5ff"/><stop offset="1" stop-color="#00ff88"/>
    </linearGradient>
  </defs>
  <rect rx="28" ry="28" width="128" height="128" fill="#0b1120"/>
  <circle cx="64" cy="64" r="50" fill="url(#g)" opacity="0.25"/>
  <g transform="translate(20,20)">
    <path d="M8 56 L28 20 L48 56 L38 56 L28 36 L18 56 Z" fill="url(#g)"/>
    <circle cx="70" cy="28" r="12" fill="url(#g)"/>
    <rect x="56" y="48" width="28" height="10" rx="5" fill="url(#g)"/>
  </g>
</svg>
`.trim();

app.get('/logo.svg', (_req, res) => {
  res.type('image/svg+xml').send(LOGO_SVG);
});

app.get('/favicon.ico', (_req, res) => {
  const svg = LOGO_SVG.replace('width="128" height="128"', 'width="64" height="64"');
  res.type('image/svg+xml').send(svg);
});

app.get('*', (_req, res) => {
  res.type('html').send(`<!doctype html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>${INFO.appName}</title>
<link rel="icon" href="/favicon.ico"/>
<style>
:root{
  --bg:#05060b; --panel:#0a0d17; --card:#0b1120; --muted:#93a3b8; --text:#e5eef9;
  --ring:#60a5fa; --glow:#22d3ee; --rgb1:#ff00ea; --rgb2:#00e5ff; --rgb3:#00ff88;
}
:root[data-theme="light"]{
  --bg:#f7fafc; --panel:#ffffff; --card:#f8fafc; --muted:#4b5563; --text:#0b1220;
  --ring:#2563eb; --glow:#06b6d4; --rgb1:#7c3aed; --rgb2:#06b6d4; --rgb3:#22c55e;
}
*{box-sizing:border-box}
html,body{height:100%}
body{
  margin:0; font-family:ui-sans-serif,system-ui,Segoe UI,Roboto,Inter,Arial;
  color:var(--text); background:
    radial-gradient(1200px 700px at 10% -10%, #0b1220 0%, #070914 50%, var(--bg) 100%);
  overflow-x:hidden;
}
:root[data-theme="light"] body{
  background: linear-gradient(180deg,#ffffff, #eef2ff);
}
body::before, body::after{
  content:""; position:fixed; inset:-20%;
  filter:blur(40px); opacity:.35; pointer-events:none; mix-blend-mode:screen;
  background:
    radial-gradient(600px 300px at 20% 20%, var(--rgb1), transparent 60%),
    radial-gradient(600px 300px at 80% 30%, var(--rgb2), transparent 60%),
    radial-gradient(600px 300px at 50% 80%, var(--rgb3), transparent 60%);
  animation: float 18s linear infinite reverse;
}
:root[data-theme="light"] body::before,
:root[data-theme="light"] body::after{ display:none; }
body::after{ animation-duration: 26s; opacity:.25; transform: rotate(10deg); }
@keyframes float{ 0%{transform:translateY(0)} 50%{transform:translateY(2%)} 100%{transform:translateY(0)} }
header{
  position:sticky; top:0; z-index:10; padding:18px 16px;
  background:
    linear-gradient(90deg, rgba(5,6,11,.8), rgba(5,6,11,.2)),
    linear-gradient(90deg, var(--rgb1), var(--rgb2), var(--rgb3));
  background-size:100% 100%, 300% 100%; animation: rgbbar 12s ease-in-out infinite;
  box-shadow: 0 10px 40px rgba(0,0,0,.45); border-bottom: 1px solid rgba(255,255,255,.06);
}
:root[data-theme="light"] header{
  background: linear-gradient(90deg, #ffffff, #eef2ff);
  box-shadow: 0 8px 24px rgba(0,0,0,.08); border-bottom: 1px solid rgba(0,0,0,.06);
}
@keyframes rgbbar{ 0%{background-position: 0 0, 0 0} 50%{background-position: 0 0, 100% 0} 100%{background-position: 0 0, 0 0} }
.hbar{display:flex;align-items:center;gap:14px;max-width:1180px;margin:0 auto;padding:0 10px}
h1{margin:0;font-size:22px;letter-spacing:.3px}
.logo{width:28px;height:28px;vertical-align:middle}
.wrap{max-width:1180px;margin:24px auto;padding:0 18px}
.grid{display:grid;grid-template-columns:2fr 1fr;gap:18px}
@media (max-width:1020px){ .grid{grid-template-columns:1fr} }
.panel{
  background: linear-gradient(180deg, rgba(255,255,255,.07), rgba(255,255,255,.02));
  border: 1px solid rgba(255,255,255,.08); border-radius: 16px;
  box-shadow: 0 12px 60px rgba(0,0,0,.35), 0 0 0 1px rgba(34,211,238,.1) inset;
  padding: 16px; backdrop-filter: saturate(120%) blur(6px);
}
:root[data-theme="light"] .panel{
  background:#fff; border:1px solid rgba(0,0,0,.06); box-shadow: 0 6px 24px rgba(0,0,0,.08);
}
.card{margin-top:14px;background:linear-gradient(180deg,rgba(255,255,255,.05),rgba(255,255,255,.02));
  border:1px solid rgba(255,255,255,.08);border-radius:14px;padding:14px}
:root[data-theme="light"] .card{background:#fff;border:1px solid rgba(0,0,0,.06)}
.badge{padding:6px 10px;border-radius:999px;background:rgba(9,10,18,.85);
  border:1px solid rgba(255,255,255,.08);font-size:12px;color:var(--muted)}
:root[data-theme="light"] .badge{background:#f8fafc;border:1px solid rgba(0,0,0,.06);color:#334155}
.muted{color:var(--muted)}
.row{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
.btn{padding:12px 14px;border-radius:12px;border:1px solid rgba(255,255,255,.08);
  background: radial-gradient(120% 180% at 0% 0%, rgba(255,255,255,.05), rgba(255,255,255,.02));
  color:var(--text);font-weight:800;letter-spacing:.3px;cursor:pointer;
  transition:.15s transform,.15s box-shadow,.15s border-color, .2s filter;
  text-shadow: 0 1px 10px rgba(96,165,250,.35); box-shadow: 0 0 0 1px rgba(34,211,238,.12) inset, 0 12px 28px rgba(0,0,0,.25);
}
.btn:hover{transform:translateY(-3px) scale(1.01);border-color: rgba(96,165,250,.55);filter: drop-shadow(0 0 12px rgba(96,165,250,.35))}
:root[data-theme="light"] .btn{text-shadow:none; box-shadow: 0 6px 18px rgba(0,0,0,.06)}
.kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px}
.kpi{padding:12px;border-radius:12px;background:linear-gradient(180deg,rgba(255,255,255,.05),rgba(255,255,255,.02));
  border:1px solid rgba(255,255,255,.08)}
:root[data-theme="light"] .kpi{background:#fff;border:1px solid rgba(0,0,0,.06)}
.kpi .v{font-size:20px;font-weight:900}
.kpi .t{font-size:12px;color:var(--muted)}
pre{white-space:pre-wrap;word-break:break-word;background:#070a14;border:1px solid rgba(255,255,255,.08);
  padding:12px;border-radius:12px;max-height:360px;overflow:auto}
:root[data-theme="light"] pre{background:#f8fafc;border:1px solid rgba(0,0,0,.06)}
</style>
</head>
<body>
<header>
  <div class="hbar">
    <img class="logo" src="/logo.svg" alt="logo"/>
    <h1>${INFO.appName}</h1>
    <div style="flex:1"></div>
    <button id="theme" class="btn" style="width:auto;padding:8px 12px">Toggle theme</button>
  </div>
</header>

<div class="wrap">
  <div class="grid">
    <section class="panel">
      <div class="row">
        <span class="badge">Env: ${INFO.env}</span>
        <span class="badge">Version: <span id="v">${INFO.version}</span></span>
        <span class="badge">Git: <span id="sha">${INFO.gitSha.slice(0, 7)}</span></span>
        <span class="badge">Health: <span id="health">checking…</span></span>
      </div>

      <div class="kpis" style="margin-top:12px">
        <div class="kpi"><div class="v" id="uptime">—</div><div class="t">Uptime</div></div>
        <div class="kpi"><div class="v" id="rss">—</div><div class="t">RSS</div></div>
        <div class="kpi"><div class="v" id="heap">—</div><div class="t">Heap</div></div>
        <div class="kpi"><div class="v" id="load">—</div><div class="t">Load Avg</div></div>
      </div>

      <div class="row" style="gap:8px; margin-top:12px; flex-wrap:wrap">
        <button class="btn" data-action="deploy">Deploy</button>
        <button class="btn" data-action="scale_up">Scale +1</button>
        <button class="btn" data-action="scale_down">Scale -1</button>
        <button class="btn" data-action="p95_report">P95 Report</button>
        <button class="btn" data-action="clear_cache">Clear Cache</button>
        <button class="btn" data-action="rotate_keys">Rotate Keys</button>
        <a class="btn" href="/health" style="text-decoration:none">/health</a>
      </div>

      <div class="card">
        <div class="row" style="justify-content:space-between">
          <div class="muted">Last Action: <b id="last">—</b></div>
          <div class="muted">Host: <b id="host">—</b></div>
        </div>
      </div>
    </section>

    <aside class="panel">
      <div class="row"><span class="muted">Live logs</span></div>
      <pre id="logs">connecting…</pre>
      <div class="row" style="margin-top:8px">
        <button id="clear" class="btn" style="width:auto">Clear view</button>
      </div>

      <div class="card">
        <div class="muted">Release notes</div>
        <ul class="muted" style="margin-top:6px">
          <li>Neon RGB aurora background</li>
          <li>Theme toggle (dark/light)</li>
          <li>Live logs via SSE</li>
          <li>Working action buttons</li>
        </ul>
      </div>
    </aside>
  </div>
</div>

<script>
const root = document.documentElement;
const savedTheme = localStorage.getItem('theme');
if (savedTheme) root.setAttribute('data-theme', savedTheme);
document.getElementById('theme').onclick = () => {
  const t = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
  root.setAttribute('data-theme', t);
  localStorage.setItem('theme', t);
};

async function pingHealth(){
  try {
    const r = await fetch('/health', {cache:'no-store'});
    document.getElementById('health').textContent = r.ok ? 'healthy' : 'unhealthy';
  } catch {
    document.getElementById('health').textContent = 'unreachable';
  }
}
function fmtSec(s){const m=Math.floor(s/60),sec=s%60; return m>0? m+'m '+sec+'s':sec+'s';}
async function loadMetrics(){
  const m = await fetch('/api/metrics', {cache:'no-store'}).then(r=>r.json());
  const sys = m.system||{};
  document.getElementById('uptime').textContent = fmtSec(sys.uptimeSec||0);
  document.getElementById('rss').textContent = (sys.rssMB||0)+' MB';
  document.getElementById('heap').textContent = (sys.heapUsedMB||0)+' MB';
  document.getElementById('load').textContent = (sys.loadAvg||[]).map(x=>x.toFixed(2)).join(' / ');
  document.getElementById('last').textContent = (m.state && m.state.lastAction) || '—';
  document.getElementById('host').textContent = sys.hostname || '—';
}

async function sendAction(action){
  const r = await fetch('/action', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({action})});
  const j = await r.json();
  await loadMetrics();
  alert(j.msg || 'OK');
}
document.querySelectorAll('.btn[data-action]').forEach(b=>{
  b.addEventListener('click', ()=> sendAction(b.dataset.action));
});

function appendLog(line){
  const el = document.getElementById('logs');
  const s = typeof line === 'string' ? line : JSON.stringify(line);
  el.textContent += (el.textContent ? '\\n' : '') + s;
  el.scrollTop = el.scrollHeight;
}
document.getElementById('clear').onclick = () => { document.getElementById('logs').textContent=''; };

function connectLogs(){
  const es = new EventSource('/api/logs/stream');
  es.addEventListener('snapshot', (e)=> {
    try { JSON.parse(e.data).forEach(x=>appendLog(x)); } catch(_){}
  });
  es.addEventListener('log', (e)=> appendLog(JSON.parse(e.data)));
  es.onerror = () => {
    appendLog({ts:new Date().toISOString(), level:'warn', msg:'SSE disconnected; retrying…'});
    es.close(); setTimeout(connectLogs, 2000);
  };
}

pingHealth();
loadMetrics();
setInterval(()=>{ pingHealth(); loadMetrics(); }, 5000);
connectLogs();
</script>
</body>
</html>`);
});

app.listen(PORT, () => {
  pushLog('info', `${INFO.appName} starting`, { env: INFO.env, version: INFO.version, git: INFO.gitSha, where: getEcsMetaEnvHint() });
  console.log(`Server listening on ${PORT}`);
});