# TinyWindow Architecture

Three SwiftPM targets, dependency direction strictly downward:

```
TinyWindow (app shell: status item, onboarding, SwiftUI settings)
    │
    ├── TinyWindowEngine (drag detection, AX window control, overlay pads)
    │       │
    └───────┴── TinyWindowCore (models, grid math, coordinates, store, importer — no AppKit)
```

`tinywindow-checks` is the executable check suite over TinyWindowCore.

## Threading lanes (load-bearing invariant)

| Lane | Owns | Why |
|---|---|---|
| **tap thread** (dedicated Thread + CFRunLoop) | `EventTapService`, `DragSessionController` (all state-machine state) | isolates the CGEventTap callback from main-thread stalls (`kCGEventTapDisabledByTimeout`); callback is O(1), allocation-free |
| **axQueue** (serial, userInteractive) | `WindowResolver`, `LayoutApplier` — every `AXUIElement*` call | AX calls are synchronous mach IPC into other apps; they may block up to the messaging timeout and must never run on the tap thread or main |
| **main** | `OverlayCoordinator`, panels, `ScreenTracker`, menu bar, settings | AppKit |

Cross-lane traffic: tap → main via `DispatchQueue.main.async` + `assumeIsolated`
(only on hover/screen **changes**, never per event); resolver/watchdog results
hop back to the tap thread via `EventTapService.perform` (CFRunLoopPerformBlock).
Shared read-mostly snapshots (`EngineSharedState`: cursor, config, screens, pad
hit rects) are `Mutex<T>`-published whole values.

## Coordinate discipline (the other load-bearing invariant)

Two global systems: **Quartz** (top-left origin, +y down — CGEvent, CGWindowList,
all AX) and **Cocoa** (bottom-left origin, +y up — NSScreen/NSPanel). The engine
speaks Quartz **exclusively** via the `QPoint`/`QRect` phantom types; Cocoa
exists only at the AppKit boundary. Conversion is a single involution in
`CoordinateSpace`, parameterized by the PRIMARY screen's height (the screen
whose Cocoa origin is zero — never "the screen the cursor is on").
`ScreenSnapshot` precomputes both representations so the hot path never converts.

## Drag pipeline

1. mouse-down: record point. **Zero AX work** (a plain click costs two stored
   CGPoints).
2. cursor travels past the threshold (default 8 pt) → identification on axQueue:
   - `CGWindowListCopyWindowInfo` pre-filter (no app IPC): topmost window under
     the down point must be layer 0, not ours, not blacklisted.
   - one AX hit-test at the ORIGINAL down point → containing AXWindow, initial
     frame.
   - **follow check**: samples ≥ 70 ms apart, ≤ 6 total; size changed ⇒ resize
     ⇒ rejected; `|Δwindow − Δmouse| ≤ max(8, 0.35·|Δmouse|)` ⇒ confirmed;
     window not tracking half the mouse travel after 2 samples ⇒ text/file drag
     ⇒ rejected. Re-arms on +12 pt of fresh travel, never on a wall clock.
3. confirmed → pads shown on the cursor's screen; the whole steady-state drag
   costs **zero AX calls** (hover = point-in-rect against published pad rects).
4. drop on a pad → pads hide immediately (same tap-thread turn), then the AX
   write runs on axQueue: **position → size → position** (move first so the
   size write resolves against the destination display), retry once on
   `.cannotComplete`, read-back with ±2 pt tolerance, silent best-effort
   failure. `AXEnhancedUserInterface` is cleared for the dance and restored
   only if it was set.

Escape cancels a drag via `CGEventSource.keyState` polling — this app never
listens to keyboard events.

## Pads-never-stick guarantees

1. every transition to idle unconditionally hides all overlays (idempotent);
2. tap-disabled events re-enable the tap and force-reset from ground truth
   (physical button state picks idle vs absorbing-rejected);
3. a 2 s watchdog force-resets when the button is physically up on two
   consecutive ticks, verifies the tap is enabled, and polls
   `AXIsProcessTrusted` (~10 s) to pause/auto-recover the engine on permission
   revocation (a dead tap is never revived — always recreated).

## Overlay panels

Per-screen `NSPanel`: borderless + nonactivating, `.statusBar`+1 level,
`[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`,
**`ignoresMouseEvents = true`** — during a drag of another app's window our
panel must never become an event target; hover is our own hit test on tap
coordinates. Strip rendering is hand-drawn AppKit (`PadStripView.draw`) for an
instant first frame; the glyphs come from `GlyphRenderer` in Core, shared with
the settings previews. Fades animate `alphaValue` with a generation token that
kills the hide-completion vs re-show race. Cross-screen moves hide the old
strip instantly (no ghost) and fade the new one in.

## Persistence

`~/Library/Application Support/TinyWindow/layouts.json` — versioned envelope
(`schemaVersion`), atomic writes, per-entry lenient decoding (unknown layout
kinds are skipped, never fail the file), refuses to load or overwrite a file
from a newer version. Settings in `UserDefaults` (`com.tinyqaq.TinyWindow`).
Launch-at-login is read live from `SMAppService`, never cached.

## Window Tidy import

`WindowTidyImporter` reads the legacy XML plist
(`~/Library/Application Support/Window Tidy/Layouts.data`): `EndX/EndY` are
exclusive; entries without `LayoutType` (or 0) are grids; type ≠ 0 is
fixed-size; empty names get geometric synthesis (halves/quarters/thirds/centre).
`OptionButton=1 → holdOptionToShow`, `ShowTitles`, `Enabled` map to settings;
`QuickLayout*`/`ScreenID` are preserved in `legacy` for deferred features.
A SHA-256 of the source file makes re-imports detectable.
