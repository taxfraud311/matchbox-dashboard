/* Matchbox Dashboard display — runs inside the tablet app's WebView (or any browser). */
(function () {
  "use strict";

  var $ = function (id) { return document.getElementById(id); };
  var host = window.PlinthHost || null;   // Android bridge (brightness, etc.)

  // ---------- Icons (SF Symbols–inspired, drawn as SVG) ----------
  var ICONS = {
    cpu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="6" y="6" width="12" height="12" rx="2.5"/><rect x="9.5" y="9.5" width="5" height="5" rx="1" fill="currentColor" stroke="none"/><path d="M9 2.5v3M15 2.5v3M9 18.5v3M15 18.5v3M2.5 9h3M2.5 15h3M18.5 9h3M18.5 15h3"/></svg>',
    gpu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M12 2.8l8 4.6v9.2l-8 4.6-8-4.6V7.4z"/><path d="M12 12l8-4.6M12 12L4 7.4M12 12v9.2"/></svg>',
    mem: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="2.5" y="6" width="19" height="10" rx="2"/><path d="M6.5 9.5v3M10.5 9.5v3M14.5 9.5v3M18 9.5v3M5 16v3M9 16v3M15 16v3M19 16v3"/></svg>',
    disk: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="2.5" y="6" width="19" height="12" rx="3.5"/><path d="M2.5 13h19"/><circle cx="17.5" cy="15.6" r="0.6" fill="currentColor"/></svg>',
    net: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3.5v16M4 15.5l4 4 4-4"/><path d="M16 20.5v-16M12 8.5l4-4 4 4" opacity="0.65"/></svg>',
    chipWeather: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"><circle cx="9" cy="9" r="3.2"/><path d="M9 2.5v1.3M3.6 9H2.3M4.4 4.4l.9.9M13.6 4.4l-.9.9"/><path d="M8 20h9a3.6 3.6 0 0 0 .4-7.2 5 5 0 0 0-9.6 1.4A2.9 2.9 0 0 0 8 20z" fill="#fff" stroke="none"/></svg>',
    chipSports: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"><path d="M7 3.5h10v5a5 5 0 0 1-10 0z"/><path d="M7 5.5H4v1.5a3 3 0 0 0 3 3M17 5.5h3v1.5a3 3 0 0 1-3 3M12 13.5v3.5M8 20.5h8M9.5 17h5"/></svg>',
    chipYouTube: '<svg viewBox="0 0 24 24"><path d="M9.5 7.8v8.4l7-4.2z" fill="#fff"/></svg>',
    chipAnime: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="6" width="18" height="13" rx="2.5"/><path d="M8 2.5l4 3.5 4-3.5"/><path d="M10 10.2v5.6l4.6-2.8z" fill="#fff" stroke="none"/></svg>',
    chipBluesky: '<svg viewBox="0 0 24 24"><path fill="#fff" d="M6.3 4.6c2.1 1.6 4.4 4.8 5.7 6.5 1.3-1.7 3.6-4.9 5.7-6.5 1.5-1.1 4-2 4 .8 0 .6-.3 4.7-.5 5.4-.7 2.4-3.2 3-5.4 2.6 3.9.7 4.9 2.9 2.7 5.1-4.1 4.2-5.9-1.1-6.4-2.4l-.1-.4-.1.4c-.5 1.3-2.3 6.6-6.4 2.4-2.2-2.2-1.2-4.4 2.7-5.1-2.2.4-4.7-.2-5.4-2.6C2.6 10.1 2.3 6 2.3 5.4c0-2.8 2.5-1.9 4-.8z"/></svg>',
    chipSteam: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"><rect x="2.5" y="7" width="19" height="11" rx="5.5"/><path d="M7.5 10.5v4M5.5 12.5h4"/><circle cx="15.5" cy="11.5" r="1" fill="#fff" stroke="none"/><circle cx="17.5" cy="13.8" r="1" fill="#fff" stroke="none"/></svg>',
    chipDeal: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12V4h8l10 10-8 8z"/><circle cx="7.5" cy="8.5" r="1.4" fill="#fff" stroke="none"/></svg>',
    chipNews: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4.5h12v14a2 2 0 0 0 2 2H6a2 2 0 0 1-2-2z"/><path d="M16 8.5h4v10a2 2 0 0 1-4 0M7.5 8.5h5M7.5 12h5M7.5 15.5h3"/></svg>',
  };
  ICONS.chipTrophy = '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 3.5h10v5.5a5 5 0 0 1-10 0z"/><path d="M12 14v3.5M8.5 20.5h7M9.5 17.5h5"/><path d="M12 6.3l.8 1.6 1.7.2-1.3 1.2.4 1.7-1.6-.9-1.6.9.4-1.7-1.3-1.2 1.7-.2z" fill="#fff" stroke="none"/></svg>';
  ICONS.chipTarget = '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="4.5"/><circle cx="12" cy="12" r="1" fill="#fff"/></svg>';
  ICONS.chipFX = '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8h13l-3.5-3.5M20 16H7l3.5 3.5"/></svg>';
  ICONS.chipKanji = '<svg viewBox="0 0 24 24"><text x="12" y="18" text-anchor="middle" font-size="16" font-weight="700" fill="#fff" font-family="sans-serif">字</text></svg>';
  ICONS.chipRadar = '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="8.5" opacity=".55"/><circle cx="12" cy="12" r="4.5" opacity=".75"/><path d="M12 12l6-6"/><circle cx="12" cy="12" r="1.3" fill="#fff"/></svg>';
  ICONS.chipSlick = '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 21V11H3.5V21zM7 11l4-8c1.6 0 2.7 1.3 2.4 2.9L12.8 9H19a2 2 0 0 1 2 2.3l-1.3 7.4A2.6 2.6 0 0 1 17.2 21H7"/></svg>';
  ICONS.claude = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 3v18M3 12h18M5.6 5.6l12.8 12.8M18.4 5.6L5.6 18.4"/></svg>';
  Array.prototype.forEach.call(document.querySelectorAll("[data-icon]"), function (el) {
    el.innerHTML = ICONS[el.getAttribute("data-icon")] || "";
  });

  // ---------- Weather icons ----------
  var CLOUD = "M17 50h28a11 11 0 0 0 1.2-21.9A15 15 0 0 0 17.4 26 12 12 0 0 0 17 50z";
  function wxKind(code) {
    if (code === 0) return ["clear", "Clear"];
    if (code === 1) return ["mostly", "Mostly Clear"];
    if (code === 2) return ["partly", "Partly Cloudy"];
    if (code === 3) return ["cloudy", "Cloudy"];
    if (code === 45 || code === 48) return ["fog", "Fog"];
    if (code >= 51 && code <= 57) return ["drizzle", "Drizzle"];
    if (code >= 61 && code <= 67) return ["rain", code >= 65 ? "Heavy Rain" : "Rain"];
    if (code >= 71 && code <= 77) return ["snow", "Snow"];
    if (code >= 80 && code <= 82) return ["rain", "Showers"];
    if (code === 85 || code === 86) return ["snow", "Snow Showers"];
    if (code >= 95) return ["storm", "Thunderstorms"];
    return ["cloudy", "—"];
  }
  function sun(cx, cy, r) {
    var rays = "";
    for (var i = 0; i < 8; i++) {
      var a = i * Math.PI / 4, r1 = r + 4, r2 = r + 9;
      rays += "M" + (cx + Math.cos(a) * r1).toFixed(1) + " " + (cy + Math.sin(a) * r1).toFixed(1) +
              "L" + (cx + Math.cos(a) * r2).toFixed(1) + " " + (cy + Math.sin(a) * r2).toFixed(1);
    }
    return '<circle cx="' + cx + '" cy="' + cy + '" r="' + r + '" fill="var(--sun)"/>' +
           '<path d="' + rays + '" stroke="var(--sun)" stroke-width="3.4" stroke-linecap="round"/>';
  }
  function moon(cx, cy, r) {
    return '<path d="M' + (cx + r * 0.2) + ' ' + (cy - r) + 'a' + r + ' ' + r + ' 0 1 0 ' + (r * 0.85) + ' ' + (r * 1.45) +
           'A' + (r * 0.85) + ' ' + (r * 0.85) + ' 0 0 1 ' + (cx + r * 0.2) + ' ' + (cy - r) + 'z" fill="var(--moon)"/>';
  }
  function wxIcon(code, isDay) {
    var k = wxKind(code)[0], s = "";
    var cloud = function (dy, fill) { return '<path d="' + CLOUD + '" transform="translate(0 ' + (dy || 0) + ')" fill="' + (fill || "var(--cloud)") + '"/>'; };
    var body = isDay ? sun : moon;
    if (k === "clear") s = isDay ? sun(32, 32, 12) : moon(30, 32, 15);
    else if (k === "mostly") s = (isDay ? sun(32, 30, 12) : moon(30, 30, 14)) + '<path d="M30 54h18a7 7 0 0 0 .8-14 9.5 9.5 0 0 0-18.3 2.4A5.8 5.8 0 0 0 30 54z" fill="var(--cloud)"/>';
    else if (k === "partly") s = body(24, 22, 10) + cloud(4);
    else if (k === "cloudy") s = '<path d="' + CLOUD + '" transform="translate(8 -8) scale(0.8)" fill="var(--cloud-dark)"/>' + cloud(2);
    else if (k === "fog") s = cloud(-6) + '<path d="M12 52h40M18 59h28" stroke="var(--cloud-dark)" stroke-width="3.6" stroke-linecap="round"/>';
    else if (k === "drizzle") s = cloud(-8) + '<path d="M22 50l-1.5 4M32 50l-1.5 4M42 50l-1.5 4" stroke="var(--rain)" stroke-width="3.6" stroke-linecap="round"/>';
    else if (k === "rain") s = cloud(-8) + '<path d="M22 49l-3 9M32 49l-3 9M42 49l-3 9" stroke="var(--rain)" stroke-width="3.6" stroke-linecap="round"/>';
    else if (k === "snow") s = cloud(-8) + '<g fill="var(--rain)"><circle cx="21" cy="52" r="2.8"/><circle cx="32" cy="57" r="2.8"/><circle cx="43" cy="52" r="2.8"/></g>';
    else if (k === "storm") s = cloud(-8) + '<path d="M34 42l-8 11h7l-4 10 11-14h-7l4-7z" fill="var(--bolt)"/>';
    return '<svg viewBox="0 0 64 64" width="100%" height="100%">' + s + "</svg>";
  }

  // ---------- State ----------
  var cfg = { clock24h: false, cycleSeconds: 12, cards: { weather: true, sports: true, news: true }, sports: {}, headlinesPerCard: 3, location: {} };
  var cfgRev = -1, feedsVer = -1, reloadToken = null;
  var feeds = { weather: null, sports: [], news: [] };
  var hist = { cpu: [], gpu: [], mem: [], rx: [], tx: [], dr: [], dw: [] };
  var HMAX = 90;
  var clockOffset = 0;          // mac time − local time
  var tz = undefined;           // mac time zone
  var theme = "day", lastBrightness = null;
  var failures = 0, gotHistory = false;

  // ---------- Formatting ----------
  function nf(v, d) { return v.toFixed(d); }
  function bits(bps) {
    if (!(bps > 0)) return ["0", "Kb/s"];
    if (bps < 1e6) return [nf(bps / 1e3, bps < 1e4 ? 1 : 0), "Kb/s"];
    if (bps < 1e9) return [nf(bps / 1e6, bps < 1e7 ? 1 : 0), "Mb/s"];
    return [nf(bps / 1e9, 2), "Gb/s"];
  }
  function bitsStr(b) { var x = bits(b); return x[0] + " " + x[1]; }
  function gib(b) { return nf(b / 1073741824, b >= 1e11 ? 0 : 1); }
  function gb(b) { return b >= 1e12 ? nf(b / 1e12, 2) + " TB" : nf(b / 1e9, b >= 1e11 ? 0 : 1) + " GB"; }
  function mbps(b) { return b < 1e6 ? nf(b / 1e3, 0) + " KB/s" : nf(b / 1e6, b < 1e7 ? 1 : 0) + " MB/s"; }
  function now() { return new Date(Date.now() + clockOffset); }
  function fmt(d, opts) {
    var o = {}; for (var k in opts) o[k] = opts[k];
    if (tz) o.timeZone = tz;
    try { return new Intl.DateTimeFormat("en-US", o).format(d); } catch (e) { delete o.timeZone; return new Intl.DateTimeFormat("en-US", o).format(d); }
  }
  function ago(ms) {
    var s = (now().getTime() - ms) / 1000;
    if (s < 90) return "Just now";
    if (s < 3600) return Math.round(s / 60) + " min ago";
    if (s < 86400) return Math.round(s / 3600) + " hr ago";
    return Math.round(s / 86400) === 1 ? "Yesterday" : Math.round(s / 86400) + " days ago";
  }
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  function push(k, v) { var a = hist[k]; a.push(v); if (a.length > HMAX) a.splice(0, a.length - HMAX); }

  // ---------- Stage scaling ----------
  var stageScale = 1;
  function fit() {
    stageScale = Math.min(window.innerWidth / 1024, window.innerHeight / 600);
    // At the Fire 7's native 1024×600 no transform is applied (keeps text on the pixel grid and avoids compositing glitches).
    $("stage").style.transform = Math.abs(stageScale - 1) < 0.01 ? "none" : "scale(" + stageScale + ")";
    if (Math.abs(stageScale - 1) < 0.01) stageScale = 1;
    sizeCanvases();
  }
  window.addEventListener("resize", fit);
  document.addEventListener("mousemove", function () { document.body.classList.add("pointer"); });

  // Compact: metrics stack in one narrow column (left quarter) instead of the left half.
  function applyLayout() {
    var on = !!cfg.compact;
    if (document.body.classList.contains("compact") === on) return;
    document.body.classList.toggle("compact", on);
    // Canvases change shape after the column animates; re-measure as it settles and once done.
    [60, 400, 900].forEach(function (ms) { setTimeout(sizeCanvases, ms); });
  }

  // ---------- Sparklines ----------
  var canvases = ["cpu-spark", "gpu-spark", "mem-spark", "net-spark"];
  function sizeCanvases() {
    var r = (window.devicePixelRatio || 1) * stageScale;
    canvases.forEach(function (id) {
      var c = $(id); c.width = Math.round(c.clientWidth * r); c.height = Math.round(c.clientHeight * r); c._r = r;
    });
  }
  var colorCache = {};
  function cssVar(name) {
    var key = theme + name;
    if (!colorCache[key]) colorCache[key] = getComputedStyle(document.body).getPropertyValue(name).trim() || "#888";
    return colorCache[key];
  }
  function rgba(hex, a) {
    var h = hex.replace("#", "");
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    var n = parseInt(h, 16);
    return "rgba(" + (n >> 16 & 255) + "," + (n >> 8 & 255) + "," + (n & 255) + "," + a + ")";
  }
  function spark(id, seriesList, max) {
    var c = $(id), ctx = c.getContext("2d"), w = c.width, h = c.height, r = c._r || 1;
    ctx.clearRect(0, 0, w, h);
    var fillA = parseFloat(cssVar("--spark-alpha")) || 0.3;
    seriesList.forEach(function (s, idx) {
      var data = s.data, n = HMAX;
      if (!data.length) return;
      var col = cssVar(s.color);
      var x = function (i) { return w - (data.length - 1 - i) * (w / (n - 1)); };
      var y = function (v) { return h - 2 * r - Math.min(1, v / max) * (h - 8 * r); };
      ctx.beginPath();
      for (var i = 0; i < data.length; i++) { var X = x(i), Y = y(data[i]); if (i) ctx.lineTo(X, Y); else ctx.moveTo(X, Y); }
      if (!s.lineOnly) {
        ctx.save();
        ctx.lineTo(w, h); ctx.lineTo(x(0), h); ctx.closePath();
        var g = ctx.createLinearGradient(0, 0, 0, h);
        g.addColorStop(0, rgba(col, fillA)); g.addColorStop(1, rgba(col, 0.02));
        ctx.fillStyle = g; ctx.fill(); ctx.restore();
        ctx.beginPath();
        for (var j = 0; j < data.length; j++) { var X2 = x(j), Y2 = y(data[j]); if (j) ctx.lineTo(X2, Y2); else ctx.moveTo(X2, Y2); }
      }
      ctx.strokeStyle = col; ctx.lineWidth = 2.6 * r; ctx.lineJoin = "round"; ctx.lineCap = "round";
      if (s.dash) ctx.setLineDash([5 * r, 4 * r]); else ctx.setLineDash([]);
      ctx.stroke();
    });
  }
  function niceMax(v) {
    var floor = 1e6; v = Math.max(v, floor);
    var p = Math.pow(10, Math.floor(Math.log10(v))), m = v / p;
    return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 5 ? 5 : 10) * p;
  }

  // ---------- Metrics ----------
  function setText(id, t) { var e = $(id); if (e.textContent !== t) e.textContent = t; }

  function renderMetrics(m) {
    var cpu = m.cpu || {}, gpu = m.gpu || {}, mem = m.mem || {}, disk = m.disk || {}, net = m.net || {};
    setText("cpu-val", Math.round(cpu.usage || 0) + "");
    setText("cpu-aside", (cpu.coreCount || "") + " cores");
    setText("cpu-sub", "Load " + nf(cpu.load || 0, 2) + (m.thermal && m.thermal !== "nominal" ? " · " + m.thermal[0].toUpperCase() + m.thermal.slice(1) + " temp" : ""));

    setText("gpu-val", Math.round(gpu.usage || 0) + "");
    setText("gpu-aside", "");
    setText("gpu-sub", gpu.memUsed ? gib(gpu.memUsed) + " GB in use" : "Apple GPU");

    setText("mem-val", Math.round(mem.percent || 0) + "");
    setText("mem-aside", mem.swapUsed > 1e9 ? "Swap " + gib(mem.swapUsed) + " GB" : "");
    setText("mem-sub", gib(mem.used || 0) + " of " + Math.round((mem.total || 0) / 1073741824) + " GB");
    $("mem-val").style.color = mem.pressure === "critical" ? "var(--up)" : mem.pressure === "warn" ? "var(--disk)" : "";

    // Every connected drive takes a turn (6 s each).
    var vols = disk.volumes && disk.volumes.length ? disk.volumes : [disk];
    var vi = Math.floor(Date.now() / 6000) % vols.length, vol = vols[vi];
    setText("disk-val", Math.round(vol.percent || 0) + "");
    setText("disk-aside", vol.name || "");
    setText("disk-sub", gb(vol.free || 0) + " free");
    $("disk-bar").style.width = (vol.percent || 0).toFixed(1) + "%";
    $("disk-bar").className = "fill" + ((vol.percent || 0) > 90 ? " hot" : "");
    var vdots = "";
    if (vols.length > 1) for (var vj = 0; vj < vols.length; vj++) vdots += '<i class="' + (vj === vi ? "on" : "") + '"></i>';
    if ($("disk-io").getAttribute("data-k") !== vi + "/" + vols.length) {
      $("disk-io").setAttribute("data-k", vi + "/" + vols.length);
      $("disk-io").innerHTML = (vols.length > 1 ? '<span class="vdots">' + vdots + "</span>" : "") + '<span class="vtot">' + gb(vol.total || 0) + " drive</span>";
      $("t-disk").classList.remove("swap"); void $("t-disk").offsetWidth; $("t-disk").classList.add("swap");
    }

    var d = bits(net.rxBps || 0), u = bits(net.txBps || 0);
    setText("net-down", d[0]); setText("net-down-u", d[1]);
    setText("net-up", u[0]); setText("net-up-u", u[1]);
    setText("net-aside", net.ifaceName || net.iface || "");
    var st = net.speedTest || {}, sub;
    if (net.speedTestRunning) sub = "Speed test running…";
    else if (st.down) sub = "Speed test  ↓ " + bitsStr(st.down) + "  ↑ " + bitsStr(st.up) + "  ·  " + ago(st.at);
    else if (st.error) sub = "Speed test unavailable";
    else sub = "Speed test pending";
    setText("net-sub", sub);

    spark("cpu-spark", [{ data: hist.cpu, color: "--cpu" }], 100);
    spark("gpu-spark", [{ data: hist.gpu, color: "--gpu" }], 100);
    spark("mem-spark", [{ data: hist.mem, color: "--mem" }], 100);
    var nm = niceMax(Math.max.apply(null, hist.rx.concat(hist.tx, [0])) * 1.1);
    spark("net-spark", [{ data: hist.tx, color: "--up", lineOnly: true }, { data: hist.rx, color: "--down" }], nm);
  }

  // ---------- Claude Code usage (optional tile, sent with each metrics poll) ----------
  function tok(n) {
    n = n || 0;
    var t = function (v, d) { return nf(v, d).replace(/\.0$/, ""); };
    return n >= 1e9 ? t(n / 1e9, 1) + "B" : n >= 1e6 ? t(n / 1e6, n >= 1e8 ? 0 : 1) + "M" : n >= 1e3 ? Math.round(n / 1e3) + "K" : String(n);
  }
  function until(ms) {
    var s = Math.max(0, (ms - now().getTime()) / 1000), d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
    return d ? d + "d " + h + "h" : h ? h + "h " + m + "m" : m + "m";
  }
  var claudeOn = null, lastClaude = null;
  function renderClaude(c) {
    var on = !!c;
    if (on !== claudeOn) {
      claudeOn = on; $("t-claude").hidden = !on;
      document.body.classList.toggle("claude", on);
      [60, 400, 900].forEach(function (ms) { setTimeout(sizeCanvases, ms); });
    }
    lastClaude = c || null;
    if (!c) return;
    var x = c.ctx;
    setText("cl-val", x ? Math.round(x.left) + "" : "–");
    setText("cl-aside", x ? x.model : "");
    $("cl-bar").style.width = x ? (100 - x.left).toFixed(1) + "%" : "0%";
    $("cl-bar").className = "fill" + (x && x.left < 15 ? " hot" : "");
    var sub = c.loading ? "Reading Claude Code usage…" : !c.any ? "No Claude Code activity yet" :
      tok(c.today) + " today" + (c.reset ? " · reset " + until(c.reset) : "");
    setText("cl-sub", sub);
  }

  function setTheme(t) {
    if (t === theme && document.body.classList.contains(t)) return;
    theme = t;
    document.body.classList.remove("day", "night");
    document.body.classList.add(t);
  }

  var lastSettled = Date.now(), pollTimer = null, reloadRequestedAt = 0;
  function pollMetrics() {
    clearTimeout(pollTimer);
    var url = "/api/metrics" + (gotHistory ? "" : "?h=1");
    fetchJSON(url, 3000).then(function (j) {
      failures = 0;
      lastOkAt = Date.now();
      document.body.classList.remove("offline");
      lastMetrics = j.m || lastMetrics;
      presence = j.presence || "awake";
      if (presence !== "awake") { awakeStreak = 0; enterStandby(presence); }
      else if (standby && ++awakeStreak >= 2) exitStandby();
      if (j.m && j.m.t) clockOffset = j.m.t - Date.now();
      if (j.tz) tz = j.tz;
      if (j.h) {
        for (var k in hist) if (j.h[k]) hist[k] = j.h[k].slice(-HMAX);
        gotHistory = true;
      } else if (j.m) {
        push("cpu", j.m.cpu.usage); push("gpu", j.m.gpu.usage || 0); push("mem", j.m.mem.percent || 0);
        push("rx", j.m.net.rxBps || 0); push("tx", j.m.net.txBps || 0);
      }
      macTheme = j.theme === "night" ? "night" : "day";
      setTheme(forcedTheme || (standby ? standbyTheme() : macTheme));
      lastDay = j.day || lastDay;
      applyDay(forcedDay ? mergeDay(j.day, forcedDay) : j.day);
      if (host && host.setBrightness && j.brightness !== lastBrightness) {
        lastBrightness = j.brightness;
        if (screenOn) { try { host.setBrightness(j.brightness); } catch (e) {} }
      }
      // The Mac app was updated/restarted: reload once to pick up new display code. Keep rendering
      // meanwhile, and if the reload never happens (stalled navigation), try again after 20 s.
      if (reloadToken !== null && j.reload !== reloadToken && Date.now() - reloadRequestedAt > 20000) {
        reloadRequestedAt = Date.now();
        if (host && host.reload) { try { host.reload(); } catch (e) { location.reload(); } }
        else location.reload();
      }
      if (reloadToken === null) reloadToken = j.reload;
      if (j.rev !== cfgRev) loadConfig(j.rev);
      if (j.fv !== feedsVer) loadFeeds(j.fv);
      if (j.screen) screenFromMac(j.screen);
      renderUpdate(j.version);
      renderClaude(j.claude);
      if (j.m) {
        saveCache(false);
        renderMetrics(j.m);
        if (host && host.heartbeat) { try { host.heartbeat(); } catch (e) {} }
      }
    }).catch(function () {
      failures++;
      if (failures >= 3) document.body.classList.add("offline");
      // Mac gone quiet for 20 s without saying goodbye (unplugged, crashed, slept before we heard): standby too.
      if (!standby && Date.now() - lastOkAt > 20000) enterStandby(presence === "awake" ? "unreachable" : presence);
    }).then(function () { lastSettled = Date.now(); pollTimer = setTimeout(pollMetrics, 1000); });
  }
  // Safety net: if the poll loop ever stalls (e.g. a request swallowed by an interrupted reload), restart it.
  setInterval(function () { if (Date.now() - lastSettled > 15000) { lastSettled = Date.now(); pollMetrics(); } }, 5000);

  function fetchJSON(url, timeout) {
    return new Promise(function (resolve, reject) {
      var x = new XMLHttpRequest();
      x.open("GET", url, true);
      x.timeout = timeout || 8000;
      x.onload = function () { if (x.status === 200) { try { resolve(JSON.parse(x.responseText)); } catch (e) { reject(e); } } else reject(x.status); };
      x.onerror = x.ontimeout = x.onabort = function () { reject("net"); };
      x.send();
    });
  }

  function loadConfig(rev) {
    fetchJSON("/api/config").then(function (c) { cfg = c; cfgRev = rev; applyLayout(); buildSlides(); updateClock(); saveCache(true); });
  }
  function loadFeeds(v) {
    fetchJSON("/api/feeds").then(function (f) { feeds = f; feedsVer = v; buildSlides(); renderGlance(); saveCache(true); });
  }

  // ---------- Offline cache: lets the display carry on (and survive a reload) while the Mac is away ----------
  var lastCacheSave = 0, lastMetrics = null, lastDay = null, macTheme = "day";
  function saveCache(force) {
    if (!window.localStorage || (!force && Date.now() - lastCacheSave < 60000)) return;
    lastCacheSave = Date.now();
    try {
      localStorage.setItem("plinth.cache", JSON.stringify({ cfg: cfg, feeds: feeds, clockOffset: clockOffset, tz: tz,
        theme: macTheme, day: lastDay, savedAt: Date.now() }));
    } catch (e) {}
  }
  function loadCache() {
    try {
      var c = JSON.parse(localStorage.getItem("plinth.cache") || "null");
      if (!c) return false;
      cfg = c.cfg || cfg; feeds = c.feeds || feeds; clockOffset = c.clockOffset || 0; tz = c.tz; macTheme = c.theme || "day"; applyLayout();
      lastDay = c.day; if (c.day) applyDay(c.day);
      setTheme(forcedTheme || macTheme);
      return true;
    } catch (e) { return false; }
  }

  // ---------- Standby: Mac asleep or logged out → clock, weather and cards take the whole screen ----------
  var standby = false, presence = "awake", awakeStreak = 0, lastOkAt = Date.now(), standbyTimers = [];
  var AWAY = {
    locked: ["Mac is locked", '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><rect x="4.5" y="10.5" width="15" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/></svg>'],
    sleeping: ["Mac is asleep", '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M14.5 3a8.5 8.5 0 1 0 6.4 14.1A7 7 0 0 1 14.5 3z"/></svg>'],
    loggedOut: ["Mac is logged out", '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>'],
    quitting: ["Matchbox Dashboard isn’t running on the Mac", '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><rect x="3" y="5" width="18" height="12" rx="2"/><path d="M8 21h8"/></svg>'],
    unreachable: ["Can’t reach the Mac", '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M2 8.5a15 15 0 0 1 20 0M5 12a10 10 0 0 1 14 0M8.5 15.5a5 5 0 0 1 7 0"/><path d="M3 3l18 18"/></svg>'],
  };
  function enterStandby(reason) {
    var a = AWAY[reason] || AWAY.unreachable;
    $("away").innerHTML = a[1] + "<span>" + a[0] + "</span>";
    if (standby) return;
    standby = true;
    document.body.classList.add("standby");
    if (window.PlinthSheets) PlinthSheets.closeMetricSheets();
    rerenderCurrent(); renderGlance();
    setTheme(forcedTheme || standbyTheme());
    // Keep weather and scores fresh straight from the internet if the tablet has Wi-Fi.
    standbyTimers.push(setInterval(directWeather, 15 * 60000));
    standbyTimers.push(setInterval(directSports, 2 * 60000));
    standbyTimers.push(setInterval(function () { setTheme(forcedTheme || standbyTheme()); }, 60000));
    var wAt = feeds.weatherAt || 0;
    if (now().getTime() - wAt > 15 * 60000) directWeather();
    setTimeout(directSports, 5000);
  }
  function exitStandby() {
    standby = false;
    document.body.classList.remove("standby");
    standbyTimers.forEach(clearInterval); standbyTimers = [];
    rerenderCurrent(); renderGlance();
    setTimeout(sizeCanvases, 900);
  }
  function rerenderCurrent() {
    if (slides[slideIdx]) $("slide-" + activeLayer).innerHTML = renderSlide(slides[slideIdx]);
  }
  /** While the Mac is away, follow sunrise/sunset at the weather location for day/night. */
  function standbyTheme() {
    var mode = cfg.theme || "auto";
    if (mode === "day" || mode === "night") return mode;
    if (presence === "locked") return macTheme;  // the Mac is still up, so follow it
    var w = feeds.weather, d = w && w.daily;
    if (!d || !d.sunrise) return macTheme;
    var off = (w.utc_offset_seconds || 0) * 1000, t = now().getTime();
    for (var i = 0; i < d.sunrise.length; i++) {
      var rise = Date.parse(d.sunrise[i] + ":00Z") - off, set = Date.parse(d.sunset[i] + ":00Z") - off;
      if (t < rise) return "night";
      if (t < set) return "day";
    }
    return "night";
  }
  function weatherURL() {
    var l = cfg.location || {}, metric = cfg.units === "metric";
    return "https://api.open-meteo.com/v1/forecast?latitude=" + l.lat + "&longitude=" + l.lon +
      "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day,precipitation,pressure_msl,uv_index,visibility,dew_point_2m" +
      "&hourly=temperature_2m,weather_code,precipitation_probability,is_day" +
      "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,uv_index_max,precipitation_sum,wind_speed_10m_max" +
      "&timezone=auto&forecast_days=7&forecast_hours=24&temperature_unit=" + (metric ? "celsius" : "fahrenheit") + "&wind_speed_unit=" + (metric ? "kmh" : "mph");
  }
  function directWeather() {
    if (!cfg.location || cfg.location.lat == null) return;
    fetchJSON(weatherURL(), 15000).then(function (w) {
      feeds.weather = w; feeds.weatherAt = now().getTime();
      buildSlides(); renderGlance(); saveCache(true);
    }).catch(function () {});
  }
  var LEAGUE_NAMES = { "football/nfl": "NFL", "basketball/nba": "NBA", "baseball/mlb": "MLB", "hockey/nhl": "NHL", "basketball/wnba": "WNBA",
    "football/college-football": "NCAAF", "basketball/mens-college-basketball": "NCAAM", "basketball/womens-college-basketball": "NCAAW",
    "soccer/usa.1": "MLS", "soccer/eng.1": "Premier League", "soccer/esp.1": "La Liga", "soccer/uefa.champions": "Champions League", "soccer/usa.nwsl": "NWSL" };
  function parseScoreboard(j, league, favs) {
    var out = [];
    (j.events || []).forEach(function (ev) {
      var comp = (ev.competitions || [])[0]; if (!comp) return;
      var st = (ev.status && ev.status.type) || {}, teams = {}, isFav = false;
      (comp.competitors || []).forEach(function (c) {
        var t = c.team || {}, abbr = t.abbreviation || "?", short = t.shortDisplayName || t.name || abbr, disp = t.displayName || short;
        var fav = favs.indexOf(abbr.toUpperCase()) >= 0 || favs.indexOf(short.toUpperCase()) >= 0 || favs.indexOf(disp.toUpperCase()) >= 0;
        isFav = isFav || fav;
        teams[c.homeAway || "home"] = { abbr: abbr, name: short, color: t.color || "888888", score: c.score || "",
          record: ((c.records || [])[0] || {}).summary || "", favorite: fav, winner: !!c.winner };
      });
      var nets = [];
      (comp.broadcasts || []).forEach(function (b) { (b.names || []).forEach(function (n) { if (nets.indexOf(n) < 0) nets.push(n); }); });
      var sit = comp.situation || {};
      out.push({ id: ev.id, league: LEAGUE_NAMES[league] || league, date: ev.date, state: st.state || "pre", detail: st.shortDetail || "",
        home: teams.home || {}, away: teams.away || {}, broadcasts: nets, situation: sit.downDistanceText || "", favorite: isFav });
    });
    return out;
  }
  function directSports() {
    var sc = cfg.sports || {}, leagues = sc.leagues || [];
    if (!leagues.length) return;
    var favs = (sc.favorites || []).map(function (f) { return String(f).toUpperCase().trim(); });
    Promise.all(leagues.map(function (lg) {
      return fetchJSON("https://site.api.espn.com/apis/site/v2/sports/" + lg + "/scoreboard", 15000)
        .then(function (j) { return parseScoreboard(j, lg, favs); }).catch(function () { return null; });
    })).then(function (lists) {
      if (lists.every(function (l) { return l === null; })) return;   // offline — keep what we have
      var all = [].concat.apply([], lists.filter(Boolean));
      var rank = function (g) { return g.state === "in" ? 0 : g.state === "pre" ? 1 : 2; };
      all.sort(function (a, b) {
        if (rank(a) !== rank(b)) return rank(a) - rank(b);
        if (a.favorite !== b.favorite) return a.favorite ? -1 : 1;
        return rank(a) === 2 ? (b.date > a.date ? 1 : -1) : (a.date > b.date ? 1 : -1);
      });
      feeds.sports = all; buildSlides();
    });
  }

  // ---------- Clock + weather glance ----------
  function updateClock() {
    var d = now(), h24 = !!cfg.clock24h;
    var parts = fmt(d, { hour: "numeric", minute: "2-digit", hour12: !h24 });
    var m = parts.match(/^([\d:]+)\s*([AP]M)?$/i);
    setText("time", m ? m[1] : parts);
    setText("ampm", m && m[2] ? m[2] : "");
    setText("date", fmt(d, { weekday: "long", month: "long", day: "numeric" }));
  }
  function renderGlance() {
    var w = feeds.weather, el = $("glance");
    if (!w || !w.current) { el.innerHTML = ""; return; }
    var c = w.current;
    el.innerHTML = '<div class="g-icon">' + wxIcon(c.weather_code, c.is_day) + "</div>" +
      '<div><div class="g-temp">' + Math.round(c.temperature_2m) + "°</div>" +
      '<div class="g-cond">' + wxKind(c.weather_code)[1] + "</div>" +
      '<div class="g-loc">' + esc((cfg.location && cfg.location.name) || "") + "</div></div>";
  }

  // ---------- Cycling cards ----------
  var slides = [], slideIdx = 0, slideTimer = null, activeLayer = "a", currentKey = null;
  var CHIP = {
    weather: { icon: ICONS.chipWeather, bg: "linear-gradient(160deg,#3ea8ff,#0a6be0)" },
    sports: { icon: ICONS.chipSports, bg: "linear-gradient(160deg,#ffb340,#ff7a00)" },
    news: { icon: ICONS.chipNews, bg: "linear-gradient(160deg,#8b88ff,#5856d6)" },
    youtube: { icon: ICONS.chipYouTube, bg: "linear-gradient(160deg,#ff4545,#d20f0f)" },
    anime: { icon: ICONS.chipAnime, bg: "linear-gradient(160deg,#ff9a3c,#f47521)" },
    bluesky: { icon: ICONS.chipBluesky, bg: "linear-gradient(160deg,#3ba1ff,#0a6cf0)" },
    steamUp: { icon: ICONS.chipSteam, bg: "linear-gradient(160deg,#2a475e,#171a21)" },
    steamDeals: { icon: ICONS.chipDeal, bg: "linear-gradient(160deg,#6ea21b,#4c6b22)" },
    steamAch: { icon: ICONS.chipTrophy, bg: "linear-gradient(160deg,#4b6a8f,#1b2838)" },
    steamClosest: { icon: ICONS.chipTarget, bg: "linear-gradient(160deg,#66c0f4,#2a6f9e)" },
    steamNews: { icon: ICONS.chipNews, bg: "linear-gradient(160deg,#2a475e,#171a21)" },
    fx: { icon: ICONS.chipFX, bg: "linear-gradient(160deg,#34c759,#1f8f3e)" },
    kanji: { icon: ICONS.chipKanji, bg: "linear-gradient(160deg,#ff5a5f,#c81d3a)" },
    radar: { icon: ICONS.chipRadar, bg: "linear-gradient(160deg,#30b0c7,#0a7b91)" },
    slickdeals: { icon: ICONS.chipSlick, bg: "linear-gradient(160deg,#2f8cff,#1360c9)" },
  };

  function chunk(arr, n) { var out = []; for (var i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n)); return out; }

  function buildSlides() {
    var cards = cfg.cards || {}, queues = [];
    if (cards.weather !== false && feeds.weather && feeds.weather.current) {
      queues.push([{ key: "wx", type: "weather", title: "Weather", sub: (cfg.location && cfg.location.name) || "" }]);
    }
    if (cards.sports !== false) {
      var sc = cfg.sports || {}, per = Math.max(2, Math.min(5, sc.maxPerCard || 4));
      var games = (feeds.sports || []).filter(function (g) {
        if (sc.onlyFavorites && !g.favorite) return false;
        if (sc.includeFinals === false && g.state === "post") return false;
        return true;
      });
      var byLeague = {}, order = [];
      games.forEach(function (g) { if (!byLeague[g.league]) { byLeague[g.league] = []; order.push(g.league); } byLeague[g.league].push(g); });
      var q = [];
      order.forEach(function (lg) {
        chunk(byLeague[lg], per).slice(0, 3).forEach(function (grp, i, all) {
          var live = grp.filter(function (g) { return g.state === "in"; }).length;
          q.push({ key: "sp:" + lg + ":" + i, type: "sports", title: lg, games: grp,
                   sub: (live ? live + " live" : grp[0].state === "pre" ? "Upcoming" : "Final") + (all.length > 1 ? "  " + (i + 1) + "/" + all.length : "") });
        });
      });
      if (q.length) queues.push(q);
    }
    if (cards.news !== false) {
      var per2 = Math.max(2, Math.min(4, cfg.headlinesPerCard || 3)), nq = [];
      (feeds.news || []).forEach(function (f, fi) {
        chunk(f.items || [], per2).slice(0, 2).forEach(function (grp, i) {
          nq.push({ key: "nw:" + fi + ":" + i, type: "news", title: f.name, sub: "Headlines", items: grp });
        });
      });
      if (nq.length) queues.push(nq);
    }
    if (cards.youtube !== false && feeds.youtube && feeds.youtube.length) {
      var yq = chunk(feeds.youtube, 3).slice(0, 3).map(function (grp, i, all) {
        return { key: "yt:" + i, type: "youtube", title: "YouTube", sub: "Latest uploads" + (all.length > 1 ? "  " + (i + 1) + "/" + all.length : ""), items: grp };
      });
      queues.push(yq);
    }
    if (cards.anime !== false && feeds.anime && feeds.anime.length) {
      var shows = upcomingAnime();
      if (shows.length) {
        queues.push(chunk(shows, 4).slice(0, 2).map(function (grp, i, all) {
          return { key: "an:" + i, type: "anime", title: "Anime", sub: "Next episodes" + (all.length > 1 ? "  " + (i + 1) + "/" + all.length : ""), shows: grp };
        }));
      }
    }
    if (cards.bluesky !== false && feeds.bluesky && feeds.bluesky.length) {
      queues.push(chunk(feeds.bluesky, 2).slice(0, 4).map(function (grp, i, all) {
        return { key: "bs:" + i, type: "bluesky", title: "Bluesky", sub: "Latest posts" + (all.length > 1 ? "  " + (i + 1) + "/" + all.length : ""), items: grp };
      }));
    }
    var steamUp = upcomingSteam();
    if (cards.steamUpcoming !== false && steamUp.length) {
      queues.push(chunk(steamUp, 4).slice(0, 2).map(function (grp, i, all) {
        return { key: "su:" + i, type: "steamUp", title: "Steam", sub: "Coming soon" + (all.length > 1 ? "  " + (i + 1) + "/" + all.length : ""), items: grp };
      }));
    }
    var minPct = (cfg.steam && cfg.steam.minDiscount) || 0;
    var deals = (feeds.steamDeals || []).filter(function (d) { return d.pct >= minPct && (!d.ends || d.ends > now().getTime()); });
    if (cards.steamDeals !== false && deals.length) {
      queues.push(chunk(deals, 4).slice(0, 2).map(function (grp, i, all) {
        return { key: "sd:" + i, type: "steamDeals", title: "Steam Deals", sub: deals.length + " on sale" + (all.length > 1 ? "  " + (i + 1) + "/" + all.length : ""), items: grp };
      }));
    }
    function paged(key, list, per, max, type, title, sub) {
      if (!list || !list.length) return;
      queues.push(chunk(list, per).slice(0, max).map(function (grp, i, all) {
        return { key: key + ":" + i, type: type, title: title, sub: sub + (all.length > 1 ? "  " + (i + 1) + "/" + all.length : ""), items: grp };
      }));
    }
    if (cards.steamAchievements !== false) paged("sa", feeds.steamRecent, 3, 3, "steamAch", "Achievements", "Recently unlocked");
    if (cards.steamClosest !== false) paged("sc", feeds.steamClosest, 3, 2, "steamClosest", "Achievements", "Within reach");
    if (cards.steamNews !== false) paged("sn", feeds.steamNews, 2, 4, "steamNews", "Steam News", "Your games");
    if (cards.slickdeals !== false) paged("sk", feeds.slickdeals, 3, 4, "slickdeals", "Slickdeals", "Latest deals");
    if (cards.fx !== false && feeds.fx && feeds.fx.length) {
      queues.push(feeds.fx.map(function (p, i) { return { key: "fx:" + p.from + p.to, type: "fx", title: "Exchange Rate", sub: p.from + " → " + p.to, pair: p }; }));
    }
    if (cards.kanji !== false && feeds.kanji && feeds.kanji.kanji) {
      queues.push([{ key: "kj:" + feeds.kanji.kanji, type: "kanji", title: "Kanji of the Hour", sub: levelName(feeds.kanji.level) }]);
    }
    if (cards.radar !== false && feeds.radar && feeds.radar.frames && feeds.radar.frames.length) {
      queues.push([{ key: "rd", type: "radar", title: "Radar", sub: feeds.radar.name || "" }]);
    }
    // Round-robin across categories so weather, scores and headlines interleave.
    var out = [], more = true, round = 0;
    while (more) {
      more = false;
      queues.forEach(function (q) { if (round < q.length) { out.push(q[round]); more = true; } });
      round++;
    }
    slides = out;
    // keep showing the same slide if it still exists; refresh its content in place
    var idx = -1;
    for (var i = 0; i < slides.length; i++) if (slides[i].key === currentKey) idx = i;
    if (idx >= 0) {
      slideIdx = idx;
      if (slides[idx].type !== "radar" && slides[idx].type !== "kanji") {     // don't restart animations on a data refresh
        $("slide-" + activeLayer).innerHTML = renderSlide(slides[idx]);
        hydrate($("slide-" + activeLayer), slides[idx]);
      }
      renderHead(slides[idx]);
    } else {
      show(0, true);
    }
    if (!slideTimer) scheduleNext();
  }

  function renderHead(s) {
    var chip = CHIP[s.type];
    $("card-chip").innerHTML = chip.icon; $("card-chip").style.background = chip.bg;
    setText("card-title", s.title || "");
    setText("card-sub", s.sub || "");
    var dots = "";
    var n = Math.min(slides.length, 10);
    for (var i = 0; i < n; i++) dots += '<i class="' + (i === slideIdx % 10 ? "on" : "") + '"></i>';
    $("dots").innerHTML = slides.length > 1 ? dots : "";
  }

  function show(i, immediate, dir) {
    clearInterval(radarTimer);
    if (!slides.length) {
      $("card-chip").innerHTML = ""; $("card-chip").style.background = "transparent";
      setText("card-title", "Matchbox Dashboard"); setText("card-sub", ""); $("dots").innerHTML = "";
      $("slide-a").innerHTML = '<div class="empty">Waiting for weather, scores<br>and headlines from your Mac…</div>';
      $("slide-a").className = "slide show"; $("slide-b").className = "slide";
      activeLayer = "a"; currentKey = null;
      return;
    }
    slideIdx = (i + slides.length) % slides.length;
    var s = slides[slideIdx];
    var next = activeLayer === "a" ? "b" : "a";
    var inEl = $("slide-" + next), outEl = $("slide-" + activeLayer);
    inEl.innerHTML = renderSlide(s);
    hydrate(inEl, s);
    renderHead(s);
    outEl.style.transform = ""; inEl.style.transform = "";
    if (immediate) { outEl.className = "slide"; inEl.className = "slide show"; }
    else if (dir) {
      // Swipe: new card slides in from the side it was pulled from.
      inEl.className = "slide " + (dir > 0 ? "enter-right" : "enter-left");
      outEl.className = "slide " + (dir > 0 ? "exit-left" : "exit-right");
      void inEl.offsetWidth; inEl.className = "slide show";
    } else {
      outEl.className = "slide";
      // force layout so the transition runs
      void inEl.offsetWidth; inEl.className = "slide show";
    }
    activeLayer = next; currentKey = s.key;
  }

  var paused = false;
  try { paused = localStorage.getItem("plinth.paused") === "1"; } catch (e) {}
  function scheduleNext(holdSecs) {
    clearTimeout(slideTimer);
    var secs = holdSecs || Math.max(4, cfg.cycleSeconds || 12);
    var bar = $("progress");
    bar.style.transition = "none"; bar.style.width = "0%";
    void bar.offsetWidth;
    $("card").classList.toggle("paused", paused);
    if (paused) { slideTimer = -1; return; }
    if (slides.length > 1) { bar.style.transition = "width " + secs + "s linear"; bar.style.width = "100%"; }
    slideTimer = setTimeout(function () { show(slideIdx + 1); scheduleNext(); }, secs * 1000);
  }

  function renderSlide(s) {
    if (s.type === "weather") return renderWeather();
    if (s.type === "sports") return renderGames(s.games);
    if (s.type === "news") return renderNews(s.items);
    if (s.type === "youtube") return renderYouTube(s.items);
    if (s.type === "anime") return renderAnime(s.shows);
    if (s.type === "bluesky") return renderBluesky(s.items);
    if (s.type === "steamUp") return renderSteamUp(s.items);
    if (s.type === "steamDeals") return renderDeals(s.items);
    if (s.type === "steamAch") return renderAch(s.items, false);
    if (s.type === "steamClosest") return renderAch(s.items, true);
    if (s.type === "steamNews") return renderSteamNews(s.items);
    if (s.type === "slickdeals") return renderSlick(s.items);
    if (s.type === "fx") return renderFX(s.pair);
    if (s.type === "kanji") return renderKanji(feeds.kanji);
    if (s.type === "radar") return '<div class="radar" data-href="' + esc(feeds.radar.url) + '" data-qt="Rain radar · ' + esc(feeds.radar.name || "") + '"><div class="rmap"></div><div class="rtime"></div><div class="rcred">RainViewer · © OpenStreetMap contributors</div></div>';
    return "";
  }

  function renderWeather() {
    var w = feeds.weather, c = w.current, d = w.daily || {}, hr = w.hourly || {};
    var kind = wxKind(c.weather_code), u = (w.current_units || {});
    var html = '<div class="wx-now"><div class="w-icon">' + wxIcon(c.weather_code, c.is_day) + "</div>" +
      '<div class="wx-temp">' + Math.round(c.temperature_2m) + "°</div>" +
      '<div class="wx-desc"><div class="cond">' + kind[1] + "</div>";
    if (d.temperature_2m_max) html += '<div class="hl">H ' + Math.round(d.temperature_2m_max[0]) + "°  L " + Math.round(d.temperature_2m_min[0]) + "°</div>";
    var wu = (u.wind_speed_10m || "").replace("mp/h", "mph").replace("km/h", "km/h");
    html += '<div class="feels">Feels ' + Math.round(c.apparent_temperature) + "°  ·  " + Math.round(c.wind_speed_10m) + " " + esc(wu) + "</div></div></div>";

    // next hours
    if (hr.time) {
      var startKey = (c.time || "").slice(0, 13), start = 0;
      for (var i = 0; i < hr.time.length; i++) { if (hr.time[i].slice(0, 13) >= startKey) { start = i; break; } }
      html += '<div class="wx-hours">';
      for (var j = start, n = 0; j < hr.time.length && n < 7; j += (n === 0 ? 1 : 2), n++) {
        var hh = parseInt(hr.time[j].slice(11, 13), 10);
        var lbl = n === 0 ? "Now" : (cfg.clock24h ? (hh < 10 ? "0" : "") + hh + ":00" : ((hh % 12) || 12) + (hh < 12 ? " AM" : " PM"));
        html += '<div class="h"><div class="t">' + lbl + '</div><div class="i">' + wxIcon(hr.weather_code[j], hr.is_day ? hr.is_day[j] : 1) +
                '</div><div class="v">' + Math.round(hr.temperature_2m[j]) + "°</div></div>";
      }
      html += "</div>";
    }
    // daily
    if (d.time) {
      html += '<div class="wx-days">';
      for (var k = 0; k < Math.min(standby ? 7 : 5, d.time.length); k++) {
        var dt = new Date(d.time[k] + "T12:00:00Z");
        var name = k === 0 ? "Today" : new Intl.DateTimeFormat("en-US", { weekday: "short", timeZone: "UTC" }).format(dt);
        var pp = d.precipitation_probability_max ? d.precipitation_probability_max[k] : 0;
        html += '<div class="d"><div class="n">' + name + '</div><div class="i">' + wxIcon(d.weather_code[k], 1) + "</div>" +
                '<div><span class="hi">' + Math.round(d.temperature_2m_max[k]) + '°</span><span class="lo">' + Math.round(d.temperature_2m_min[k]) + "°</span></div>" +
                '<div class="p">' + (pp >= 20 ? pp + "%" : "") + "</div></div>";
      }
      html += "</div>";
    }
    return html;
  }

  function gameTime(iso) {
    var d = new Date(iso), today = fmt(now(), { month: "numeric", day: "numeric" }) === fmt(d, { month: "numeric", day: "numeric" });
    var t = fmt(d, { hour: "numeric", minute: "2-digit", hour12: !cfg.clock24h });
    return today ? t : fmt(d, { weekday: "short" }) + " " + t;
  }

  function teamRow(t, g, other) {
    var post = g.state === "post", s = parseFloat(t.score), o = parseFloat(other.score);
    var lose = post && !isNaN(s) && !isNaN(o) && s < o;
    return '<div class="team' + (lose ? " lose" : "") + (t.favorite ? " fav" : "") + '">' +
      '<span class="sw" style="background:#' + esc(t.color || "888") + '"></span>' +
      '<span class="nm">' + esc(t.name || t.abbr) + "</span>" +
      (t.record && g.state === "pre" ? '<span class="rec">' + esc(t.record) + "</span>" : "") +
      '<span class="sc">' + (g.state === "pre" ? "" : esc(t.score)) + "</span></div>";
  }

  // ESPN gives "15:00 - 3rd" → show "3rd 15:00" so the period survives truncation.
  function liveDetail(d) {
    var m = String(d || "").match(/^(.+?)\s+-\s+(.+)$/);
    return m ? m[2] + " " + m[1] : d;
  }

  function renderGames(games) {
    var html = '<div class="games">';
    games.forEach(function (g) {
      var st = g.state === "in" ? '<div class="st live">' + esc(liveDetail(g.detail)) + "</div>"
             : g.state === "pre" ? '<div class="st">' + gameTime(g.date) + "</div>"
             : '<div class="st">' + esc(g.detail || "Final") + "</div>";
      var sit = g.state === "in" && g.situation ? '<div class="sit">' + esc(g.situation) + "</div>" : "";
      var tv = g.broadcasts && g.broadcasts.length ? '<span class="tv">' + esc(g.broadcasts.slice(0, 2).join(" · ")) + "</span>" : "";
      var gl = g.leagueKey && g.id ? "https://www.espn.com/" + g.leagueKey.split("/").pop() + "/game/_/gameId/" + g.id : "";
      html += '<div class="game"' + qa(gl, g.away.name + " at " + g.home.name) + '><div class="teams">' + teamRow(g.away, g, g.home) + teamRow(g.home, g, g.away) + "</div>" +
              '<div class="gstat">' + st + sit + (g.state !== "post" ? tv : "") + "</div></div>";
    });
    return html + "</div>";
  }

  function img(u) { return "/img?u=" + encodeURIComponent(u); }
  function compact(n) {
    if (!(n > 0)) return "";
    return n >= 1e9 ? (n / 1e9).toFixed(1) + "B" : n >= 1e6 ? (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + "M" : n >= 1e3 ? Math.round(n / 1e3) + "K" : String(n);
  }
  function renderYouTube(items) {
    var html = '<div class="yt">';
    items.forEach(function (v) {
      var meta = [esc(v.channel), v.date ? ago(v.date) : "", v.views ? compact(v.views) + " views" : ""].filter(Boolean).join(" · ");
      html += '<div class="vid"' + qa(v.link, v.title, v.thumb) + '><div class="th"><img src="' + img(v.thumb) + '" alt=""></div>' +
              '<div class="vt"><div class="hd">' + esc(v.title) + '</div><div class="meta">' + meta + "</div></div></div>";
    });
    return html + "</div>";
  }

  // Anime: each show carries its upcoming (and just-aired) episode times; pick the next one locally so
  // countdowns roll over without waiting for the Mac. "Out now" stays up for 3 hours after release.
  var OUT_NOW_MS = 3 * 3600 * 1000;
  function upcomingAnime() {
    var delay = ((cfg.anime && cfg.anime.delayMinutes) || 0) * 60000, t = now().getTime(), out = [];
    (feeds.anime || []).forEach(function (s) {
      var eps = (s.schedule || []).slice().sort(function (a, b) { return a.at - b.at; });
      for (var i = 0; i < eps.length; i++) {
        var rel = eps[i].at * 1000 + delay;
        if (rel > t - OUT_NOW_MS) { out.push({ show: s, ep: eps[i].ep, release: rel }); break; }
      }
    });
    return out.sort(function (a, b) { return a.release - b.release; });
  }
  function countdown(ms) {
    var s = Math.floor(ms / 1000);
    if (s <= 0) return "Out now";
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60;
    if (d > 0) return d + "d " + h + "h";
    if (h > 0) return h + "h " + m + "m";
    return m + ":" + (sec < 10 ? "0" : "") + sec;
  }
  function renderAnime(list) {
    var html = '<div class="anime">';
    list.forEach(function (a) {
      var when = fmt(new Date(a.release), { weekday: "short", hour: "numeric", minute: "2-digit", hour12: !cfg.clock24h });
      html += '<div class="ani"' + qa("https://anilist.co/anime/" + a.show.id, a.show.title, a.show.cover) + '><div class="cv" style="background:' + esc(a.show.color || "#888") + '"><img src="' + img(a.show.cover) + '" alt=""></div>' +
              '<div class="st2"><div class="nm">' + esc(a.show.title) + '</div><div class="meta">Episode ' + esc(a.ep) +
              (a.show.episodes ? " of " + esc(a.show.episodes) : "") + (a.show.crunchyroll ? ' · <span class="cr">Crunchyroll</span>' : "") + "</div></div>" +
              '<div class="cdw"><div class="cd" data-t="' + a.release + '">' + countdown(a.release - now().getTime()) + '</div><div class="when">' + when + "</div></div></div>";
    });
    return html + "</div>";
  }
  // Live countdown ticker for whichever anime slide is on screen.
  setInterval(function () {
    var els = document.querySelectorAll("#slide-" + activeLayer + " .cd[data-t]"), t = now().getTime();
    for (var i = 0; i < els.length; i++) {
      var ms = +els[i].getAttribute("data-t") - t, txt = countdown(ms);
      if (els[i].textContent !== txt) els[i].textContent = txt;
      els[i].className = "cd" + (ms <= 0 ? " now" : ms < 3600000 ? " soon" : "");
    }
  }, 1000);

  // ---------- Bluesky ----------
  function renderBluesky(posts) {
    var html = '<div class="bsky">';
    posts.forEach(function (p) {
      var meta = [p.likes ? "♥ " + compact(p.likes) : "", p.reposts ? "↻ " + compact(p.reposts) : "", p.replies ? "↩ " + compact(p.replies) : ""].filter(Boolean).join("   ");
      var pm = /^at:\/\/([^/]+)\/app\.bsky\.feed\.post\/(.+)$/.exec(p.uri || "");
      html += '<div class="post"' + qa(pm ? "https://bsky.app/profile/" + p.handle + "/post/" + pm[2] : "", "@" + p.handle, p.avatar) + '>' + (p.repostBy ? '<div class="rp">↻ Reposted by ' + esc(p.repostBy) + "</div>" : "") +
        '<div class="pr"><div class="av">' + (p.avatar ? '<img src="' + img(p.avatar) + '" alt="">' : "") + "</div>" +
        '<div class="pb"><div class="ph"><b>' + esc(p.name) + "</b><span>@" + esc(p.handle) + " · " + shortAgo(p.date) + "</span></div>" +
        (p.text ? '<div class="pt' + (p.image ? " withimg" : "") + '">' + esc(p.text) + "</div>" : "") +
        (meta ? '<div class="pm">' + meta + "</div>" : "") + "</div>" +
        (p.image ? '<div class="pi"><img src="' + img(p.image) + '" alt=""></div>' : "") + "</div></div>";
    });
    return html + "</div>";
  }
  function shortAgo(ms) {
    var s = (now().getTime() - ms) / 1000;
    return s < 60 ? "now" : s < 3600 ? Math.round(s / 60) + "m" : s < 86400 ? Math.round(s / 3600) + "h" : Math.round(s / 86400) + "d";
  }

  // ---------- Steam wishlist ----------
  // Items keep their exact release time when Steam has one, so countdowns tick down on the tablet itself.
  function upcomingSteam() {
    var t = now().getTime();
    return (feeds.steamUpcoming || []).filter(function (g) {
      return !(g.precision === "date_full" && g.date && g.date < t - 3 * 86400000);   // drop things released >3 days ago
    });
  }
  function steamWhen(g) {
    var d = g.date ? new Date(g.date) : null;
    switch (g.precision) {
      case "date_full": return d ? fmt(d, { weekday: "short", month: "short", day: "numeric" }) : "";
      case "date_month": return d ? fmt(d, { month: "long", year: "numeric" }) : "";
      case "date_quarter": return d ? "Q" + (Math.floor(+fmt(d, { month: "numeric" }) / 3.01) + 1) + " " + fmt(d, { year: "numeric" }) : "";
      case "date_year": return d ? fmt(d, { year: "numeric" }) : "";
      default: return g.label || "Coming soon";
    }
  }
  function renderSteamUp(items) {
    var html = '<div class="steam">';
    items.forEach(function (g) {
      var exact = g.precision === "date_full" && g.date;
      var right = exact ? '<div class="cd" data-t="' + g.date + '">' + countdown(g.date - now().getTime()) + '</div><div class="when">' + steamWhen(g) + "</div>"
                        : '<div class="rough">' + esc(steamWhen(g)) + "</div>";
      var sub = g.earlyAccessExit ? "Leaving Early Access" : exact ? "Release date" : g.precision === "date_year" || g.precision === "date_quarter" || g.precision === "date_month" ? "Planned release" : "No date yet";
      html += '<div class="sg"' + qa("https://store.steampowered.com/app/" + g.appid, g.name, g.img) + '><div class="cap"><img src="' + img(g.img) + '" alt=""></div><div class="sn"><b>' + esc(g.name) + "</b><span>" + sub + "</span></div>" +
              '<div class="cdw">' + right + "</div></div>";
    });
    return html + "</div>";
  }
  function renderDeals(items) {
    var html = '<div class="steam">';
    items.forEach(function (d) {
      var ends = d.ends ? "Ends " + (d.ends - now().getTime() < 86400000 ? "in " + countdown(d.ends - now().getTime()) : fmt(new Date(d.ends), { weekday: "short", month: "short", day: "numeric" })) : "On sale";
      html += '<div class="sg"' + qa("https://store.steampowered.com/app/" + d.appid, d.name, d.img) + '><div class="cap"><img src="' + img(d.img) + '" alt=""></div><div class="sn"><b>' + esc(d.name) + "</b><span>" + ends + "</span></div>" +
              '<div class="deal"><span class="pct">−' + d.pct + '%</span><span class="pr2"><s>' + esc(d.orig) + "</s><b>" + esc(d.final) + "</b></span></div></div>";
    });
    return html + "</div>";
  }

  // data-href makes an item tappable: the tablet shows a QR code for it.
  function qa(url, title, thumb) {
    if (!url) return "";
    return ' data-href="' + esc(url) + '" data-qt="' + esc(title || "") + '"' + (thumb ? ' data-qi="' + esc(thumb) + '"' : "");
  }

  // ---------- Steam achievements ----------
  function renderAch(items, locked) {
    var html = '<div class="ach">';
    items.forEach(function (a) {
      var desc = a.desc || (a.hidden ? "Hidden achievement" : "");
      var right = locked ? '<b>' + (a.pct >= 10 ? Math.round(a.pct) : a.pct.toFixed(1)) + '%</b><small>of players</small>'
                         : (a.pct > 0 && a.pct < 10 ? '<span class="rare">Rare</span>' : "") + '<b>' + (a.pct >= 10 ? Math.round(a.pct) : a.pct.toFixed(1)) + '%</b><small>of players</small>';
      var meta = locked ? '<span class="g">' + esc(a.game) + '</span><span class="gp"><i style="width:' + (a.got / Math.max(1, a.total) * 100).toFixed(0) + '%"></i></span><span class="g2">' + a.got + "/" + a.total + "</span>"
                        : '<span class="g">' + esc(a.game) + " · " + shortAgo(a.at) + "</span>";
      html += '<div class="ar' + (locked ? " locked" : "") + '"' + qa(a.url, a.name + " — " + a.game, a.icon) + '><div class="aic">' + (a.icon ? '<img src="' + img(a.icon) + '" alt="">' : "") +
              (locked ? '<span class="lk">' + LOCK + "</span>" : "") + '</div><div class="an2"><b>' + esc(a.name) + "</b>" +
              (desc ? '<span class="d">' + esc(desc) + "</span>" : "") + '<div class="am">' + meta + "</div></div>" +
              '<div class="ap">' + right + "</div></div>";
    });
    return html + "</div>";
  }
  var LOCK = '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="round"><rect x="5" y="11" width="14" height="10" rx="2.5" fill="#fff" stroke="none"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>';

  function renderSteamNews(items) {
    var html = '<div class="snews">';
    items.forEach(function (n) {
      html += '<div class="sni"' + qa(n.url, n.title, n.img) + '><div class="ni">' + (n.img ? '<img src="' + img(n.img) + '" alt="">' : "") + '</div><div class="nb"><b>' + esc(n.title) + "</b>" +
              '<span class="g">' + esc(n.game) + " · " + shortAgo(n.date) + "</span>" + (n.text ? "<p>" + esc(n.text) + "</p>" : "") + "</div></div>";
    });
    return html + "</div>";
  }

  // ---------- Slickdeals ----------
  function renderSlick(items) {
    var html = '<div class="slick">';
    items.forEach(function (d) {
      var meta = [d.store ? esc(d.store) : "", d.score ? "👍 " + (d.score > 0 ? "+" : "") + d.score : "", d.date ? shortAgo(d.date) : ""].filter(Boolean).join(" · ");
      html += '<div class="sk"' + qa(d.link, d.title, d.img) + '><div class="si">' + (d.img ? '<img src="' + img(d.img) + '" alt="">' : "") + "</div>" +
              '<div class="sb"><b>' + esc(d.title) + "</b><span>" + meta + "</span></div>" + (d.price ? '<div class="sp">' + esc(d.price) + "</div>" : "") + "</div>";
    });
    return html + "</div>";
  }

  // ---------- Exchange rates ----------
  function fxNum(v) {
    if (v >= 100) return v.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    if (v >= 1) return v.toFixed(4);
    return v.toPrecision(4);
  }
  function chg(p, label) {
    var cls = p > 0.005 ? "up" : p < -0.005 ? "down" : "";
    return '<span class="' + cls + '">' + (p > 0.005 ? "▲ " : p < -0.005 ? "▼ " : "") + Math.abs(p).toFixed(2) + "% " + label + "</span>";
  }
  function renderFX(p) {
    var s = p.series || [], W = 440, H = 120, lo = Math.min.apply(null, s), hi = Math.max.apply(null, s), pad = (hi - lo) * 0.12 || hi * 0.01 || 1;
    lo -= pad; hi += pad;
    var pts = s.map(function (v, i) { return (i / Math.max(1, s.length - 1) * W).toFixed(1) + "," + (H - (v - lo) / (hi - lo) * H).toFixed(1); });
    var col = s.length > 1 && s[s.length - 1] < s[0] ? "var(--up)" : "var(--mem)";
    var svg = s.length > 1 ? '<svg class="fx-chart" viewBox="0 0 ' + W + " " + H + '" preserveAspectRatio="none"><path d="M0,' + H + " L" + pts.join(" L") + " L" + W + "," + H + 'Z" fill="' + col + '" opacity="0.14"/>' +
              '<polyline points="' + pts.join(" ") + '" fill="none" stroke="' + col + '" stroke-width="3" stroke-linejoin="round" vector-effect="non-scaling-stroke"/></svg>' : "";
    var d = p.date ? new Date(p.date + "T12:00:00Z") : null;
    return '<div class="fx"' + qa(p.url, p.from + " → " + p.to) + '><div class="fx-top"><div class="fx-rate"><small>1 ' + esc(p.from) + " =</small><b>" + fxNum(p.rate) + "</b><span>" + esc(p.to) + "</span></div>" +
      '<div class="fx-ch">' + chg(p.d1 || 0, "day") + chg(p.d30 || 0, "month") + "</div></div>" + svg +
      '<div class="fx-foot">1 ' + esc(p.to) + " = " + fxNum(1 / p.rate) + " " + esc(p.from) + (d ? " · ECB rate for " + fmt(d, { month: "short", day: "numeric", timeZone: "UTC" }) : "") + "</div></div>";
  }

  // ---------- Kanji of the hour ----------
  function levelName(l) {
    var m = /^(jlpt|grade)-(\d)$/.exec(l || "");
    if (m) return m[1] === "jlpt" ? "JLPT N" + m[2] : "Grade " + m[2];
    return { joyo: "Jōyō", jinmeiyo: "Jinmeiyō", kyouiku: "Kyōiku" }[l] || "";
  }
  function readings(list, kun) {
    var out = [];
    (list || []).forEach(function (r) {
      if (/^-|-$/.test(r)) return;
      r = kun ? r.replace(/\.(.+)$/, "($1)") : r;
      if (out.indexOf(r) < 0) out.push(r);
    });
    return out.slice(0, kun ? 3 : 3).join("・");
  }
  function renderKanji(k) {
    var paths = (k.strokes || []).map(function (d, i) { return '<path d="' + esc(d) + '"/>'; }).join("");
    var box = paths ? '<svg class="kvg" viewBox="0 0 109 109"><g class="ghost">' + paths + '</g><g class="ink">' + paths + "</g></svg>"
                    : '<div class="kch">' + esc(k.kanji) + "</div>";
    var on = readings(k.on_readings), kun = readings(k.kun_readings, true);
    var facts = [k.stroke_count ? k.stroke_count + " strokes" : "", k.jlpt ? "JLPT N" + k.jlpt : "", k.grade ? (k.grade <= 6 ? "Grade " + k.grade : "Secondary") : ""].filter(Boolean).join(" · ");
    var words = (k.words || []).map(function (w) {
      return '<div class="kw"><b>' + esc(w.w) + "</b><span>" + esc(w.r) + "</span><i>" + esc(w.m) + "</i></div>";
    }).join("");
    var next = k.next ? '<div class="kj-next">Next: <b>' + esc(k.next) + "</b> at " + fmt(new Date(k.hour + 3600000), { hour: "numeric", minute: "2-digit", hour12: !cfg.clock24h }) + "</div>" : "";
    return '<div class="kanji"' + qa(k.url, k.kanji + " — " + (k.meanings || []).slice(0, 2).join(", ")) + '><div class="kj-l"><div class="kj-box">' + box + '</div><div class="kj-f">' + facts + "</div></div>" +
      '<div class="kj-r"><div class="kj-m">' + esc((k.meanings || []).slice(0, 3).join(", ")) + "</div>" +
      (on ? '<div class="kj-rd"><span class="lb">On</span>' + esc(on) + "</div>" : "") +
      (kun ? '<div class="kj-rd"><span class="lb">Kun</span>' + esc(kun) + "</div>" : "") +
      '<div class="kj-ws">' + words + "</div>" + next + "</div></div>";
  }

  // ---------- Things that need the DOM after a slide is inserted ----------
  var radarTimer = null;
  function hydrate(el, s) {
    if (s.type === "kanji") {
      var ink = el.querySelectorAll(".kvg .ink path"), t = 0.3;
      for (var i = 0; i < ink.length; i++) {
        var L = Math.ceil(ink[i].getTotalLength ? ink[i].getTotalLength() : 200) + 2, dur = Math.max(0.25, Math.min(0.7, L / 140));
        ink[i].style.strokeDasharray = L; ink[i].style.strokeDashoffset = L;
        ink[i].style.animation = "kstroke " + dur.toFixed(2) + "s " + t.toFixed(2) + "s ease-in-out forwards";
        t += dur + 0.12;
      }
    }
    if (s.type === "radar") { clearInterval(radarTimer); setTimeout(function () { buildRadar(el.querySelector(".radar")); }, 30); }
  }
  function buildRadar(root) {
    var r = feeds.radar; if (!root || !r) return;
    var map = root.querySelector(".rmap"), W = map.clientWidth, H = map.clientHeight;
    if (!W || !H) return;
    var z = r.zoom, n = Math.pow(2, z), latR = r.lat * Math.PI / 180;
    var px = (r.lon + 180) / 360 * n * 256 - W / 2;
    var py = (1 - Math.log(Math.tan(latR) + 1 / Math.cos(latR)) / Math.PI) / 2 * n * 256 - H / 2;
    var dark = theme === "night";
    function layer(urlFor, cls) {
      var html = "";
      for (var tx = Math.floor(px / 256); tx <= Math.floor((px + W) / 256); tx++)
        for (var ty = Math.floor(py / 256); ty <= Math.floor((py + H) / 256); ty++) {
          if (ty < 0 || ty >= n) continue;
          html += '<img src="' + img(urlFor(((tx % n) + n) % n, ty)) + '" style="left:' + Math.round(tx * 256 - px) + "px;top:" + Math.round(ty * 256 - py) + 'px" alt="">';
        }
      var d = document.createElement("div"); d.className = "rl " + cls; d.innerHTML = html; map.appendChild(d); return d;
    }
    map.innerHTML = "";
    layer(function (x, y) { return "https://tile.openstreetmap.org/" + z + "/" + x + "/" + y + ".png"; }, "base");
    var frames = r.frames.map(function (f) {
      return layer(function (x, y) { return r.host + f.path + "/256/" + z + "/" + x + "/" + y + "/2/1_1.png"; }, "rf");
    });
    var pin = document.createElement("div"); pin.className = "rpin"; pin.style.left = W / 2 + "px"; pin.style.top = H / 2 + "px"; map.appendChild(pin);
    var i = 0, hold = 0, last = frames.length - 1, nowT = now().getTime();
    var pastLast = 0; r.frames.forEach(function (f, j) { if (f.t <= nowT) pastLast = j; });
    function step() {
      if (hold > 0) { hold--; return; }
      frames.forEach(function (f, j) { f.style.opacity = j === i ? "0.82" : "0"; });
      var f = r.frames[i], mins = Math.round((f.t - nowT) / 60000);
      root.querySelector(".rtime").innerHTML = fmt(new Date(f.t), { hour: "numeric", minute: "2-digit", hour12: !cfg.clock24h }) +
        (f.t > nowT + 60000 ? ' <span class="fc">+' + mins + " min forecast</span>" : i === pastLast ? ' <span class="nowt">Now</span>' : "");
      if (i === pastLast) hold = 3;
      i = i >= last ? 0 : i + 1;
      if (i === 0) hold = Math.max(hold, 2);
    }
    step(); radarTimer = setInterval(step, 600);
  }

  function renderNews(items) {
    var html = '<div class="news">';
    items.forEach(function (it) {
      html += '<div class="story"' + qa(it.link, it.title) + '><div class="hd">' + esc(it.title) + "</div>" +
              (it.date ? '<div class="meta">' + ago(it.date) + "</div>" : "") + "</div>";
    });
    return html + "</div>";
  }

  // Swipe the card left/right to change it; tap the weather card for the full forecast, any other card to skip ahead.
  // After a manual change the card stays put for 30 s before rotation resumes.
  (function () {
    var card = $("card"), sx = 0, sy = 0, st = 0, dragging = false, dx = 0, id = null;
    function activeEl() { return $("slide-" + activeLayer); }
    var lp = null, lpFired = false;
    card.addEventListener("pointerdown", function (e) {
      if (e.target.closest && e.target.closest("#card-ctl")) return;
      if (ctlOpen()) { hideCtl(); lpFired = true; id = e.pointerId; return; }
      if (id !== null) return;
      id = e.pointerId; sx = e.clientX; sy = e.clientY; st = Date.now(); dx = 0; dragging = false; lpFired = false;
      clearTimeout(lp);
      lp = setTimeout(function () { lp = null; if (!dragging && id !== null) { lpFired = true; showCtl(); } }, 550);
    });
    card.addEventListener("pointermove", function (e) {
      if (e.pointerId !== id) return;
      var mx = (e.clientX - sx) / stageScale, my = (e.clientY - sy) / stageScale;
      if (Math.abs(mx) + Math.abs(my) > 10) { clearTimeout(lp); lp = null; }
      if (lpFired) return;
      if (!dragging && Math.abs(mx) > 12 && Math.abs(mx) > Math.abs(my)) { dragging = true; try { card.setPointerCapture(id); } catch (x) {} }
      if (dragging) {
        dx = mx;
        var el = activeEl(); el.classList.add("dragging");
        el.style.transform = "translateX(" + dx + "px)"; el.style.opacity = String(Math.max(0.35, 1 - Math.abs(dx) / 500));
      }
    });
    function end(e) {
      if (e.target && e.target.closest && e.target.closest("#card-ctl") && id === null) return;
      if (e.pointerId !== id) return;
      id = null; clearTimeout(lp); lp = null;
      if (lpFired) { lpFired = false; return; }
      var el = activeEl(); el.classList.remove("dragging"); el.style.opacity = "";
      if (dragging) {
        if (slides.length > 1 && Math.abs(dx) > 60) { show(slideIdx + (dx < 0 ? 1 : -1), false, dx < 0 ? 1 : -1); scheduleNext(30); }
        else el.style.transform = "";
        return;
      }
      if (e.type === "pointercancel" || Date.now() - st > 600) return;
      var s = slides[slideIdx];
      var link = e.target && e.target.closest ? e.target.closest("[data-href]") : null;
      if (link && window.PlinthSheets) {
        PlinthSheets.open("qr", { url: link.getAttribute("data-href"), title: link.getAttribute("data-qt") || "", thumb: link.getAttribute("data-qi") || "",
                                  chip: CHIP[s.type], from: s.title });
        if (!paused) scheduleNext(45);
      }
      else if (s && s.type === "weather" && window.PlinthSheets) PlinthSheets.open("forecast");
      else if (slides.length > 1) { show(slideIdx + 1, false, 1); scheduleNext(30); }
    }
    card.addEventListener("pointerup", end);
    card.addEventListener("pointercancel", end);
  })();

  // Long-press the card: pause / play, step through, and pick the time per card.
  var ctlTimer = null, INTERVALS = [6, 8, 12, 20, 30, 60];
  function ctlOpen() { return $("card-ctl").classList.contains("open"); }
  function renderCtl() {
    var cur = cfg.cycleSeconds || 12;
    $("ctl-pause").innerHTML = paused ? '<svg viewBox="0 0 24 24"><path d="M8 5.5v13l11-6.5z" fill="currentColor"/></svg>' : '<svg viewBox="0 0 24 24"><rect x="6.5" y="5" width="4" height="14" rx="1.3" fill="currentColor"/><rect x="13.5" y="5" width="4" height="14" rx="1.3" fill="currentColor"/></svg>';
    $("ctl-state").textContent = paused ? "Paused" : "Playing";
    $("ctl-int").innerHTML = INTERVALS.map(function (n) { return '<button data-s="' + n + '" class="' + (n === cur ? "on" : "") + '">' + n + "s</button>"; }).join("");
  }
  function showCtl() { renderCtl(); $("card-ctl").classList.add("open"); pokeCtl(); }
  function hideCtl() { $("card-ctl").classList.remove("open"); clearTimeout(ctlTimer); }
  function pokeCtl() { clearTimeout(ctlTimer); ctlTimer = setTimeout(hideCtl, 8000); }
  function setPaused(p) {
    paused = p;
    try { localStorage.setItem("plinth.paused", p ? "1" : "0"); } catch (e) {}
    scheduleNext();
  }
  $("card-ctl").addEventListener("click", function (e) {
    pokeCtl();
    var b = e.target.closest("button"); if (!b) { if (e.target === $("card-ctl")) hideCtl(); return; }
    if (b.id === "ctl-pause") setPaused(!paused);
    else if (b.id === "ctl-prev") { show(slideIdx - 1, false, -1); scheduleNext(paused ? 0 : 30); }
    else if (b.id === "ctl-next") { show(slideIdx + 1, false, 1); scheduleNext(paused ? 0 : 30); }
    else if (b.hasAttribute("data-s")) {
      var n = +b.getAttribute("data-s"); cfg.cycleSeconds = n;
      var x = new XMLHttpRequest(); x.open("POST", "/api/tablet"); x.setRequestHeader("Content-Type", "application/json");
      x.send(JSON.stringify({ action: "cycle", seconds: n }));
      scheduleNext();
    }
    renderCtl();
  });

  // Long-press the top-left corner (2 s) for the tablet app's connection settings.
  (function () {
    var t = null;
    document.addEventListener("pointerdown", function (e) {
      var r = $("stage").getBoundingClientRect();
      if ((e.clientX - r.left) / stageScale < 110 && (e.clientY - r.top) / stageScale < 110) {
        t = setTimeout(function () { t = null; if (host && host.showSettings) host.showSettings(); }, 2000);
      }
    });
    ["pointerup", "pointercancel", "pointermove"].forEach(function (ev) {
      document.addEventListener(ev, function (e) { if (t && (ev !== "pointermove" || Math.abs(e.movementX) + Math.abs(e.movementY) > 6)) { clearTimeout(t); t = null; } });
    });
  })();

  window.plinth = { key: function () { return currentKey; }, next: function () { show(slideIdx + 1); scheduleNext(); }, slides: function () { return slides; },
                    standby: function (on, why) { if (on) enterStandby(why || "sleeping"); else exitStandby(); } };
  // Shared with sheets.js
  window.PlinthCore = {
    cfg: function () { return cfg; }, feeds: function () { return feeds; }, metrics: function () { return lastMetrics; },
    hist: hist, HMAX: HMAX, now: now, fmt: fmt, tz: function () { return tz; }, wxIcon: wxIcon, wxKind: wxKind, esc: esc,
    bits: bits, bitsStr: bitsStr, gib: gib, gb: gb, mbps: mbps, ago: ago, fetchJSON: fetchJSON, ICONS: ICONS,
    tok: tok, until: until, claude: function () { return lastClaude; }, presence: function () { return presence; },
    cssVar: cssVar, rgba: rgba, scale: function () { return stageScale; }, standby: function () { return standby; }, theme: function () { return theme; },
  };
  var forcedTheme = (location.search.match(/[?&]theme=(day|night)/) || [])[1];
  // ?day=golden|wallpaper|custom&color=%23hex lets the manager preview a choice before it's saved.
  var forcedDay = (function () {
    var m = (location.search.match(/[?&]day=(golden|wallpaper|custom)/) || [])[1];
    var c = (location.search.match(/[?&]color=(%23|#)?([0-9a-f]{6})/i) || [])[2];
    return m ? { mode: m, custom: c ? "#" + c : undefined } : null;
  })();
  function mergeDay(day, f) { var o = {}; for (var k in day) o[k] = day[k]; o.mode = f.mode; if (f.custom) o.custom = f.custom; return o; }

  var lastDayKey = null;
  function applyDay(day) {
    if (!day || !window.PlinthPalette) return;
    var key = day.mode + "|" + day.custom + "|" + (day.wallpaper && day.wallpaper.key);
    if (key === lastDayKey) return;
    lastDayKey = key;
    PlinthPalette.apply(day);
    colorCache = {};   // sparkline colors are read from CSS variables
  }

  // ---------- Screen timeout ----------
  // "always": keep the screen on (default). "timeout": off after N minutes without a touch. "screensaver": off while
  // the Mac's screen saver runs (not the lock screen). Off = the tablet app drops its keep-awake and the page goes
  // black, so the tablet's own timeout switches the panel off; over USB the Mac switches it off right away.
  var screenMode = "always", screenTimeout = 600, screenOn = true, lastTouch = Date.now(), lastSaver = null, lastTick = Date.now();
  function setScreen(on) {
    if (on === screenOn) return;
    screenOn = on;
    document.body.classList.toggle("screen-off", !on);
    if (host && host.setKeepAwake) { try { host.setKeepAwake(on); } catch (e) {} }
    if (host && host.setBrightness) {
      try { host.setBrightness(on ? (lastBrightness == null ? -1 : lastBrightness) : 0.01); } catch (e) {}
    }
    var x = new XMLHttpRequest(); x.open("POST", "/api/tablet"); x.setRequestHeader("Content-Type", "application/json");
    x.send(JSON.stringify({ action: "screen", on: on }));
  }
  function wake() { lastTouch = Date.now(); if (!screenOn) setScreen(true); }
  try { var sv = JSON.parse(localStorage.getItem("plinth.screen") || "null"); if (sv) { screenMode = sv.mode; screenTimeout = sv.timeout; } } catch (e) {}
  function screenFromMac(sc) {
    if (sc.mode !== screenMode || sc.timeout !== screenTimeout) {
      try { localStorage.setItem("plinth.screen", JSON.stringify({ mode: sc.mode, timeout: sc.timeout })); } catch (e) {}
    }
    screenMode = sc.mode || "always"; screenTimeout = sc.timeout || 600;
    if (screenMode === "always") { lastSaver = null; if (!screenOn) setScreen(true); return; }
    if (screenMode === "screensaver") {
      // Act on changes only, so waking the tablet by hand while the screen saver runs keeps it on.
      if (sc.saver !== lastSaver) { lastSaver = sc.saver; if (lastSaver !== null) setScreen(!sc.saver); }
    } else lastSaver = null;
  }
  setInterval(function () {
    var t = Date.now();
    if (t - lastTick > 8000) wake();          // the page was paused: the screen just came back on
    lastTick = t;
    if (screenMode === "timeout" && screenOn && t - lastTouch > screenTimeout * 1000) setScreen(false);
  }, 1000);
  document.addEventListener("pointerdown", wake, true);
  document.addEventListener("visibilitychange", function () { if (!document.hidden) wake(); });
  window.plinthResumed = wake;
  $("screen-off").addEventListener("pointerdown", function (e) { e.stopPropagation(); e.preventDefault(); wake(); });

  // ---------- Update available ----------
  // A newer Mac app on GitHub, or (after the Mac updated) a newer tablet app than this one. Dismissed per version.
  function newer(a, b) {
    var x = String(a || "").split("."), y = String(b || "").split(".");
    for (var i = 0; i < Math.max(x.length, y.length); i++) {
      var p = parseInt(x[i] || 0, 10) || 0, q = parseInt(y[i] || 0, 10) || 0;
      if (p !== q) return p > q;
    }
    return false;
  }
  var noteKey = null;
  function renderUpdate(v) {
    var mine = null, key = null, html = "";
    try { mine = host && host.version ? host.version() : null; } catch (e) {}
    if (v && v.update) { key = "mac-" + v.update; html = "Matchbox Dashboard <b>" + esc(v.update) + "</b> is available · update from the menu bar on your Mac"; }
    else if (v && v.tablet && mine && newer(v.tablet, mine)) { key = "tab-" + v.tablet; html = "Tablet app <b>" + esc(v.tablet) + "</b> is ready · choose Install App on Tablet on your Mac"; }
    var dismissed = null;
    try { dismissed = localStorage.getItem("plinth.updateDismissed"); } catch (e) {}
    var el = $("update-note");
    if (!key || key === dismissed) { el.hidden = true; noteKey = null; return; }
    if (key !== noteKey) { $("un-text").innerHTML = html; noteKey = key; }
    el.hidden = false;
  }
  $("un-close").addEventListener("click", function (e) {
    e.stopPropagation();
    try { localStorage.setItem("plinth.updateDismissed", noteKey); } catch (x) {}
    $("update-note").hidden = true;
  });

  // ---------- Boot ----------
  var hadCache = loadCache();
  if (forcedTheme) setTheme(forcedTheme);
  fit();
  updateClock();
  if (hadCache) { buildSlides(); renderGlance(); }
  // Started from the tablet's cached copy because the Mac was asleep/away: go straight to standby.
  try { if (host && host.isOfflineCopy && host.isOfflineCopy()) enterStandby("unreachable"); } catch (e) {}
  setInterval(updateClock, 1000);
  show(0, true);
  pollMetrics();
  // Re-render relative timestamps on news/sports every minute.
  setInterval(function () { if (slides[slideIdx] && slides[slideIdx].type !== "weather") $("slide-" + activeLayer).innerHTML = renderSlide(slides[slideIdx]); }, 60000);
})();
