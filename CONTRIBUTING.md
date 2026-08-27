# Contributing to TinyWindow

## Toolchain

**No Xcode required.** Command Line Tools with Swift 6.2+ and the macOS 26 SDK
build everything (`xcode-select --install`). Xcode users can `open Package.swift`
for IDE features — but always verify behavior with `make run`, never the bare
binary (a bare binary has no bundle: no LSUIElement, and TCC grants attach to
the wrong thing).

## Make targets

| Target | What it does |
|---|---|
| `make build` | `swift build -c release` |
| `make app` | build + assemble + sign `dist/TinyWindow.app` |
| `make run` | `make app`, restart the app |
| `make test` | run the `tinywindow-checks` suite |
| `make doctor` | check signing identity / legacy Window Tidy |
| `make release` | build the distribution zip |

## Signing & the Accessibility grant

macOS keys the Accessibility permission to the app's code-signature designated
requirement. Ad-hoc signatures (`codesign -s -`) change every build → the grant
silently dies on each rebuild (the checkbox still LOOKS on — toggle it off/on,
or `tccutil reset Accessibility com.tinyqaq.TinyWindow` and re-grant).

One-time fix: create a self-signed code-signing certificate named
`TinyWindow Dev` (`scripts/dev-cert.sh`, or Keychain Access → Certificate
Assistant). `scripts/bundle.sh` picks it up automatically; the designated
requirement is then stable and the grant survives rebuilds.

## Tests

The Command Line Tools ship no XCTest/Swift Testing runner, so the suite is a
plain executable (`Sources/tinywindow-checks`) that runs identically on dev
machines and CI: `make test`. Pure logic lives in `TinyWindowCore` (no AppKit)
precisely so it stays testable headless. Manual end-to-end checklist:
`docs/TESTING.md`.

## Architecture

Read `docs/ARCHITECTURE.md` before touching the engine — the threading lanes
(tap thread / axQueue / main) and the Quartz-only coordinate discipline are
load-bearing invariants, not style preferences.

## PRs

- CI must be green (build + checks on `macos-26`).
- Match the existing code style; keep the engine allocation-free on the
  per-event hot path.
