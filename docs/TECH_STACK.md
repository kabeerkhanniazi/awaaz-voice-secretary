# Tech stack

Everything Awaaz is built from, which version, and why it was chosen. For how the pieces talk to each other, see [ARCHITECTURE.md](ARCHITECTURE.md). For how a call moves through them, see [WORKFLOW.md](WORKFLOW.md).

---

## At a glance

| Layer | Technology | Version | Role |
|---|---|---|---|
| Voice AI | **AssemblyAI Voice Agent API** | v1 (WebSocket) | Two agents per call: one screens the caller, one briefs the owner |
| Post-call AI | **AssemblyAI LLM Gateway** | `qwen3.5-4b-32k-fast` | One-sentence summary and a follow-up task per call |
| Gateway | **Node.js** with `ws` | Node 18+ (CI 18, Railway 24.21) | Call registry, roles, routing, audio bridge, the owner's secretary |
| Caller page | Plain HTML, CSS and JavaScript | — | The public "call me" page, with the mic and playback in the browser |
| Owner page | Plain HTML, CSS and JavaScript | — | Take calls in any browser, iPhone included |
| Owner app | **Flutter** with **Riverpod** | Flutter 3.47.3, Dart ^3.13.3 | Android app: ringing, call screen, records, tasks, contacts, settings |
| Native Android | **Kotlin** | JVM 17, compileSdk 37 | Foreground service, lock-screen ringing, voice-call audio |
| Hosting | **Railway** (Railpack builder) | — | Two services from one folder: the live line and the demo line |
| Code and CI | **GitHub** and GitHub Actions | — | Public repo, tests on every push, APK releases |

The whole gateway has **two runtime dependencies**. The web pages have **none**: no build step, no framework, no CDN.

---

## 1. AssemblyAI

Awaaz uses two AssemblyAI products. The details, and what we learned using them, are in [VOICE_AGENT_API_NOTES.md](VOICE_AGENT_API_NOTES.md).

### Voice Agent API: agent A, the caller's secretary

| Aspect | Value |
|---|---|
| Where it runs | In the **caller's browser**, over `wss://agents.assemblyai.com/v1/ws` |
| Authentication | A short-lived token minted by the gateway at `GET /api/voice-token`, from `https://agents.assemblyai.com/v1/token` with `expires_in_seconds=300` and `max_session_duration_seconds=600`. The API key never reaches a browser. |
| Persona | `SECRETARY_SYSTEM_PROMPT`, `SECRETARY_GREETING` in `gateway/server.js` |
| Voice | `alba` |
| Tools | `save_caller_details` (name, company, reason, urgent, message, callbackNumber, callbackEmail, bestTime), `end_call` |
| Steered by | `reply.create` instructions sent when the owner decides (connect, hold, relay, decline, check in) |

### Voice Agent API: agent B, the owner's secretary

| Aspect | Value |
|---|---|
| Where it runs | **Server-side**, in `gateway/master-session.js`; the phone or owner page streams the owner's mic to it through the gateway |
| Voice | `alba`, the same voice, because it is the same secretary |
| Tools | `connect_caller`, `hold_caller` (minutes), `relay_message` (message), `add_task` (task, due date), `end_call` |
| Live context | The system prompt is refreshed during the session with the confirmed caller details, the call so far, trust and warnings, and who else is waiting |

### LLM Gateway

| Aspect | Value |
|---|---|
| Endpoint | `https://llm-gateway.assemblyai.com/v1/chat/completions` |
| Model | `qwen3.5-4b-32k-fast` by default; override with `SUMMARY_MODEL` |
| Used for | `POST /api/analyze-call`: a one-sentence summary, the most important follow-up, and a sentiment score, returned as JSON |
| Fallback | If the model call fails, a keyword-based summary is returned instead |

---

## 2. The gateway (`gateway/`)

A single Node.js process: an HTTP server and a WebSocket server on the same port.

