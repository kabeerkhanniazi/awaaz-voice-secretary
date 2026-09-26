# Frequently asked questions

### What is Awaaz, in one sentence?

An AI secretary that answers your calls, briefs you privately by voice while the caller is still on the line, and does what you say: put them through, hold, pass on a message, or take one.

### How is it different from an AI receptionist?

| | Replaces you | Reports to you afterwards | **You decide during the call** |
|---|---|---|---|
| Voicemail and call-summary tools | | ✓ | |
| AI receptionists | ✓ | ✓ | |
| **Awaaz** | | ✓ (records and tasks) | **✓, by voice, mid-call, and it can put the caller through** |

The AI talks to **both** people: one agent screens the caller, and a second, private one talks with you.

### Is the demo real?

Yes. **https://aivs.up.railway.app** rings Kabeer's actual phone. If he's busy, the secretary takes your message. The demo line and the owner page let you play the owner yourself.

### Why is the caller on a web page and not a phone number?

- A link costs nothing to run and works in any browser.
- It's exactly the "call me" button people put on portfolios, LinkedIn and email signatures, which is the first use case.
- A real phone number is a new front door on the same system, and it's on the [roadmap](ROADMAP.md).

### Do I need an Android phone to try the owner side?

No. Open **https://awaaz-demo.up.railway.app/owner** on any device, iPhone included, press Start, and call the link it shows from another device. With an Android phone, you can install the [demo app](https://github.com/kabeerkhanniazi/awaaz-voice-secretary/releases/tag/demo-apk-1) instead, which also rings over the lock screen.

### How do you know who's really calling?

- **Only a personal link verifies.** You send a contact their own link, and a call through it shows "Verified · via Maria's link".
- **Anyone else is "Not verified"**, even if their name matches a contact.
- **Warnings** flag a browser that called before under another name, a link used with the wrong name, and old links.
- **Scam patterns** are flagged too: claimed authority with urgency, or asking for money or codes.

See [SECURITY.md](SECURITY.md).

### What if I don't answer?

After 90 seconds the secretary takes a message. She always gets a way to reach the caller (a number or email and the best time), reads it back, and confirms it. You get a "Call back" task that dials in one tap.

### What if I'm busy or asleep?

Set **Busy** or **Do not disturb**. Calls stop ringing, and the secretary takes messages after 12 seconds, telling callers when you'll be free. Contacts you trust can be set to **always ring**, but only through their personal link.

### What if two people call at once?

The second caller gets their own secretary and waits. Your secretary knows who's waiting, and they come up as soon as your current call ends.

### Can the secretary be tricked into giving out my details?

She's instructed never to share your whereabouts, schedule, contacts or numbers, and to agree to nothing when a caller claims authority. That was tested live: asked where Kabeer was and for his number, she declined.

### Does the AI listen to the call after I pick up?

No. When you say "put her through", the caller's AI session ends, your secretary steps out, and the gateway relays the audio directly between the two of you.

### Is the call recorded?

Audio isn't stored. The call record keeps the transcript of the secretary's conversation, the details, a summary and your tasks, on your phone (or in the owner page's browser).

### What does a call cost?

AssemblyAI's Voice Agent API is $4.50 per hour. A typical screened call (about 1.5 minutes with the caller, plus about 1 minute with you) comes to about **$0.19**. Once you're connected, the bridge costs nothing.

### Does it speak Urdu?

Not yet. The Voice Agent API speaks English, Spanish, French, German, Italian and Portuguese, so the secretary asks other callers to continue in English or to leave a number. Urdu, including mixed Urdu and English, is next on the [roadmap](ROADMAP.md), using AssemblyAI's real-time transcription, which understands Urdu.

### Can I run it for myself?

Yes. It's MIT licensed. See [DEPLOYMENT.md](DEPLOYMENT.md): set your AssemblyAI key and a secret, change the owner's name in the prompts, and deploy the `gateway/` folder.

### Why "Awaaz"?

*Awaaz* means "voice" in Urdu. The project began on 26 August 2026 as "Vox Sonus", and was renamed the same day.

### Who built it?

Kabeer Khan Niazi, solo, in Pakistan, for the lablab.ai AssemblyAI Voice Agent Hackathon (September 2026). Contact: mu.kabir2004@gmail.com, or just [call](https://aivs.up.railway.app).
