// app/src/server.js

// Lightweight demo API/UI server with live logs & metrics.
// Designed to run both locally (Docker) and on AWS ECS Fargate.

// ---------------------- Imports & Setup ----------------------
const express = require('express');
const os = require('os');

const app = express();
// Respect provided PORT (ECS task env) and default to 80 for container runtimes.
const PORT = Number(process.env.PORT || 80);

// Parse JSON bodies for simple demo actions (/action endpoint)
app.use(express.json());

// ---------------------- App Info (immutable) -----------------
// Snapshot some metadata at boot time to show in UI and metrics.
const startedAt = Date.now();
const INFO = {
  appName: process.env.APP_NAME || 'Ruslan AWS 🚀',     // Shown in the UI header
  env: process.env.APP_ENV || 'prod',               // Environment label
  version: process.env.APP_VERSION || '1.0.0',          // App version for display
  gitSha: process.env.GIT_SHA || process.env.IMAGE_SHA || process.env.GITHUB_SHA || 'unknown', // Build/commit hint
};

// ---------------------- In-memory State & Logs ---------------
// Volatile counters for the demo buttons in the UI.
// (Reset to zero on each container restart/redeploy)
const STATE = {
  deploys: 0,
  scaled: 1,
  cacheClears: 0,
  keyRotations: 0,
  lastAction: null,
};

// Ring buffer with recent log entries (kept small to avoid memory growth)
const LOGS = [];
const MAX_LOGS = 500;

// Set of open Server-Sent Events (SSE) clients for live log streaming
const clients = new Set();

/**
 * Push a structured log record into LOGS and broadcast to SSE clients.
 * @param {"info"|"warn"|"error"|"action"} level
 * @param {string} msg
 * @param {object} extra - optional structured context
 */
function pushLog(level, msg, extra = {}) {
  const entry = { ts: new Date().toISOString(), level, msg, ...extra };
  LOGS.push(entry);
  if (LOGS.length > MAX_LOGS) LOGS.shift();

  // Fan-out to all connected live log subscribers (SSE)
  const data = `event: log\ndata: ${JSON.stringify(entry)}\n\n`;
  for (const res of clients) {
    try { res.write(data); } catch (_) { /* ignore broken pipes */ }
  }
}

/**
 * Quick hint for “where am I running?” — local vs ECS Fargate.
 * AWS injects AWS_EXECUTION_ENV into tasks/runtime.
 */
function getEcsMetaEnvHint() {
  return process.env.AWS_EXECUTION_ENV ? 'running on AWS (Fargate/ECS)' : 'local/docker';
}

/**
 * Collect minimal system/process metrics from Node/OS.
 * These are used by the UI KPIs and the heartbeat logs.
 */
function getLocalMetrics() {
  const mem = process.memoryUsage();
  return {
    hostname: os.hostname(),
    platform: `${os.type()} ${os.release()}`,
    arch: process.arch,
    uptimeSec: Math.round((Date.now() - startedAt) / 1000),
    cpuCount: os.cpus()?.length || 1,
    loadAvg: os.loadavg(),                     // [1m, 5m, 15m] load averages
    rssMB: Math.round(mem.rss / 1024 / 1024),
    heapUsedMB: Math.round(mem.heapUsed / 1024 / 1024),
    externalIpHint: getEcsMetaEnvHint(),
  };
}

// Periodic heartbeat — emits a small metrics snapshot every 15s.
// Useful to verify the container stays healthy/alive.
setInterval(() => {
  const m = getLocalMetrics();
  pushLog('info', 'heartbeat', { uptimeSec: m.uptimeSec, rssMB: m.rssMB, heapMB: m.heapUsedMB, load: m.loadAvg });
}, 15000);

// ---------------------- ECS Task Metadata (best-effort) ------
// ECS injects metadata endpoint via ECS_CONTAINER_METADATA_URI(V4).
// We read it if present; otherwise we return null for local/dev runs.
async function getEcsMetadata() {
  try {
    const base = process.env.ECS_CONTAINER_METADATA_URI_V4 || process.env.ECS_CONTAINER_METADATA_URI;
    if (!base) return null;

    // Fetch both task-level and container-level metadata concurrently.
    const [task, container] = await Promise.all([
      fetch(`${base}/task`).then(r => r.ok ? r.json() : null).catch(() => null),
      fetch(base).then(r => r.ok ? r.json() : null).catch(() => null),
    ]);
    return { task, container };
  } catch (_) {
    return null;
  }
}

// ---------------------- API Routes ---------------------------

// Simple health endpoint used by Docker HEALTHCHECK and Uptime card.
app.get('/health', (_req, res) => res.status(200).send('OK'));

