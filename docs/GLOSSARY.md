# Glossary

The words used across Awaaz's code and documentation.

| Term | Meaning |
|---|---|
| **Owner** | The person whose calls are screened: "Kabeer" in this repository. The owner uses the Android app or the owner page |
| **Caller** | Anyone calling the owner, through the caller page |
| **Caller page** | The public web page callers use (`/`, `gateway/web/caller.html`) |
| **Owner page** | The web page that lets the owner take calls in any browser (`/owner`, `gateway/web/owner.html`) |
| **Gateway** | The Node.js server that connects everyone (`gateway/server.js`) |
| **The caller's secretary (agent A)** | The AssemblyAI Voice Agent session that answers and screens the caller. It runs in the caller's browser |
| **Your secretary (agent B)** | A second Voice Agent session, private to the owner, that briefs them and takes spoken decisions. It runs on the gateway. In the code it's the *master session* |
| **Master** | The code's name for the owner: `MASTER_DIRECTIVE`, `MASTER_SESSION_START`, and a speaker labelled `Master` |
| **Screening** | The secretary learning who is calling and why |
| **Caller details** | What the caller confirmed: name, company, reason, urgency, message, call-back number or email, best time. Recorded with the `save_caller_details` tool |
| **Briefing** | Your secretary telling you who is calling and why, using confirmed details only |
| **Directive (instruction)** | A numbered decision from the owner's device (`MASTER_DIRECTIVE`): `holding`, `patchedToMaster`, `custom`, `declined`, `checkIn` or `hangup`. The caller page turns each into words for the caller's secretary |
| **Command** | A decision your secretary heard you make (`MASTER_COMMAND`): `connect`, `hold`, `relay`, `task` or `end`. Your device runs it exactly like the matching button |
| **Patch In / put through** | Connecting the caller to the owner directly (`patchedToMaster`) |
| **Bridge (live bridge)** | After Patch In: the gateway relays raw audio between caller and owner, with no AI in between |
| **Relay** | Passing a message from the owner to the caller, in the secretary's words (`relay_message`, `custom`) |
| **Hold / check-in** | Asking the caller to wait 1 to 30 minutes (`holding`). When the time is up, the secretary checks in with them (`checkIn`) instead of connecting automatically |
| **Take a message** | The secretary taking a message and a way to reach the caller: when nobody acts for 90 seconds, when the owner is away, or when the owner ends the call |
| **Quiet call** | A call that doesn't ring because the owner is away (`quiet: away`) or the caller is set to never ring (`quiet: unavailable`) |
| **Availability** | Available, busy until a time, or do not disturb (`OWNER_SETTINGS`) |
| **Personal link** | A caller-specific link (`?from=TOKEN`) that the owner sends a contact. The only thing that verifies a caller. Revocable |
| **Always ring / never ring** | Per-contact settings that apply only to calls through that contact's personal link |
| **Trust level** | How sure Awaaz is about the caller: **verified** (a personal link), **recognised** (this browser called before under the same name), **unverified** (a claim), or **warning** (a reason for suspicion) |
| **Browser id** | A random, anonymous id the caller page keeps in the caller's browser (`awaaz_device`), used to recognise and block repeat callers |
| **Line** | Who a call belongs to. The live deployment has one line; a demo deployment has one per phone or owner page |
| **Line code** | A demo line's six-character id, for example `K7Q2PX`. It replaces the secret on a demo deployment |
| **Live line** | The real deployment at `aivs.up.railway.app`, which rings Kabeer's own phone |
| **Demo line** | The deployment for judges at `awaaz-demo.up.railway.app` (`DEMO_MODE=1`), where every phone or owner page gets its own line |
| **Standby service** | The Android foreground service (`AwaazService`) that stays connected and rings while the app is closed |
| **Missed calls** | Calls that ended while no owner device logged them. The gateway keeps them for up to 24 hours until one confirms (`CALL_LOGGED`) |
| **Waiting caller** | A caller who rang while the owner was on another call. They're screened by their own secretary and come up next |
| **Barge-in** | Talking over the secretary: she stops at once (`MASTER_AUDIO_FLUSH`) |
| **Hackathon Edition** | This public repository: the submitted system under MIT, synced from the private working copy |
