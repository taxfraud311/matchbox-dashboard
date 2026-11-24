/* Day-theme palette: turns the Mac's wallpaper colors (or a chosen color) into a bright,
   matching backdrop. Shared by the tablet display and the manager. */
(function (global) {
  "use strict";

  function hexToRgb(hex) {
    var h = String(hex || "").replace("#", "");
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    var n = parseInt(h, 16);
    if (isNaN(n)) return null;
    return [n >> 16 & 255, n >> 8 & 255, n & 255];
  }
  function rgbToHsl(c) {
    var r = c[0] / 255, g = c[1] / 255, b = c[2] / 255, mx = Math.max(r, g, b), mn = Math.min(r, g, b);
    var h = 0, s = 0, l = (mx + mn) / 2, d = mx - mn;
    if (d) {
      s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
      h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
      h *= 60;
    }
    return [h, s, l];
  }
  function hslToRgb(h, s, l) {
    h = ((h % 360) + 360) % 360 / 360;
    var q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
    function f(t) { t = (t + 1) % 1; return t < 1 / 6 ? p + (q - p) * 6 * t : t < 0.5 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p; }
    return [Math.round(f(h + 1 / 3) * 255), Math.round(f(h) * 255), Math.round(f(h - 1 / 3) * 255)];
  }
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }
  function css(rgb, a) { return a == null ? "rgb(" + rgb.join(",") + ")" : "rgba(" + rgb.join(",") + "," + a + ")"; }

  // Keep the hue; force a bright pastel lightness. Near-greys stay gentle instead of inventing color.
  function tone(hsl, l, satBoost) {
    var s = hsl[1] < 0.1 ? hsl[1] * 2.5 + 0.06 : clamp(hsl[1] * (satBoost || 1.1), 0.32, 0.72);
    return hslToRgb(hsl[0], s, l);
  }

  /**
   * day = { mode: "wallpaper" | "custom" | "golden", custom: "#rrggbb", wallpaper: { colors: {tl,tr,bl,br,c,all} } }
   * Returns a map of CSS custom properties, or null for the built-in Golden Gate palette.
   */
  function build(day) {
    if (!day || day.mode === "golden") return null;
    var src;
    if (day.mode === "custom") {
      var base = rgbToHsl(hexToRgb(day.custom) || [58, 130, 247]);
      var hs = clamp(base[1], 0.35, 0.8);
      src = {
        tl: [base[0] - 24, hs, 0.5], tr: [base[0] + 18, hs, 0.5], bl: [base[0] - 8, hs, 0.5],
        br: [base[0] + 38, hs * 0.85, 0.5], c: [base[0], hs, 0.5], all: [base[0], hs, 0.5],
      };
    } else {
      var w = (day.wallpaper && day.wallpaper.colors) || null;
      if (!w || !w.c) return null;
      src = {};
      ["tl", "tr", "bl", "br", "c", "all"].forEach(function (k) { src[k] = rgbToHsl(hexToRgb(w[k] || w.c)); });
    }
    var shadowHsl = src.all;
    var shadow = hslToRgb(shadowHsl[0], clamp(shadowHsl[1], 0.25, 0.55), 0.24);
    return {
      "--w-bg": css(tone(src.c, 0.82)),
      "--w-tl": css(tone(src.tl, 0.84)),
      "--w-tr": css(tone(src.tr, 0.77)),
      "--w-br": css(tone(src.br, 0.76)),
      "--w-bl": css(tone(src.bl, 0.80)),
      "--w-base-1": css(tone(src.tl, 0.82)),
      "--w-base-2": css(tone(src.c, 0.76)),
      "--w-base-3": css(tone(src.br, 0.80)),
      "--w-blob-1": css(tone(src.bl, 0.60, 1.3), 0.5),
      "--w-blob-2": css(tone(src.tr, 0.72, 1.3), 0.6),
      "--w-blob-3": css(tone(src.br, 0.64, 1.3), 0.5),
      "--w-shadow": shadow.join(","),
    };
  }

  var VARS = ["--w-bg", "--w-tl", "--w-tr", "--w-br", "--w-bl", "--w-base-1", "--w-base-2", "--w-base-3",
              "--w-blob-1", "--w-blob-2", "--w-blob-3", "--w-shadow"];

  function apply(day, el) {
    el = el || document.documentElement;
    var vars = build(day);
    VARS.forEach(function (k) {
      if (vars && vars[k]) el.style.setProperty(k, vars[k]); else el.style.removeProperty(k);
    });
    return vars;
  }

  global.PlinthPalette = { build: build, apply: apply };
})(window);
