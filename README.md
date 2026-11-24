<p align="center"><img src="web/manager/icon.png" width="128" alt="Matchbox Dashboard icon"></p>

# Matchbox Dashboard

Turns a 12th‑gen Amazon Fire 7 into a live info screen that sits under your Mac mini. A small menu bar app on the Mac does all the work; the tablet just shows the page.

- **Left side:** live Mac metrics: CPU, GPU, memory, disk (capacity + I/O), network throughput and periodic speed tests. They take the left half, or the left quarter with *Compact metrics* on.
- **Right side:** a big clock with a weather glance, plus a card carousel: weather, live scores with TV networks, headlines, YouTube uploads, anime countdowns, Bluesky posts, Steam wishlist releases, deals, achievements and news, exchange rates, a kanji of the hour, rain radar and Slickdeals.
- **Day / Night:** a warm Liquid Glass day theme, and an ultra high-contrast pure-black night theme. It switches when your Mac switches Light/Dark (including Auto at sunset) and can dim the tablet's backlight at night.
- **Standby:** when the Mac sleeps or locks, the metrics slide away and the clock and cards take the whole screen.

Everything is set up in a local web page on the Mac (the manager). No accounts are needed except an optional free Steam Web API key for the achievement and news cards.

## Requirements

- A Mac running macOS 14 or later. Developed on an Apple silicon Mac mini.
- An Amazon Fire tablet. The layout is designed for the 12th‑gen Fire 7 (1024×600) and scales on other screens.
- To build from source: Xcode command-line tools, the Android SDK (platform 34) and JDK 17. With Homebrew: `brew install openjdk@17 android-platform-tools` plus the Android SDK from Android Studio or `brew install --cask android-commandlinetools`.

## Download