| Item | Detail |
|---|---|
| Runtime | Node.js 18 or newer. CI tests on Node 18; Railway runs Node 24.21 |
| Dependencies | `ws` ^8.21 (WebSocket server and client), `dotenv` ^17.4 (local `.env` loading) |
| Framework | None. Routing is a handful of `if` statements over `http.createServer`, which keeps the surface small and easy to audit |
| Entry point | `server.js`, started by `npm start` (the `Procfile` does the same) |
| Owner's secretary | `master-session.js`: one `MasterSession` per answered call |
| Static files | `web/caller.html` at `/`, `web/owner.html` at `/owner`, `web/pcm-processor.js` |
| State | In memory: live calls, sockets and their roles, per-line owner settings, and recently ended calls |
| Tests | `test/*.test.js`, four suites with 28 checks, run by `npm test` with no network and no API key |

### HTTP endpoints

| Endpoint | Purpose |
|---|---|
| `GET /` | The caller page |
| `GET /owner` | The owner page |
| `GET /pcm-processor.js` | The AudioWorklet that turns the microphone into 24 kHz PCM16 |
| `GET /health` | Status, whether a key is present, the build commit, uptime, demo mode |
| `GET /api/voice-token` | A single-use token and the persona for agent A (rate-limited) |
| `POST /api/call` | Registers a call: line, browser id, personal-link token (rate-limited) |
| `POST /api/analyze-call` | The post-call summary (owner only: the secret, or a registered demo line) |

