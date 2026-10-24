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
- Printable demo props live in `props/`.
- Keys: copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` (git-ignored) and fill it in. Read them in code with `APIKeys.gemini` / `APIKeys.elevenLabs`.

## Conventions

- Swift 5 language mode, SwiftUI, `@Observable`, no third-party dependencies.
- Numbers are computed in Swift (`GraspKit/Math`), never by the AI.
- Pure logic both apps can use (math, gestures, link messages) lives in GraspKit with tests. Camera, Vision and UI code live in the app targets.
- The app folders are folder-synced groups: a new file in `GraspMac/` or `GraspPhone/` joins its target automatically, with no project edits.
- The user makes every git commit. Never commit; list the changed files and suggest a message instead.
