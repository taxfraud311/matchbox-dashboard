package com.plinth.display;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Fullscreen kiosk that shows the Matchbox Dashboard display served by the Mac.
 *
 * Connection order:
 *   1. http://127.0.0.1:8787  — USB, via `adb reverse` set up automatically by the Mac app
 *   2. a saved Wi-Fi address  — entered by long-pressing the top-left corner
 *   3. a Mac found on Wi-Fi via Bonjour (_plinth._tcp)
 */
public class MainActivity extends Activity {
    static final String USB_BASE = "http://127.0.0.1:8787";
    static final String SERVICE_TYPE = "_plinth._tcp.";

    private final Handler ui = new Handler(Looper.getMainLooper());
    private final ExecutorService io = Executors.newSingleThreadExecutor();

    private FrameLayout root;
    private WebView web;
    private LinearLayout waiting;
    private TextView waitingDetail;

    private SharedPreferences prefs;
    private String currentBase = null;      // Mac the dashboard page was loaded from
    private boolean offlineCopy = false;    // page shown from the WebView cache because no Mac answered
    private boolean loadFailed = false;
    private int emptyProbes = 0;
    private String discoveredBase = null;
    private int watchdogFailures = 0;
    private volatile long lastHeartbeat = 0;   // set by the page after every successful data poll
    private boolean probing = false;

    private NsdManager nsd;
    private NsdManager.DiscoveryListener discovery;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        prefs = getSharedPreferences("plinth", MODE_PRIVATE);

