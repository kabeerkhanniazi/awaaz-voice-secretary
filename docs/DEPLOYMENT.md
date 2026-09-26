# Running and deploying Awaaz

Everything needed to run Awaaz on your laptop, host it, and ship the Android app. For the development and release process, see [WORKFLOW.md](WORKFLOW.md#part-2-how-awaaz-is-built-and-shipped).

---

## Requirements

| For | You need |
|---|---|
| The gateway | Node.js 18 or newer, and an AssemblyAI API key with Voice Agent API access |
| The Android app | Flutter (version in [`app/.flutter-version`](../app/.flutter-version)), the Android SDK, and a phone or emulator running Android 8 or newer |
| Hosting | Any Node host that supports WebSockets and gives you HTTPS. Awaaz runs on Railway |

---

## Environment variables

| Variable | Required | Default | What it does |
|---|---|---|---|
| `ASSEMBLYAI_API_KEY` | **Yes** | — | Mints secretary tokens, runs your secretary's sessions, and powers summaries. Without it, callers get a clear error |
| `GATEWAY_AUTH_SECRET` | On a normal deployment | — | The owner's password. Only a device that presents it can take calls. Not used when `DEMO_MODE=1` |
| `PORT` | No | `3000` | The HTTP and WebSocket port. Hosts like Railway set it for you |
| `DEMO_MODE` | No | off | `1` makes this a demo deployment: every phone gets its own line code, and no secret is used |
| `TAKE_MESSAGE_AFTER_MS` | No | `90000` | How long a call rings before the secretary takes a message |
| `QUIET_TAKE_MESSAGE_MS` | No | `12000` | How soon she takes a message when you're away |
| `SUMMARY_MODEL` | No | `qwen3.5-4b-32k-fast` | The LLM Gateway model for post-call summaries |
| `KABEER_TIMEZONE` | No | `Asia/Karachi` | The owner's time zone, for dictated due dates ("by Friday") |
| `BUILD_SHA` | No | Railway's commit, or `local-dev` | Shown on `/health`, so you can tell which build is live |

Copy [`.env.example`](../.env.example) to `gateway/.env` for local runs. Never commit `.env`.

---

## Run it locally

```bash
cd gateway
npm install
npm start
```

| Open | What you get |
|---|---|
| `http://localhost:3000` | The caller page. Press Call and the secretary answers |
| `http://localhost:3000/owner` | The owner page. Press Start, enter the secret, and take calls in the browser |
| `http://localhost:3000/health` | The status, build and mode |

Browsers allow the microphone on `localhost` without HTTPS. On any other address, the pages need HTTPS.

**Try the owner side without a second person:** use two browser windows, the owner page in one and the caller page in the other. Wear headphones, so each page only hears you.

---

## Make it yours

The secretary works for "Kabeer" in this repository. To run it for yourself, change the name in:
- `SECRETARY_SYSTEM_PROMPT`, `SECRETARY_GREETING` and the instruction texts in `gateway/server.js`;
- `BASE_PROMPT` in `gateway/master-session.js`;
- the instruction texts in `gateway/web/caller.html`;
- the page title and heading in `gateway/web/caller.html`.

Per-owner names and voices are on the [roadmap](ROADMAP.md).

---

## Host it on Railway

Awaaz runs as **two Railway services built from the same folder**: the live line and the demo line.

### The live line

1. **+ Create → GitHub Repo →** your fork of this repository, branch `main`.
2. **Settings → Source → Root Directory:** `gateway`.
3. **Settings → Build → Watch Paths:** `/gateway/**`. Then README and app changes don't restart the line.
4. **Variables:** `ASSEMBLYAI_API_KEY` and `GATEWAY_AUTH_SECRET`.
5. **Settings → Networking → Generate Domain.** If Railway asks for a port, use the number after `Port:` in the deploy logs.
6. **Check it:** `https://<your domain>/health` should show `"status":"ok"` and `"assemblyaiKeyPresent":true`.

Railpack detects Node from `gateway/package.json` and runs `npm start`. The first build fails if it starts before the root directory is set; that's harmless, because a failed build never replaces a running one.

### The demo line (optional)

Repeat the steps above as a second service, with two differences:

| Variable | Value |
|---|---|
| `ASSEMBLYAI_API_KEY` | `${{web.ASSEMBLYAI_API_KEY}}`: a reference to the live service's variable (use your live service's name), so the key is typed once |
| `DEMO_MODE` | `1` |

Don't set `GATEWAY_AUTH_SECRET` on the demo line. `/health` should then show `"demoMode":true`.

### Other hosts

Render, Fly.io or a VPS all work. You need Node 18 or newer, WebSocket support, and HTTPS in front. The `Procfile` runs `node server.js`, and the server listens on `PORT`.

### Restarts

Live calls, per-line settings and missed calls not yet collected are kept in memory:
- A deploy or restart ends calls in progress.
- Owner devices reconnect and re-send their settings by themselves.
- Deploy when the line is quiet.
- With watch paths set, only gateway changes cause a restart.

---

## The Android app

### Your own build

```bash
cd app
flutter pub get
flutter run --release          # installs on a connected phone
# or
flutter build apk --release    # build/app/outputs/flutter-apk/app-release.apk
```

In the app's **Settings**:
1. **Gateway:** `wss://<your domain>` (or `ws://<your laptop's address>:3000` on your network).
2. **Gateway secret:** the same `GATEWAY_AUTH_SECRET`.
3. **Test connection.**
4. **Ring when the app is closed:** turn it on for the standby service.
5. **Your name** and **Country code:** your country code makes local numbers work with WhatsApp.

Don't share this build. It connects to your line, and whoever has your secret receives your calls.

### The demo build

```bash
cd app
flutter build apk --release --dart-define=AWAAZ_DEMO_GATEWAY=wss://<your demo domain>
```

The demo build:
- connects to the demo line;
- creates its own line code on first launch;
- hides the secret setting;
- shows "Your demo line" with its link.

Publish it as a GitHub Release, with install steps and its SHA-256 checksum:

```bash
sha256sum app-release.apk
```

To confirm the demo address is compiled in, search the Dart snapshot for it:

```bash
unzip -p app-release.apk lib/arm64-v8a/libapp.so | grep -a -c "<your demo domain>"
```

### Signing

Release builds are signed with the build machine's debug key, which is enough for sideloading. For the Play Store, add a release keystore and a `key.properties` (both kept out of git) and point `signingConfigs.release` at them. Keep one signing key for all builds of an install: Android only updates an app signed with the same key.

### Don't install the demo build over your own

Both builds have the same app ID. Installing one replaces the other, and your real line would stop ringing you. Test the demo build on an emulator or a spare phone.

---

## Checking a deployment

```bash
curl https://<your domain>/health
```

```json
{"status":"ok","assemblyaiKeyPresent":true,"buildSha":"<commit>","uptime":42.1,"demoMode":false}
```

| Field | Check |
|---|---|
| `status` | `ok` |
| `assemblyaiKeyPresent` | `true` |
| `buildSha` | The commit you just deployed |
| `demoMode` | `false` on the live line, `true` on the demo line |

Then open `/` and `/owner` to confirm both pages load.

---

## Rolling back

- **Railway:** in the service's **Deployments** tab, redeploy the last good deployment.
- **Code:** `git revert` the change and deploy again.
