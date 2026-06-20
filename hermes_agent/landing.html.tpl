<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Hermes Agent</title>
  <style>
    :root{color-scheme:dark;--bg:#0c1017;--panel:#121823;--line:#263142;--text:#e8edf4;--muted:#9aa7b8;--blue:#3b82f6;--green:#10b981}
    *{box-sizing:border-box}
    body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Noto Sans,sans-serif;margin:0;padding:18px;background:var(--bg);color:var(--text)}
    a{font:inherit}
    main{max-width:1120px;margin:0 auto}
    header{display:flex;justify-content:space-between;gap:16px;align-items:flex-start;margin-bottom:14px}
    h1{font-size:24px;line-height:1.15;margin:0 0 6px}
    p{margin:0}
    .muted{color:var(--muted);font-size:14px;line-height:1.5}
    .actions{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
    .btn{background:var(--blue);color:#fff;border:0;border-radius:8px;padding:10px 14px;text-decoration:none;display:inline-flex;align-items:center;min-height:40px;font-size:14px}
    .btn.secondary{background:#2d3748}
    .btn:hover{filter:brightness(1.12)}
    .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px;margin:14px 0}
    .panel{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:12px}
    .label{display:block;color:var(--muted);font-size:12px;margin-bottom:4px;text-transform:uppercase}
    .value{font-size:15px}
    .ok{color:var(--green)}
    .terminal{height:58vh;min-height:360px;border:1px solid var(--line);border-radius:8px;overflow:hidden;background:#000}
    iframe{width:100%;height:100%;border:0;background:#000}
    code{background:#0b1220;border:1px solid #1c2736;padding:2px 6px;border-radius:6px}
    @media(max-width:720px){header{display:block}.actions{margin-top:12px}.btn{width:100%;justify-content:center}.terminal{height:52vh}}
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <h1>Hermes Agent</h1>
        <p class="muted">Runs Hermes inside Home Assistant with event monitoring, smart-home tools, dashboard access, and a maintenance terminal.</p>
      </div>
      <div class="actions">
        <a class="btn" id="dashboard-link" href="http://localhost:__DASHBOARD_PORT__/" target="_blank" rel="noreferrer">Dashboard</a>
        <a class="btn secondary" id="webui-link" href="http://localhost:__WEBUI_PORT__/" target="_blank" rel="noreferrer">Web UI</a>
        <a class="btn secondary" href="./terminal/" target="_self">Terminal</a>
      </div>
    </header>

    <div class="grid">
      <div class="panel">
        <span class="label">Agent</span>
        <span class="value ok">Gateway process supervised</span>
      </div>
      <div class="panel">
        <span class="label">Dashboard</span>
        <span class="value">__DASHBOARD_STATUS__</span>
      </div>
      <div class="panel">
        <span class="label">Terminal</span>
        <span class="value">__TERMINAL_STATUS__</span>
      </div>
      <div class="panel">
        <span class="label">Storage</span>
        <span class="value">__DISK_USED__ / __DISK_TOTAL__ used, __DISK_AVAIL__ free</span>
      </div>
    </div>

    <section class="panel" style="margin-bottom:14px">
      <p class="muted">
        Configure models and API keys with Hermes itself: <code>hermes setup</code>,
        <code>hermes model</code>, or <code>hermes config edit</code>.
        Add-on options only manage Home Assistant access, event filters, and the local UI.
      </p>
    </section>

    <div class="terminal">
      <iframe src="./terminal/" title="Hermes terminal"></iframe>
    </div>
  </main>
  <script>
    const dashboardLink = document.getElementById('dashboard-link');
    if (dashboardLink) {
      dashboardLink.href = `http://${window.location.hostname}:__DASHBOARD_PORT__/`;
    }
    const webuiLink = document.getElementById('webui-link');
    if (webuiLink) {
      webuiLink.href = `http://${window.location.hostname}:__WEBUI_PORT__/`;
    }
  </script>
</body>
</html>