Get the **Matchbox-Dashboard-…-macOS.zip** file from the [latest release](https://github.com/taxfraud311/matchbox-dashboard/releases/latest). The release notes walk through the first launch: the app isn't notarized, so macOS asks you to allow it once under **System Settings › Privacy & Security**. Then follow *Tablet setup* below. Building from source is only needed if you want to change it.

## Pieces

| Folder | What it is |
|---|---|
| `mac/` | **Matchbox Dashboard.app**, a Swift menu bar app. It samples metrics, proxies weather (Open‑Meteo), scores (ESPN) and RSS, and serves the display and manager on port 8787. It also runs `adb reverse` automatically so the tablet works over the USB cable. |
| `web/display/` | The tablet dashboard, designed pixel-for-pixel for 1024×600. |
| `web/manager/` | The manager at **http://localhost:8787/manager/**: live preview and every setting. It's only reachable from the Mac itself. |
| `android/` | **MatchboxDashboard.apk**, a 20 KB fullscreen kiosk WebView for Fire OS. It tries USB first, then a saved or Bonjour-discovered Wi‑Fi address. It keeps the screen on, lets the Mac set brightness, and relaunches after reboot. |

## Build

```bash
git clone https://github.com/taxfraud311/matchbox-dashboard.git
cd matchbox-dashboard
./scripts/build.sh            # → build/Matchbox Dashboard.app and build/MatchboxDashboard.apk (APK is bundled inside the app)
./scripts/build.sh --install  # also copies to /Applications and opens the manager
```

The build looks for JDK 17 at `/opt/homebrew/opt/openjdk@17` (or `$JAVA_HOME_17`) and the Android SDK at `~/Library/Android/sdk` (or `$ANDROID_HOME`). The Mac app is signed ad hoc on your machine, so macOS doesn't block it.

## Tablet setup (once)

1. Fire tablet: **Settings › Device Options › About Fire Tablet** → tap **Serial Number** 7×.
2. **Device Options › Developer Options** → turn on **USB debugging**.
3. `brew install android-platform-tools` on the Mac (if adb isn't installed).
4. Plug the tablet into the Mac mini and tap **Allow** (tick *Always allow*).
5. Matchbox Dashboard menu bar icon → **Install App on Tablet** (or the button in the manager).

After that, the display opens by itself whenever the tablet is plugged in or reboots. If the display process dies (for example during a WebView update), the Mac relaunches it.

**Wi‑Fi instead of USB:** in the Silk browser on the tablet, open `http://<mac-ip>:8787/download/MatchboxDashboard.apk` (the manager shows the address) and install it. Then long-press the top-left corner of the display to enter the address. The app also finds the Mac automatically via Bonjour.

## Notes

- Only Amazon Fire tablets (model `KF…`) are touched over adb. Other Android devices on the Mac are ignored unless you turn on *Use any Android device* in the manager.
- "Use the Mac's San Francisco font" streams `/System/Library/Fonts/SFNS*.ttf` from your Mac to your tablet. Apple's font license is written for Apple platforms, so switch it off if that matters to you. The tablet then falls back to its own font.
- **Compact metrics** (manager › Display) stacks the Mac metrics in one narrow column on the left quarter of the screen, so the clock and cards get three quarters.
- **Day mode colors** (manager › Display) has three options:
  - *Match Wallpaper* (default) samples five regions of your current wallpaper (Aerials included) and turns them into a bright pastel gradient, re-checked every 15 s.
  - *Custom* builds the gradient around a color you pick.
  - *Golden Gate* is the original warm palette.
- **YouTube card:** follow channels in manager › YouTube. Paste a channel URL or @handle, or import `subscriptions.csv` from [Google Takeout](https://takeout.google.com) (YouTube and YouTube Music › subscriptions). Matchbox Dashboard reads each channel's public upload feed, so no Google sign-in is needed. Shorts are hidden by default.
- **Anime card:** search for shows in manager › Anime, or link an AniList username. Countdowns use AniList's public airing schedule, which gives the Japanese broadcast time. Crunchyroll has no public API, so set *Crunchyroll release delay* if its simulcasts appear later.
- **Bluesky card:** add accounts in manager › Bluesky (@handle or profile link). Shows their newest posts with the first image and like/repost/reply counts, using Bluesky's public API with no sign-in. Reposts are optional.
- **Steam cards:** connect your profile in manager › Steam (profile link or SteamID). The wishlist must be public (Privacy › Game details).
  - *Steam · Coming soon* counts down to exact release dates. It shows the rough window when Steam only has one ("Q1 2027", "2027", "Coming soon"), and "Out now" for 3 days after release.
  - *Steam Deals* lists discounted wishlist games, biggest discount first, with sale end times. Set a minimum discount in the manager.
  - Store data refreshes every 30 minutes. The 1,500 highest-priority wishlist games are checked.
- **Steam achievements and news** need a free Steam Web API key (manager › Steam; get one at steamcommunity.com/dev/apikey). The key stays on the Mac: `/api/config` never returns it. Matchbox Dashboard looks at your 25 most recently played games:
  - *Achievements · Recently unlocked* shows what you've earned lately, with how many players have each one.
  - *Achievements · Within reach* lists locked achievements that most players have, favoring games you're furthest through. Steam doesn't publish per-achievement progress (the bars in the Steam client), so this is the best signal available.
  - *Steam News* shows official announcements for your 18 most recently played games from the last 60 days.
- **Exchange rates:** up to 4 currency pairs (manager › Exchange Rates), each with a 30-day chart. European Central Bank reference rates via Frankfurter, updated each business day.
- **Kanji of the hour:** a new kanji every hour from the level you pick (JLPT N5–N1, school grade, Jōyō…), with meanings, on/kun readings, three common words and an animated stroke order. Data from kanjiapi.dev and KanjiVG.
- **Radar:** RainViewer's rain radar looped over the last two hours on an OpenStreetMap base map, at the weather location or any place you choose. RainViewer's free tiles stop at zoom level 7.
- **Slickdeals:** Frontpage and/or Popular deals plus up to 8 categories or searches. Slickdeals has no category feeds, so each category is a search.
- **Tap any item for a QR code** (headlines, videos, games, posts, deals, achievements, kanji…) to open it on your phone. The Mac draws the code; scores link to ESPN's game page.
- **Long-press the card** to pause or resume the carousel, step through cards, or set the time per card (6–60 s). Pausing is remembered on the tablet; the time per card is saved to the Mac.
- **Disk:** the tile takes turns showing each connected drive (6 s each). Tap it to see what's using the space: a folder list and a WinDirStat-style treemap you can drill into. The first scan of a drive takes from seconds to a few minutes and is redone after 6 hours (or on *Rescan*). On the startup disk, macOS may ask about Desktop, Documents and Downloads. Without Full Disk Access, other apps' containers and a few protected folders are skipped and shown as *Not measured*.
- Thumbnails and cover art are fetched by the Mac (`/img`, allow-listed hosts only), so they show up on a USB-only tablet.
- **Standby:** when the Mac is about to sleep, log out, shut down or switch users, Matchbox Dashboard tells the tablet first. System sleep is held for about 1.6 s so the message gets through. The tablet then slides the metrics away and gives the clock, weather and cards the whole screen. If the Mac just stops answering for 20 s, the same happens with "Can't reach the Mac".
  - While the Mac is away, the tablet keeps the Mac's last known time and its cached data. It refreshes weather and scores directly if it has Wi‑Fi, and follows sunrise and sunset for day/night.
  - It even restarts from its cached copy if the tablet itself reboots in the meantime.
  - To test without sleeping the Mac: `curl -X POST localhost:8787/api/action -d '{"action":"presence","state":"sleeping","seconds":30}'`.
- **Touch:**
  - Tap a metric tile for details: per-core load, top apps by CPU/memory/disk/network with their icons, memory breakdown, volumes, GPU info, router/DNS, and a Run Speed Test button.
  - Tap the clock for the world clock (cities are set in the manager), or the temperature or weather card for the full forecast.
  - Swipe the card left or right to change it; it stays put for 30 s afterwards.
  - Long-press the top-left corner for 2 s for the tablet's connection settings.
- The screen stays on whenever the display is open: the window flag, the view flag, and the flag again on resume.
- If the tablet is in front but hasn't fetched data for 60 s, the Mac rebuilds the USB forward and restarts the display.
- If adb restarts (Android Studio, other tools), Matchbox Dashboard notices the new transport id and recreates the USB forward. The tablet reloads the page if it stops getting data.
- Settings live in `~/Library/Application Support/Plinth/config.json` (the folder kept its original name when the app was renamed from Plinth, so existing settings carry over).
- `http://localhost:8787/display/?theme=night` previews either theme in a browser. Tapping the card on the tablet skips to the next one.

## License

MIT. See [LICENSE](LICENSE).
