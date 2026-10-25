# Grasp: 5-minute YouTube video

One presenter on camera at the start and end, the Mac's screen for the demo, and a second camera (any phone on a stand) on the hands and the bench. About 600 words of talking, so there's room for Grasp's own voice and for the demo to breathe.

The rule for the whole video: **show it working, then say one line about why it matters.** Say the numbers your screen actually shows; Gemini's wording changes a little between takes.

---

## Before you record

- [ ] Keys in `Config/Secrets.xcconfig`, a fresh build of GraspMac, GraspPhone on the iPhone and connected ("Waiting for iPhone" is gone)
- [ ] Pico plugged in, Thonny closed, the cup chart says it's reading the board (not "Simulated probes")
- [ ] Printed: car contract, credit union quote, phone bill, research paper, paper notes, protocol (all in `props/`)
- [ ] Warm water at about 50 °C (never above 60 °C), two cups with the probes taped in, one lid, paper towels
- [ ] Mac: Do Not Disturb on, Dock hidden, volume up (Grasp's voice is part of the demo), no other copy of Grasp running
- [ ] Canvas cleared (⌘⇧⌫) before each segment
- [ ] Mic: AirPods or a clip-on mic for the presenter

Record each segment as its own take, then cut them together. It's fine to speed up the 2-minute wait in the experiment (show "2 minutes later" or 8× speed).

---

## The script

### 0:00 – 0:20 · The hook
**Camera:** presenter, holding the car contract.

> "Ever been told it's only three eighty-eight a month? Sounds fine. Let's hand the contract to Grasp."

**Do:** hold the contract up to the iPhone. Cut to the screen: the true-cost card.

> "Twenty-seven thousand, nine hundred and fifty-six dollars. Over six thousand of it is interest. Nobody reads the fine print. Grasp does."

### 0:20 – 0:40 · What Grasp is
**Screen:** the canvas with the loan card.

> "Grasp is one engine. Hand it anything with numbers on it: a contract, a bill, a research paper, even a lab bench. It reads it, shows where every number came from, lets you hold the numbers with your hands, and answers you out loud."

### 0:40 – 1:30 · Money: receipts, twist, compare, what to say
**Do:** hover the $27,956.

> "Every number has a receipt. Hover the total and you get the formula, and each input with the exact words it came from on the contract. Grasp's code does the math, not the AI."

**Do:** pinch the card and turn your wrist (film the hand with the second camera, cut between).

> "Now the fun part. Pinch, and turn your wrist like a dial. Forty-eight months: more a month, but two thousand two hundred dollars saved."

**Do:** hold up the credit union quote, then push the two cards together.

> "Here's a credit union quote at six point four percent. Push the two offers together to compare them."

**Do:** ⌘J. Let Grasp speak.

> "So what do I actually say to the dealer?"

*(Grasp reads its three questions aloud.)*

### 1:30 – 2:10 · Bills: catches, dispute, ask, type
**Do:** clear the canvas, hold up the phone bill.

> "Same engine, different page. A phone bill. The charges add up to one thirty-five thirty-two, but the bill says one forty-five thirty-two. Grasp rechecks every total, so it catches that."

**Do:** ⌘⇧W.

> "One shortcut writes the dispute: forty-two dollars to get back, every amount worked out from the bill itself."

**Do:** make a fist and ask "Why was I charged a late fee?", open your hand.

> "Ask it anything. Make a fist, talk, and it answers with the sentence it came from."

**Do:** ⌘K, type "Is this a good deal?", Return.

> "And in a loud room like a hackathon, press Command-K and just type. It checks the bill against today's prices on the web, with sources."

### 2:10 – 3:55 · Research: paper, experiment, notebook
**Do:** clear the canvas, hold up the research paper.

> "Grasp isn't only for money. This is a paper on how a lid slows a hot drink's cooling. Grasp turns it into a live model, running the paper's own equation."

**Do:** point at the red line on the model card.

> "And it caught something. The table says twenty-five point nine minutes for a ceramic cup with a lid, but the paper's own numbers give thirty-three point six."

**Do:** ⌘⇧M.

> "It maps the method too: what they changed, what they measured, and what they didn't control, like evaporation."

**Do:** hold up the protocol. Say "I'm starting the experiment." Cut to the second camera on the bench.

> "This is our bench: a Raspberry Pi Pico W with two sealed temperature probes, a room sensor and a little screen showing the step."

**Do:** pour into cup A (the probe jumps, the step ticks off), then into cup B and put the lid on.

> "Grasp reads each step out loud, and the probes confirm every pour. My hands are wet, so I don't touch anything. I just say..."

**Do:** say "done" for a step that needs it. Speed up the 2-minute wait.

**Do:** ⌘⇧B, or push the paper's model into the cup chart.

> "Now push the paper into our live data. Grasp fits each cup's cooling rate, with an error bar, and compares it with the paper."

*(Read the result on screen, e.g. which paper condition cup B matches.)*

**Do:** say "we're done".

> "Say 'we're done' and the notebook writes itself: every step, what was said, what each probe did at that moment, a Methods section, the data, and a time-lapse of the run."

**Do:** hold up the notes page, then type or say "Has anyone done this?"

> "Hand it your notes and it checks each one against the paper. Ask 'has anyone done this?' and it finds real papers and tells you which next steps are still open."

### 3:55 – 4:20 · Study and deep dive
**Do:** ⌘V a YouTube lecture link (or ⌘O `props/lecture-cooling.mp4`), hover a moment.

> "Studying? Paste a lecture. It becomes a page with moments you can jump to, and notes you type get the timestamp."

**Do:** zoom in with both hands over a catch.

> "And zoom in on anything with both hands to dig deeper on the web, every finding with its source."

### 4:20 – 4:45 · How it works
**Screen:** the deck's "How a page becomes cards" and "The AI reads. Swift does the math." slides.

> "Under the hood: a Mac app, an iPhone as the camera, and the Pico bench. Gemini reads the page. Every bit of math is done in Swift, so the numbers can't be made up. ElevenLabs is the voice, and Tiger Data stores every page, answer and reading. We planted six math mistakes in our test documents, and Grasp caught all six, every run."

### 4:45 – 5:00 · Close
**Camera:** presenter.

> "Grasp. Hand it anything. Because let's be honest: you ain't reading all that. Grasp is."

**End card (3 s):** GRASP logo, `github.com/SaatvikPradhan/Grasp`, [team names], HackPSU Fall 2026.

---

## If something fails on the day

- **No hot water allowed:** use the simulated bench (Bench menu pours, lids and ices for you) and say so in one line: "here on the simulated bench."
- **Board won't connect:** same; the guided run works the same way on simulated probes.
- **Voice misheard:** use ⌘K and type it. That's a feature, so show it.
- **A Gemini read comes out odd:** redo the take; don't edit numbers in post.

## YouTube title and description

**Title:** Grasp: hand it anything, hold the numbers (HackPSU Fall 2026)

**Description:**

```
Grasp reads anything with numbers on it (a car contract, a phone bill, a research paper, a lab bench), shows where every number came from, lets you twist the numbers with your bare hands, and answers out loud. Built at HackPSU Fall 2026.

0:00 The $388-a-month pitch
0:20 What Grasp is
0:40 Every number has a receipt, twist the loan, compare offers
1:30 A phone bill: catches, dispute letter, ask by voice or typing
2:10 A research paper becomes a live model; a guided experiment on our bench
3:55 Lectures and deep dives
4:20 How it works

Code: https://github.com/SaatvikPradhan/Grasp
Built with Swift, Apple Vision, Gemini, ElevenLabs, Tiger Data and a Raspberry Pi Pico W.
```
