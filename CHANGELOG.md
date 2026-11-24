# Changelog

## 1.4: The AI notch

**Install:** download **Notchy.dmg**, drag Notchy into Applications, then click **Open Anyway** in System Settings →
Privacy & Security the first time. On 1.3 or later? Notchy offers this update itself.

**New: Claude in your notch**
- A new **Claude** tab: ask anything from the top of your screen and watch the answer stream in. Uses your own
  Anthropic account: paste an API key once in Settings → Connections → Claude (stored in your keychain). An
  `ant auth login` sign-in or `ANTHROPIC_API_KEY` works too.
- **Ask about files:** drag files onto the notch and drop them on the new **Ask Claude** tile. Images, PDFs, text and
  code files, and folders all work.
- **Web search** with sources under each answer, for anything current.
- **Live activity:** close the notch and keep working. It shows *"Claude is searching the web"*, then the answer as it
  arrives, and a pop-up when it's done.
- Claude Sonnet 5.5 by default, with Opus 5.5 and Haiku 5.5 one click away, plus Quick / Balanced / Thorough answers.
- `notchy://ask?q=…` asks Claude from Shortcuts or Raycast.

**New: answer T3 Code from the notch**
- When an agent wants to run a command or change files, approve it (once or for the session) or decline it in the
  Agents tab without opening T3 Code.
- When an agent asks you a question, pick an option or type your own answer right there.
- Pop-ups now say whether an agent needs an approval or has a question, and clicking one opens that thread.
- Notchy uses its own access token from T3 Code, kept in your keychain and only sent to T3 Code on your Mac. Revoke
  it in Settings → Connections → T3 Code.

**Improved**
- The island stays open while you're typing in the Claude or Agents box, until you click somewhere else.

**For developers**
- A test suite: `./scripts/test.sh` (plus opt-in live tests against the Claude API and T3 Code).

Requires a Mac with Apple silicon and macOS 14 or later.

## 1.3.1

- Much lower CPU use (pointer sampling instead of mouse monitors, timers paused while the display sleeps, a lighter
  T3 Code connection), efficiency mode and anonymous diagnostics.
- Optional always-visible logo on Macs without a notch.
- File drags work from any tab.

## 1.3

- T3 Code agents tab and live activity (including waiting for approval), in-app updates, the directional
  volume/brightness sweep, battery always visible, and a notarization-ready release build.
