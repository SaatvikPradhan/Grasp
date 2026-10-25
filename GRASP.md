# Grasp: HackPSU project brief

> **Grab what you see and hear. Understand it with your hands.**
>
> Grasp listens to what is said, reads the paper or experiment in front of it, and turns the numbers into charts on a laptop. You work the charts with bare hands: pinch to grab, twist to dial a value, push two charts together to compare. One engine, two modes: **Research** (lab bench to notebook) and **Money** (the moment you sign a loan).

This file is the single source of truth for the project. Give it to a new Claude Code session (see "First prompt for a new session" at the end) and keep it in the repo root.

---

## 0. TL;DR

| | |
|---|---|
| **Product** | Grasp: a laptop canvas you control with hand gestures, an iPhone "eye", and live sensors |
| **Stack** | One Xcode project: macOS app (brain, ~80% of code) + thin iOS app (camera) + shared Swift package `GraspKit`. Arduino or ESP32 for sensors. Gemini for all AI. ElevenLabs for voice. |
| **Tracks entered** | Grand Prize, FNB, Research, Nittany AI, plus MLH side prizes |
| **Estimated odds** | 94% at least one prize, 84% at least one cash prize (model estimates, see section 1) |
| **Research demo** | Iodine clock reaction in 3 cups at 3 temperatures; camera times the color change; probes log temperatures; twist to fit activation energy (Arrhenius); notebook writes itself |
| **Money demo** | Car salesperson says "$388 a month"; Grasp reads the contract, charts the true cost ($27,956), you twist to 48 months (save $2,204), push in a credit union quote (save $3,416), it says what to ask for, a printer prints "The Real Receipt" |
| **Domain** | Top pick `aintreadingallthat.co`, or `touchgrasp.co` (check which extensions the GoDaddy Registry code covers) |
| **Live pages** | Explainer: https://claude.ai/artifact/PThBpnPrBbxVm6BhNjpg1t · Build plan checklist: https://claude.ai/artifact/53z9ido8enZMBRCp5nrjj6 · Odds board: https://claude.ai/artifact/GQud6vrTmdpNLqQM2LcXcV |

---

## 1. Event, tracks and odds

**Judging:** Grand Prize is judged by **undergrads** (non-technical). **FNB** and **Research** have **their own judges** (FNB staff, research judges). Lead each panel with its own story.

| Track | Prize | Judged by | Lead with | Est. odds |
|---|---|---|---|---|
| Grand Prize (top 3) | $2,000 / $1,000 / $500 | Undergrads | 30-second hands demo (car loan + twist) | 46% |
| FNB | $1,500 | FNB staff | Money mode, car loan, Real Receipt | 44% |
| Research | $1,500 | Research judges | Research mode, iodine clock + Arrhenius | 49% |
| Nittany AI (top 3) | $99 / $50 / $25 gift card per member | Nittany AI | Real AI use, helps students | 62% |
| Mystery Stack | $1,500 | — | **Not entered** (requires a phone-motion group game for 4+) | — |
| AI Strategy Case | $500 | — | **Not eligible** (no-code teams only) | — |

- At least one prize: **94%**. At least one cash prize: **84%**. Prize money if it wins every entered track (team of 4): **$5,396**.
- Assumptions: top-tier build; 40 / 12 / 10 / 25 teams with working demos in Grand / FNB / Research / Nittany AI; Plackett–Luce model, strength = fit × execution × build ease × demo. These are judgment-based estimates, useful for comparing ideas, not exact odds.