The WebSocket protocol, every message and its fields, is in [ARCHITECTURE.md](ARCHITECTURE.md#gateway-messages-json-over-websocket-unless-noted).

### Tuning values

| Setting | Value | Where |
|---|---|---|
| Message taken when nobody answers | after 90 s | `TAKE_MESSAGE_AFTER_MS` (env) |
| Message taken when the owner is away | after 12 s | `QUIET_TAKE_MESSAGE_MS` (env) |
| Rate limit | 20 requests per IP per 10 minutes | `RATE_LIMIT_MAX`, `RATE_LIMIT_WINDOW_MS` |
| Secretary session | tokens valid 5 minutes, sessions up to 10 minutes | `/api/voice-token` |
| A call whose page never connected | forgotten after 2 minutes | `STALE_CALL_MS` |
| Ended calls kept for the phone | up to 50, for 24 hours | `ENDED_CALLS_MAX`, `ENDED_CALL_TTL_MS` |
| Personal links / blocked browsers per line | 500 / 1,000 | `MAX_LINKS`, `MAX_BLOCKED` |
| WebSocket message size | 64 KB | `maxPayload` |
| Hold | 1 to 30 minutes | `MASTER_DIRECTIVE` handling |
| Owner's time zone for due dates | `Asia/Karachi` | `KABEER_TIMEZONE` (env) |

---

## 3. The web pages (`gateway/web/`)

Both pages are single, self-contained HTML files with inline CSS and JavaScript.

| Feature | How |
|---|---|
| Microphone | `getUserMedia` with echo cancellation, noise suppression and automatic gain |
| Resampling | `pcm-processor.js`, an **AudioWorklet** that resamples from the device rate (usually 48 kHz) to **24 kHz PCM16** and posts 50 ms chunks (1,200 samples) |
| Playback | Web Audio `AudioBufferSource` nodes scheduled back to back, with an 80 ms lead on the live bridge to absorb network jitter |
| Barge-in | Scheduled audio is stopped the moment the owner talks over the secretary (`MASTER_AUDIO_FLUSH`) |
| Browser id | A random UUID in `localStorage` (`awaaz_device`), so a repeat caller can be recognised or blocked. It is not a fingerprint |
| Themes | CSS custom properties with a `prefers-color-scheme: dark` variant |
| Owner page extras | Wake Lock (keeps a phone screen on while waiting), a Web Audio ringtone, vibration on Android, a flashing tab title, `localStorage` for call records and demo-line settings |

---

## 4. The owner app (`app/`)

### Flutter and Dart

| Package | Version | Used for |
|---|---|---|
| `flutter_riverpod` | ^3.4.3 | App state: the call state machine, contacts, records, owner settings |
| `web_socket_channel` | ^3.0.3 | The gateway connection while the app is open |
| `record` | ^7.1.1 | The microphone as a PCM16 24 kHz mono stream, with echo cancellation, noise suppression and gain |
| `http` | ^1.6.0 | The post-call summary request |
| `shared_preferences` | ^2.5.5 | Call records, tasks, contacts and settings on the phone |
| `flutter_secure_storage` | ^11.2.0 | The gateway secret, kept in the Android Keystore |
| `flutter_contacts` | ^2.5.0 | Importing contacts from the phone |
| `permission_handler` | ^13.0.2 | Microphone, notifications and contacts permissions |
| `url_launcher` | ^6.3.2 | Tap to dial, WhatsApp (`wa.me`) and email links |
| `share_plus` | ^13.3.0 | Sharing personal links and the call link |
| `intl` | ^0.20.3 | Times and dates ("free after 3:00 PM") |
| `uuid` | ^4.6.0 | Record and task ids |

### Native Android (Kotlin)

| File | What it does |
|---|---|
| `AwaazService.kt` | A **foreground service** (types `microphone` and `specialUse`). It keeps a standby connection to the gateway while the app is closed, raises a full-screen incoming-call alert, keeps calls alive with the screen off, and re-sends the owner's settings on every reconnection |
| `CallAudioPlayer.kt` | Plays the secretary and the caller through an `AudioTrack` with `USAGE_VOICE_COMMUNICATION`, so the phone's echo cancellation works during the live bridge. Speakerphone is on during calls |
| `BootReceiver.kt` | Restarts the standby service after the phone reboots |
| `MainActivity.kt` | Platform channels between Flutter and the native side (configure, start and stop, owner settings) |

**Permissions:** `RECORD_AUDIO`, `INTERNET`, `POST_NOTIFICATIONS`, `USE_FULL_SCREEN_INTENT`, `FOREGROUND_SERVICE` (with `_MICROPHONE` and `_SPECIAL_USE`), `RECEIVE_BOOT_COMPLETED`, `MODIFY_AUDIO_SETTINGS`, `VIBRATE`, and `READ_CONTACTS` (optional, for importing contacts).

**Build:** Gradle Kotlin DSL, `compileSdk 37`, JVM target 17, and Flutter's default `minSdk`/`targetSdk`. The demo build is the same source with `--dart-define=AWAAZ_DEMO_GATEWAY=wss://…`.

---

## 5. Infrastructure

| Piece | Setup |
|---|---|
| **Live line** | Railway service `web`: `https://aivs.up.railway.app`, built from this repo's `gateway/` folder on `main`, watch paths `/gateway/**` |
| **Demo line** | Railway service `awaaz-demo`: `https://awaaz-demo.up.railway.app`, the same folder, with `DEMO_MODE=1`. Its API key is a Railway reference variable pointing at the live service's, so the key is typed in one place only |
| **Builder** | Railpack detects Node from `gateway/package.json` and runs `npm start` |
| **CI** | GitHub Actions (`.github/workflows/ci.yml`): "Gateway and audio tests" (Node 18) and "Flutter analyse and tests" (`flutter analyze --fatal-infos`, `flutter test`, plus a demo-build settings test) |
| **Releases** | GitHub Releases carry the demo APK with its SHA-256 checksum |

---

## 6. Audio formats

| Path | Format |
|---|---|
| Caller's mic → agent A | PCM16 little-endian, mono, 24 kHz, base64 in `input.audio` |
| Agent A → caller | PCM16 24 kHz, played by Web Audio |
| Owner's mic → gateway → agent B | Raw PCM16 24 kHz binary WebSocket frames |
| Agent B → owner | Raw PCM16 24 kHz binary frames |
| The live bridge, both ways | Raw PCM16 24 kHz binary frames, relayed as they arrive, with no AI in between |

---

## 7. Why these choices

- **A web caller page instead of a phone number.** It costs nothing to run, works in any browser, and is exactly the "call me" button on a portfolio or LinkedIn. A real number is on the [roadmap](ROADMAP.md).
- **Two agents instead of one.** One agent can't talk to the caller and privately to the owner at the same time. Two sessions keep each conversation clean, and the gateway joins them with confirmed facts only.
- **Flutter, plus Kotlin where it matters.** Flutter made the screens fast to build. Ringing over the lock screen and voice-call audio need native Android APIs, so those parts are Kotlin.
- **No framework in the gateway.** Two dependencies and one file per concern keep it small, easy to audit and easy to test without a network.
- **State in memory.** It was the simplest thing that could work for a single owner. Persistence is on the [roadmap](ROADMAP.md).
