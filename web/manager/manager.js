(function () {
  "use strict";
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  var NAV_ICONS = {
    tablet: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.2"><rect x="3" y="5" width="18" height="12" rx="2"/><path d="M8 20h8"/></svg>',
    display: '<svg viewBox="0 0 24 24" fill="#fff"><circle cx="12" cy="12" r="4.5"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9 7 7M17 17l2.1 2.1M4.9 19.1 7 17M17 7l2.1-2.1" stroke="#fff" stroke-width="2" stroke-linecap="round"/></svg>',
    weather: '<svg viewBox="0 0 24 24" fill="#fff"><path d="M7 19h10a4 4 0 0 0 .5-8 5.5 5.5 0 0 0-10.6 1.4A3.3 3.3 0 0 0 7 19z"/></svg>',
    sports: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round"><path d="M7 4h10v5a5 5 0 0 1-10 0zM12 14v4M8 21h8"/></svg>',
    news: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M8 9h8M8 13h8M8 17h5"/></svg>',
    network: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M8 4v15M4 15l4 4 4-4M16 20V5M12 9l4-4 4 4"/></svg>',
    bluesky: '<svg viewBox="0 0 24 24"><path fill="#fff" d="M6.3 4.6c2.1 1.6 4.4 4.8 5.7 6.5 1.3-1.7 3.6-4.9 5.7-6.5 1.5-1.1 4-2 4 .8 0 .6-.3 4.7-.5 5.4-.7 2.4-3.2 3-5.4 2.6 3.9.7 4.9 2.9 2.7 5.1-4.1 4.2-5.9-1.1-6.4-2.4l-.1-.4-.1.4c-.5 1.3-2.3 6.6-6.4 2.4-2.2-2.2-1.2-4.4 2.7-5.1-2.2.4-4.7-.2-5.4-2.6C2.6 10.1 2.3 6 2.3 5.4c0-2.8 2.5-1.9 4-.8z"/></svg>',
    steam: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round"><rect x="2.5" y="7" width="19" height="11" rx="5.5"/><path d="M7.5 10.5v4M5.5 12.5h4"/></svg>',
    exchange: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8h13l-3.5-3.5M20 16H7l3.5 3.5"/></svg>',
    kanji: '<svg viewBox="0 0 24 24"><text x="12" y="17.5" text-anchor="middle" font-size="15" font-weight="700" fill="#fff" font-family="sans-serif">字</text></svg>',
    radar: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="8.5" opacity=".6"/><circle cx="12" cy="12" r="4.5"/><path d="M12 12l6-6"/></svg>',
    slickdeals: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 21V11H3.5V21zM7 11l4-8c1.6 0 2.7 1.3 2.4 2.9L12.8 9H19a2 2 0 0 1 2 2.3l-1.3 7.4A2.6 2.6 0 0 1 17.2 21H7"/></svg>',
    worldclock: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/></svg>',
    youtube: '<svg viewBox="0 0 24 24"><path d="M9 7.5v9l7.5-4.5z" fill="#fff"/></svg>',
    anime: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round"><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2M9 2.5h6"/></svg>',
    connection: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round"><path d="M12 3v12M8 7l4-4 4 4M7 13v3a5 5 0 0 0 10 0v-3"/></svg>',
  };
  $$("nav a").forEach(function (a) { $(".nico", a).innerHTML = NAV_ICONS[a.getAttribute("href").slice(1)] || ""; });

  var LEAGUES = [
    ["football/nfl", "NFL"], ["basketball/nba", "NBA"], ["baseball/mlb", "MLB"], ["hockey/nhl", "NHL"],
    ["basketball/wnba", "WNBA"], ["football/college-football", "College Football"],
    ["basketball/mens-college-basketball", "Men’s College Basketball"], ["basketball/womens-college-basketball", "Women’s College Basketball"],
    ["soccer/usa.1", "MLS"], ["soccer/usa.nwsl", "NWSL"], ["soccer/eng.1", "Premier League"], ["soccer/esp.1", "La Liga"],
    ["soccer/uefa.champions", "Champions League"],
  ];

  var cfg = {};

  function get(path) { return path.split(".").reduce(function (o, k) { return o == null ? undefined : o[k]; }, cfg); }
  function patchFor(path, v) {
    var parts = path.split("."), root = {}, cur = root;
    for (var i = 0; i < parts.length - 1; i++) { cur[parts[i]] = {}; cur = cur[parts[i]]; }
    cur[parts[parts.length - 1]] = v;
    return root;
  }
  function setLocal(path, v) {
    var parts = path.split("."), cur = cfg;
    for (var i = 0; i < parts.length - 1; i++) { if (typeof cur[parts[i]] !== "object" || cur[parts[i]] === null) cur[parts[i]] = {}; cur = cur[parts[i]]; }
    cur[parts[parts.length - 1]] = v;
  }

  // ---------- Saving ----------
  var pending = {}, saveTimer = null;
  function merge(a, b) { for (var k in b) { if (b[k] && typeof b[k] === "object" && !Array.isArray(b[k]) && a[k] && typeof a[k] === "object" && !Array.isArray(a[k])) merge(a[k], b[k]); else a[k] = b[k]; } return a; }
  function save(path, v, immediate) {
    setLocal(path, v);
    merge(pending, patchFor(path, v));
    $("#saved").textContent = "Saving…"; $("#saved").className = "side-foot busy";
    clearTimeout(saveTimer);
    saveTimer = setTimeout(flush, immediate ? 0 : 350);
  }
  function flush() {
    var body = pending; pending = {};
    var portChange = body.port !== undefined;
    fetch("/api/config", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) })
      .then(function (r) { if (!r.ok) throw r.status; return r.json(); })
      .then(function () {
        $("#saved").textContent = "All changes saved"; $("#saved").className = "side-foot";
        if (portChange && String(body.port) !== location.port) {
          toast("Moving to port " + body.port + "…");
          setTimeout(function () { location.href = location.protocol + "//" + location.hostname + ":" + body.port + "/manager/"; }, 1500);
        }
      })
      .catch(function () { $("#saved").textContent = "Couldn’t save — is Matchbox Dashboard running?"; });
  }

  function toast(msg) {
    var t = $("#toast"); t.textContent = msg; t.classList.add("show");
    clearTimeout(t._h); t._h = setTimeout(function () { t.classList.remove("show"); }, 2200);
  }

  // ---------- Generic bindings ----------
  function fmtOut(el, v) {
    if (el.hasAttribute("data-bright")) return v < 0 ? "Auto" : Math.round(v * 100) + "%";
    return v + (el.getAttribute("data-suffix") || "");
  }
  function updateOut(path) {
    $$('[data-out="' + path + '"]').forEach(function (o) { o.textContent = fmtOut(o, get(path)); });
  }

  function bindAll() {
    $$("input[data-key]").forEach(function (el) {
      var path = el.getAttribute("data-key"), v = get(path);
      if (el.type === "checkbox") el.checked = !!v;
      else el.value = v == null ? "" : v;
      updateOut(path);
      if (el._bound) return; el._bound = true;
      var handler = function () {
        var val = el.type === "checkbox" ? el.checked : el.value;
        if (el.hasAttribute("data-num")) val = Number(val);
        if (el.hasAttribute("data-bright") && val < 0) val = -1;
        if (el.hasAttribute("data-key") && path === "port" && (val < 1024 || val > 65535)) return;
        setLocal(path, val); updateOut(path);
        save(path, val);
      };
      el.addEventListener(el.hasAttribute("data-lazy") ? "change" : (el.type === "checkbox" ? "change" : "input"), handler);
    });
    $$(".seg[data-key]").forEach(function (seg) {
      var path = seg.getAttribute("data-key");
      $$("button", seg).forEach(function (b) { b.classList.toggle("on", b.getAttribute("data-v") === get(path)); });
      if (seg._bound) return; seg._bound = true;
      seg.addEventListener("click", function (e) {
        var b = e.target.closest("button"); if (!b) return;
        $$("button", seg).forEach(function (x) { x.classList.toggle("on", x === b); });
        save(path, b.getAttribute("data-v"));
      });
    });
    renderLeagues(); renderFeeds(); syncDayOptions(); renderChannels(); renderShows(); renderClocks(); renderBsky(); renderSteam();
    renderFX(); renderSlick(); renderRadar(); keyStatus(); $("#kj-level").value = get("kanji.level") || "jlpt-4";
    $("#favorites").value = (get("sports.favorites") || []).join(", ");
    $("#loc-current").textContent = locLabel();
  }

  function locLabel() {
    var l = cfg.location || {};
    return (l.full || l.name || "Not set") + (l.lat != null ? "  ·  " + Number(l.lat).toFixed(2) + ", " + Number(l.lon).toFixed(2) : "");
  }

  // ---------- Day colors ----------
  var PRESETS = ["#3a82f7", "#8e5cf0", "#e35da8", "#ef4b4b", "#f5902d", "#e8c02c", "#3cb55e", "#2bb3b8", "#8a8f99"];
  var presetBox = $("#presets");
  presetBox.innerHTML = PRESETS.map(function (c) { return '<button data-c="' + c + '" style="background:' + c + '" title="' + c + '"></button>'; }).join("");
  presetBox.addEventListener("click", function (e) {
    var b = e.target.closest("button"); if (!b) return;
    var c = b.getAttribute("data-c");
    $('input[data-key="dayColors.custom"]').value = c;
    save("dayColors.custom", c); syncDayOptions();
  });
  $('input[data-key="dayColors.custom"]').addEventListener("input", function () { syncDayOptions(); });
  $("#day-mode").addEventListener("click", function () { setTimeout(syncDayOptions, 0); });

  var dayTouched = false;
  function syncDayOptions() {
    var mode = get("dayColors.mode") || "wallpaper";
    $$(".day-opt").forEach(function (r) { r.hidden = r.getAttribute("data-for") !== mode; });
    var cur = (get("dayColors.custom") || "").toLowerCase();
    $$("#presets button").forEach(function (b) { b.classList.toggle("on", b.getAttribute("data-c") === cur); });
    applyPalette();
    // Editing day colors? Show the preview in Day mode so the change is visible even after sunset.
    if (dayTouched && previewTheme !== "day") setPreviewTheme("day");
    dayTouched = true;
  }

  var lastWallpaper = null, wpKey = null;
  function applyPalette() {
    var day = { mode: get("dayColors.mode") || "wallpaper", custom: get("dayColors.custom"), wallpaper: lastWallpaper };
    if (window.PlinthPalette && !matchMedia("(prefers-color-scheme: dark)").matches) PlinthPalette.apply(day);
  }
  function renderWallpaper(wp) {
    if (!wp || !wp.colors) return;
    lastWallpaper = wp;
    if (wp.key === wpKey) return;
    wpKey = wp.key;
    $("#wp-thumb").src = "/api/wallpaper.png?k=" + encodeURIComponent(wp.key);
    $("#wp-name").textContent = wp.source === "aerial" ? "Aerial wallpaper" : (wp.name || "Your wallpaper");
    var raw = ["tl", "tr", "c", "bl", "br"].map(function (k) { return '<i style="background:' + wp.colors[k] + '"></i>'; }).join("");
    var vars = PlinthPalette.build({ mode: "wallpaper", wallpaper: wp }) || {};
    var soft = ["--w-tl", "--w-tr", "--w-bg", "--w-bl", "--w-br"].map(function (k) { return '<i class="pastel" style="background:' + vars[k] + '"></i>'; }).join("");
    $("#wp-swatches").innerHTML = raw + '<span class="arrow">→</span>' + soft;
    applyPalette();
  }

  // ---------- Bluesky ----------
  function renderBsky() {
    var list = get("bluesky.accounts") || [], box = $("#bs-list");
    if (!list.length) { box.innerHTML = '<div class="row"><div class="lbl" style="color:var(--text-2)">No accounts yet — add one above.</div></div>'; return; }
    box.innerHTML = list.map(function (a, i) {
      return '<div class="row media-row" data-i="' + i + '">' + (a.avatar ? '<img src="' + esc(a.avatar) + '" alt="" style="width:40px;height:40px;border-radius:50%">' : "") +
             '<div class="lbl"><b>' + esc(a.name || a.handle) + '</b><div class="url">@' + esc(a.handle) + '</div></div><button class="x" title="Remove">×</button></div>';
    }).join("");
  }
  $("#bs-list").addEventListener("click", function (e) {
    var row = e.target.closest(".media-row"); if (!row || !e.target.classList.contains("x")) return;
    var list = (get("bluesky.accounts") || []).slice(); list.splice(+row.getAttribute("data-i"), 1);
    save("bluesky.accounts", list); renderBsky();
  });
  $("#bs-add-btn").addEventListener("click", function () {
    var q = $("#bs-add").value.trim(); if (!q) return;
    var btn = $("#bs-add-btn"); btn.disabled = true; btn.textContent = "Finding…";
    fetch("/api/bluesky/resolve?q=" + encodeURIComponent(q)).then(function (r) { return r.json(); }).then(function (a) {
      if (a.error) { toast(a.error); return; }
      var list = (get("bluesky.accounts") || []).slice();
      if (list.some(function (x) { return x.did === a.did; })) { toast("@" + a.handle + " is already added"); return; }
      list.push(a); save("bluesky.accounts", list, true); renderBsky();
      $("#bs-add").value = ""; toast("Added " + a.name);
    }).catch(function () { toast("Couldn’t reach Matchbox Dashboard"); })
      .then(function () { btn.disabled = false; btn.textContent = "Add Account"; });
  });
  $("#bs-add").addEventListener("keydown", function (e) { if (e.key === "Enter") $("#bs-add-btn").click(); });

  // ---------- Steam ----------
  function renderSteam() {
    var prof = get("steam.profile") || "";
    $("#st-profile").value = prof;
    $("#st-disconnect").hidden = !prof;
    if (!prof) { $("#st-status").textContent = "Not connected"; return; }
    $("#st-status").textContent = "Loading wishlist…";
    fetch("/api/feeds").then(function (r) { return r.json(); }).then(function (f) {
      var st = f.steam || {};
      if (st.name) $("#st-status").textContent = "Connected as " + st.name + " · " + st.count + " game" + (st.count === 1 ? "" : "s") + " · " +
        (f.steamUpcoming || []).length + " upcoming · " + (f.steamDeals || []).length + " on sale";
      else if (!(f.errors || {}).steam) setTimeout(renderSteam, 3000);
      else $("#st-status").textContent = "Couldn’t load the wishlist";
    });
  }
  $("#st-btn").addEventListener("click", function () {
    var q = $("#st-profile").value.trim(); if (!q) return;
    var btn = $("#st-btn"); btn.disabled = true; btn.textContent = "Checking…";
    fetch("/api/steam/resolve?q=" + encodeURIComponent(q)).then(function (r) { return r.json(); }).then(function (a) {
      if (a.error) { toast(a.error); return; }
      save("steam.profile", a.steamid, true);
      toast("Connected to " + a.name + "’s wishlist");
      setTimeout(renderSteam, 2500);
    }).catch(function () { toast("Couldn’t reach Matchbox Dashboard"); })
      .then(function () { btn.disabled = false; btn.textContent = "Connect"; });
  });
  $("#st-profile").addEventListener("keydown", function (e) { if (e.key === "Enter") $("#st-btn").click(); });
  $("#st-disconnect").addEventListener("click", function () { save("steam.profile", "", true); setTimeout(renderSteam, 300); });

  // ---------- Steam API key (write-only: the Mac never sends it back) ----------
  function keyStatus() {
    var set = get("steam.apiKeySet");
    $("#st-key").placeholder = set ? "Key saved ••••••••" : "Paste key";
  }
  $("#st-key-btn").addEventListener("click", function () {
    var k = $("#st-key").value.trim();
    if (!k) { toast("Paste your key first"); return; }
    if (!/^[0-9A-Fa-f]{32}$/.test(k)) { toast("That doesn’t look like a Steam Web API key (32 letters and numbers)"); return; }
    save("steam.apiKey", k, true); setLocal("steam.apiKeySet", !!k); setLocal("steam.apiKey", "");
    $("#st-key").value = ""; keyStatus();
    toast(k ? "Key saved — loading achievements and news…" : "Key removed");
  });

  // ---------- Exchange rates ----------
  var CURRENCIES = [["USD","US dollar"],["EUR","Euro"],["JPY","Japanese yen"],["GBP","British pound"],["CAD","Canadian dollar"],["AUD","Australian dollar"],
    ["CHF","Swiss franc"],["CNY","Chinese yuan"],["HKD","Hong Kong dollar"],["KRW","South Korean won"],["MXN","Mexican peso"],["BRL","Brazilian real"],
    ["INR","Indian rupee"],["SGD","Singapore dollar"],["NZD","New Zealand dollar"],["SEK","Swedish krona"],["NOK","Norwegian krone"],["DKK","Danish krone"],
    ["PLN","Polish złoty"],["CZK","Czech koruna"],["HUF","Hungarian forint"],["TRY","Turkish lira"],["ZAR","South African rand"],["THB","Thai baht"],
    ["PHP","Philippine peso"],["IDR","Indonesian rupiah"],["MYR","Malaysian ringgit"],["ILS","Israeli shekel"],["ISK","Icelandic króna"],["RON","Romanian leu"]];
  ["#fx-from", "#fx-to"].forEach(function (id, j) {
    $(id).innerHTML = CURRENCIES.map(function (c) { return '<option value="' + c[0] + '">' + c[0] + " — " + c[1] + "</option>"; }).join("");
    $(id).value = j ? "JPY" : "USD";
  });
  function renderFX() {
    var list = get("exchange.pairs") || [], box = $("#fx-list");
    box.innerHTML = list.length ? list.map(function (p, i) {
      return '<div class="row media-row" data-i="' + i + '"><div class="lbl"><b>' + esc(p.from) + " → " + esc(p.to) + '</b></div><button class="x" title="Remove">×</button></div>';
    }).join("") : '<div class="row"><div class="lbl" style="color:var(--text-2)">No pairs yet — add one above.</div></div>';
  }
  $("#fx-add").addEventListener("click", function () {
    var f = $("#fx-from").value, t = $("#fx-to").value, list = (get("exchange.pairs") || []).slice();
    if (f === t) { toast("Pick two different currencies"); return; }
    if (list.length >= 4) { toast("Up to 4 pairs — remove one first"); return; }
    if (list.some(function (p) { return p.from === f && p.to === t; })) { toast(f + " → " + t + " is already added"); return; }
    list.push({ from: f, to: t }); save("exchange.pairs", list, true); renderFX();
  });
  $("#fx-list").addEventListener("click", function (e) {
    var row = e.target.closest(".media-row"); if (!row || !e.target.classList.contains("x")) return;
    var list = (get("exchange.pairs") || []).slice(); list.splice(+row.getAttribute("data-i"), 1);
    save("exchange.pairs", list, true); renderFX();
  });

  // ---------- Kanji ----------
  $("#kj-level").addEventListener("change", function () { save("kanji.level", $("#kj-level").value, true); });

  // ---------- Radar ----------
  var ZOOMS = { 3: "Country", 4: "Large region", 5: "Region", 6: "State", 7: "Metro area" };
  function renderRadar() {
    var useWx = get("radar.useWeatherLocation") !== false;
    $("#rd-pick").hidden = useWx;
    var l = cfg.location || {};
    $("#rd-weather").textContent = l.name ? "Currently " + l.name : "";
    var rn = get("radar.name");
    $("#rd-current").textContent = rn ? rn + " · " + Number(get("radar.lat")).toFixed(2) + ", " + Number(get("radar.lon")).toFixed(2) : "Not set";
    $("#rd-zoom-out").textContent = ZOOMS[get("radar.zoom") || 6] || "";
  }
  document.querySelector('[data-key="radar.useWeatherLocation"]').addEventListener("change", function () { setTimeout(renderRadar, 0); });
  document.querySelector('[data-key="radar.zoom"]').addEventListener("input", function () { setTimeout(renderRadar, 0); });
  var rdQ = $("#rd-q"), rdRes = $("#rd-results"), rdTimer, rdFound = [];
  rdQ.addEventListener("input", function () {
    clearTimeout(rdTimer);
    var term = rdQ.value.trim();
    if (term.length < 2) { rdRes.classList.remove("open"); return; }
    rdTimer = setTimeout(function () {
      fetch("https://geocoding-api.open-meteo.com/v1/search?count=6&language=en&format=json&name=" + encodeURIComponent(term))
        .then(function (r) { return r.json(); })
        .then(function (j) {
          rdFound = j.results || [];
          rdRes.innerHTML = rdFound.length ? rdFound.map(function (r, i) {
            return '<div data-i="' + i + '">' + esc(r.name) + "<small>" + esc([r.admin1, r.country].filter(Boolean).join(", ")) + "</small></div>";
          }).join("") : '<div style="opacity:.6">No matches</div>';
          rdRes.classList.add("open");
        }).catch(function () { rdRes.innerHTML = '<div style="opacity:.6">Search unavailable</div>'; rdRes.classList.add("open"); });
    }, 300);
  });
  rdRes.addEventListener("click", function (e) {
    var d = e.target.closest("[data-i]"); if (!d) return;
    var r = rdFound[+d.getAttribute("data-i")];
    save("radar.name", r.name); save("radar.lat", r.latitude); save("radar.lon", r.longitude, true);
    rdRes.classList.remove("open"); rdQ.value = ""; renderRadar(); toast("Radar centered on " + r.name);
  });
  document.addEventListener("click", function (e) { if (!e.target.closest("#radar .search")) rdRes.classList.remove("open"); });

  // ---------- Slickdeals ----------
  var SD_CATS = [["Laptops", "laptop"], ["Monitors", "monitor"], ["TVs", "tv"], ["Headphones", "headphones"], ["Apple", "apple"], ["Phones", "phone"],
    ["SSDs & storage", "ssd"], ["Video games", "video game"], ["Nintendo Switch", "nintendo switch"], ["PlayStation", "ps5"], ["Xbox", "xbox"],
    ["Smart home", "smart home"], ["Tools", "tools"], ["Kitchen", "kitchen"], ["Clothing", "clothing"], ["Grocery", "grocery"], ["LEGO & toys", "lego"], ["Travel", "travel"]];
  function renderSlick() {
    var on = get("slickdeals.searches") || [], box = $("#sd-cats");
    box.innerHTML = "";
    SD_CATS.forEach(function (c) {
      var lab = document.createElement("label"), has = on.indexOf(c[1]) >= 0;
      lab.className = has ? "on" : "";
      lab.innerHTML = '<input type="checkbox"' + (has ? " checked" : "") + ">" + esc(c[0]);
      lab.addEventListener("click", function (e) {
        e.preventDefault();
        var cur = (get("slickdeals.searches") || []).slice(), i = cur.indexOf(c[1]);
        if (i >= 0) cur.splice(i, 1); else if (cur.length >= 8) { toast("Up to 8 categories and searches"); return; } else cur.push(c[1]);
        save("slickdeals.searches", cur); renderSlick();
      });
      box.appendChild(lab);
    });
    var custom = on.filter(function (q) { return !SD_CATS.some(function (c) { return c[1] === q; }); });
    $("#sd-list").innerHTML = custom.length ? custom.map(function (q) {
      return '<div class="row media-row" data-q="' + esc(q) + '"><div class="lbl"><b>' + esc(q) + '</b></div><button class="x" title="Remove">×</button></div>';
    }).join("") : '<div class="row"><div class="lbl" style="color:var(--text-2)">No custom searches.</div></div>';
  }
  $("#sd-list").addEventListener("click", function (e) {
    var row = e.target.closest(".media-row"); if (!row || !e.target.classList.contains("x")) return;
    var q = row.getAttribute("data-q"), cur = (get("slickdeals.searches") || []).filter(function (x) { return x !== q; });
    save("slickdeals.searches", cur, true); renderSlick();
  });
  $("#sd-add-btn").addEventListener("click", function () {
    var q = $("#sd-add").value.trim().toLowerCase(); if (!q) return;
    var cur = (get("slickdeals.searches") || []).slice();
    if (cur.indexOf(q) >= 0) { toast("Already added"); return; }
    if (cur.length >= 8) { toast("Up to 8 categories and searches"); return; }
    cur.push(q); save("slickdeals.searches", cur, true); $("#sd-add").value = ""; renderSlick();
  });
  $("#sd-add").addEventListener("keydown", function (e) { if (e.key === "Enter") $("#sd-add-btn").click(); });

  // ---------- World clock ----------
  function clockNow(tz) {
    try { return new Intl.DateTimeFormat([], { hour: "numeric", minute: "2-digit", timeZone: tz }).format(new Date()); } catch (e) { return ""; }
  }
  function renderClocks() {
    var list = get("worldClocks") || [], box = $("#wc-list");
    if (!list.length) { box.innerHTML = '<div class="row"><div class="lbl" style="color:var(--text-2)">No cities — the clock shows just your home time.</div></div>'; return; }
    box.innerHTML = list.map(function (c, i) {
      return '<div class="row media-row" data-i="' + i + '"><div class="lbl"><b>' + esc(c.name) + '</b><div class="url">' + esc(c.tz) + " · " + clockNow(c.tz) + "</div></div>" +
             '<button class="mv" data-mv="-1"' + (i === 0 ? " disabled" : "") + '>▲</button><button class="mv" data-mv="1"' + (i === list.length - 1 ? " disabled" : "") + '>▼</button>' +
             '<button class="x" title="Remove">×</button></div>';
    }).join("");
  }
  $("#wc-list").addEventListener("click", function (e) {
    var row = e.target.closest(".media-row"); if (!row) return;
    var i = +row.getAttribute("data-i"), list = (get("worldClocks") || []).slice();
    if (e.target.classList.contains("x")) list.splice(i, 1);
    else if (e.target.hasAttribute("data-mv")) {
      var j = i + +e.target.getAttribute("data-mv"); if (j < 0 || j >= list.length) return;
      var t = list[i]; list[i] = list[j]; list[j] = t;
    } else return;
    save("worldClocks", list); renderClocks();
  });
  var wcQ = $("#wc-q"), wcRes = $("#wc-results"), wcTimer, wcFound = [];
  wcQ.addEventListener("input", function () {
    clearTimeout(wcTimer);
    var term = wcQ.value.trim();
    if (term.length < 2) { wcRes.classList.remove("open"); return; }
    wcTimer = setTimeout(function () {
      fetch("https://geocoding-api.open-meteo.com/v1/search?count=6&language=en&format=json&name=" + encodeURIComponent(term))
        .then(function (r) { return r.json(); })
        .then(function (j) {
          wcFound = (j.results || []).filter(function (r) { return r.timezone; });
          wcRes.innerHTML = wcFound.length ? wcFound.map(function (r, i) {
            return '<div data-i="' + i + '">' + esc(r.name) + "<small>" + esc([r.admin1, r.country].filter(Boolean).join(", ")) + " · " + clockNow(r.timezone) + "</small></div>";
          }).join("") : '<div style="opacity:.6">No matches</div>';
          wcRes.classList.add("open");
        }).catch(function () { wcRes.innerHTML = '<div style="opacity:.6">Search unavailable</div>'; wcRes.classList.add("open"); });
    }, 300);
  });
  wcRes.addEventListener("click", function (e) {
    var d = e.target.closest("[data-i]"); if (!d) return;
    var r = wcFound[+d.getAttribute("data-i")], list = (get("worldClocks") || []).slice();
    if (list.length >= 5) { toast("Up to 5 cities fit on the tablet — remove one first"); return; }
    list.push({ name: r.name, tz: r.timezone });
    save("worldClocks", list, true); renderClocks();
    wcRes.classList.remove("open"); wcQ.value = "";
    toast("Added " + r.name);
  });
  document.addEventListener("click", function (e) { if (!e.target.closest("#worldclock .search")) wcRes.classList.remove("open"); });

  // ---------- YouTube ----------
  function renderChannels() {
    var list = get("youtube.channels") || [], box = $("#yt-channels");
    $("#yt-count").textContent = list.length ? "Channels (" + list.length + ")" : "Channels";
    if (!list.length) { box.innerHTML = '<div class="row"><div class="lbl" style="color:var(--text-2)">No channels yet — add one above or import your subscriptions.</div></div>'; return; }
    box.innerHTML = '<div class="yt-list">' + list.map(function (c, i) {
      return '<div class="row media-row" data-i="' + i + '"><div class="lbl"><b>' + esc(c.title || c.id) + '</b><div class="url">' + esc(c.id) +
             '</div></div><button class="x" title="Remove">×</button></div>';
    }).join("") + "</div>" +
    (list.length > 1 ? '<div class="row" style="justify-content:flex-end"><button class="btn danger" id="yt-clear">Remove All</button></div>' : "");
  }
  $("#yt-channels").addEventListener("click", function (e) {
    if (e.target.id === "yt-clear") {
      if (confirm("Remove all " + (get("youtube.channels") || []).length + " channels?")) { save("youtube.channels", []); renderChannels(); }
      return;
    }
    var row = e.target.closest(".media-row"); if (!row || !e.target.classList.contains("x")) return;
    var list = (get("youtube.channels") || []).slice(); list.splice(+row.getAttribute("data-i"), 1);
    save("youtube.channels", list); renderChannels();
  });
  function addChannels(items) {
    var list = (get("youtube.channels") || []).slice(), have = {}, added = 0;
    list.forEach(function (c) { have[c.id] = true; });
    items.forEach(function (c) {
      if (c.id && !have[c.id]) { var e = { id: c.id, title: c.title || c.id }; if (c.handle) e.handle = c.handle; list.push(e); have[c.id] = true; added++; }
    });
    list.sort(function (a, b) { return (a.title || "").localeCompare(b.title || ""); });
    save("youtube.channels", list, true); renderChannels();
    return added;
  }
  $("#yt-add-btn").addEventListener("click", function () {
    var q = $("#yt-add").value.trim(); if (!q) return;
    var btn = $("#yt-add-btn"); btn.disabled = true; btn.textContent = "Finding…";
    fetch("/api/youtube/resolve?q=" + encodeURIComponent(q)).then(function (r) { return r.json(); }).then(function (c) {
      if (c.error) { toast(c.error); return; }
      if (addChannels([c])) { toast("Added " + c.title); $("#yt-add").value = ""; } else toast(c.title + " is already in the list");
    }).catch(function () { toast("Couldn’t reach Matchbox Dashboard"); })
      .then(function () { btn.disabled = false; btn.textContent = "Add Channel"; });
  });
  $("#yt-add").addEventListener("keydown", function (e) { if (e.key === "Enter") $("#yt-add-btn").click(); });

  // ---- Paste from youtube.com/feed/channels ----
  // The copied page lists each channel as "Name / @handle•1.2M subscribers / description…". Only take an @ that starts
  // a word, so email addresses inside channel descriptions ("hello@example.com") are ignored.
  function handlesIn(text) {
    var out = [], seen = {}, ids = [], m;
    var re = /(^|[\s•·|,(])@([A-Za-z0-9._-]{3,30})/g;
    while ((m = re.exec(text))) {
      var h = m[2].replace(/[.\-_]+$/, "");
      if (h.length >= 3 && !seen[h.toLowerCase()]) { seen[h.toLowerCase()] = 1; out.push("@" + h); }
    }
    var idRe = /\b(UC[A-Za-z0-9_-]{22})\b/g;
    while ((m = idRe.exec(text))) if (!seen[m[1]]) { seen[m[1]] = 1; ids.push(m[1]); }
    return out.concat(ids);
  }
  var pasteBox = $("#yt-paste"), pasteBtn = $("#yt-paste-btn"), pasteInfo = $("#yt-paste-info");
  function updatePasteInfo() {
    var n = handlesIn(pasteBox.value).length;
    pasteInfo.textContent = pasteBox.value.trim() ? (n ? n + " channel" + (n === 1 ? "" : "s") + " found" : "No @handles found — did the copy include the channel list?") : "";
    pasteBtn.disabled = !n;
  }
  pasteBox.addEventListener("input", updatePasteInfo);
  pasteBtn.addEventListener("click", function () {
    var items = handlesIn(pasteBox.value);
    var have = {};
    (get("youtube.channels") || []).forEach(function (c) { if (c.handle) have[c.handle.toLowerCase()] = 1; have[c.id] = 1; });
    items = items.filter(function (h) { return !have[h.toLowerCase()] && !have[h]; });
    if (!items.length) { toast("All of those channels are already in the list"); return; }
    pasteBtn.disabled = true; pasteBox.disabled = true;
    var done = 0, found = [], failed = [], next = 0;
    function worker() {
      if (next >= items.length) return Promise.resolve();
      var q = items[next++];
      return fetch("/api/youtube/resolve?q=" + encodeURIComponent(q)).then(function (r) { return r.json(); })
        .then(function (c) { if (c.id) { c.handle = q.charAt(0) === "@" ? q : undefined; found.push(c); } else failed.push(q); })
        .catch(function () { failed.push(q); })
        .then(function () {
          done++;
          pasteInfo.textContent = "Looking up channels… " + done + " of " + items.length;
          // Save as we go so a long import isn't lost if the page is closed.
          if (found.length && done % 10 === 0) { addChannels(found.splice(0)); }
          return worker();
        });
    }
    Promise.all([worker(), worker(), worker(), worker()]).then(function () {
      var added = addChannels(found);
      pasteBox.disabled = false; pasteBox.value = "";
      pasteInfo.textContent = "Imported " + (done - failed.length) + " channel" + (done - failed.length === 1 ? "" : "s") +
        (failed.length ? " · couldn’t find " + failed.slice(0, 5).join(", ") + (failed.length > 5 ? " and " + (failed.length - 5) + " more" : "") : "");
      pasteBtn.disabled = true;
      toast("YouTube channels imported — uploads appear within a minute");
      fetch("/api/action", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "refresh" }) });
    });
  });

  // Google Takeout's subscriptions.csv: "Channel Id,Channel Url,Channel Title"
  function parseCSV(text) {
    var rows = [], row = [], f = "", q = false;
    for (var i = 0; i < text.length; i++) {
      var ch = text[i];
      if (q) { if (ch === '"') { if (text[i + 1] === '"') { f += '"'; i++; } else q = false; } else f += ch; }
      else if (ch === '"') q = true;
      else if (ch === ",") { row.push(f); f = ""; }
      else if (ch === "\n" || ch === "\r") { if (ch === "\r" && text[i + 1] === "\n") i++; row.push(f); rows.push(row); row = []; f = ""; }
      else f += ch;
    }
    if (f || row.length) { row.push(f); rows.push(row); }
    return rows.filter(function (r) { return r.some(function (x) { return x.trim(); }); });
  }
  $("#yt-import").addEventListener("change", function (e) {
    var file = e.target.files[0]; if (!file) return;
    var reader = new FileReader();
    reader.onload = function () {
      var rows = parseCSV(String(reader.result)), items = [];
      rows.forEach(function (r) {
        var id = (r.join(" ").match(/UC[A-Za-z0-9_-]{22}/) || [])[0];
        if (id) items.push({ id: id, title: (r[2] || "").trim() || id });
      });
      if (!items.length) { toast("No channels found in that file"); return; }
      var n = addChannels(items);
      toast("Imported " + n + " new channel" + (n === 1 ? "" : "s") + " (" + items.length + " in file)");
    };
    reader.readAsText(file);
    e.target.value = "";
  });

  // ---------- Anime (AniList search runs right here in the browser) ----------
  function anilist(query, vars) {
    return fetch("https://graphql.anilist.co", { method: "POST", headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ query: query, variables: vars }) }).then(function (r) { return r.json(); });
  }
  function anTitle(m) { return (m.title && (m.title.english || m.title.romaji)) || "Untitled"; }
  function renderShows() {
    var list = get("anime.shows") || [], box = $("#an-shows");
    if (!list.length) { box.innerHTML = '<div class="row"><div class="lbl" style="color:var(--text-2)">No shows yet — search above' + (get("anime.anilistUser") ? " (plus your AniList lists)" : "") + ".</div></div>"; return; }
    box.innerHTML = list.map(function (s, i) {
      return '<div class="row media-row" data-i="' + i + '">' + (s.cover ? '<img src="' + esc(s.cover) + '" alt="">' : "") +
             '<div class="lbl"><b>' + esc(s.title) + "</b>" + (s.crunchyroll ? '<div class="hint cr">Crunchyroll</div>' : "") + "</div>" +
             '<button class="x" title="Remove">×</button></div>';
    }).join("");
  }
  $("#an-shows").addEventListener("click", function (e) {
    var row = e.target.closest(".media-row"); if (!row || !e.target.classList.contains("x")) return;
    var list = (get("anime.shows") || []).slice(); list.splice(+row.getAttribute("data-i"), 1);
    save("anime.shows", list); renderShows();
  });
  var anQ = $("#an-q"), anRes = $("#an-results"), anTimer, anFound = [];
  anQ.addEventListener("input", function () {
    clearTimeout(anTimer);
    var term = anQ.value.trim();
    if (term.length < 2) { anRes.classList.remove("open"); return; }
    anTimer = setTimeout(function () {
      anilist("query ($s: String) { Page(perPage: 10) { media(search: $s, type: ANIME, sort: [POPULARITY_DESC]) { id status title { english romaji } " +
              "coverImage { medium } nextAiringEpisode { episode airingAt } externalLinks { site } seasonYear format } } }", { s: term })
        .then(function (j) {
          anFound = ((j.data && j.data.Page && j.data.Page.media) || []);
          anRes.innerHTML = anFound.length ? anFound.map(function (m, i) {
            var cr = (m.externalLinks || []).some(function (l) { return l.site === "Crunchyroll"; });
            var when = m.nextAiringEpisode ? "Ep " + m.nextAiringEpisode.episode + " on " + new Date(m.nextAiringEpisode.airingAt * 1000).toLocaleDateString([], { weekday: "short", month: "short", day: "numeric" })
                     : m.status === "FINISHED" ? "Finished airing" : m.status === "NOT_YET_RELEASED" ? "Not yet airing" : "";
            return '<div class="an-res" data-i="' + i + '"><img src="' + esc(m.coverImage && m.coverImage.medium) + '" alt=""><div>' + esc(anTitle(m)) +
                   "<small>" + [when, m.seasonYear, cr ? '<span class="cr">Crunchyroll</span>' : ""].filter(Boolean).join(" · ") + "</small></div></div>";
          }).join("") : '<div style="opacity:.6">No matches</div>';
          anRes.classList.add("open");
        }).catch(function () { anRes.innerHTML = '<div style="opacity:.6">AniList search unavailable</div>'; anRes.classList.add("open"); });
    }, 300);
  });
  anRes.addEventListener("click", function (e) {
    var d = e.target.closest("[data-i]"); if (!d) return;
    var m = anFound[+d.getAttribute("data-i")], list = (get("anime.shows") || []).slice();
    if (list.some(function (s) { return s.id === m.id; })) { toast(anTitle(m) + " is already followed"); return; }
    list.push({ id: m.id, title: anTitle(m), cover: m.coverImage && m.coverImage.medium,
                crunchyroll: (m.externalLinks || []).some(function (l) { return l.site === "Crunchyroll"; }) });
    save("anime.shows", list, true); renderShows();
    anRes.classList.remove("open"); anQ.value = "";
    toast("Following " + anTitle(m) + (m.status === "FINISHED" ? " — it has finished airing, so no countdown will show" : ""));
  });
  document.addEventListener("click", function (e) { if (!e.target.closest("#anime .search")) anRes.classList.remove("open"); });

  // ---------- Sports ----------
  function renderLeagues() {
    var on = get("sports.leagues") || [], box = $("#leagues");
    box.innerHTML = "";
    LEAGUES.forEach(function (l) {
      var lab = document.createElement("label");
      lab.className = on.indexOf(l[0]) >= 0 ? "on" : "";
      lab.innerHTML = '<input type="checkbox"' + (on.indexOf(l[0]) >= 0 ? " checked" : "") + ">" + l[1];
      lab.addEventListener("click", function (e) {
        e.preventDefault();
        var cur = (get("sports.leagues") || []).slice(), i = cur.indexOf(l[0]);
        if (i >= 0) cur.splice(i, 1); else cur.push(l[0]);
        save("sports.leagues", cur); renderLeagues();
      });
      box.appendChild(lab);
    });
  }
  $("#favorites").addEventListener("change", function (e) {
    var list = e.target.value.split(",").map(function (s) { return s.trim(); }).filter(Boolean);
    save("sports.favorites", list);
  });

  // ---------- Feeds ----------
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  function renderFeeds() {
    var feeds = cfg.feeds || [], box = $("#feeds");
    if (!feeds.length) { box.innerHTML = '<div class="row"><div class="lbl" style="color:var(--text-2)">No feeds yet — add one below.</div></div>'; return; }
    box.innerHTML = feeds.map(function (f, i) {
      return '<div class="row feed" data-i="' + i + '"><div class="lbl"><b>' + esc(f.name || "Untitled") + '</b><div class="url">' + esc(f.url) + "</div></div>" +
        '<button class="mv" data-mv="-1" title="Move up"' + (i === 0 ? " disabled" : "") + ">▲</button>" +
        '<button class="mv" data-mv="1" title="Move down"' + (i === feeds.length - 1 ? " disabled" : "") + ">▼</button>" +
        '<label class="switch"><input type="checkbox"' + (f.enabled !== false ? " checked" : "") + "><i></i></label>" +
        '<button class="x" title="Remove">×</button></div>';
    }).join("");
  }
  $("#feeds").addEventListener("click", function (e) {
    var row = e.target.closest(".feed"); if (!row) return;
    var i = +row.getAttribute("data-i"), feeds = (cfg.feeds || []).slice();
    if (e.target.classList.contains("x")) { feeds.splice(i, 1); }
    else if (e.target.hasAttribute("data-mv")) {
      var j = i + +e.target.getAttribute("data-mv"); if (j < 0 || j >= feeds.length) return;
      var t = feeds[i]; feeds[i] = feeds[j]; feeds[j] = t;
    } else return;
    save("feeds", feeds); renderFeeds();
  });
  $("#feeds").addEventListener("change", function (e) {
    var row = e.target.closest(".feed"); if (!row) return;
    var feeds = (cfg.feeds || []).map(function (f) { return Object.assign({}, f); });
    feeds[+row.getAttribute("data-i")].enabled = e.target.checked;
    save("feeds", feeds);
  });
  $("#feed-add").addEventListener("click", function () {
    var url = $("#feed-url").value.trim(), name = $("#feed-name").value.trim();
    if (!/^https?:\/\//i.test(url)) { toast("Enter a feed URL starting with http:// or https://"); return; }
    var feeds = (cfg.feeds || []).slice();
    feeds.push({ name: name, url: url, enabled: true });
    save("feeds", feeds, true); renderFeeds();
    $("#feed-url").value = ""; $("#feed-name").value = "";
    toast("Feed added — headlines appear in a few seconds");
  });

  // ---------- Location search (Open-Meteo geocoding) ----------
  var q = $("#loc-q"), results = $("#loc-results"), searchTimer, found = [];
  q.addEventListener("input", function () {
    clearTimeout(searchTimer);
    var term = q.value.trim();
    if (term.length < 2) { results.classList.remove("open"); return; }
    searchTimer = setTimeout(function () {
      fetch("https://geocoding-api.open-meteo.com/v1/search?count=6&language=en&format=json&name=" + encodeURIComponent(term))
        .then(function (r) { return r.json(); })
        .then(function (j) {
          found = j.results || [];
          results.innerHTML = found.length ? found.map(function (r, i) {
            return '<div data-i="' + i + '">' + esc(r.name) + "<small>" + esc([r.admin1, r.country].filter(Boolean).join(", ")) + "</small></div>";
          }).join("") : '<div style="opacity:.6">No matches</div>';
          results.classList.add("open");
        }).catch(function () { results.innerHTML = '<div style="opacity:.6">Search unavailable</div>'; results.classList.add("open"); });
    }, 300);
  });
  results.addEventListener("click", function (e) {
    var d = e.target.closest("[data-i]"); if (!d) return;
    var r = found[+d.getAttribute("data-i")];
    var loc = { name: r.name, full: [r.name, r.admin1, r.country].filter(Boolean).join(", "), lat: r.latitude, lon: r.longitude };
    save("location", loc, true);
    results.classList.remove("open"); q.value = "";
    $("#loc-current").textContent = locLabel();
    toast("Weather location set to " + r.name);
  });
  document.addEventListener("click", function (e) { if (!e.target.closest(".search")) results.classList.remove("open"); });

  // ---------- Actions ----------
  $$("[data-action]").forEach(function (b) {
    b.addEventListener("click", function () {
      var a = b.getAttribute("data-action");
      fetch("/api/action", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: a }) })
        .then(function (r) { return r.json(); })
        .then(function () {
          toast({ install: "Installing on tablet…", launch: "Relaunching tablet display", reload: "Reloading display",
                  speedtest: "Speed test started (about 20 seconds)", refresh: "Refreshing feeds",
                  wallpaper: "Resampling your wallpaper" }[a] || "Done");
          if (a === "wallpaper") wpKey = null;
          if (a === "reload") setTimeout(function () { $("#preview").src = $("#preview").src; }, 300);
        });
    });
  });
  $("#reset").addEventListener("click", function () {
    if (!confirm("Reset all Matchbox Dashboard settings to their defaults?")) return;
    fetch("/api/config/reset", { method: "POST" }).then(function () { location.reload(); });
  });

  // ---------- Preview ----------
  var preview = $("#preview");
  function fitPreview() {
    var bez = $(".bezel"), w = bez.clientWidth * (1 - 0.044);
    preview.style.transform = "scale(" + (w / 1024) + ")";
  }
  window.addEventListener("resize", fitPreview);
  var previewTheme = "";
  function setPreviewTheme(v) {
    previewTheme = v;
    $$("#preview-theme button").forEach(function (x) { x.classList.toggle("on", x.getAttribute("data-v") === v); });
    preview.src = "/display/" + (v ? "?theme=" + v : "");
  }
  $("#preview-theme").addEventListener("click", function (e) {
    var b = e.target.closest("button"); if (!b) return;
    setPreviewTheme(b.getAttribute("data-v"));
  });
  $("#btn-next").addEventListener("click", function () {
    try { preview.contentWindow.plinth.next(); } catch (e) {}
  });

  // ---------- Status polling ----------
  function bitsStr(b) {
    if (!(b > 0)) return "0 Kb/s";
    if (b < 1e6) return (b / 1e3).toFixed(0) + " Kb/s";
    if (b < 1e9) return (b / 1e6).toFixed(b < 1e7 ? 1 : 0) + " Mb/s";
    return (b / 1e9).toFixed(2) + " Gb/s";
  }
  function ago(ms) {
    var s = (Date.now() - ms) / 1000;
    if (s < 90) return "just now"; if (s < 3600) return Math.round(s / 60) + " min ago";
    return Math.round(s / 3600) + " hr ago";
  }
  function friendly(m) { return m === "KFQUWI" ? "Fire 7 (12th gen)" : (m || "Tablet").replace(/_/g, " "); }

  function pollStatus() {
    Promise.all([fetch("/api/status").then(function (r) { return r.json(); }), fetch("/api/metrics").then(function (r) { return r.json(); })])
      .then(function (res) {
        var s = res[0], m = res[1];
        var devs = (s.adb && s.adb.devices) || [], ready = devs.filter(function (d) { return d.state === "device"; });
        var others = ready.filter(function (d) { return !d.eligible; });
        ready = ready.filter(function (d) { return d.eligible; });
        var usb = $("#usb-status"), hint = $("#usb-hint");
        if (!others.length || ready.length) hint.removeAttribute("data-k");
        if (!s.adb || !s.adb.adbPath) {
          usb.innerHTML = '<span class="dot warn"></span>adb not installed';
          hint.innerHTML = "Install with <code>brew install android-platform-tools</code> for USB mode";
        } else if (ready.length) {
          var d = ready[0];
          usb.innerHTML = '<span class="dot ' + (d.reversed ? "ok" : "warn") + '"></span>' + friendly(d.model) + " via USB";
          var seen = s.adb.tabletSeenAgo;
          hint.textContent = d.appInstalled === false ? "Matchbox Dashboard isn’t installed on this tablet yet — click Install App on Tablet"
                          : seen != null && seen < 10 ? "Display is live · port " + s.port + " forwarded over the cable"
                          : seen != null ? "Display last updated " + Math.round(seen) + " s ago" + (d.message ? " · " + d.message : "")
                          : d.reversed ? "Port " + s.port + " is forwarded over the cable" : (d.message || "Setting up port forwarding…");
        } else if (devs.some(function (d) { return d.state === "unauthorized"; })) {
          usb.innerHTML = '<span class="dot warn"></span>Waiting for permission';
          hint.textContent = "Tap “Allow” on the tablet’s USB debugging prompt";
        } else if (others.length) {
          // Android devices other than Fire tablets wait to be picked, so phones and TV boxes are left alone.
          usb.innerHTML = '<span class="dot warn"></span>' + esc(friendly(others[0].model)) + " found";
          var key = others.map(function (d) { return d.serial; }).join(",");
          if (hint.getAttribute("data-k") !== key) {
            hint.setAttribute("data-k", key);
            hint.innerHTML = "Not set up yet. Choose the tablet to show the display on: " + others.map(function (d) {
              return '<button class="btn small use-dev" data-serial="' + esc(d.serial) + '">Use ' + esc(friendly(d.model)) + "</button>";
            }).join(" ");
          }
        } else {
          usb.innerHTML = '<span class="dot"></span>No tablet on USB';
          hint.textContent = "Connect your Android tablet with a USB cable (USB debugging on)";
        }
        $("#mode-status").textContent = (s.theme === "night" ? "Night" : "Day") + " · Mac is in " + (s.macDark ? "Dark" : "Light") + " mode";
        var ips = (s.addresses || []).map(function (a) { return "http://" + a.ip + ":" + s.port; });
        $("#wifi-url").textContent = s.localOnly ? "Disabled (USB only)" : (ips[0] || "No network");
        $("#adb-found").textContent = s.adb && s.adb.adbPath ? "Using " + s.adb.adbPath : "Not found";
        $("#config-path").textContent = "Settings file: " + s.configPath + "  ·  Matchbox Dashboard " + s.version;
        $("#apk-link").style.display = s.apkBundled ? "" : "none";
        $$("[data-action=install]").forEach(function (b) { b.disabled = !s.apkBundled || !ready.length; });
        var msg = $("#action-msg");
        if (s.lastAction) { msg.hidden = false; msg.textContent = s.lastAction; } else msg.hidden = true;
        ["weather", "sports", "news", "youtube", "anime", "bluesky", "steam", "steamActivity", "fx", "kanji", "radar", "slickdeals"].forEach(function (k) {
          var el = $('[data-err="' + k + '"]'), e = s.feedErrors && s.feedErrors[k];
          el.hidden = !e; el.textContent = e ? "⚠︎ " + e : "";
        });

        var net = (m.m && m.m.net) || {};
        $("#net-live").textContent = "↓ " + bitsStr(net.rxBps) + "   ↑ " + bitsStr(net.txBps) + "  ·  " + (net.ifaceName || "");
        var st = net.speedTest || {};
        $("#st-result").textContent = net.speedTestRunning ? "Running…" : st.down ? "↓ " + bitsStr(st.down) + "   ↑ " + bitsStr(st.up) : (st.error ? "Failed" : "Not run yet");
        $("#st-when").textContent = st.at ? ago(st.at) + (st.rpm ? " · responsiveness " + Math.round(st.rpm) + " RPM" : "") : "";
        $("#brand-sub").textContent = m.host || "Info display manager";
        if (m.day) renderWallpaper(m.day.wallpaper);
      })
      .catch(function () { $("#usb-status").textContent = "Matchbox Dashboard isn’t responding"; })
      .then(function () { setTimeout(pollStatus, 2000); });
  }

  $("#usb-hint").addEventListener("click", function (e) {
    var b = e.target.closest(".use-dev"); if (!b) return;
    var list = (get("adb.allowed") || []).slice(), serial = b.getAttribute("data-serial");
    if (list.indexOf(serial) < 0) list.push(serial);
    save("adb.allowed", list, true);
    b.disabled = true; b.textContent = "Setting up…";
    toast("The display will use this device. Click Install App on Tablet if it isn’t installed yet.");
  });

  // ---------- Sidebar highlight ----------
  var content = $(".content");
  content.addEventListener("scroll", function () {
    var top = content.scrollTop + 60, cur = "tablet";
    $$(".content section").forEach(function (s) { if (s.offsetTop <= top) cur = s.id; });
    $$("nav a").forEach(function (a) { a.classList.toggle("on", a.getAttribute("href") === "#" + cur); });
  });

  // ---------- Boot ----------
  fetch("/api/config").then(function (r) { return r.json(); }).then(function (c) { cfg = c; bindAll(); });
  fitPreview();
  setTimeout(fitPreview, 300);
  pollStatus();
})();
