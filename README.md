# Notchy

**[Website](https://rishidil.github.io/notchy/) · [Download](https://github.com/rishidil/notchy/releases/latest/download/Notchy.dmg)**

![Notchy](website/public/screenshots/home.jpg)

A Dynamic Island for your MacBook's notch. Native SwiftUI + AppKit, no dependencies, ~0% CPU at idle.

Hover the notch to expand it. When something's happening, the notch grows a **live activity**: now playing,
timers, charging, volume/brightness, upcoming meetings and notification previews.

## Features

| | |
| --- | --- |
| 🎵 **Now Playing** | Spotify & Apple Music: artwork, equalizer tinted to the album art, play/pause/skip, seekable progress |
| 🔊 **Volume & brightness HUD** | Bars pop out of the notch. Optionally replaces the system HUD entirely |
| 🔔 **Notification previews** | New notifications appear in the notch (right-click to mute an app) |
| 📅 **Calendar** | Next event + today/tomorrow agenda, one-click **Join** for Meet/Zoom/Teams links, works with **Google Calendar** |
| ⏱ **Timer & Pomodoro** | Presets, custom timers and focus/break cycles that count down in the notch |
| 🌤 **Weather** | Current conditions, hourly and daily forecast ([Open-Meteo](https://open-meteo.com), no account) |
| ✅ **To-Do** | A quick task list in the notch |
| 🎤 **Live lyrics** | Synced lyrics for Spotify & Apple Music ([LRCLIB](https://lrclib.net)), optionally under the notch |
| 🎧 **Bluetooth** | Connected devices with battery levels (AirPods, Magic Keyboard/Mouse…), connect/disconnect, pop-up on connect |
| 📊 **System monitor** | CPU, memory, network and disk with live graphs |
| ⏳ **Screen Time** | Today's usage and top apps, tracked privately on your Mac |
| 🔔 **Notification history** | Recent notifications in their own tab |
| 🪄 **Drop actions** | Drag files onto the notch: keep on shelf, AirDrop, compress, copy path or email |
| 📥 **File shelf** | Hold dropped files, drag them out anywhere later, or AirDrop them |
| ⚡ **Quick toggles** | Dark Mode, Keep Awake (uses [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704) if installed; right-click for durations), Mute, Screenshot, Sleep Display |
| 🚀 **App shelf** | Your favorite apps one click away (`+` to add, right-click to remove) |
| 🔋 **Battery** | Charging animation when you plug in, battery level in the header |

**Make it yours:** a Settings window opens on first launch so you can choose which tabs your notch shows and in what
order, toggle features, and grant only the permissions you need. Reopen it from ⚙︎ → **Settings…**.

## Download (no Terminal needed)

Works on any Mac with Apple silicon (M1 or newer) running macOS 14 Sonoma or later, with or without a notch.

1. **[Download Notchy.dmg](https://github.com/rishidil/notchy/releases/latest/download/Notchy.dmg)**
2. Open the downloaded file and drag **Notchy** onto the **Applications** folder
3. Open **Applications** and double-click **Notchy**. macOS will say it *"could not verify"* the app; click **Done**
   (this happens because the app isn't sold through Apple, not because anything is wrong)
4. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to *"Notchy was blocked"*.
   Confirm with your password or Touch ID

That's it. The island now lives in your notch. Hover over it to open it (no notch? push the cursor to the top center
of the screen). You only do step 4 once.

To quit or change settings, right-click the island or use the ⚙︎ in the expanded view.
Turn on **Launch at Login** there so it starts with your Mac.

## Build from source

Requires an Apple Silicon Mac with macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/rishidil/notchy.git
cd notchy
./build.sh install     # builds, copies to /Applications and launches
```

Other commands: `./build.sh` (just build into `build/`), `./build.sh run` (build + relaunch from `build/`) and `./build.sh dmg` (make the installer disk image).


## Permissions

Each feature asks only when needed:

| Feature | Permission | How |
| --- | --- | --- |
| Calendar | Calendars | Prompted on first launch |
| Weather | Location (or pick a city in Settings) | Prompted when the Weather tab is on |
| Bluetooth tab | Bluetooth | Prompted when the Bluetooth tab is on |
| Music controls, Dark Mode, Amphetamine | Automation (Spotify / Music / System Events / Amphetamine) | Prompted on first use |
| Notification previews & history | **Full Disk Access** | ⚙︎ → *Enable Notification Previews…*, then add **Notchy** with `+` |
| Replace system volume/brightness HUD | **Accessibility** | ⚙︎ → *Replace System Volume & Brightness HUD*, then allow it |

### Connect Google Calendar

Notchy reads calendars through macOS, so Google sync (including recurring events and Meet links) works by adding
your Google account to the Mac:

1. ⚙︎ → **Add Google / Other Calendar Account…** (or System Settings → Internet Accounts → Add Account → Google)
2. Sign in and make sure **Calendars** is turned on
3. Choose which calendars appear from the Calendar tab → **Calendars** menu

Tip: in Calendar.app → Settings → Accounts, set *Refresh Calendars* to **Push** or **Every 5 minutes** for faster updates.

### Keep permissions across rebuilds (optional, for developers)

`build.sh` signs ad-hoc by default, so macOS forgets permissions every time you rebuild. To fix that, create a
self-signed code-signing certificate named `Notch Island Dev` once; `build.sh` picks it up automatically.

Either use **Keychain Access → Certificate Assistant → Create a Certificate…** (name `Notch Island Dev`,
type **Code Signing**), or from Terminal:

```bash
cat > /tmp/nid.cnf <<'CNF'
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=Notch Island Dev
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/nid.key -out /tmp/nid.pem -days 7300 -config /tmp/nid.cnf
openssl pkcs12 -export -legacy -inkey /tmp/nid.key -in /tmp/nid.pem -out /tmp/nid.p12 -passout pass:temp -name "Notch Island Dev"
security import /tmp/nid.p12 -k ~/Library/Keychains/login.keychain-db -P temp -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db /tmp/nid.pem  # asks for your password
rm /tmp/nid.key /tmp/nid.p12 /tmp/nid.pem /tmp/nid.cnf
```

After the first build signed this way, grant permissions one last time; they'll stick from then on.

## How it works

| File | Purpose |
| --- | --- |
| `NotchWindowController.swift` | Transparent panel over the notch, notch geometry, mouse pass-through, file-drag detection |
| `NotchViewModel.swift` | Expanded/collapsed state, live-activity priority, tabs, sizes, media-key handling |
| `NotchViews.swift` | Notch shape, collapsed live activities, settings menu, shared components |
| `ExpandedViews.swift` | Expanded tabs: Home, Calendar, Timer, Shelf |
| `MusicController.swift` | Spotify / Apple Music via distributed notifications + AppleScript |
| `HUDServices.swift` | Volume (CoreAudio), brightness (DisplayServices), media-key event tap |
| `NotificationWatcher.swift` | Reads new entries from Notification Center's local database (read-only) |
| `SystemServices.swift` | Battery (IOKit), Calendar (EventKit), quick toggles, app shelf |
| `TimerService.swift`, `FileShelf.swift` | Timer/Pomodoro, file shelf and drop-action helpers |
| `FeatureTabs.swift` | Weather, To-Do, Lyrics, Bluetooth, System, Screen Time, Notifications tabs and drop actions |
| `WeatherService.swift`, `LyricsService.swift`, `BluetoothService.swift`, `SystemMonitor.swift`, `ScreenTimeTracker.swift`, `TodoStore.swift` | The services behind those tabs |
| `SettingsView.swift` | Settings / first-launch window |
| `DemoData.swift` | Sample data for screenshots (`--demo`; nothing saved) |
| `website/` | The Next.js + shadcn/ui website (deployed to GitHub Pages) |

Automation: `notchy://open?tab=weather`, `notchy://timer?minutes=10`, `notchy://pomodoro`,
`notchy://settings` (handy for Shortcuts or Raycast).

### Limitations

- **Music:** only Spotify and Apple Music. macOS 15.4+ blocks third-party apps from the system-wide Now Playing API,
  so browser audio (YouTube etc.) can't be shown.
- **Private APIs:** brightness and notification previews use private macOS APIs, which could break in a future macOS update.
- **Macs without a notch** (M1 Air, 13" Pro, iMac, external displays): the island stays invisible until something
  happens (music, timer, volume…), then appears as a slim pill in the menu bar. Push the cursor to the top center of
  the screen to open it. Turn off *Show Music & Timer in Menu Bar* in ⚙︎ to show only pop-ups.
- **Screen Time** is tallied by Notchy itself from the moment you turn the tab on (macOS has no public Screen Time API).
- **Privacy:** notification content, screen time and your files never leave your Mac. Weather requests send only
  approximate coordinates to Open-Meteo; lyrics lookups send the song title and artist to LRCLIB.
