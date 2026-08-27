# Manual E2E checklist

> **Precondition: QUIT the legacy Window Tidy first** (`com.lightpillar.Window-Tidy`).
> Two event taps + two AX movers double-handle every drop.
> Also run `make doctor` — the signing identity must exist or the Accessibility
> grant dies on every rebuild.

Automated checks (`make test`) cover the pure logic; everything below is
behavior only a human (or a scripted pointer) can verify. Test on BOTH displays.

## Permission flow
1. `tccutil reset Accessibility com.tinyqaq.TinyWindow` → launch → onboarding
   shows, system prompt appears; grant → step 1 turns green without relaunch,
   engine starts (status icon un-dims).
2. Revoke Accessibility while running → within ~10 s the status icon dims and
   the menu shows the re-grant hint; re-grant → auto-recovers without relaunch.
3. Rebuild after a one-line change (`make run`) → drag still works with NO
   re-grant (requires the `TinyWindow Dev` cert).

## Drag & pads
4. Drag a Finder window slowly: pads appear after ~8 pt of travel, near-instant.
5. Plain click and sloppy 5 pt click: no pads, ever.
6. Text selection drag inside an editor, file drag in Finder, desktop
   rubber-band: no pads.
7. Window RESIZE from any edge/corner: no pads.
8. Drag across both displays: strip vanishes from the old screen instantly and
   fades in on the new one; hover highlights + target preview track correctly.
9. Drop on a pad on the OTHER display: window lands there with the exact
   region frame (spot-check with a screenshot ruler or AX read-back).
10. Release with no pad hovered: nothing happens (window stays where dropped).
11. Escape mid-drag: pads hide; releasing over a former pad position does nothing.
12. Every layout in the menu bar applies correctly to the frontmost window on
    the screen that window occupies.

## Option modes (Settings → 通用)
13. `always`: pads on every window drag.
14. `holdOptionToShow`: pads only while ⌥ held; press/release ⌥ mid-drag
    toggles them (release while stationary registers on the next pointer twitch).
15. `optionHides`: inverse.

## Settings & layouts
16. Create a 4×4 layout by drag-selecting cells → it appears on the pads and
    applies; rename inline; paste works in the rename field (Edit-menu proof);
    reorder changes pad order; delete removes the pad.
17. Blacklist an app → no pads when dragging its windows; menu apply still works.
18. Titles toggle, pad edge (all four), minimum drag distance take effect on
    the next drag.
19. Settings window fronts reliably 5/5 times while another app is active.
20. Import tab: re-import replaces/appends; hash note shows for an unchanged file.

## Robustness
21. `kill -STOP <pid>` a target app → drag its window: pads simply don't appear
    (identification times out); `kill -CONT` restores. No beachball ever.
22. Close the dragged window mid-drag (⌘W from another hand): drop is a silent
    no-op.
23. Change display arrangement / unplug a display mid-drag: session cancels,
    pads hide, next drag works on the new geometry.
24. Mission Control / Space switch mid-drag: pads survive or reset within ~4 s;
    nothing sticks.
25. Menu "把当前窗口移到鼠标所在屏幕" recovers a window pushed mostly off-screen.
26. `layouts.json` survives relaunch; `launchctl`-free login item toggles in
    System Settings → General → Login Items.
