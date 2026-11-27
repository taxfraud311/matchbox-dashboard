/* Matchbox Dashboard display — tap-to-expand sheets: metric details, world clock and full forecast. */
(function () {
  "use strict";
  var C = window.PlinthCore;
  if (!C) return;
  var $ = function (id) { return document.getElementById(id); };
  var esc = C.esc;

  var wrap = $("sheet"), bodyEl = $("sheet-body");
  var current = null, refreshTimer = null, idleTimer = null, detail = {}, busy = false;
  var IDLE_CLOSE_MS = 60000;

  var GEAR = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="4" y="4" width="16" height="16" rx="4"/><path d="M9 9h6v6H9z"/></svg>';
  var CLOCK_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>';

  var META = {
    cpu: { title: "CPU", accent: "--cpu", icon: C.ICONS.cpu },
    gpu: { title: "GPU", accent: "--gpu", icon: C.ICONS.gpu },
    mem: { title: "Memory", accent: "--mem", icon: C.ICONS.mem },
    disk: { title: "Disk", accent: "--disk", icon: C.ICONS.disk },
    net: { title: "Network", accent: "--down", icon: C.ICONS.net },
    claude: { title: "Claude Code", accent: "--claude", icon: C.ICONS.claude },
    clock: { title: "World Clock", accent: "--cpu", icon: CLOCK_ICON },
    forecast: { title: "Weather", accent: "--cpu", icon: C.ICONS.chipWeather },
    qr: { title: "Open on your phone", accent: "--cpu", icon: "" },
  };
  var METRIC = { cpu: 1, gpu: 1, mem: 1, disk: 1, net: 1, claude: 1 };

  // ---------- Open / close ----------
  var args = {};
  function open(kind, opts) {
    if (METRIC[kind] && C.standby()) return;
    current = kind; detail = {}; args = opts || {}; diskSig = "";
    var m = META[kind];
    $("sheet-chip").innerHTML = kind === "qr" && args.chip ? args.chip.icon : m.icon;
    $("sheet-chip").style.background = kind === "forecast" ? "linear-gradient(160deg,#3ea8ff,#0a6be0)" : kind === "clock" ? "linear-gradient(160deg,#8e8e93,#48484a)" :
      kind === "qr" ? (args.chip ? args.chip.bg : "var(--cpu)") : "var(" + m.accent + ")";
    $("sheet-chip").style.color = "#fff";
    $("sheet-title").textContent = kind === "qr" && args.from ? args.from : m.title;
    $("sheet-sub").textContent = "";
    wrap.style.setProperty("--accent", "var(" + m.accent + ")");
    wrap.classList.add("open");
    void wrap.offsetWidth;
    wrap.classList.add("shown");
    render();
    clearInterval(refreshTimer);
    if (METRIC[kind]) { fetchDetail(); refreshTimer = setInterval(fetchDetail, kind === "claude" ? 10000 : 2000); }
    else if (kind === "clock") refreshTimer = setInterval(render, 1000);
    poke();
  }
  function close() {
    if (!current) return;
    current = null;
    clearInterval(refreshTimer); clearTimeout(idleTimer);
    wrap.classList.remove("shown");
    setTimeout(function () { if (!current) { wrap.classList.remove("open"); bodyEl.innerHTML = ""; } }, 350);
  }
  function poke() { clearTimeout(idleTimer); idleTimer = setTimeout(close, IDLE_CLOSE_MS); }

  $("sheet-close").addEventListener("click", close);
  $("sheet-backdrop").addEventListener("click", close);
  wrap.addEventListener("pointerdown", poke);
  bodyEl.addEventListener("click", function (e) {
    if (e.target.id === "dk-canvas") { diskTap(e); return; }
    var b = e.target.closest("[data-act]");
    var act = b && b.getAttribute("data-act");
    if (act === "vol") {
      diskVol = b.getAttribute("data-v"); diskPath = []; diskSig = "";
      try { localStorage.setItem("plinth.diskVol", diskVol); } catch (x) {}
      refetchDisk(); return;
    }
    if (act === "into") { diskPath.push(b.getAttribute("data-n")); diskSig = ""; refetchDisk(); return; }
    if (act === "crumb") { diskPath = diskPath.slice(0, +b.getAttribute("data-i")); diskSig = ""; refetchDisk(); return; }
    if (act === "rescan") { b.disabled = true; b.textContent = "Starting…"; refetchDisk("&rescan=1"); return; }
    if (act === "openmac") {
      b.disabled = true;
      var o = new XMLHttpRequest(); o.open("POST", "/api/tablet"); o.setRequestHeader("Content-Type", "application/json");
      o.timeout = 5000;
      var msg = function (t, again) { var el = $("qr-msg"); if (el) el.textContent = t; if (again) b.disabled = false; };
      o.onload = function () {
        var r = {}; try { r = JSON.parse(o.responseText); } catch (e) {}
        if (o.status === 200) msg(r.presence === "locked" ? "Opened. You’ll see it when you unlock the Mac." : "Opened in your Mac’s browser.");
        else msg(r.error || "Couldn’t open it on the Mac", true);
      };
      o.onerror = o.ontimeout = function () { msg("Couldn’t reach the Mac", true); };
      o.send(JSON.stringify({ action: "open", url: args.url || "" }));
      return;
    }
    if (b && b.getAttribute("data-act") === "speedtest") {
      b.disabled = true; b.textContent = "Starting…";
      var x = new XMLHttpRequest(); x.open("POST", "/api/tablet"); x.setRequestHeader("Content-Type", "application/json");
      x.send(JSON.stringify({ action: "speedtest" }));
    }
  });

  function fetchDetail() {
    var kind = current;
    if (busy) return;
    busy = true;
    var url = kind === "disk" ? "/api/diskscan?vol=" + encodeURIComponent(diskVol || "") + "&path=" + encodeURIComponent(diskPath.join("/")) + (diskExtra || "")
                              : "/api/detail?kind=" + kind;
    diskExtra = "";
    C.fetchJSON(url, 12000).then(function (d) {
      busy = false;
      if (kind !== current) return;
      detail = d; render();
    }).catch(function () { busy = false; if (kind === current) render(); });
  }

  function render() {
    if (!current) return;
    var fn = { cpu: renderCPU, gpu: renderGPU, mem: renderMem, disk: renderDisk, net: renderNet, claude: renderClaude, clock: renderClock, forecast: renderForecast, qr: renderQR }[current];
    var html = fn();
    if (html != null) {
      bodyEl.className = "sheet-body " + (current === "clock" ? "" : current === "forecast" ? "forecast" : current === "disk" ? "disk" : current === "qr" ? "qr" : "two");
      bodyEl.innerHTML = html;
      if (current === "disk") drawDisk();
    }
    drawCharts();
  }

  // ---------- Shared bits ----------
  function appIcon(a) {
    return '<div class="ai">' + (a.icon ? '<img src="/api/appicon?name=' + encodeURIComponent(a.name) + '" alt="">' : GEAR) + "</div>";
  }
  function appList(apps, fmtVal, emptyMsg) {
    if (!apps || !apps.length) return '<div class="note2">' + (emptyMsg || "Gathering…") + "</div>";
    var top = 0;
    apps.forEach(function (a) { top = Math.max(top, a._sort != null ? a._sort : a.value); });
    return '<div class="applist">' + apps.map(function (a) {
      var v = a._sort != null ? a._sort : a.value;
      return '<div class="app">' + appIcon(a) + '<div class="an"><b>' + esc(a.name) + '</b><div class="bar2"><i style="width:' +
        (top > 0 ? Math.max(2, v / top * 100) : 0).toFixed(1) + '%"></i></div></div><div class="av">' + fmtVal(a) +
        (a.count > 1 ? "<small>" + a.count + " processes</small>" : "") + "</div></div>";
    }).join("") + "</div>";
  }
  function kv(k, v) { return '<div class="kv"><span class="k">' + k + '</span><span class="v">' + v + "</span></div>"; }
  function pct(v) { return Math.round(v || 0) + '<span class="unit">%</span>'; }
  function dur(s) {
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
    return (d ? d + "d " : "") + h + "h " + m + "m";
  }

  var charts = [];
  function chart(id, series, max, height) {
    charts.push({ id: id, series: series, max: max });
    return '<canvas class="chart" id="' + id + '" style="height:' + (height || 120) + 'px"></canvas>';
  }
  function drawCharts() {
    var list = charts; charts = [];
    list.forEach(function (c) {
      var el = $(c.id); if (!el) return;
      var r = (window.devicePixelRatio || 1) * C.scale();
      el.width = Math.round(el.clientWidth * r); el.height = Math.round(el.clientHeight * r);
      var ctx = el.getContext("2d"), w = el.width, h = el.height;
      var fillA = parseFloat(C.cssVar("--spark-alpha")) || 0.3;
      // light grid
      ctx.strokeStyle = C.rgba(C.cssVar(C.theme() === "night" ? "--cloud" : "--cloud-dark"), 0.18); ctx.lineWidth = r;
      for (var g = 1; g < 4; g++) { ctx.beginPath(); ctx.moveTo(0, h * g / 4); ctx.lineTo(w, h * g / 4); ctx.stroke(); }
      c.series.forEach(function (s) {
        var data = s.data; if (!data.length) return;
        var col = C.cssVar(s.color), n = C.HMAX;
        var x = function (i) { return w - (data.length - 1 - i) * (w / (n - 1)); };
        var y = function (v) { return h - 3 * r - Math.min(1, v / c.max) * (h - 10 * r); };
        ctx.beginPath();
        data.forEach(function (v, i) { if (i) ctx.lineTo(x(i), y(v)); else ctx.moveTo(x(i), y(v)); });
        ctx.strokeStyle = col; ctx.lineWidth = 3 * r; ctx.lineJoin = "round"; ctx.stroke();
        if (!s.lineOnly) {
          ctx.lineTo(w, h); ctx.lineTo(x(0), h); ctx.closePath();
          var gr = ctx.createLinearGradient(0, 0, 0, h);
          gr.addColorStop(0, C.rgba(col, fillA)); gr.addColorStop(1, C.rgba(col, 0.02));
          ctx.fillStyle = gr; ctx.fill();
        }
      });
    });
  }
  function niceMax(v) {
    v = Math.max(v, 1e6);
    var p = Math.pow(10, Math.floor(Math.log10(v))), m = v / p;
    return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 5 ? 5 : 10) * p;
  }

  // ---------- CPU ----------
  function renderCPU() {
    var m = C.metrics() || {}, cpu = m.cpu || {}, d = detail, load = d.load || [cpu.load || 0, 0, 0];
    $("sheet-sub").textContent = d.chip ? d.chip + " · " + (cpu.coreCount || "") + " cores" : "";
    var cores = (cpu.cores || []).map(function (v) { return '<div class="c"><i style="height:' + Math.min(100, v).toFixed(0) + '%"></i></div>'; }).join("");
    var short = { Performance: "Perf", Efficiency: "Eff" };
    var levels = (d.levels || []).map(function (l) { return l.cores + " " + esc(short[l.name] || l.name); }).join(" · ");
    return '<div class="col"><div class="big">' + pct(cpu.usage) + "</div>" +
      '<div class="panel"><div class="panel-title">Each core</div><div class="cores">' + cores + "</div></div>" +
      '<div class="panel">' + chart("ch-cpu", [{ data: C.hist.cpu, color: "--cpu" }], 100, 54) + "</div>" +
      '<div>' + kv("Load average", load.map(function (v) { return (+v).toFixed(2); }).join("  ·  ")) +
      (levels ? kv("Cores", levels) : "") + kv("Up time", dur(m.uptime || 0)) +
      kv("Temperature", (m.thermal || "nominal").replace(/^./, function (c) { return c.toUpperCase(); })) + "</div></div>" +
      '<div class="col"><div class="panel-title">Apps using the most CPU' + (d.processCount ? " · " + d.processCount + " processes running" : "") + "</div>" +
      appList(d.apps, function (a) { return a.value.toFixed(1) + "%"; }) + "</div>";
  }

  // ---------- GPU ----------
  function renderGPU() {
    var m = C.metrics() || {}, gpu = m.gpu || {}, d = detail;
    $("sheet-sub").textContent = (d.model || d.chip || "Apple GPU") + (d.cores ? " · " + d.cores + "-core GPU" : "");
    return '<div class="col"><div class="big">' + pct(gpu.usage) + "</div><div>" +
      kv("Renderer", Math.round(d.renderer || gpu.renderer || 0) + "%") + kv("Tiler", Math.round(d.tiler || 0) + "%") +
      kv("Memory in use", C.gib(d.memUsed || gpu.memUsed || 0) + " GB") + kv("Memory allocated", C.gib(d.memAlloc || 0) + " GB") +
      (d.cores ? kv("GPU cores", d.cores) : "") + "</div>" +
      '<div class="note2">macOS doesn’t let third-party apps see which apps are using the GPU.</div></div>' +
      '<div class="col"><div class="panel-title">Last 90 seconds</div><div class="panel">' + chart("ch-gpu", [{ data: C.hist.gpu, color: "--gpu" }], 100, 300) + "</div></div>";
  }

  // ---------- Memory ----------
  function renderMem() {
    var m = C.metrics() || {}, mem = m.mem || {}, d = detail, total = mem.total || 1;
    var wired = mem.wired || 0, comp = mem.compressed || 0, app = Math.max(0, (mem.used || 0) - wired - comp);
    var cached = mem.cached || 0, free = Math.max(0, total - (mem.used || 0) - cached);
    var segs = [["App memory", app, "var(--mem)"], ["Wired", wired, "var(--disk)"], ["Compressed", comp, "var(--gpu)"],
                ["Cached files", cached, "var(--cpu)"], ["Free", free, "var(--track)"]];
    $("sheet-sub").textContent = C.gib(mem.used || 0) + " of " + Math.round(total / 1073741824) + " GB used";
    var pressure = { normal: "Normal", warn: "Elevated", critical: "Critical" }[mem.pressure] || "Normal";
    return '<div class="col"><div class="big">' + pct(mem.percent) + "</div>" +
      '<div class="panel"><div class="segbar">' + segs.map(function (s) { return '<i style="width:' + (s[1] / total * 100).toFixed(2) + "%;background:" + s[2] + '"></i>'; }).join("") + "</div>" +
      '<div class="legend">' + segs.map(function (s) { return '<div><span class="sw2" style="background:' + s[2] + '"></span>' + s[0] + "<b>" + C.gib(s[1]) + " GB</b></div>"; }).join("") + "</div></div>" +
      '<div class="panel">' + chart("ch-mem", [{ data: C.hist.mem, color: "--mem" }], 100, 70) + "</div>" +
      "<div>" + kv("Memory pressure", pressure) + kv("Swap used", C.gib(mem.swapUsed || 0) + " GB") + "</div></div>" +
      '<div class="col"><div class="panel-title">Apps using the most memory</div>' +
      appList(d.apps, function (a) { return a.value >= 1073741824 ? (a.value / 1073741824).toFixed(2) + " GB" : Math.round(a.value / 1048576) + " MB"; }) + "</div>";
  }

  // ---------- Disk: what's using the space (list + WinDirStat-style treemap) ----------
  var diskVol = null, diskPath = [], diskSig = "", diskExtra = "", diskHits = [];
  try { diskVol = localStorage.getItem("plinth.diskVol"); } catch (e) {}
  var PALETTE = ["#3d7cf5", "#ef4b3f", "#f5a623", "#30c15a", "#a854e0", "#00b3d6", "#ff6fae", "#b08a5a", "#6e7cff", "#e0c100", "#14b8a6", "#ff8a3d"];
  function refetchDisk(extra) { diskExtra = extra || ""; busy = false; fetchDetail(); }
  function diskItems(d) {
    var n = d.node; if (!n) return [];
    var kids = (n.c || []).map(function (c, i) { return { node: c, color: c.o ? "#8e8e93" : PALETTE[i % PALETTE.length] }; });
    if (!d.path.length && d.unseen > Math.max(1e9, d.used * 0.01)) {
      kids.push({ node: { n: "Not measured", s: d.unseen, u: true }, color: C.theme() === "night" ? "#48484a" : "#c7c7cc" });
      kids.sort(function (a, b) { return b.node.s - a.node.s; });
    }
    return kids;
  }
  function count(n) { return n >= 1e6 ? (n / 1e6).toFixed(1) + "M" : n >= 1e4 ? Math.round(n / 1e3) + "K" : n.toLocaleString("en-US"); }
  function renderDisk() {
    var d = detail || {};
    var vols = d.volumes || [], vol = vols.filter(function (v) { return v.id === d.volume; })[0];
    if (vol) { diskVol = vol.id; $("sheet-sub").textContent = vol.name + " · " + C.gb(vol.used) + " used of " + C.gb(vol.total); }
    var sig = JSON.stringify([d.volume, d.path, d.at, d.running, d.running ? Math.round((d.scanned || 0) / 2e9) : 0, C.theme()]);
    if (sig === diskSig && bodyEl.querySelector(".dk-main, .dk-scan")) return null;
    diskSig = sig;

    var bar = '<div class="dk-bar">';
    if (vols.length > 1) bar += '<div class="dk-vols">' + vols.map(function (v) {
      return '<button data-act="vol" data-v="' + esc(v.id) + '" class="' + (v.id === d.volume ? "on" : "") + '">' + esc(v.name) + "</button>";
    }).join("") + "</div>";
    var crumbs = [(vol && vol.name) || "Disk"].concat(d.path || []);
    bar += '<div class="dk-crumbs">' + crumbs.map(function (c, i) {
      return i < crumbs.length - 1 ? '<button data-act="crumb" data-i="' + i + '">' + esc(c) + "</button><span>›</span>" : "<b>" + esc(c) + "</b>";
    }).join("") + "</div>";
    var status = d.running ? "Scanning… " + C.gb(d.scanned || 0) + " · " + count(d.files || 0) + " files"
                           : d.at ? "Scanned " + C.ago(d.at) : "";
    bar += '<div class="dk-st">' + status + "</div>" + (d.running ? "" : '<button class="dk-re" data-act="rescan">Rescan</button>') + "</div>";

    if (!d.node) {
      var p = d.used ? Math.min(99, (d.scanned || 0) / d.used * 100) : 0;
      return bar + '<div class="dk-scan"><div class="big">' + Math.round(p) + '<span class="unit">%</span></div><div class="bar"><div class="fill" style="width:' + p.toFixed(1) + '%"></div></div>' +
        '<div class="note2">' + (d.volume ? "Measuring every folder on this drive. The first scan takes a minute or two; after that it reopens instantly." : "Loading…") + "</div>" +
        (d.fullDiskAccess === false && vol && vol.root ? '<div class="note2">macOS may ask whether Matchbox Dashboard can read your Desktop, Documents and Downloads folders.</div>' : "") + "</div>";
    }
    var n = d.node, items = diskItems(d), total = items.reduce(function (a, b) { return a + b.node.s; }, 0) || 1;
    var rows = items.map(function (it) {
      var c = it.node, dir = c.d && c.c && c.c.length, pctv = c.s / total * 100;
      return '<div class="dk-row' + (dir ? " dir" : "") + '"' + (dir ? ' data-act="into" data-n="' + esc(c.n) + '"' : "") + '><i class="sw" style="background:' + it.color + '"></i>' +
        '<div class="dk-n"><b>' + esc(c.n) + (dir ? '<span class="chev">›</span>' : "") + '</b><div class="bar2"><i style="width:' + Math.max(1, pctv).toFixed(1) + "%;background:" + it.color + '"></i></div></div>' +
        '<div class="dk-s">' + C.gb(c.s) + "<small>" + (pctv >= 1 ? Math.round(pctv) : pctv.toFixed(1)) + "%" + (c.f ? " · " + count(c.f) + " files" : "") + "</small></div></div>";
    }).join("");
    var foot = d.denied && d.fullDiskAccess === false && !d.path.length
      ? '<div class="note2">' + d.denied + " protected folders were skipped. For a complete picture, add Matchbox Dashboard in System Settings › Privacy &amp; Security › Full Disk Access.</div>" : "";
    return bar + '<div class="dk-main"><div class="dk-list">' + rows + foot + '</div><div class="dk-map"><canvas id="dk-canvas"></canvas></div></div>';
  }

  function squarify(vals, x, y, w, h) {
    var out = [], total = 0; vals.forEach(function (v) { total += v; });
    if (total <= 0 || w <= 0 || h <= 0) return vals.map(function () { return [x, y, 0, 0]; });
    var areas = vals.map(function (v) { return v * w * h / total; }), i = 0;
    function worst(row, side) {
      var s = 0, mx = 0, mn = Infinity; row.forEach(function (a) { s += a; mx = Math.max(mx, a); mn = Math.min(mn, a); });
      return Math.max(side * side * mx / (s * s), s * s / (side * side * mn));
    }
    while (i < areas.length) {
      var side = Math.min(w, h), row = [areas[i]], j = i + 1;
      while (j < areas.length && worst(row.concat(areas[j]), side) <= worst(row, side)) { row.push(areas[j]); j++; }
      var s = 0; row.forEach(function (a) { s += a; });
      if (w >= h) { var cw = s / h, cy = y; row.forEach(function (a) { var ch = a / cw; out.push([x, cy, cw, ch]); cy += ch; }); x += cw; w -= cw; }
      else { var rh = s / w, cx = x; row.forEach(function (a) { var cw2 = a / rh; out.push([cx, y, cw2, rh]); cx += cw2; }); y += rh; h -= rh; }
      i = j;
    }
    return out;
  }
  function shade(hex, f) {
    var n = parseInt(hex.slice(1), 16), rr = n >> 16, g = (n >> 8) & 255, b = n & 255;
    function m(v) { return Math.round(f > 0 ? v + (255 - v) * f : v * (1 + f)); }
    return "rgb(" + m(rr) + "," + m(g) + "," + m(b) + ")";
  }
  function drawDisk() {
    var cv = $("dk-canvas"), d = detail; if (!cv || !d || !d.node) return;
    var W = cv.parentNode.clientWidth, H = cv.parentNode.clientHeight, k = (window.devicePixelRatio || 1) * C.scale();
    cv.width = Math.round(W * k); cv.height = Math.round(H * k); cv.style.width = W + "px"; cv.style.height = H + "px";
    var ctx = cv.getContext("2d"); ctx.setTransform(k, 0, 0, k, 0, 0);
    var items = diskItems(d); diskHits = [];
    function cushion(x, y, w, h, col) {
      ctx.fillStyle = col; ctx.fillRect(x, y, w, h);
      if (w > 4 && h > 4) {
        var g = ctx.createRadialGradient(x + w * 0.38, y + h * 0.32, 0, x + w * 0.5, y + h * 0.5, Math.max(w, h) * 0.72);
        g.addColorStop(0, "rgba(255,255,255,0.42)"); g.addColorStop(0.55, "rgba(255,255,255,0.04)"); g.addColorStop(1, "rgba(0,0,0,0.34)");
        ctx.fillStyle = g; ctx.fillRect(x, y, w, h);
      }
      if (w > 2 && h > 2) { ctx.strokeStyle = "rgba(0,0,0,0.28)"; ctx.lineWidth = 0.75; ctx.strokeRect(x + 0.4, y + 0.4, w - 0.8, h - 0.8); }
    }
    function lay(nodes, x, y, w, h, depth, col) {
      var list = nodes.filter(function (c) { return c.s > 0; });
      var rects = squarify(list.map(function (c) { return c.s; }), x, y, w, h);
      list.forEach(function (c, i) {
        var r = rects[i], cc = c.o ? shade(col, 0.45) : shade(col, ((i % 5) - 2) * 0.07);
        if (c.c && c.c.length && depth < 3 && r[2] > 8 && r[3] > 8) lay(c.c, r[0], r[1], r[2], r[3], depth + 1, col);
        else cushion(r[0], r[1], r[2], r[3], cc);
      });
    }
    var rects = squarify(items.map(function (it) { return it.node.s; }), 0, 0, W, H);
    items.forEach(function (it, i) {
      var r = rects[i], c = it.node;
      if (c.c && c.c.length) lay(c.c, r[0], r[1], r[2], r[3], 1, it.color); else cushion(r[0], r[1], r[2], r[3], it.color);
      diskHits.push({ r: r, node: c });
    });
    // Outline and label the top-level blocks.
    items.forEach(function (it, i) {
      var r = rects[i];
      ctx.strokeStyle = C.theme() === "night" ? "#000" : "rgba(255,255,255,0.9)"; ctx.lineWidth = 2.5; ctx.strokeRect(r[0] + 1.25, r[1] + 1.25, r[2] - 2.5, r[3] - 2.5);
      if (r[2] > 74 && r[3] > 30) {
        ctx.font = "700 " + (r[2] > 180 && r[3] > 60 ? 18 : 14) + "px " + (C.cssVar("--font") || "sans-serif");
        ctx.fillStyle = "#fff"; ctx.shadowColor = "rgba(0,0,0,0.75)"; ctx.shadowBlur = 4;
        var label = it.node.n, maxW = r[2] - 14;
        while (label.length > 3 && ctx.measureText(label).width > maxW) label = label.slice(0, -2);
        if (label !== it.node.n) label = label.replace(/.$/, "…");
        ctx.fillText(label, r[0] + 8, r[1] + 22);
        if (r[3] > 52) { ctx.font = "600 13px " + (C.cssVar("--font") || "sans-serif"); ctx.fillText(C.gb(it.node.s), r[0] + 8, r[1] + 40); }
        ctx.shadowBlur = 0;
      }
    });
  }
  function diskTap(e) {
    var cv = $("dk-canvas"), b = cv.getBoundingClientRect(), sc = C.scale();
    var x = (e.clientX - b.left) / sc, y = (e.clientY - b.top) / sc;
    diskHits.forEach(function (h) {
      var r = h.r;
      if (x >= r[0] && x < r[0] + r[2] && y >= r[1] && y < r[1] + r[3] && h.node.d && h.node.c && h.node.c.length) {
        diskPath.push(h.node.n); diskSig = ""; refetchDisk();
      }
    });
  }

  // ---------- Open on your phone (QR) ----------
  function renderQR() {
    var u = args.url || "", short = u.replace(/^https?:\/\/(www\.)?/, "").replace(/\?.*$/, "");
    if (short.length > 60) short = short.slice(0, 57) + "…";
    var host = u.replace(/^https?:\/\/(www\.)?/, "").split("/")[0];
    $("sheet-sub").textContent = host;
    return '<div class="qr-code"><img src="/api/qr?u=' + encodeURIComponent(u) + '" alt="" onerror="this.parentNode.className=\'qr-code off\'"><span>QR code needs the Mac</span></div>' +
      '<div class="qr-info">' + (args.thumb ? '<div class="qr-thumb"><img src="/img?u=' + encodeURIComponent(args.thumb) + '" alt="" onerror="this.parentNode.remove()"></div>' : "") +
      '<div class="qr-title">' + esc(args.title || host) + '</div><div class="qr-url">' + esc(short) + "</div>" +
      '<div class="qr-hint"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="6.5" y="2.5" width="11" height="19" rx="2.5"/><path d="M10.5 18.5h3"/></svg>Point your phone’s camera at the code to open it.</div>' +
      '<div class="qr-actions"><button class="btn2" data-act="openmac"' + (C.presence() === "awake" || C.presence() === "locked" ? "" : " disabled") + ">" +
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="2.5" y="4" width="19" height="13" rx="2"/><path d="M8.5 21h7M12 17v4"/></svg>Open on Mac</button>' +
      '<span class="note2" id="qr-msg"></span></div></div>';
  }

  // ---------- Claude Code ----------
  function limitBars(lim, bridge) {
    function one(name, L) {
      if (!L) return "";
      return '<div class="cl-lim"><div class="kvr"><b>' + name + '</b><span>' + Math.round(L.used) + "% used · resets in " + C.until(L.reset) + "</span></div>" +
        '<div class="bar2" style="height:8px;border-radius:4px;background:var(--track);overflow:hidden"><i style="display:block;height:100%;background:' +
        (L.used >= 85 ? "var(--live)" : "var(--claude)") + ";width:" + Math.min(100, L.used).toFixed(1) + '%"></i></div></div>';
    }
    if (!lim.five && !lim.week) return bridge ? "" : '<div class="note2">Plan limits: connect Claude Code in the manager (Display › Claude Code usage).</div>';
    return one("5-hour limit", lim.five) + one("Weekly limit", lim.week);
  }

  function renderClaude() {
    var d = detail, x = d.ctx, tok = C.tok, until = C.until;
    if (!d.today && !d.error) return '<div class="col"><div class="note2">Reading Claude Code usage…</div></div><div class="col"></div>';
    if (!d.any) return '<div class="col"><div class="big" style="font-size:44px">No activity yet</div><div class="note2">Usage appears here once you use Claude Code on this Mac (the app’s Code tab or the claude command). Chats in the Claude app aren’t stored on the Mac.</div></div><div class="col">' + limitBars(d.limits || {}, true) + "</div>";
    $("sheet-sub").textContent = x ? x.model + " · " + tok(x.window) + " context" : "";
    var t = d.today || {}, w = d.week || {}, b = d.block;
    var top = Math.max.apply(null, (d.days || []).map(function (v) { return v.tokens; }).concat([1]));
    var days = (d.days || []).map(function (v, i, all) {
      var dt = new Date(v.t);
      return '<div' + (i === all.length - 1 ? ' class="today"' : "") + '><i style="height:' + Math.max(2, v.tokens / top * 70).toFixed(1) + 'px"></i><span>' +
        C.fmt(dt, { weekday: "short" }) + "</span></div>";
    }).join("");
    function rows(list) {
      var mx = Math.max.apply(null, (list || []).map(function (r) { return r.tokens; }).concat([1]));
      return '<div class="applist">' + (list || []).map(function (r) {
        return '<div class="app"><div class="an"><b>' + esc(r.name) + '</b><div class="bar2"><i style="width:' + Math.max(2, r.tokens / mx * 100).toFixed(1) +
          '%"></i></div></div><div class="av">' + tok(r.tokens) + (r.at ? "<small>" + C.ago(r.at) + "</small>" : "") + "</div></div>";
      }).join("") + "</div>";
    }
    var resetWhen = d.reset ? new Date(d.reset) : null;
    return '<div class="col">' +
      (x ? '<div class="panel-title">Context left · ' + esc(x.session || x.folder || "Latest session") + '</div><div class="big">' + Math.round(x.left) + '<span class="unit">%</span></div>' +
        '<div class="bar2" style="height:10px;border-radius:5px;background:var(--track);overflow:hidden"><i style="display:block;height:100%;background:var(--claude);width:' + (100 - x.left).toFixed(1) + '%"></i></div>' +
        '<div class="note2">' + tok(x.used) + " of " + tok(x.window) + " tokens used · last reply " + C.ago(x.at) + "</div>" : "") +
      limitBars(d.limits || {}, d.bridge) +
      "<div>" +
        kv("Weekly reset", resetWhen ? "in " + until(d.reset) + " · " + C.fmt(resetWhen, { weekday: "short", hour: "numeric", minute: "2-digit", hour12: !(C.cfg() || {}).clock24h }) : "Not set") +
        ((d.limits || {}).five ? "" : kv("5-hour window (est.)", b ? "ends in " + until(b.end) : "No recent use")) +
        kv("Tokens this window", b ? tok(b.tokens) : "–") +
      "</div>" +
      '<div class="panel"><div class="panel-title">Last 7 days</div><div class="cl-days">' + days + "</div></div></div>" +
      '<div class="col"><div class="tiles">' +
        [["Today", tok(t.tokens)], [d.weekFromReset ? "This week" : "Last 7 days", tok(w.tokens)], ["Replies today", (t.messages || 0) + ""],
         ["Output today", tok(t.output)], ["Cache writes", tok(t.cacheWrite)], ["Cache reads", tok(t.cacheRead)]]
          .map(function (p) { return '<div class="t"><div class="k">' + p[0] + '</div><div class="v">' + p[1] + "</div></div>"; }).join("") + "</div>" +
      '<div class="panel-title">' + (d.weekFromReset ? "This week" : "Last 7 days") + " by session</div>" + rows((d.sessions || []).slice(0, 4)) +
      ((d.models || []).length > 1 ? '<div class="panel-title">By model</div>' + rows(d.models) : "") +
      "</div>";
  }

  // ---------- Network ----------
  function renderNet() {
    var m = C.metrics() || {}, net = m.net || {}, d = detail, st = net.speedTest || {};
    $("sheet-sub").textContent = (net.ifaceName || net.iface || "") + (d.ip ? " · " + d.ip : "");
    var max = niceMax(Math.max.apply(null, C.hist.rx.concat(C.hist.tx, [0])) * 1.1);
    var apps = (d.apps || []).map(function (a) { a._sort = a.rx + a.tx; a.value = a._sort; return a; });
    var stLine = net.speedTestRunning ? "Running…" : st.down ? "↓ " + C.bitsStr(st.down) + "   ↑ " + C.bitsStr(st.up) : "Not run yet";
    return '<div class="col"><div style="display:flex;gap:26px"><div class="big" style="font-size:54px"><span style="color:var(--down)">↓</span>' +
      C.bits(net.rxBps)[0] + '<span class="unit">' + C.bits(net.rxBps)[1] + "</span></div>" +
      '<div class="big" style="font-size:54px"><span style="color:var(--up)">↑</span>' + C.bits(net.txBps)[0] + '<span class="unit">' + C.bits(net.txBps)[1] + "</span></div></div>" +
      '<div class="panel">' + chart("ch-net", [{ data: C.hist.tx, color: "--up", lineOnly: true }, { data: C.hist.rx, color: "--down" }], max, 86) + "</div>" +
      '<div class="panel"><div class="panel-title">Speed test' + (st.at && !net.speedTestRunning ? " · " + C.ago(st.at) : "") + "</div>" +
      '<div style="display:flex;align-items:center;gap:12px"><div style="flex:1;font-size:24px;font-weight:750">' + stLine +
      (st.rpm ? '<div class="note2">Responsiveness ' + Math.round(st.rpm) + " RPM" + (st.rtt ? " · Latency " + Math.round(st.rtt) + " ms" : "") + "</div>" : "") +
      '</div><button class="btn2" data-act="speedtest"' + (net.speedTestRunning ? " disabled" : "") + ">" + (net.speedTestRunning ? "Testing…" : "Run Test") + "</button></div></div>" +
      "<div>" + kv("Router", esc(d.router || "–")) + kv("DNS", esc(d.dns || "–")) + "</div></div>" +
      '<div class="col"><div class="panel-title">Apps using the network</div>' +
      appList(apps, function (a) { return "↓ " + C.bitsStr(a.rx) + "<small>↑ " + C.bitsStr(a.tx) + "</small>"; }, "Measuring…") + "</div>";
  }

  // ---------- World clock ----------
  function tzParts(date, zone) {
    var o = { hour12: false, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" };
    if (zone) o.timeZone = zone;
    var p = {};
    try { new Intl.DateTimeFormat("en-US", o).formatToParts(date).forEach(function (x) { p[x.type] = x.value; }); } catch (e) { return null; }
    var h = +p.hour % 24;
    return { y: +p.year, mo: +p.month, d: +p.day, h: h, mi: +p.minute, s: +p.second, utc: Date.UTC(+p.year, +p.month - 1, +p.day, h, +p.minute, +p.second) };
  }
  function face(p, dark) {
    var ticks = "";
    for (var i = 0; i < 12; i++) {
      var a = i * Math.PI / 6, r1 = i % 3 === 0 ? 46 : 50;
      ticks += '<line x1="' + (60 + Math.sin(a) * r1).toFixed(1) + '" y1="' + (60 - Math.cos(a) * r1).toFixed(1) + '" x2="' + (60 + Math.sin(a) * 55).toFixed(1) +
               '" y2="' + (60 - Math.cos(a) * 55).toFixed(1) + '" stroke-width="' + (i % 3 === 0 ? 3.5 : 2) + '"/>';
    }
    var ha = (p.h % 12 + p.mi / 60) * 30, ma = (p.mi + p.s / 60) * 6, sa = p.s * 6;
    var fg = dark ? "#fff" : "var(--text)", bg = dark ? "#1c1c1e" : "rgba(255,255,255,0.9)";
    if (!dark && C.theme() === "night") { bg = "#000"; fg = "#fff"; }
    return '<svg class="face" viewBox="0 0 120 120"><circle cx="60" cy="60" r="58" fill="' + bg + '" stroke="' + (dark || C.theme() === "night" ? "rgba(255,255,255,0.3)" : "rgba(0,0,0,0.08)") + '" stroke-width="1.5"/>' +
      '<g stroke="' + fg + '" stroke-linecap="round">' + ticks + "</g>" +
      '<g stroke="' + fg + '" stroke-linecap="round"><line x1="60" y1="60" x2="60" y2="30" stroke-width="5.5" transform="rotate(' + ha + ' 60 60)"/>' +
      '<line x1="60" y1="60" x2="60" y2="14" stroke-width="3.5" transform="rotate(' + ma + ' 60 60)"/></g>' +
      '<line x1="60" y1="70" x2="60" y2="12" stroke="#ff9f0a" stroke-width="1.8" stroke-linecap="round" transform="rotate(' + sa + ' 60 60)"/>' +
      '<circle cx="60" cy="60" r="4" fill="#ff9f0a"/></svg>';
  }
  function renderClock() {
    var cfg = C.cfg(), d = C.now(), here = tzParts(d, C.tz());
    var list = [{ name: (cfg.location && cfg.location.name) || "Here", tz: C.tz(), here: true }].concat((cfg.worldClocks || []).slice(0, 5));
    $("sheet-sub").textContent = C.fmt(d, { weekday: "long", month: "long", day: "numeric" });
    return '<div class="wc-grid">' + list.map(function (c) {
      var p = tzParts(d, c.tz); if (!p) return "";
      var diff = Math.round((p.utc - here.utc) / 360000) / 10;
      var dayRel = p.d === here.d ? "Today" : p.utc > here.utc ? "Tomorrow" : "Yesterday";
      var rel = c.here ? "Local time" : dayRel + ", " + (diff === 0 ? "same time" : (diff > 0 ? "+" : "−") + Math.abs(diff) + (Math.abs(diff) === 1 ? " hr" : " hrs"));
      var dark = p.h < 6 || p.h >= 18;
      var t = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", hour12: !cfg.clock24h, timeZone: c.tz }).format(d);
      return '<div class="wc' + (dark && C.theme() !== "night" ? " dark" : "") + '">' + face(p, dark && C.theme() !== "night") +
        '<div><div class="wc-city"><small>' + (c.here ? "Home" : esc(c.tz.split("/")[0])) + "</small>" + esc(c.name) + '</div><div class="wc-time">' + t +
        '</div><div class="wc-rel">' + rel + "</div></div></div>";
    }).join("") + "</div>";
  }

  // ---------- Full forecast ----------
  function hm(iso, h24) {
    if (!iso) return "–";
    var h = +iso.slice(11, 13), mi = iso.slice(14, 16);
    return h24 ? (h < 10 ? "0" : "") + h + ":" + mi : ((h % 12) || 12) + ":" + mi + " " + (h < 12 ? "AM" : "PM");
  }
  function compass(deg) { return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(((deg || 0) % 360) / 45) % 8]; }
  function hourlySVG(hr, cfg, cur) {
    var W = 512, H = 168, top = 34, bottom = 128, n = Math.min(24, hr.time.length);
    if (n < 2) return "";
    var startKey = (cur.time || "").slice(0, 13), s0 = 0;
    for (var i = 0; i < hr.time.length; i++) if (hr.time[i].slice(0, 13) >= startKey) { s0 = i; break; }
    var temps = hr.temperature_2m.slice(s0, s0 + n), lo = Math.min.apply(null, temps), hi = Math.max.apply(null, temps), span = Math.max(1, hi - lo);
    var x = function (i) { return 14 + i * (W - 28) / (temps.length - 1); };
    var y = function (t) { return bottom - 16 - (t - lo) / span * (bottom - top - 30); };
    var path = temps.map(function (t, i) { return (i ? "L" : "M") + x(i).toFixed(1) + " " + y(t).toFixed(1); }).join(" ");
    var out = '<svg class="hourly" viewBox="0 0 ' + W + " " + H + '">';
    for (var k = 0; k < temps.length; k++) {
      var pp = (hr.precipitation_probability || [])[s0 + k] || 0;
      if (pp > 0) out += '<rect x="' + (x(k) - 6).toFixed(1) + '" y="' + (bottom - pp * 0.3).toFixed(1) + '" width="12" height="' + (pp * 0.3).toFixed(1) + '" rx="3" fill="var(--rain)" opacity="0.35"/>';
    }
    out += '<path d="' + path + ' L' + x(temps.length - 1) + " " + bottom + " L" + x(0) + " " + bottom + 'Z" fill="var(--disk)" opacity="0.12"/>';
    out += '<path d="' + path + '" fill="none" stroke="var(--disk)" stroke-width="3.5" stroke-linejoin="round" stroke-linecap="round"/>';
    for (var j = 0; j < temps.length; j += 3) {
      var hh = +hr.time[s0 + j].slice(11, 13);
      var lbl = j === 0 ? "Now" : cfg.clock24h ? hh + ":00" : ((hh % 12) || 12) + (hh < 12 ? "a" : "p");
      out += '<circle cx="' + x(j).toFixed(1) + '" cy="' + y(temps[j]).toFixed(1) + '" r="4.5" fill="var(--disk)"/>' +
        '<text x="' + x(j).toFixed(1) + '" y="' + (y(temps[j]) - 11).toFixed(1) + '" text-anchor="middle" font-size="17" font-weight="750" fill="var(--text)">' + Math.round(temps[j]) + "°</text>" +
        '<text x="' + x(j).toFixed(1) + '" y="' + (H - 18) + '" text-anchor="middle" font-size="15" font-weight="650" fill="var(--text-3)">' + lbl + "</text>" +
        '<g transform="translate(' + (x(j) - 11).toFixed(1) + " " + (H - 14) + ') scale(0.34)">' + C.wxIcon(hr.weather_code[s0 + j], hr.is_day ? hr.is_day[s0 + j] : 1).replace(/<\/?svg[^>]*>/g, "") + "</g>";
    }
    return out + "</svg>";
  }
  function renderForecast() {
    var feeds = C.feeds(), cfg = C.cfg(), w = feeds.weather;
    if (!w || !w.current) return '<div class="empty">No forecast yet.</div>';
    var c = w.current, d = w.daily || {}, hr = w.hourly || {}, u = w.current_units || {}, metric = cfg.units === "metric";
    var kind = C.wxKind(c.weather_code);
    $("sheet-title").textContent = "Weather";
    $("sheet-sub").textContent = ((cfg.location && (cfg.location.full || cfg.location.name)) || "") + (feeds.weatherAt ? " · updated " + C.ago(feeds.weatherAt).toLowerCase() : "");
    var precip = d.precipitation_sum ? d.precipitation_sum[0] : 0;
    var precipStr = metric ? precip.toFixed(1) + " mm" : (precip / 25.4).toFixed(2) + " in";
    var pressure = c.pressure_msl ? (metric ? Math.round(c.pressure_msl) + " hPa" : (c.pressure_msl * 0.02953).toFixed(2) + " inHg") : "–";
    var wu = (u.wind_speed_10m || "").replace("mp/h", "mph");
    var tiles = [
      ["UV index", c.uv_index != null ? Math.round(c.uv_index) + (d.uv_index_max ? " / " + Math.round(d.uv_index_max[0]) : "") : "–"],
      ["Humidity", Math.round(c.relative_humidity_2m) + "%"],
      ["Wind", Math.round(c.wind_speed_10m) + " " + esc(wu) + " " + compass(c.wind_direction_10m)],
      ["Sunrise", hm(d.sunrise && d.sunrise[0], cfg.clock24h)],
      ["Sunset", hm(d.sunset && d.sunset[0], cfg.clock24h)],
      ["Rain today", precipStr],
    ];
    if (c.pressure_msl) tiles.push(["Pressure", pressure]);
    var lo = Math.min.apply(null, d.temperature_2m_min || [0]), hi = Math.max.apply(null, d.temperature_2m_max || [1]), span = Math.max(1, hi - lo);
    var days = (d.time || []).slice(0, 7).map(function (t, k) {
      var name = k === 0 ? "Today" : new Intl.DateTimeFormat("en-US", { weekday: "short", timeZone: "UTC" }).format(new Date(t + "T12:00:00Z"));
      var a = d.temperature_2m_min[k], b = d.temperature_2m_max[k], pp = d.precipitation_probability_max ? d.precipitation_probability_max[k] : 0;
      return '<div class="fc-day"><span class="n">' + name + '</span><span class="i">' + C.wxIcon(d.weather_code[k], 1) + '</span><span class="p">' + (pp >= 20 ? pp + "%" : "") +
        '</span><span class="lo">' + Math.round(a) + '°</span><span class="rng"><i style="left:' + ((a - lo) / span * 100).toFixed(1) + "%;right:" + ((hi - b) / span * 100).toFixed(1) +
        '%"></i></span><span class="hi">' + Math.round(b) + "°</span></div>";
    }).join("");
    return '<div class="col"><div class="fc-now"><div class="w-icon">' + C.wxIcon(c.weather_code, c.is_day) + '</div><div class="big">' + Math.round(c.temperature_2m) + '°</div>' +
      '<div style="margin-left:auto;text-align:right"><div style="font-size:28px;font-weight:750">' + kind[1] + '</div><div style="font-size:21px;font-weight:650;color:var(--text-2)">H ' +
      Math.round(d.temperature_2m_max[0]) + "°  L " + Math.round(d.temperature_2m_min[0]) + '°</div><div class="note2" style="font-size:18px">Feels like ' + Math.round(c.apparent_temperature) + "°</div></div></div>" +
      '<div class="panel" style="padding:8px 10px 4px">' + (hr.time ? hourlySVG(hr, cfg, c) : "") + "</div>" +
      '<div class="tiles">' + tiles.slice(0, 6).map(function (t) { return '<div class="t"><div class="k">' + t[0] + '</div><div class="v">' + t[1] + "</div></div>"; }).join("") + "</div></div>" +
      '<div class="col"><div class="panel-title">7-day forecast</div><div class="fc-days">' + days + "</div></div>";
  }

  // ---------- Hook up the tap targets ----------
  [["t-cpu", "cpu"], ["t-gpu", "gpu"], ["t-mem", "mem"], ["t-disk", "disk"], ["t-net", "net"], ["t-claude", "claude"]].forEach(function (p) {
    $(p[0]).addEventListener("click", function () { open(p[1]); });
  });
  $("clock-main").addEventListener("click", function () { open("clock"); });
  $("glance").addEventListener("click", function (e) { e.stopPropagation(); open("forecast"); });

  window.PlinthSheets = {
    open: open, close: close,
    closeMetricSheets: function () { if (current && METRIC[current]) close(); },
    current: function () { return current; },
  };
})();
