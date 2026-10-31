<p align="center">
  <a href="https://prathje.github.io/plushies/?scene=video&amp;design=live"><img src="assets/tangerine-supreme.png" width="140" alt="Tangerine Supreme"></a>
</p>

<h1 align="center">GoodSticky</h1>

<p align="center">Native, lightweight sticky notes for macOS.<br>Made for personal use because Apple Stickies sucks.</p>

<p align="center"><img src="assets/demo.gif" width="720" alt="Type and undo, stack notes with wiggle feedback, swipe to a new note, tuck a side note into the screen edge and hover to reveal it, then snooze a reminder until it returns."></p>

<p align="center"><img src="assets/comparison.svg" width="720" alt="GoodSticky: 18 MB, 0.14 s launch CPU. Apple Stickies: 32 MB, 0.34 s launch CPU."></p>

<sub>Median of 3 warm launches, 1 visible note each. M1 Max, macOS 27.0.1. CPU is app process time, not launch latency; excludes WindowServer. GoodSticky’s sample includes an image.</sub>

macOS 13+ with Swift command-line tools. Quit the running app, then:

```sh
./scripts/install.sh
```

⌃⌥N creates a note · ⌘W hides it · ⌘Z / ⌘⇧Z undo / redo. Undo survives hiding and stacking until you quit the app.

- **Stacks:** notes can overlap freely. Drag one by its top strip until it sits almost exactly on another; it wiggles to show it will stack. Let go to stack, or keep dragging to cancel. Swipe between notes in a stack; swipe past the last one to start a new note.
- **Side notes:** push a note against the left or right edge of the screen. It tucks away as a thin tab and slides out when you hover over the tab. Drag it away from the edge to put it back on the desktop.
- **Snooze:** the moon button next to Copy hides a note until a chosen time, then brings it back in front of your windows. Defaults: next morning (9 AM), evening (9 PM), in 12 hours, next week (Monday 9 AM). Choose the times in Settings.

Tests: `./scripts/test.sh` and `./scripts/test-install.sh`.
