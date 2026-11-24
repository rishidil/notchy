# Changelog

## 1.4: The AI notch

**Install:** download **Notchy.dmg**, drag Notchy into Applications, then click **Open Anyway** in System Settings →
Privacy & Security the first time. On 1.3 or later? Notchy offers this update itself.

**New: AI in your notch**
- A new **AI** tab: ask anything from the top of your screen and watch the answer stream in, with three engines:
  - **On-device:** Apple's built-in model answers quick questions for free, privately and offline (macOS 26 with
    Apple Intelligence).
  - **Claude via T3 Code:** files and harder questions go to Claude on the plan you already use in T3 Code. No API
    credits needed, and every chat is saved as a thread in a "Notchy" project in T3 Code.
  - **Claude API:** connect an Anthropic API key (or an `ant auth login` sign-in) for Claude with web search and
    sources, billed by Anthropic.
- **Automatic** picks for you: quick questions on-device, files and bigger questions to Claude. **Ask Claude instead**
  re-asks an on-device answer with Claude.
- **Ask about files:** drag files onto the notch and drop them on the new **Ask AI** tile. Images, PDFs, text and code
  files, and folders all work with Claude; the on-device model reads short text files.
- **Live activity:** close the notch and keep working. It shows *"Claude is searching the web"*, then the answer as it
  arrives, and a pop-up when it's done.
- `notchy://ask?q=…` asks from Shortcuts or Raycast.

**New: answer T3 Code from the notch**
- When an agent wants to run a command or change files, approve it (once or for the session) or decline it in the
  Agents tab without opening T3 Code.
- When an agent asks you a question, pick an option or type your own answer right there.
- Pop-ups now say whether an agent needs an approval or has a question, and clicking one opens that thread.
- Notchy uses its own access token from T3 Code, kept in your keychain and only sent to T3 Code on your Mac. Revoke
  it in Settings → Connections → T3 Code.

**Improved**
- The island stays open while you're typing in the AI or Agents box, until you click somewhere else.

**For developers**
- New [developer docs](https://rishidil.github.io/notchy/docs/) on the website: architecture, the AI engines, the T3
  Code integration and every connection Notchy makes.
- A test suite: `./scripts/test.sh`, plus opt-in live tests for the on-device model, T3 Code and the Claude API.

Requires a Mac with Apple silicon and macOS 14 or later.

## 1.3.1

- Much lower CPU use (pointer sampling instead of mouse monitors, timers paused while the display sleeps, a lighter
  T3 Code connection), efficiency mode and anonymous diagnostics.
- Optional always-visible logo on Macs without a notch.
- File drags work from any tab.

## 1.3

- T3 Code agents tab and live activity (including waiting for approval), in-app updates, the directional
  volume/brightness sweep, battery always visible, and a notarization-ready release build.
