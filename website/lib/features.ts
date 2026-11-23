import {
  AudioLines,
  Bell,
  Bluetooth,
  CalendarDays,
  CloudSun,
  Cpu,
  Hourglass,
  House,
  Inbox,
  ListTodo,
  MicVocal,
  SunMedium,
  Timer,
  type LucideIcon,
} from "lucide-react";

export type Feature = {
  id: string;
  name: string;
  /** File name inside /public/screenshots */
  screenshot: string;
  icon: LucideIcon;
  /** Accent color from the logo palette */
  color: string;
  tagline: string;
  description: string;
  points: string[];
};

const cyan = "#59d9ff";
const indigo = "#5c6bff";
const violet = "#bf59ff";
const pink = "#ff619e";
const orange = "#ffa84d";

export const FEATURES: Feature[] = [
  {
    id: "home",
    name: "Home",
    screenshot: "home.jpg",
    icon: House,
    color: pink,
    tagline: "Everything you reach for, one hover away.",
    description:
      "Now playing with controls tinted to the album art, plus volume and brightness sliders, quick toggles and your favorite apps.",
    points: [
      "Album-art tinted play, pause, skip and seek",
      "Volume & brightness sliders",
      "Dark Mode, Keep Awake (Amphetamine), Mute, Screenshot",
      "App shelf for one-click launching",
    ],
  },
  {
    id: "music-live",
    name: "Live Activity",
    screenshot: "music-live.jpg",
    icon: AudioLines,
    color: violet,
    tagline: "Now playing, even when it's closed.",
    description:
      "The collapsed notch grows just enough to show artwork and a live equalizer, so you always know what's on.",
    points: [
      "Artwork and animated equalizer around the notch",
      "Hover to expand into full controls",
      "Timers, charging and meetings get live activities too",
    ],
  },
  {
    id: "calendar",
    name: "Calendar",
    screenshot: "calendar.jpg",
    icon: CalendarDays,
    color: indigo,
    tagline: "Never be late to a call again.",
    description:
      "Today and tomorrow at a glance, with a one-click Join button for Google Meet, Zoom and Teams links.",
    points: [
      "Today / tomorrow agenda",
      "Google Calendar through your macOS accounts",
      "One-click Join for Meet, Zoom and Teams",
    ],
  },
  {
    id: "timer",
    name: "Timer & Pomodoro",
    screenshot: "timer.jpg",
    icon: Timer,
    color: orange,
    tagline: "Focus, with the clock in plain sight.",
    description:
      "Start a preset or a custom timer, or run focus/break Pomodoro cycles that count down right in the notch.",
    points: [
      "Presets and custom durations",
      "Pomodoro focus / break cycles",
      "Live countdown in the collapsed notch, chime when done",
    ],
  },
  {
    id: "weather",
    name: "Weather",
    screenshot: "weather.jpg",
    icon: CloudSun,
    color: cyan,
    tagline: "Know before you go.",
    description:
      "Current conditions plus hourly and daily forecasts, powered by Open-Meteo. No account or API key needed.",
    points: [
      "Current conditions",
      "Hourly & daily forecast",
      "Open-Meteo — no sign-up",
    ],
  },
  {
    id: "todo",
    name: "To-Do",
    screenshot: "todo.jpg",
    icon: ListTodo,
    color: pink,
    tagline: "Capture it before it slips away.",
    description:
      "A lightweight task list that lives in the notch — jot something down and check it off without switching apps.",
    points: ["Add tasks in a second", "Check off right in the notch", "Stays on your Mac"],
  },
  {
    id: "lyrics",
    name: "Live Lyrics",
    screenshot: "lyrics.jpg",
    icon: MicVocal,
    color: violet,
    tagline: "Sing along, line by line.",
    description:
      "Time-synced lyrics for whatever's playing in Spotify or Apple Music, scrolling along with the song.",
    points: ["Synced to playback", "Spotify & Apple Music", "Lyrics from LRCLIB"],
  },
  {
    id: "bluetooth",
    name: "Bluetooth",
    screenshot: "bluetooth.jpg",
    icon: Bluetooth,
    color: indigo,
    tagline: "Your devices and their batteries.",
    description:
      "See connected AirPods, keyboards and mice with battery levels, and connect or disconnect in a click.",
    points: ["Battery levels for AirPods & accessories", "Connect / disconnect quickly", "Keyboards, mice and more"],
  },
  {
    id: "system",
    name: "System Monitor",
    screenshot: "system.jpg",
    icon: Cpu,
    color: cyan,
    tagline: "Your Mac's vitals at a glance.",
    description: "CPU, memory, network, disk and battery stats, without opening Activity Monitor.",
    points: ["CPU & memory", "Network & disk", "Battery level & thermal state"],
  },
  {
    id: "screentime",
    name: "Screen Time",
    screenshot: "screentime.jpg",
    icon: Hourglass,
    color: orange,
    tagline: "Where did the day go?",
    description:
      "Today's usage and your top apps, tracked privately on-device. Nothing is ever uploaded.",
    points: ["Today's total usage", "Top apps", "Tracked privately on your Mac"],
  },
  {
    id: "notifications",
    name: "Notifications",
    screenshot: "notifications.jpg",
    icon: Bell,
    color: pink,
    tagline: "Previews that pop out of the notch.",
    description:
      "New notifications slide out of the notch, and recent ones stay in a history you can scroll back through.",
    points: ["Previews from the notch", "Recent history", "Right-click to mute an app"],
  },
  {
    id: "drop",
    name: "Drop Actions",
    screenshot: "drop.jpg",
    icon: Inbox,
    color: violet,
    tagline: "Drag. Drop. Done.",
    description:
      "Drag files onto the notch to shelve them for later, AirDrop them, compress them or copy their path.",
    points: ["File shelf — drag out anywhere later", "AirDrop", "Compress or copy path"],
  },
  {
    id: "hud",
    name: "Volume & Brightness",
    screenshot: "hud.jpg",
    icon: SunMedium,
    color: cyan,
    tagline: "A HUD that fits the hardware.",
    description:
      "Volume and brightness bars pop out of the notch, optionally replacing the system HUD entirely.",
    points: ["Pops out of the notch", "Replaces the system HUD (optional)", "Works with media keys"],
  },
];
