# Devpost submission: Grasp

Everything to paste into Devpost, field by field. Fill in the bracketed parts (team names, video link) before submitting.

---

## Project name

Grasp

## Elevator pitch

Hand Grasp anything with numbers on it. It reads the page, shows where every number came from, lets you twist the numbers with your bare hands, and answers out loud.

## Thumbnail

`media/thumbnail.png` (1500 × 1000, 3:2)

---

## About the project

Paste everything between the lines into the "About the project" box. Devpost reads it as Markdown.

---

### Inspiration

"It's only $388 a month." That number is true, but only at 72 months, and the same contract costs $27,956 once you add it up. Students sign leases, phone plans, loans and aid letters every year without reading all of it, because let's be honest, nobody does.

Researchers have the same problem from the other side. Re-deriving a paper's numbers, reproducing its result, timing every step with a stopwatch, writing up what happened and checking whether an idea is new all take hours away from the experiment itself.

AI summaries look like a fix, but they ask you to trust numbers you can't check. We wanted the opposite: an assistant where **every number shows where it came from**, the math is done by real code, and you can grab the numbers with your hands and see what changes.

### What it does

Grasp is one engine. Hand it anything with numbers on it: hold a page up to the iPhone, open a photo or video on the Mac, or paste a YouTube link. It reads it, and from then on:

- **Receipts for every number.** Each fact keeps the exact words it came from, and Apple Vision finds those words on the photo. Hover any number for its crop of the page, or for a computed number, the formula and where each input came from.
- **Does it add up?** Every total, rate and percentage on the page is rechecked in Swift. A wrong one shows up as a red catch with the right number.
- **Hold it with your hands.** The Mac's webcam tracks both hands. Pinch to drag a card, twist your wrist like a dial to change a loan's term or a paper's cooling rate, push two offers together to compare them, give a thumbs up to put a card away, and pull two pinches apart to deep-dive into anything.
- **Ask it anything.** Make a fist or hold Space and ask, or press ⌘K and type it when the room is too loud. The answer is read aloud by ElevenLabs, with the source sentence highlighted on the page. Follow-ups work, and the numbers come from Swift calculator tools, never from the model.
- **Money.** A car contract becomes a true-cost chart: twist from 72 to 48 months and see $2,204 saved. Push in a credit union quote to compare, and Grasp tells you what to say to the dealer. A phone bill becomes a dispute letter ($42.00 to get back on our sample bill), and every page with money on it gets a "What to do" plan checked against current prices on the web, with sources.
- **Research.** A paper becomes a live model: its equation and each condition's rate, run in Swift, with every reported result re-derived. On our sample paper it catches a table row that its own equation contradicts. Push the model into the live cup chart and Grasp fits your cups' cooling rate, with an error bar, against the paper's.
- **A guided experiment.** Hand Grasp the protocol and say "I'm starting the experiment." Each step is read aloud and shown on the bench's LCD. The temperature probes confirm each pour, the phone's camera confirms what the probes can't, and you never touch the laptop: "done", "go back", "say that again" and "we're done" work hands-free.
- **The notebook writes itself.** While it records, Grasp keeps camera frames, what was said and every probe reading. Stopping writes the notebook: each step with its quote and what the probe did then, a Methods paragraph, the CSV, the transcript and a captioned time-lapse video.
- **Around the bench.** A method map of the paper (what was varied, measured, held the same and not controlled), related work from real OpenAlex papers with each next step marked "studied", "partly" or "looks open", and a page of handwritten notes checked line by line against the paper.
- **Study.** A lecture video or YouTube link becomes a page: a timestamped transcript, moments to jump to, and facts at the second they're said. Notes typed while it plays get the time.

Everything is saved to Tiger Data: pages, answers, notes, deep dives and lab notebooks as rows, and every probe reading in a TimescaleDB hypertable.

### How we built it

- **One Xcode project, three parts.** A macOS SwiftUI app is the brain and the canvas. A thin iOS app is the camera, sending frames to the Mac over Multipeer Connectivity, which works without the venue's Wi-Fi. A shared Swift package, GraspKit, holds the math, gesture logic, readers and link messages, with their tests.
- **Reading.** Every page goes to three readers at once: one for car offers, one for any page (facts, catches and a model, each with an exact quote), and Apple Vision for where every line of text is. Gemini 3.5 Flash-Lite with a JSON response schema reads a contract in about two seconds. A matcher ties each quote to its line on the photo, which is what makes every number hoverable.
- **Math.** All of it is Swift: loan payments, totals, the arithmetic check, Newton's law of cooling and least-squares fits of each cup's cooling rate with its standard error. The AI only reads and words things.
- **Hands.** Apple Vision hand pose gives 21 points per hand at about 30 frames a second. A gesture engine in GraspKit, unit tested, turns them into pinch, twist, push, fist, thumbs up, two-hand zoom, swipe and trash, with smoothing and hysteresis.
- **Voice.** Apple Speech for listening, ElevenLabs for speaking. Numbers are spelled out as words before they're spoken.
- **The web.** Gemini with Google Search grounding for deep dives and "What to do" (a finding is kept only if a web page backs it), and OpenAlex for related work.
- **The bench.** A Raspberry Pi Pico W running MicroPython reads two 10 kΩ thermistors sealed in straws, a DHT11 for room air, an I2C LCD and a buzzer, and talks to the Mac over USB serial. When no board is plugged in, a simulated bench speaks the same protocol, so every demo rehearses anywhere.
- **Storage.** We wrote our own Postgres client (TLS and SCRAM-SHA-256 sign-in) to keep the project free of third-party packages, and save to Tiger Data.