        Window w = getWindow();
        w.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                | WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON);
        if (Build.VERSION.SDK_INT >= 28) {
            w.getAttributes().layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        }
        w.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.BLACK));

        root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        root.setKeepScreenOn(true);   // belt and braces alongside FLAG_KEEP_SCREEN_ON

        web = new WebView(this);
        web.setBackgroundColor(Color.BLACK);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setTextZoom(100);                    // ignore system font scaling; the layout is pixel-designed
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);   // the Mac marks pages no-cache but lets the large SF font files cache
        s.setUseWideViewPort(true);
        s.setLoadWithOverviewMode(true);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        web.setVerticalScrollBarEnabled(false);
        web.setHorizontalScrollBarEnabled(false);
        web.setOverScrollMode(View.OVER_SCROLL_NEVER);
        web.setLayerType(View.LAYER_TYPE_HARDWARE, null);
        WebView.setWebContentsDebuggingEnabled(true);
        web.addJavascriptInterface(new Host(), "PlinthHost");
        web.setWebViewClient(new Client());
        web.setVisibility(View.INVISIBLE);
        root.addView(web, new FrameLayout.LayoutParams(-1, -1));

        root.addView(buildWaitingView(), new FrameLayout.LayoutParams(-1, -1));

        // Connection settings: long-press the waiting screen, or long-press the dashboard's top-left corner (handled in the page).
        waiting.setOnLongClickListener(v -> { showSettings(); return true; });

        setContentView(root);
        nsd = (NsdManager) getSystemService(Context.NSD_SERVICE);
        startDiscovery();
        probeAndLoad();
    }

    private View buildWaitingView() {
        waiting = new LinearLayout(this);
        waiting.setOrientation(LinearLayout.VERTICAL);
        waiting.setGravity(Gravity.CENTER);
        waiting.setBackgroundColor(Color.BLACK);

        TextView title = new TextView(this);
        title.setText("Matchbox Dashboard");
        title.setTextColor(Color.WHITE);
        title.setTextSize(44);
        title.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        title.setGravity(Gravity.CENTER);

        TextView sub = new TextView(this);
        sub.setText("Waiting for your Mac…");
        sub.setTextColor(0xDDFFFFFF);
        sub.setTextSize(24);
        sub.setGravity(Gravity.CENTER);
        sub.setPadding(0, 12, 0, 24);

        waitingDetail = new TextView(this);
        waitingDetail.setTextColor(0x99FFFFFF);
        waitingDetail.setTextSize(17);
        waitingDetail.setGravity(Gravity.CENTER);
        waitingDetail.setLineSpacing(0, 1.25f);
        waitingDetail.setText("Make sure Matchbox Dashboard is running on the Mac and the USB cable is connected.\n"
                + "Using Wi-Fi instead? Long-press anywhere here to enter the Mac’s address.");

        waiting.addView(title);
        waiting.addView(sub);
        waiting.addView(waitingDetail);
        return waiting;
    }

    // ---------- Connection management ----------

    private List<String> candidates() {
        List<String> c = new ArrayList<>();
        c.add(USB_BASE);
        String saved = prefs.getString("base", null);
        if (saved != null && !saved.isEmpty() && !c.contains(saved)) c.add(saved);
        if (discoveredBase != null && !c.contains(discoveredBase)) c.add(discoveredBase);
        return c;
    }

    private static boolean reachable(String base) {
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) new URL(base + "/api/metrics").openConnection();
            conn.setConnectTimeout(1500);
            conn.setReadTimeout(2500);
            conn.setUseCaches(false);
            return conn.getResponseCode() == 200;
        } catch (Exception e) {
            return false;
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    private void load(String base, boolean fromCache) {
        currentBase = base;
        offlineCopy = fromCache;
        loadFailed = false;
        lastHeartbeat = android.os.SystemClock.elapsedRealtime();
        web.getSettings().setCacheMode(fromCache ? WebSettings.LOAD_CACHE_ONLY : WebSettings.LOAD_DEFAULT);
        web.stopLoading();
        web.loadUrl(base + "/display/");
    }

    /**
     * Find the first Mac address that answers and show the dashboard from it.
     * Once the dashboard is on screen it stays there while the Mac sleeps or is logged out — the page
     * switches to its full-screen standby layout and keeps going from its own cache.
     */
    private void probeAndLoad() {
        if (probing) return;
        probing = true;
        ui.removeCallbacks(retryProbe);
        final List<String> list = candidates();
        io.execute(() -> {
            String found = null;
            for (String b : list) { if (reachable(b)) { found = b; break; } }
            final String base = found;
            ui.post(() -> {
                probing = false;
                if (base == null) {
                    emptyProbes++;
                    String last = prefs.getString("lastBase", null);
                    if (currentBase == null && last != null && emptyProbes >= 2) {
                        load(last, true);              // cold start while the Mac is away: use the cached dashboard
                    } else if (currentBase == null) {
                        showWaiting(true);
                    }
                    ui.postDelayed(retryProbe, 3000);
                    return;
                }
                emptyProbes = 0;
                if (currentBase == null || offlineCopy || !base.equals(currentBase)) load(base, false);
                watchdogFailures = 0;
                scheduleWatchdog();
            });
        });
    }
    private final Runnable retryProbe = this::probeAndLoad;

    /** Every 5 s make sure the current Mac still answers; fall back to other routes (USB ⇄ Wi-Fi) if not. */
    private void scheduleWatchdog() {
        ui.removeCallbacks(watchdog);
        ui.postDelayed(watchdog, 5000);
    }

    private final Runnable watchdog = new Runnable() {
        @Override public void run() {
            final String base = currentBase;
            if (base == null || offlineCopy) { probeAndLoad(); return; }
            io.execute(() -> {
                boolean ok = reachable(base);
                boolean usbBack = !USB_BASE.equals(base) && reachable(USB_BASE);   // prefer the cable when it returns
                ui.post(() -> {
                    if (usbBack) { load(USB_BASE, false); scheduleWatchdog(); return; }
                    if (ok) {
                        watchdogFailures = 0;
                        // Mac answers but the page has stopped polling (stuck reload, dead JS): reload it.
                        if (android.os.SystemClock.elapsedRealtime() - lastHeartbeat > 30000) load(base, false);
                        scheduleWatchdog();
                        return;
                    }
                    // Mac gone (asleep, logged out, unplugged): leave the page up — it shows standby —
                    // and look for another route every few seconds.
                    if (++watchdogFailures >= 3) probeAndLoad();
                    else scheduleWatchdog();
                });
            });
        }
    };

    private void showWaiting(boolean show) {
        waiting.setVisibility(show ? View.VISIBLE : View.GONE);
        web.setVisibility(show ? View.INVISIBLE : View.VISIBLE);
    }

    private class Client extends WebViewClient {
        @Override public void onPageFinished(WebView view, String url) {
            if (loadFailed || currentBase == null || !url.startsWith(currentBase)) return;
            showWaiting(false);
            if (!offlineCopy) prefs.edit().putString("lastBase", currentBase).apply();
        }

        @Override public void onReceivedError(WebView view, WebResourceRequest req, WebResourceError err) {
            if (req.isForMainFrame()) {
                loadFailed = true;
                boolean wasOffline = offlineCopy;
                currentBase = null; offlineCopy = false;
                showWaiting(true);
                if (wasOffline) emptyProbes = -1000;   // no cached copy available — don't keep trying the cache
                ui.removeCallbacks(retryProbe);
                ui.postDelayed(retryProbe, 2000);
            }
        }

        @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
            // Kiosk: reloads and other pages on the Mac are fine; never navigate anywhere else.
            String u = req.getUrl().toString();
            return currentBase == null || !u.startsWith(currentBase);
        }

        @Override public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
            // Renderer crashed or was killed for memory — rebuild the activity cleanly.
            recreate();
            return true;
        }
    }

    // ---------- Bonjour discovery for Wi-Fi mode ----------

    private void startDiscovery() {
        if (nsd == null) return;
        discovery = new NsdManager.DiscoveryListener() {
            @Override public void onDiscoveryStarted(String t) {}
            @Override public void onDiscoveryStopped(String t) {}
            @Override public void onStartDiscoveryFailed(String t, int e) {}
            @Override public void onStopDiscoveryFailed(String t, int e) {}
            @Override public void onServiceLost(NsdServiceInfo info) {}
            @Override public void onServiceFound(NsdServiceInfo info) {
                try {
                    nsd.resolveService(info, new NsdManager.ResolveListener() {
                        @Override public void onResolveFailed(NsdServiceInfo i, int e) {}
                        @Override public void onServiceResolved(NsdServiceInfo i) {
                            InetAddress h = i.getHost();
                            if (h == null) return;
                            String addr = h.getHostAddress();
                            if (addr == null || addr.contains(":")) return;   // keep it simple: IPv4 only
                            discoveredBase = "http://" + addr + ":" + i.getPort();
                        }
                    });
                } catch (Exception ignored) {}
            }
        };
        try { nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discovery); } catch (Exception ignored) {}
    }

    // ---------- Settings (long-press top-left) ----------

    private void showSettings() {
        final EditText input = new EditText(this);
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        input.setHint("http://192.168.1.20:8787");
        String saved = prefs.getString("base", "");
        input.setText(saved);
        input.setSingleLine(true);
        int pad = (int) (20 * getResources().getDisplayMetrics().density);
        FrameLayout box = new FrameLayout(this);
        box.setPadding(pad, pad / 2, pad, 0);
        box.addView(input);

        String status = "Connected to: " + (currentBase == null ? "nothing yet" : currentBase)
                + (discoveredBase != null ? "\nFound on Wi-Fi: " + discoveredBase : "");

        new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("Matchbox Dashboard connection")
                .setMessage(status + "\n\nUSB is always tried first. Enter the Mac’s Wi-Fi address (shown in the Matchbox Dashboard manager) to use Wi-Fi when no cable is connected.")
                .setView(box)
                .setPositiveButton("Save", (d, wh) -> {
                    String v = input.getText().toString().trim();
                    if (!v.isEmpty() && !v.startsWith("http")) v = "http://" + v;
                    if (v.endsWith("/")) v = v.substring(0, v.length() - 1);
                    if (v.endsWith("/display")) v = v.substring(0, v.length() - 8);
                    if (!v.isEmpty() && !v.matches("^https?://[^/]+:\\d+$") && v.matches("^https?://[^/:]+$")) v = v + ":8787";
                    prefs.edit().putString("base", v).apply();
                    currentBase = null;
                    probeAndLoad();
                })
                .setNeutralButton("Reload", (d, wh) -> { currentBase = null; probeAndLoad(); })
                .setNegativeButton("Cancel", null)
                .show();
    }

    // ---------- Bridge for the web page ----------

    private class Host {
        /** 0.0–1.0 sets the screen brightness while the display is in front; negative = use the system setting. */
        @JavascriptInterface
        public void setBrightness(final float v) {
            ui.post(() -> {
                WindowManager.LayoutParams lp = getWindow().getAttributes();
                lp.screenBrightness = v < 0 ? WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE : Math.max(0.01f, Math.min(1f, v));
                getWindow().setAttributes(lp);
            });
        }

        @JavascriptInterface
        public void heartbeat() { lastHeartbeat = android.os.SystemClock.elapsedRealtime(); }

        @JavascriptInterface
        public void showSettings() { ui.post(MainActivity.this::showSettings); }

        /** True when the page came from the WebView cache because the Mac wasn't reachable at start-up. */
        @JavascriptInterface
        public boolean isOfflineCopy() { return offlineCopy; }

        /** Hard reload from native code — works even if a page-initiated reload stalls. */
        @JavascriptInterface
        public void reload() {
            ui.post(() -> {
                if (currentBase == null || offlineCopy) { probeAndLoad(); return; }
                load(currentBase, false);
            });
        }

        @JavascriptInterface
        public String version() { return "1.3"; }
    }

    // ---------- Fullscreen / lifecycle ----------

    private void goImmersive() {
        if (Build.VERSION.SDK_INT >= 30) {
            getWindow().setDecorFitsSystemWindows(false);
            WindowInsetsController c = getWindow().getInsetsController();
            if (c != null) {
                c.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
                c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            getWindow().getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN);
        }
    }

    @Override public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) goImmersive();
    }

    @Override protected void onResume() {
        super.onResume();
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        goImmersive();
        web.onResume();
        if (currentBase == null) probeAndLoad(); else scheduleWatchdog();
    }

    @Override protected void onPause() {
        web.onPause();
        ui.removeCallbacks(watchdog);
        super.onPause();
    }

    @Override protected void onDestroy() {
        ui.removeCallbacksAndMessages(null);
        try { if (nsd != null && discovery != null) nsd.stopServiceDiscovery(discovery); } catch (Exception ignored) {}
        io.shutdownNow();
        web.destroy();
        super.onDestroy();
    }

    @SuppressWarnings("deprecation")
    @Override public void onBackPressed() {
        // Kiosk: Back does nothing. Use Home to leave.
    }
}
