# Notch Island

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
| ⏱ **Timer** | Presets or custom; counts down in the notch and chimes when done |
| 📥 **File shelf** | Drag files onto the notch to hold them, drag them out anywhere later, or AirDrop them |
| ⚡ **Quick toggles** | Dark Mode, Keep Awake, Mute, Screenshot, Sleep Display |
| 🚀 **App shelf** | Your favorite apps one click away (`+` to add, right-click to remove) |
| 🔋 **Battery** | Charging animation when you plug in, battery level in the header |

## Install

Requires an Apple Silicon Mac with macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/rishidil/notch-island.git
cd notch-island
./build.sh install     # builds, copies to /Applications and launches
```

Other commands: `./build.sh` (just build into `build/`) and `./build.sh run` (build + relaunch from `build/`).

To quit or change settings, right-click the island or use the ⚙︎ in the expanded view.

## Permissions

Each feature asks only when needed:

| Feature | Permission | How |
| --- | --- | --- |
| Calendar | Calendars | Prompted on first launch |
| Music controls, Dark Mode | Automation (Spotify / Music / System Events) | Prompted on first use |
| Notification previews | **Full Disk Access** | ⚙︎ → *Enable Notification Previews…*, then add **Notch Island** with `+` |
| Replace system volume/brightness HUD | **Accessibility** | ⚙︎ → *Replace System Volume & Brightness HUD*, then allow it |

### Connect Google Calendar

Notch Island reads calendars through macOS, so Google sync (including recurring events and Meet links) works by adding
your Google account to the Mac:

1. ⚙︎ → **Add Google / Other Calendar Account…** (or System Settings → Internet Accounts → Add Account → Google)
2. Sign in and make sure **Calendars** is turned on
3. Choose which calendars appear from the Calendar tab → **Calendars** menu

Tip: in Calendar.app → Settings → Accounts, set *Refresh Calendars* to **Push** or **Every 5 minutes** for faster updates.

### Keep permissions across rebuilds (optional, for developers)

`build.sh` signs ad-hoc by default, so macOS forgets permissions every time you rebuild. To fix that, create a
self-signed certificate once: **Keychain Access → Certificate Assistant → Create a Certificate…**, name it
`Notch Island Dev`, set the type to **Code Signing**. `build.sh` will pick it up automatically.

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
| `TimerService.swift`, `FileShelf.swift` | Timer and file shelf |

### Limitations

- **Music:** only Spotify and Apple Music. macOS 15.4+ blocks third-party apps from the system-wide Now Playing API,
  so browser audio (YouTube etc.) can't be shown.
- **Private APIs:** brightness and notification previews use private macOS APIs, which could break in a future macOS update.
- **External displays:** shows a small black pill in place of the notch.
- **Privacy:** notification content never leaves your Mac.