### Challenges we ran into

- **Models "fixing" numbers.** Asked to list a page's arithmetic, a model will sometimes quietly correct the wrong total it was supposed to catch. Now each input is labelled with its line, Swift rereads the number from that line, and a number only counts if it's on the page.
- **Telling a twist from a pinch or a fist.** Turning your wrist while pinching moves the pinch point and curls your fingers. Twist now locks in at 12° of rotation while the wrist or pinch stays put, and the pinch is measured against the palm as it was when the pinch started.
- **Two listeners, one microphone.** Push-to-talk started a second speech recognizer, which silently cut off the always-listening lab recorder. Now there is one listener while recording, it restarts the microphone if anything stops it, and bench commands are heard without a fist.
- **A hand holding a cup looks like a fist.** At the bench, gripping a kettle started voice commands. While recording, fist-to-talk is off and "done" just works.
- **Voice reading numbers wrong.** The fast ElevenLabs model misread digits, so money, percents, decimals and times go in as words.
- **Thermistors aren't waterproof.** We sealed them in straws with hot glue. That means keeping water under 60 °C and living with 10 to 30 seconds of lag, which shifts the curve but barely changes the fitted cooling rate.
- **Tiger Cloud's own certificate authority, and no packages.** We implemented the Postgres wire protocol, STARTTLS and SCRAM-SHA-256 sign-in ourselves.

### Accomplishments that we're proud of

- One engine handles a car loan, a phone bill, a research paper, a lab bench and a lecture video, with no modes.
- We planted six arithmetic mistakes across five test documents. Grasp caught all six in 3 of 3 runs, with no false alarms on the four correct pages.
- Four-question follow-up chains on those documents: 59 of 60 answers right.
- Grasp catches a result in our sample paper that the paper's own equation contradicts (the table says 25.9 minutes; its k gives 33.6), then fits your cups against the paper live.
- A guided experiment you can run with wet hands, start to finish, by voice.
- 183 offline tests, live test batteries against Gemini, and no third-party Swift packages.

### What we learned

- An AI people can trust shows its sources. Keeping the exact quote behind every fact did more for trust than any prompt.
- Keep the model away from arithmetic. Reading with a fast model and a schema, then checking in Swift, beat bigger models doing math.
- Design for the real setting: wet hands, a noisy hall, Wi-Fi that blocks device-to-device traffic, sensors that lag.

### What's next for Grasp

- **Rate check:** compare any APR with Federal Reserve averages.
- **Reads any display:** point the phone at a scale, multimeter or pH meter.
- **Ask your data:** "When did it drop below 40 °C?", answered with a marker on the chart.
- **Savings planner:** twist to see when you reach a goal.
- **More lab models**, like Arrhenius for reaction rates.

---

## Built with

Paste these as tags:

```
swift
swiftui
swift-charts
apple-vision
apple-speech
avfoundation
multipeer-connectivity
xcode
macos
ios
gemini
google-search-grounding
elevenlabs
tiger-data
timescaledb
postgresql
openalex
raspberry-pi-pico-w
micropython
thermistor
dht11
```

## "Try it out" links

- GitHub: https://github.com/SaatvikPradhan/Grasp
- Demo video: [YouTube link, 5 minutes]

## Image gallery

Upload in this order from `media/screens/` (each 1920 × 1280, 3:2). Captions:

| File | Caption |
|---|---|
| `01-twist-the-loan.png` | Twist your wrist to change the loan: 48 months saves $2,204 over the 72-month pitch. |
| `02-every-number-has-a-receipt.png` | Hover any number: the formula, and each input traced to its words on the contract. |
| `03-compare-two-offers.png` | Push the dealer's offer and a credit union quote together to compare them. |
| `04-what-to-say.png` | What to say to the dealer, read aloud, with every number computed by Grasp. |
| `05-catches-on-a-phone-bill.png` | A phone bill's catches, each with the spot on the page it came from. |
| `06-dispute-letter.png` | From the bill to a dispute letter: $42.00 to get back, each amount worked out from the bill. |
| `07-what-to-do.png` | What to do: how the bill compares with current prices, with sources, and steps tied to the lines they fix. |
| `08-ask-anything.png` | Ask out loud and get the answer with the sentence it came from. |
| `09-paper-to-live-model.png` | A paper becomes a live model, and Grasp catches a result its own equation contradicts. |
| `10-your-cups-vs-the-paper.png` | Your cups against the paper: each cup's cooling rate fitted with an error bar. |
| `11-guided-protocol.png` | A guided run of the two-cup protocol: steps read aloud, pours confirmed by the probes. |
| `12-lab-notebook.png` | The notebook writes itself: what was said and what each probe did at that moment. |
| `13-method-map.png` | A method map: what the paper varied, measured, held the same and didn't control. |
| `14-related-work.png` | Related work from OpenAlex, and which next steps look open. |
| `15-notes-checked.png` | Your notes checked against the paper: matches, differs, or not in it. |
| `16-video-study.png` | A lecture video becomes a page with moments and facts at the second they're said. |
| `17-deep-dive.png` | Zoom in with both hands for a deep dive with numbered web sources. |

## Before you submit

- [ ] Team members added: [team names]
- [ ] 5-minute demo video on YouTube, linked (script: `docs/VIDEO-SCRIPT.md`)
- [ ] Tracks: Grand Prize, FNB, Research, Nittany AI
- [ ] MLH prizes: Best Use of Gemini, ElevenLabs, Tiger Data, GoDaddy Registry (if the domain is registered)
- [ ] GitHub repository is public