// Aggregated metrics endpoint: app info, internal state, system & ECS metadata.
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

// Last N logs as JSON (fallback for environments without SSE)
app.get('/api/logs', (_req, res) => {
  res.json(LOGS.slice(-200));
});

// Live logs over Server-Sent Events (SSE)
// - Keeps an open HTTP response and pushes new log entries.
// - Includes an initial "snapshot" event with recent entries.
app.get('/api/logs/stream', (req, res) => {
  res.set({
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache, no-transform',
    'Connection': 'keep-alive',
  });
  res.flushHeaders();
  clients.add(res);

  // Send a recent snapshot so the viewer sees some context immediately.
  const snapshot = LOGS.slice(-100);
  res.write(`event: snapshot\ndata: ${JSON.stringify(snapshot)}\n\n`);

  // Periodic comment frames keep idle connections alive across proxies.
  const hb = setInterval(() => res.write(': ping\n\n'), 10000);

  // Cleanup when client disconnects
  req.on('close', () => {
    clearInterval(hb);
    clients.delete(res);
  });
});

// Demo actions endpoint — mutates in-memory STATE and emits log events.
// In real apps this would trigger CI/CD jobs, scaling APIs, cache invalidation, etc.
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
      // Validate input; keep 4xx for client errors.
      return res.status(400).json({ ok: false, msg: 'Unknown action' });
  }
});

// ---------------------- Branding: Logo & Favicon -------------
// Inline SVG allows shipping a single self-contained container image.
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

// SVG logo for header
app.get('/logo.svg', (_req, res) => {
  res.type('image/svg+xml').send(LOGO_SVG);
});

// Minimal favicon (SVG) without extra assets
app.get('/favicon.ico', (_req, res) => {
  const svg = LOGO_SVG.replace('width="128" height="128"', 'width="64" height="64"');
  res.type('image/svg+xml').send(svg);
});

// ---------------------- UI (SSR) ------------------------------
// Single route that serves a lightweight HTML app:
// - Dark/light theme toggle
// - Live metrics (polling)
// - Live logs (SSE)
// - Demo action buttons
app.get('*', (_req, res) => {
  res.type('html').send(`<!doctype html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>${INFO.appName}</title>
<link rel="icon" href="/favicon.ico"/>
<style>
/* (Styles omitted here for brevity in this comment — kept as-is in code) */
${''}
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
// ---------- Client-side helpers & UI wiring -------------

// Theme toggle (persist to localStorage)
const root = document.documentElement;
const savedTheme = localStorage.getItem('theme');
if (savedTheme) root.setAttribute('data-theme', savedTheme);
document.getElementById('theme').onclick = () => {
  const t = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
  root.setAttribute('data-theme', t);
  localStorage.setItem('theme', t);
};

// Periodically check /health (used by the badge)
async function pingHealth(){
  try {
    const r = await fetch('/health', {cache:'no-store'});
    document.getElementById('health').textContent = r.ok ? 'healthy' : 'unhealthy';
  } catch {
    document.getElementById('health').textContent = 'unreachable';
  }
}

// Show seconds as "Xm Ys" for nicer uptime display
function fmtSec(s){const m=Math.floor(s/60),sec=s%60; return m>0? m+'m '+sec+'s':sec+'s';}

// Pull metrics for KPI tiles
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

// Send demo action to the server and refresh KPIs
async function sendAction(action){
  const r = await fetch('/action', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({action})});
  const j = await r.json();
  await loadMetrics();
  alert(j.msg || 'OK');
}
document.querySelectorAll('.btn[data-action]').forEach(b=>{
  b.addEventListener('click', ()=> sendAction(b.dataset.action));
});

// Simple log viewer that appends lines to <pre>
function appendLog(line){
  const el = document.getElementById('logs');
  const s = typeof line === 'string' ? line : JSON.stringify(line);
  el.textContent += (el.textContent ? '\\n' : '') + s;
  el.scrollTop = el.scrollHeight;
}
document.getElementById('clear').onclick = () => { document.getElementById('logs').textContent=''; };

// Connect to SSE stream with automatic reconnect on error.
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

// Kick everything off
pingHealth(); loadMetrics(); setInterval(()=>{pingHealth();loadMetrics()}, 5000);
connectLogs();
</script>
</body>
</html>`);
});

// ---------------------- Server start --------------------------
app.listen(PORT, () => {
  pushLog('info', `${INFO.appName} starting`, {
    env: INFO.env, version: INFO.version, git: INFO.gitSha, where: getEcsMetaEnvHint()
  });
  console.log(`Server listening on ${PORT}`);
});