**MLH side prizes** (not in the odds): Gemini (use for every AI call), ElevenLabs (Grasp's voice), Tiger Data (store sessions and readings), Vultr (host share links), GoDaddy Registry (domain), DEV writing challenge ($100, post after the event).

**Deadline:** last fall, Devpost was due **12:00 PM Sunday**. Confirm this year's time at the help desk.

---

## 2. The product

- **Name:** Grasp. You grab charts with your hand, and you grasp what the numbers mean.
- **Tagline:** Grab what you see and hear. Understand it with your hands.
- **Closing line:** "Because let's be honest, you ain't reading all that. Grasp is."

### The loop (every feature runs through it)

| Step | What happens | Tech |
|---|---|---|
| **Hear** | Transcribes speech, catches numbers and commands ("fit it", "just $388 a month") | Apple Speech + Gemini |
| **See** | iPhone reads what you hold up or what is on the bench: contract, figure, equation, cups | Gemini vision (+ Apple Vision text for boxes) |
| **Chart** | Numbers become charts and live models, source shown under each | Swift Charts |
| **Grab** | Laptop webcam tracks 21 points per hand; move, dial, merge, switch charts in the air | Apple Vision hand pose |
| **Act** | Answers out loud, exports notebook or one-page summary | ElevenLabs + export |

### The rig

| Piece | Role | Details |
|---|---|---|
| **Laptop (Mac)** | The canvas | macOS SwiftUI app. Shows everything. Webcam tracks hands. Reads sensors over USB. Calls Gemini. Mirror to a TV if available. |
| **iPhone** | The eye | Thin iOS app. Hold up to a contract, or stand it over the bench. Sends frames to the Mac over Multipeer Connectivity. Shows highlights sent back. |
| **Sensors** | Live data | 3× DS18B20 probes on an ESP32 (or Arduino) over USB. LED strip. Optional receipt printer. |

---

## 3. Features

Tags: **[Demo]** build for the demo · **[If time]** · **[Next]** pitch as future.

### Research mode
- **[Demo] Live sensor charts.** Any Arduino sensor; readings chart themselves once a second.
- **[Demo] Protocol watcher.** Load steps; the overhead camera checks each one; marks skipped or late steps on the chart.
- **[Demo] Voice notes on the timeline.** "Lid on" drops a labeled marker at that second.
- **[Demo] Figure to data.** Hold up a figure from a paper or textbook; its points come out as data to overlay.
- **[Demo] Equation to live model.** Hold up an equation; twist to set parameters; "fit it" runs least squares with error bars.
- **[Demo] Compare runs.** Push two charts together: your run vs the paper, today vs yesterday.
- **[Demo] Reproducible export.** Notebook (log, data, figures, fit) + CSVs + Jupyter file that reruns the analysis + **Methods paragraph and figure caption** written from the log.
- **[Demo] The notebook writes itself.** Camera logs meaningful actions (poured, lid on, stirred) with a thumbnail and a chart marker.
- **[If time] Reads any display.** Point the phone at a scale, multimeter or pH meter.
- **[If time] Ask your data.** "When did it drop below 40 degrees?" Answer plus marker.
- **[If time] Cites what you showed it.** Reads title or DOI, adds citation via OpenAlex.
- **[Next] Replay.** Scrub the timeline: bench photo and data at the same moment. (Build if time; strong for research judges.)

### Money mode
Built (Oct 24): offer reader, add-ons merged across contract and sticker, true-cost chart, twist, compare, hears the pitch (consent prompt, `PitchChecker`), what to say (Gemini wording checked against Swift's numbers, read aloud by ElevenLabs), decision summary PDF (⌘E). Money menu: ⌘J what to say, ⌘⇧L listen to the salesperson.

- **[Demo] Offer reader.** Car loans, leases, credit card offers, BNPL, aid letters: rate, term, fees, penalties.
- **[Demo] Add-on fee spotter.** Paint protection, nitrogen tires, large doc fees.
- **[Demo] True-cost chart.** Amount financed vs interest.
- **[Demo] Twist the terms.** Term, down payment, rate, extra payment.
- **[Demo] Compare two offers.** Push dealer financing and a credit union quote together.
- **[Demo] Hears the pitch.** With consent, pins spoken numbers and checks them against the paper ("$388 a month, but for 72 months").
- **[Demo] What to say.** Short list of questions, read aloud.
- **[Demo] Decision summary.** One page with numbers, sources, the choice.
- **[If time] Pressure check.** Flags "this price ends today"; phone buzzes with a calm reminder.
- **[If time] Rate check.** Compare APR with Federal Reserve averages from FRED.
- **[If time] Chart check.** Hold up a fund ad; flag a cherry-picked window; show full history.
- **[Next] Savings planner.** Income and costs; twist to see when you reach a goal.

---

## 4. Gestures

| Gesture | You do | It does | Detection (suggested starting values) |
|---|---|---|---|
| **Pinch and drag** | Thumb to index, move, release | Grab and move the chart under the hand | Thumb-to-index gap over palm length (wrist → middle knuckle): enter < 0.30, exit > 0.45 (hysteresis); built, sliders in the ⌘D panel |
| **Twist** | Pinch, then rotate wrist like a knob | Dial a value (term, rate, k, Ea) | Angle of vector wrist → middleMCP; map delta angle to value with a gain; snap to steps where useful |
| **Push together** | Pinch one chart with each hand, bring hands together | Merge two charts into one comparison | Built as overlap: two loan cards light up green at 15% overlap and merge at 45% (works with one hand, two hands or the mouse) |
| **Fist** | Close your hand like gripping a mic | Talk to Grasp; open the hand to send (Space works too) | Built: index tip < 1.25 palm lengths from the wrist and the other tips < 1.2, held 0.25 s; a fist never starts a pinch |
| **Trash** | Drag a card to the bin (bottom right, shows while holding) | Delete the card | Built: let go within 110 pt of the bin; ⌫ deletes the front card, ⌘⇧⌫ clears all |
| **Swipe** | Open hand sweeps sideways | Switch chart type (line ↔ bar) | Built: fingertips ≥ 1.5 palm lengths from the wrist, wrist moves ≥ 0.22 of the canvas sideways within 0.35 s, 0.8 s cooldown |

- `VNDetectHumanHandPoseRequest`, `maximumHandCount = 2`, run on webcam frames at ~30 fps.
- Mirror front-camera x. Smooth positions (exponential moving average α≈0.4, or a One Euro filter).
- **On-screen hand cursor, 4 states:** open hand (gray ring follows hand), over a chart (green ring), pinch (orange ring with two dots), twist (orange arc showing the value).

---

## 5. Demo scripts

### Grand Prize: 30 seconds (undergrad judges). Lead with the hands.
1. **0:00** "Ever been told it's only $388 a month?" Hold the contract up to the iPhone. The total-cost chart appears on the laptop.
2. **0:10** Twist your hand like a dial. The term shrinks, interest falls, "$2,204 saved" pops up.
3. **0:20** Grab both loan charts and push them together. Grasp says out loud what to ask the dealer.
4. **0:28** "Same hands work in the lab." Point at the live chart on the bench, then **hand a judge the controls**.

### FNB: 90 seconds (FNB judges)
FNB asks how to help people at the moments that matter most: information → understanding → confidence → action.
1. **0:00 The pitch.** A teammate plays the salesperson: "We can get you in at just $388 a month." With consent, Grasp pins the number.
2. **0:20 Read the paper.** Scan the window add-on sticker (flags $1,194 of add-ons) and the contract: $21,600 at 8.9% for 72 months. True cost: **$27,956**, including **$6,356** interest.
3. **0:45 Twist to compare.** 48 months: payment **$536**, interest **$4,152**, saving **$2,204**. LED strip fills red with interest as the term grows. Push in a 6.4% credit union quote: saving grows to **$3,416**.
4. **1:05 Check the numbers.** "$388 only holds for 72 months." Doc fee and paint protection can be removed.
5. **1:20 What to say.** Grasp answers aloud: ask for the out-the-door price, 48 months without add-ons, and a match to the credit union rate. **The printer prints "The Real Receipt"**; hand it to the judge.

Props: toy car or cardboard door with printed window sticker + dealer add-on sticker ("Nitrogen tires $299, Paint protection $895"), printed contract (2 copies), credit union quote card ("Pre-approved 6.4%"), teammate as salesperson, LED strip, receipt printer.

### Research: 3 minutes (research judges)
The Research track asks for a tool that removes a bottleneck. Grasp removes several: stopwatch timing, hand notes, hand plotting, digitizing a textbook figure, re-coding its model, writing the Methods.
1. **0:00 Setup.** 3 cups on the printed mat: **A warm (~40 °C), B room, C cold**, probe in each. Live temperatures on the canvas. "Grasp, start the clock reaction."
2. **0:15 Pour.** Grasp logs each pour time automatically (the hard part to do by hand).
3. **0:20–1:30 The snaps.** Cups turn dark blue one after another: A first (~20 s), B (~45 s), C (~90 s). Each snap: marker, "Cup A turned at 0:36 at 38.2 °C", LED strip flashes.
4. **1:40 The law.** Hold up the Arrhenius equation. Grasp plots ln(1/t) vs 1/T. Twist to set Ea, or say "fit it". Report Ea in kJ/mol with an error bar. Push against the textbook value to compare.
5. **2:40 Write it up.** Say "export." Notebook with protocol log, temperatures, times, plot, Ea, Methods paragraph, Jupyter file. Judges scan a QR to open it.

**Backup experiment** (no chemicals allowed / pharmacy closed): **ice and salt**, 3 cups of ice water: A plain (~0 °C), B + salt (drops below zero within a minute), C + same amount of sugar (barely drops). Model: freezing-point depression ΔT = i·K_f·m (K_f water = 1.86 °C·kg/mol; i ≈ 2 for NaCl, 1 for sugar). Twist to set salt concentration until the model matches.

---

## 6. Architecture

### Project layout (one Xcode project)
```
Grasp/
├─ Grasp.xcodeproj        GraspMac + GraspPhone targets (folder-synced groups)
├─ Config/                Base.xcconfig, Secrets.xcconfig (git-ignored keys), Info.plists
├─ GraspKit/              Swift package shared by both apps
│  ├─ Models/             Reading, LabEvent, LoanTerms, ChartSpec, CupState, Session
│  ├─ Math/               LoanMath, OneEuroFilter, LeastSquares, Arrhenius, FreezingPoint
│  ├─ Gestures/           HandSample, GestureEngine (pure logic, unit tested; reusable on the iPhone fallback)
│  ├─ Hardware/           ProbeProtocol (serial lines ↔ messages), SimulatedBench
│  ├─ AI/                 APIKeys, GeminiClient (+ JSON schemas), Prompts
│  └─ Link/               LinkMessage (Codable), MultipeerLink
├─ GraspMac/              macOS app (the brain)
│  ├─ Canvas/             CanvasModel, Card (loan, comparison, temperatures, scan), card views, HandCursor, CanvasSnapshot
│  ├─ Hands/              WebcamCapture, HandTracker (Vision), HandPipeline, debug panel
│  ├─ Voice/              SpeechListener (SFSpeechRecognizer), VoiceController (hold Space), VoiceBar; VoiceOut (ElevenLabs) next
│  ├─ Hardware/           SerialPort, ProbeSource (+ SimulatedProbeSource), LEDStrip, ReceiptPrinter
│  ├─ Modes/              PaperReader + PageText (Gemini reads, Vision boxes), PaperPanel; ResearchMode, MoneyMode next
│  ├─ Bench/              CupColorTimer (pixel averages per mat circle), ActionLogger
│  └─ Export/             NotebookExporter (MD, CSV, .ipynb, Methods), SummaryPDF, QR
├─ GraspPhone/            iOS app (the eye)
│  ├─ CameraView (+ scan result with highlights), FrameSender (~4 fps live + sharp capture), PhoneModel
│  ├─ HighlightOverlay (boxes sent back from the Mac), FlingDetector (hold still on the paper, then flick the top away; Flick on/off button)
│  └─ PressureBuzz (haptics on message)
└─ firmware/              Arduino or ESP32 sketch
```

### Phone ↔ Mac link: Multipeer Connectivity
- Works over peer-to-peer Wi-Fi and Bluetooth without the venue network (hackathon Wi-Fi often blocks device-to-device traffic).
- Service type `grasp-link`. The Mac advertises and accepts; the phone joins the first Mac it finds.
- Everything is `.reliable`. Live frames (720 px, ~15 KB, ~4 fps) go one at a time: the next waits for the Mac's `received`, so a slow link drops frames instead of lagging. Captures (2000 px, ~60 KB) skip the queue.
- The simulator has no camera, so GraspPhone sends numbered test frames there: run it in the simulator to test the link without an iPhone.
- Built so far (`GraspKit/Link`): `frame(LinkFrame)` and `received(frameID, sentAt)`, as binary plists (JPEG bytes stay raw). Add the rest as features need them.
- Planned messages:
  - Phone → Mac: `hello(device)`, `frame(jpeg, ts, purpose: live|capture)`, `fling(captureId)`
  - Mac → Phone: `highlights([{text, rect, kind: term|addon}])`, `buzz(message)`, `status(text)`
- **Fallbacks:** Continuity Camera (zero iPhone code; Desk View shows the table from above), then the phone's hotspot + a small local WebSocket.

### Serial protocol (USB, 115200 baud, one line per message)
- Board → Mac: `READY`, `T,<cup>,<celsius>` every second (e.g. `T,A,38.25`)
- Mac → Board: `LED,<r>,<g>,<b>` (fill), `FLASH,<r>,<g>,<b>,<ms>`, `METER,<0..1>` (fill strip red proportionally), `PRINT,<text line>` … `PRINTEND`
- Start with `SimulatedProbeSource` behind the same protocol so research work does not wait on hardware.

### AI (Gemini for every call)
Use `gemini-3.5-flash-lite` with `thinkingLevel: minimal` and a response schema (`GeminiClient.fastModel`). On Oct 24 it read the demo contract perfectly in ~1.5 s, even tilted and low quality; `gemini-3.8-flash` was equally accurate but ~4.5 s (and rejects `minimal`; use `low`). Send small JPEGs. Numbers are always computed in Swift, never by the AI.

| Call | Input | Output (JSON) |
|---|---|---|
| Contract reader (`OfferReader`, built) | Photo (Vision text lines later, for highlight boxes) | `{document_type, cash_price, fees:[{name, amount, is_addon}], down_payment, amount_financed, apr_percent, term_months, monthly_payment}`; Swift checks the payment and itemization add up |
| Highlight matching | Field values + Vision line boxes | Done on device: match values to recognized text lines, send boxes to phone |
| Action logger | Overhead frame + protocol steps + labeled objects + last state | `{event: null}` or `{event: {action, object, step_id, confidence}}` |
| Figure to data | Photo of a figure | `{x_label, y_label, points:[[x,y],…]}` (show for confirmation) |
| Equation reader | Photo of an equation | `{latex, model_id: arrhenius|newton_cooling|freezing_point|loan, params:[…]}` |
| Voice command | Transcript | Function call: `plot`, `fit`, `set_param`, `compare`, `export`, `explain`, `what_to_say` |
| What to say / Methods | Facts computed in Swift (+ log) | Short text |

- **Cup color timing is on device, not AI:** average pixel color inside each mat circle every frame; normalize against the mat's white and blue reference squares; the snap is when "blueness" crosses a threshold. Fast and reliable.
- **Action logger efficiency:** only call Gemini when on-device hand tracking sees a hand near an object.

### Exports and sharing
- Notebook (Markdown → PDF), CSVs, `.ipynb` (load CSV, fit, plot), Methods paragraph, decision summary.
- QR codes with Core Image `CIQRCodeGenerator`. Host share pages on a small Vultr server under your domain. Store sessions and readings in Tiger Data (Postgres) or local SQLite first.

---

## 7. Math

### Loan
Monthly payment: `M = P·r / (1 − (1 + r)^(−n))`, with `r = APR / 12`, `n` = months.

Demo contract: cash price $19,900 + doc fee $499 + paint protection $895 + tax and title $1,306 − down payment $1,000 = **$21,600 financed**.

| Option | Monthly | Total paid | Interest | vs 72-month pitch |
|---|---|---|---|---|
| 72 mo @ 8.9% | $388.28 | $27,956 | $6,356 | — |
| 60 mo @ 8.9% | $447.33 | $26,840 | $5,240 | saves $1,116 |
| 48 mo @ 8.9% | $536.49 | $25,752 | $4,152 | saves $2,204 |
| 48 mo @ 6.4% (credit union) | $511.25 | $24,540 | $2,940 | saves $3,416 |

Window sticker add-ons: nitrogen tires $299 + paint protection $895 = **$1,194**. Contract add-ons: doc fee $499 + paint protection $895 = **$1,394**.

Rate check (if time): FRED has commercial-bank new-car loan rate series (e.g. `TERMCBAUTO48NS`); verify the series ID on fred.stlouisfed.org.

### Arrhenius (research demo)
- Rate is proportional to 1/t (t = seconds until the cup turns blue).
- `ln(1/t) = ln A − (Ea/R)·(1/T)`, T in kelvin, R = 8.314 J/(mol·K).
- Linear least squares on (1/T, ln(1/t)); `Ea = −slope × R`; report ± from the slope's standard error. Three points give a rough value; say so.
- Twist sets Ea and redraws the model line; "fit it" snaps to the least-squares value.

---

## 8. Hardware

### From the MLH hardware table
| Item | Qty | Priority | Notes |
|---|---|---|---|
| **ESP32 dev board** | 1 (+1 spare) | Must | Several serial ports: probes + LED + printer on one board |
| Arduino Uno/Nano (if no ESP32) | 2 | Must | One for probes + LED, one for printer |
| **DS18B20 waterproof temperature probe** | 3 (+1 spare) | Must | All share one data wire |
| **4.7 kΩ resistor** | 2 | Must | Pull-up for the probe data line |
| **WS2812 / NeoPixel strip or ring, 8–16 LEDs** | 1 | Nice | Cup flashes + money meter |
| 330 Ω resistor | 1 | Nice | On the LED data line |
| **Thermal receipt printer** (Adafruit mini type, TTL) | 1 | Nice | "The Real Receipt" |
| 5 V 2 A power supply + barrel jack adapter | 1 | Nice | Printer needs its own power |
| Half-size breadboard | 2 | Must | |
| Jumper wires (M-M, M-F) | ~30 | Must | |
| USB cables for the boards | 2 | Must | |
| **USB-C hub with 2+ USB-A ports** | 1 | Must | MacBooks only have USB-C |
| Phone stand / gooseneck clamp | 1 | Must | iPhone over the cups |
| Raspberry Pi | 1 | Backup | Only if a board dies; skip otherwise (OS setup + venue Wi-Fi risk) |

**Test before leaving the table:** each probe reads, the printer powers on.

### Wiring
- **DS18B20 (all 3 in parallel):** red → 3.3 V (ESP32) or 5 V (Uno); black → GND; yellow → one data pin (e.g. GPIO4 / D2); **4.7 kΩ between data and VCC**. Libraries: `OneWire`, `DallasTemperature`. Print each probe's address at startup and map them to cups A, B, C.
- **WS2812:** data pin through 330 Ω; 5 V and GND; ≤16 LEDs at low brightness (≤40/255) to stay on USB power. Library: `Adafruit_NeoPixel`.
- **Thermal printer:** TTL serial at 19200 baud; ESP32 `Serial2` (e.g. GPIO16/17), Uno `SoftwareSerial`; separate 5 V 2 A supply; **common ground** with the board. Library: `Adafruit_Thermal`.

### Pharmacy run (iodine clock)
Vitamin C tablets 1000 mg · Iodine tincture 2% · Hydrogen peroxide 3% · Liquid laundry starch (or cornstarch) · Oral medicine syringes 5–10 mL ×4 · Nitrile gloves.

### Food area / store
9 small clear cups · tray · paper towels · spoon · ice · hot water · salt packets (backup) · tape and marker (label A, B, C).

### To print
Cup mat (circles A, B, C + **white and blue reference squares**) · Arrhenius equation card + a textbook Ea value · car contract ×2 (`props/contract.html`, open in a browser and print) · window sticker + dealer add-on sticker · credit union quote card · toy car or cardboard car door.

### Iodine clock: starting recipe (tune by rehearsal)
- **Stock:** crush one 1000 mg vitamin C tablet into 60 mL warm water.
- **Solution A (per cup):** 5 mL stock + 60 mL water + 5 mL 2% iodine → turns clear.
- **Solution B (per cup):** 60 mL water + 15 mL 3% hydrogen peroxide + 2.5 mL liquid starch.
- Pour B into A, swirl. After a delay it snaps dark blue. Warmer = faster: set temperatures with warm and ice water baths for both solutions.
- Adjust volumes until A ≈ 20 s, B ≈ 45 s, C ≈ 90 s. Use syringes for repeatable volumes.
- **Safety:** gloves, tray, nothing near the laptop, no drinking, iodine stains, rinse down the sink with lots of water. **Ask organizers first.** If not allowed, use the ice and salt backup.

---

## 9. Build plan (24 hours)

Hours count from when you start. Live checklist with clock times: https://claude.ai/artifact/53z9ido8enZMBRCp5nrjj6

### Go / no-go gates (hours 0.5–3)
| Gate | Pass when | If it fails |
|---|---|---|
| **G1** Hands move a chart | Pinch and drag a chart at 30 fps with Vision on the Mac webcam | iPhone front camera for hands, or a Leap Motion; last resort trackpad gestures |
| **G2** Phone reaches the Mac | iPhone frame appears on the Mac within 300 ms over Multipeer | Continuity Camera, then phone hotspot + local server |
| **G3** Gemini reads a frame | Contract photos → correct JSON terms; cup photo → lid on/off | On-device Vision text + number parsing; pixel averages for cups |
| **G4** Probes reach the Mac | Three temperatures over USB once a second (when sensors arrive) | Swap probe or board, or Raspberry Pi; keep the simulated source |

### Blocks
- **0:00–0:30 Setup** — Xcode project (macOS + iOS + GraspKit) · Gemini and ElevenLabs keys in a git-ignored config · git repo + first commit · claim MLH codes, register the domain
- **0:30–3:00 Go/no-go** — G1 · G2 · G3 · simulated probe source (same interface as the real one) · G4 when sensors arrive
- **3:00–8:00 Shared loop** — canvas with spring-motion chart cards + 4 cursor states · gestures with smoothing · voice → command → chart via Gemini function calls · phone scanner with highlights from the Mac · **fling to send** (flick the phone, the scan flies onto the canvas)
- **8:00–12:00 Money mode** — contract → loan model in Swift · add-on flags (contract + window sticker) · true-cost chart, twist the term, push in credit union quote · spoken-number check · "what to say" with ElevenLabs · one-page summary
- **12:00–13:00 Rehearse FNB** — full 90 s FNB script with props; 30 s Grand opener
- **13:00–18:00 Research mode** — firmware (3 probes out, LED commands in) · Mac serial reader → live charts · cup mat + color timing · action log with thumbnails + markers · Arrhenius plot, twist/fit, error bars, textbook compare · export (notebook, CSV, .ipynb, Methods) · tune iodine clock to ~20 / 45 / 90 s
- **18:00–21:00 Wow layer (in this order)** — LED cup flashes + money meter · receipt printer · replay scrubber · pressure-alert buzz · QR share links on your domain
- **21:00–24:00 Freeze, rehearse, submit** — feature freeze · demo-mode hotkeys that load the last good run of each act (labeled as replay) · rehearse each script 10× · backup video of every demo · Devpost (tagline, video < 2 min, screenshots, all four tracks + MLH categories) · practice 3 pitches · pack and charge everything

**Sleep:** if you sleep, take 90 minutes after Research mode and cut from the wow layer. Never before the gates pass.

### Cut order if behind
1. Chart merging (show side by side) → 2. Replay scrubber → 3. Pressure alert (say it aloud) → 4. Receipt printer (page + QR) → 5. Textbook figure act → 6. Voice (big on-screen text).
**Never cut:** the hands, the live probe chart, contract reading, the twist.

### Top upgrades (impact for effort)
1. Hand the judge the controls (free) · 2. Fling to send (1 h) · 3. Reaction snaps on cue with LED flash · 4. Notebook writes itself (2 h) · 5. Methods section in one click (30 min) · 6. Money meter LED (1 h) · 7. The Real Receipt (2 h) · 8. Replay (2 h) · 9. Pressure alert (1 h) · 10. QR links on your domain (1 h)

---

## 10. Risks and backups

| Risk | Backup |
|---|---|
| Venue Wi-Fi blocks phone ↔ laptop | Multipeer works without it; then Continuity Camera; then phone hotspot |
| Gemini slow | Fast model, small frames, short "reading" animation, cache results for demo props |
| Hand tracking jitter | Smoothing, higher pinch threshold, no bright window behind you |
| Hall noise breaks voice | AirPods mic + push-to-talk key |
| Chemicals not allowed | Ice and salt version, same probes and flow |
| Color readings drift | Reference squares on the mat, phone fixed, same lighting |
| No receipt printer | Receipt as a page + QR |
| A live act fails on stage | Demo-mode hotkey loads the last good run, labeled as a replay |
| Recording consent (Pennsylvania requires everyone's consent) | Money mode listens only with consent, or works from documents and your own voice |

---

## 11. Pitch lines and judge questions

- **Grand opener:** "Ever been told it's only $388 a month?"
- **FNB close:** "Grasp turns the paper in front of you into a decision you understand, then tells you what to say." (hand over The Real Receipt)
- **Research close:** "From bench to Methods section without touching a keyboard."
- **Everyone:** "Because let's be honest, you ain't reading all that. Grasp is."

| Question | Answer |
|---|---|
| Isn't this just Jarvis? | Jarvis is fiction. Grasp works from the paper, bench and sensors in front of you; every number comes from a document, live data or real math. |
| Does it record people? | Pennsylvania requires everyone's consent. Money mode listens only with consent, or uses documents and your voice. |
| How reliable are the gestures? | Four gestures with clear thresholds; pinch is the most robust; smoothed; tested in the first 3 hours. |
| Can the AI get the math wrong? | The AI only reads and understands. Payments and fits are computed in Swift; figure data is shown for confirmation. |
| Why a laptop and a phone? | The laptop is the big screen with room to track hands; the phone is a camera you can point anywhere. |
| What's new? | Note takers, figure digitizers, equation readers and loan calculators each do one piece. Grasp connects hearing, seeing and live data to charts you can hold, then to an answer. |

---

## 12. Names and domains

**Name: Grasp** (decided). Alternatives considered: Receipts, Digit, Twist, Mathing, TL;DR, No Cap, Fine Print, Pinch, Clutch, Handy, Fathom (conflicts with an existing AI note-taker).

**Domain shortlist** (check which extensions the GoDaddy Registry code covers; .co, .us, .biz, .club are likely):
| Domain | Why |
|---|---|
| **aintreadingallthat.co** ⭐ | The "I ain't reading all that" meme; Grasp reads it for you |
| touchgrasp.co | "Touch grass," but you touch your data |
| ihavereadtheterms.co | The lie everyone tells; Grasp makes it true |
| dothemathfor.us | Reads as "do the math for us" |
| nofunny.biz | "No funny business" for car dealers |
| youcantfool.us | "You can't fool us" |
| whatdidisign.co | The post-signing panic |
| showmethereceipts.co | If you ever rename to Receipts |

---

## 13. Pages from the planning session

- Grasp explainer (features, mockups, scripts, odds, architecture): https://claude.ai/artifact/PThBpnPrBbxVm6BhNjpg1t
- Grasp build plan (live checklist, syncs across devices): https://claude.ai/artifact/53z9ido8enZMBRCp5nrjj6
- HackPSU odds board (all ideas compared; still labels Grasp as "Atlas"): https://claude.ai/artifact/GQud6vrTmdpNLqQM2LcXcV

Offline copies are in `artifacts/` next to this file.

---

## 14. First prompt for a new session

Put this file in the repo root (or copy its contents into `CLAUDE.md`), open Claude Code there, and paste:

```
Read GRASP.md fully. We are building Grasp for HackPSU (24 hours, I am the main builder).
Start Block 0: create one Xcode project with a macOS app (GraspMac), an iOS app (GraspPhone)
and a shared Swift package (GraspKit) using the layout in section 6. Add a git-ignored
Config with GEMINI_API_KEY and ELEVENLABS_API_KEY. Then build gate G1: the macOS app shows
one chart card and I can pinch and drag it with my hand using Vision hand pose on the
webcam, with the 4 cursor states. Keep commits small and tell me exactly what to run.
```
