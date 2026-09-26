# User guide

How to use Awaaz, whether you're **calling** someone, **taking calls** in the Android app, or taking calls on the **owner page** in any browser.

---

## For callers

1. Open the call link, for example **https://aivs.up.railway.app**, in any browser with a microphone.
2. Press **Call** and allow the microphone.
3. The secretary answers: *"Hello! You've reached Kabeer's line. I'm his secretary. May I know who's calling please?"*
4. Tell her your name, where you're from, what it's about, and whether it's urgent.
5. She checks with Kabeer while you hold. Then one of these happens:
   - **You're put through,** and you're talking to Kabeer directly;
   - she passes on **his message** ("Kabeer will call you back in ten minutes");
   - you're asked to **hold** for a few minutes;
   - she **takes a message**. She'll ask for a number or email and a good time, read it back, and say goodbye.

**Good to know:**
- You'll see the call's status, not a transcript.
- If someone sent you a **personal link**, use it. It tells Kabeer's secretary it's really you.
- The page keeps a random, anonymous id in your browser, so a repeat caller can be recognised. The page footer says so.
- The secretary speaks English.

---

## For owners: the Android app

### Setting up

Open **Settings**:

| Setting | What to do |
|---|---|
| **Gateway** | Your gateway's address, `wss://…` (already set in the demo app) |
| **Gateway secret** | Your secret. It's stored in the Android Keystore. The demo app doesn't need one |
| **Test connection** | Checks both of the above |
| **Ring when the app is closed** | Turn on: a standby service rings over the lock screen |
| **Secretary joins automatically** | On: your secretary starts briefing you as soon as a call arrives. Off: you start her from the call screen |
| **Your name** | Used in the links and messages you send |
| **Country code** | For example 92: local numbers like `0300…` then work with WhatsApp |
| **Availability** | Available, busy for 30 minutes, 1 hour or 2 hours, or do not disturb |
| **Your call link** | Copy it, or share it on WhatsApp |
| **Blocked callers** | Browsers you've blocked, each with **Unblock** |

Allow the **microphone** and **notifications** when asked. Contacts access is optional.

### The four tabs

| Tab | What's there |
|---|---|
| **Calls** | Every call, newest first, filtered by **All**, **You talked**, **Handled** or **Spam**. At the top: your availability, and search. Tap a call for its record |
| **Tasks** | Call-backs and dictated reminders, with due dates, and **call**, **WhatsApp** and **email** buttons |
| **Contacts** | Import from your phone, or add people: name, company, relationship, number. Each contact has a **personal link** |
| **Settings** | As above |

### When a call comes in

The phone rings, even when the app is closed. The call screen shows:
- **The caller's name**, as they gave it, and a **trust line** underneath: Verified · via Maria's link, Not verified, or **Warning** with the reason.
- **Their details** as the secretary learns them: company, reason, urgency.
- **Your secretary's briefing,** and whether she's listening or speaking.
- **Four buttons:** **Connect**, **Hold**, **Message** and **End**.
- **The menu (⋯):** **Spam: block and end** and **Impostor: block and end**.

Just talk. Your secretary hears you, answers your questions, and does what you say. See the [voice commands](#voice-commands) below.

### After a call

Open it from **Calls**. Each record shows:
- the AI summary and the outcome;
- the trust label;
- **How to reach them**: a number, email and best time, each with a button;
- your dictated tasks;
- the conversation.

From the record you can **block** or **unblock** the caller, or **delete** the record; its tasks stay in your list.

### Personal links

1. Open a contact, then **Personal link**, then **Send on WhatsApp**.
2. They get a message with their own link. When they call through it, you see **Verified**, and your secretary can say how you know them.
3. **Revoke link** makes the old link stop identifying them; **Send new** issues a fresh one.
4. **Always ring**: their calls ring even when you're away. **Never ring**: your secretary always takes a message instead. Both work only through the link, so nobody can get past your do-not-disturb by giving a name.

### Availability

| Mode | What callers get |
|---|---|
| **Available** | Calls ring. Messages are taken after 90 seconds if you don't act |
| **Busy for 30 min / 1 h / 2 h** | No ringing. After 12 seconds: "Kabeer isn't taking calls right now. He expects to be free after 3:00 PM." Then a message |
| **Do not disturb** | The same, without a time, until you switch it off |

---

## For owners: the owner page (any browser, iPhone included)

Open **`/owner`** on your line: **https://awaaz-demo.up.railway.app/owner** for the demo line, or your own gateway's address. Keep the page open and in front: it rings only while it's open.

### On the demo line

1. Press **Start taking calls** and allow the microphone.
2. The page gets its own line and shows its link (for example `…/?line=W83JSY`). **Copy** or **Share** it.
3. Open the link on another device and press Call. The page rings, and you play Kabeer.
4. Under **You** you can set availability, create **personal links** by name (each with "Always ring"), and see and unblock **blocked browsers**. These are kept in this browser.

### On the live line

1. Enter your **gateway secret**. Tick **Remember on this device** only on your own device.
2. Press **Start taking calls**. Availability, links and blocking stay in the phone app. The page never changes them.
3. If your phone is connected too, both ring. Answer on one.

### Taking a call

| When | Buttons |
|---|---|
| Ringing | **Answer** (talk to your secretary), **Put through**, **Message**, **End** |
| Answered | **Put through**, **Hold** (2 minutes), **Message**, **Mute**, **End**. Plus "Talk to your secretary" if she has stepped out, and on a demo line, "Impostor or spam: block and end" |
| On the call | **Mute**, **Hang up** |

**What the caller said** opens the conversation so far. **Recent calls** keeps each call in this browser, with its AI summary, call-back details and tasks.

Use headphones on a laptop, so your secretary doesn't hear herself.

---

## For judges: the demo app

1. Download **awaaz-demo.apk** from the [release](https://github.com/kabeerkhanniazi/awaaz-voice-secretary/releases/tag/demo-apk-1), open it on an Android phone, and allow installs from that source.
2. Open Awaaz, and allow the microphone and notifications.
3. The **Calls** tab shows **Your demo line** with its link. Open it on a laptop and press Call.
4. Answer on the phone and try the commands below.

Your line is yours alone: nobody else's calls reach it, and yours reach nobody else. Don't install the demo app on a phone that runs your own Awaaz: it would replace it.

---

## Voice commands

Talk to your secretary naturally. These are examples, not fixed phrases:

| You say | What happens |
|---|---|
| *"Who is it?"*, *"What do they want?"* | She tells you, from confirmed details only |
| *"Is it urgent?"*, *"What exactly does she need?"* | She answers from the call so far |
| *"Is anyone else waiting?"* | She tells you who else is on the line |
| *"Put her through"*, *"Connect me"* | She tells the caller she's connecting them, then you're talking directly |
| *"Ask him to hold for five minutes"* | The caller is asked to hold, and your screen counts down. At zero she checks in with them |
| *"Tell her I'm in a meeting and I'll call back in ten minutes"* | She says it to the caller in her own words: "Kabeer is in a meeting…" |
| *"Remind me to send the mockups by Friday"* | A task with Friday's date |
| *"End the call"*, *"I can't talk now"* | She takes a number and a good time from the caller, reads it back, and says goodbye |

You can talk over her; she stops and listens.
