# Roadmap

Where Awaaz is today, and where it goes next. Items are grouped into phases. Each says **why** it matters and **what it takes**, so the order can be argued with.

**Principles that don't change**
1. **You stay in the call.** The AI screens and briefs, and you decide. Nothing is decided for you that you'd want to decide yourself.
2. **Never take a name on trust.** A claim is shown as a claim until something real verifies it.
3. **Private by default.** The secretary gives nothing away, and your records stay with you.
4. **One person's secretary first, then teams.** It has to be excellent for one owner before it routes for many.

---

## Phase 0: done (August–September 2026)

| Date | Milestone |
|---|---|
| 26 Aug | First prototype, "Vox Sonus": five voice agents on the AssemblyAI Voice Agent API. Renamed Awaaz the same day. |
| 18 Sep | The gateway grows up: socket roles and a gateway secret, the Patch In audio bridge, the owner's own secretary session, confirmed-facts-only briefings, AI summaries through the LLM Gateway, message taking, waiting callers. |
| 19 Sep | The Android app: ringing when closed (a foreground service), a minimal full-screen call UI, the secret in the Android Keystore, contact-aware briefings, dictated tasks with due dates, CI with real tests. |
| 20 Sep | The Hackathon Edition published under MIT, with CI. |
| 21 Sep | The demo line: a personal line per phone, no secret, a preconfigured demo build. |
| 25 Sep | Caller trust and personal links, blocking, availability, call-back details, tap to dial and WhatsApp, privacy and English-only rules. The live line moves to this repo, with a secret scan before every deploy. |
| 26 Sep | The hosted demo line and the demo APK release. **The owner page**: take calls in any browser, iPhone included. |

## Phase 1: judging (October 2026)

| Item | Why | What it takes |
|---|---|---|
| Keep both lines up and funded | Judges try it at any hour | A weekly `/health` check, the AssemblyAI balance, and a Railway plan beyond the trial |
| Bug fixes only | Stability beats features during judging | Fixes go through the same tests, secret scan and deploy |
| Measured latencies | Numbers build trust | Median of five runs for three timings: Call to ring, "put her through" to hearing the caller, and an instruction to the caller hearing it |

## Phase 2: foundations (the first 1–2 months after)

| Item | Why | What it takes |
|---|---|---|
| **Persistence** | Missed calls, settings and links now live in the gateway's memory, so a restart before a phone reconnects loses uncollected calls | A small database (Postgres or SQLite on a volume) for calls not yet logged, per-line settings, links and blocks |
| **Push notifications as a backup channel** | Some phones' battery savers stop the standby service | Firebase Cloud Messaging alongside the standby socket. Push wakes the app, and the socket carries the call |
| **Accounts and your own secretary** | The persona says "Kabeer", so every new owner needs their own | Sign-up, a name and pronouns, a secretary voice (from the Voice Agent API's voices), a greeting, and prompts built from them |
| **One-time codes for strangers** | Personal links verify people you know. A stranger can only be checked by you | Email (or SMS) a six-digit code to the address the caller gives, and have the caller read it back to the secretary. A match means "Verified email" |
| **Recognition hints** | Names like "Brightline" or Urdu names are easy to mis-hear | Send your contacts' names and companies as recognition hints (keyterms) to the speech recognition |
| **Calendar-aware availability** | "Busy until 3" should come from your calendar, not a button | Read-only calendar access. Busy blocks become availability automatically, with meeting titles never shared |
| **The owner page as an app** | Fewer steps on iPhone | Make it installable (a PWA) with web push, so it can ring when it isn't in front |
| **End-to-end audio tests** | Today's tests cover logic and routing, not sound | Automated calls with recorded audio against a local gateway, asserting on transcripts and timing |

## Phase 3: reach (3–6 months)

| Item | Why | What it takes |
|---|---|---|
| **A real phone number** | Most calls still come from phones, not links | SIP/PSTN inbound through a telephony provider. Calls to a number (or forwarded from yours) enter the same gateway as the caller page. The audio is already PCM16, so it's a new front door on the same system |
| **Urdu, and mixing Urdu and English** | The first market is Pakistan, where people switch languages mid-sentence | The Voice Agent API speaks six European languages. AssemblyAI's real-time transcription (Universal-3.5 Pro Realtime) understands Urdu, so the secretary becomes that transcription, a model through the LLM Gateway, and an Urdu voice. The same gateway protocol carries it |
| **iOS app** | Some owners want a native app on iPhone | Swift equivalents of the ringing service and audio player, with CallKit and PushKit |
| **More ways in** | Callers reach people on WhatsApp too | WhatsApp calling or voice notes as another front door, screened by the same secretary |

## Phase 4: a business (6–12 months)

| Item | Why | What it takes |
|---|---|---|
| **Plans** | It has to pay for itself | Free: a "call me" link with message-taking. Pro: the live owner line, put through, tasks, personal links. About $0.19 of AI per screened call today, and the bridge costs nothing |
| **Teams and routing** | Small firms want one secretary for several people | "Who would you like to speak to?", then ring the right person, with shared call records |
| **Integrations** | Records belong where the work is | Send summaries and tasks to calendars, CRMs and to-do apps |
| **Controls and compliance** | Trust at scale | Retention settings, export and delete, a caller notice for AI-handled calls, and consent rules per region |
| **Spam intelligence** | One owner's impostor is everyone's | Shared, privacy-preserving signals about browsers and numbers that others have blocked |

## Ideas we're exploring

- **Your own voice for relays:** the secretary relays your message in her voice today. A short clip of yours could be offered to the caller instead.
- **Urgency learned from you:** if you always take calls about "the server is down", the secretary should learn that.
- **Answer from your watch:** a one-tap "put through" or "take a message" from a wearable.

---

Suggestions and questions are welcome through GitHub issues.
