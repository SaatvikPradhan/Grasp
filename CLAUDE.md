# Grasp

@GRASP.md

GRASP.md is the HackPSU brief and the source of truth. Update it when a decision changes.

## Build and run

- Open `Grasp.xcodeproj`. Schemes: **GraspMac** (the canvas, run on My Mac) and **GraspPhone** (the eye).
- Mac app from the command line: `xcodebuild -project Grasp.xcodeproj -scheme GraspMac -destination 'platform=macOS' build`
- iPhone app compile check: `xcodebuild -project Grasp.xcodeproj -scheme GraspPhone -destination 'generic/platform=iOS Simulator' build`
- Shared logic tests: `cd GraspKit && swift test`
- Live Gemini test (reads `Fixtures/contract-photo.jpg`): `GEMINI_API_KEY=... swift test --filter LiveGemini` from `GraspKit/`. Skipped without the key.
- Test the phone link without an iPhone: run GraspPhone in the simulator; it sends numbered test frames.
- Printable demo props live in `props/` (contract, window sticker, credit union quote, phone plan). In the simulator, the phone's shutter sends the first three in turn.
- The product is one engine, not modes: any page → document card (facts, catches, model) with provenance on hover; Ask (fist or ⌘K) answers from the pages with Swift math. Keep new features inside that engine.
- Check the Mac UI without screen recording: launch with `open -n --env GRASP_SNAPSHOT=/tmp/shot.png [--env GRASP_SNAPSHOT_DELAY=6] [--env GRASP_SNAPSHOT_SETUP=…] <Grasp.app>` and read the PNG. Setup steps: `demo`, `term48`, `quote`, `compare`, `lines`, `advice`, `summary`, `read:/path/page.jpg`, `ask:question`, `hover`, `hovertotal`, `hoveranswer`. ⌘⇧S saves a snapshot to the Desktop.
- Mouse and keyboard stand-ins for every gesture are in the Canvas menu (⌘[ ⌘] term, ⌘L bars/lines, ⌘M compare, ⌘U demo quote, ⌘T temperatures, ⌫ delete card). Make a fist or hold Space to talk.
- Money menu: ⌘J what to say (spoken by ElevenLabs), ⌘⇧L listen to the salesperson (asks for consent), ⌘E decision summary PDF. Snapshot runs stay silent.
- Live ElevenLabs test: `ELEVENLABS_API_KEY=... swift test --filter LiveElevenLabs` (costs ~30 characters).
- Keys: copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` (git-ignored) and fill it in. Read them in code with `APIKeys.gemini` / `APIKeys.elevenLabs`.

## Conventions

- Swift 5 language mode, SwiftUI, `@Observable`, no third-party dependencies.
- Numbers are computed in Swift (`GraspKit/Math`), never by the AI.
- Pure logic both apps can use (math, gestures, link messages) lives in GraspKit with tests. Camera, Vision and UI code live in the app targets.
- The app folders are folder-synced groups: a new file in `GraspMac/` or `GraspPhone/` joins its target automatically, with no project edits.
- The user makes every git commit. Never commit; list the changed files and suggest a message instead.
