# Verified performance measurements

Run `./scripts/bench.sh dist/GoodSticky.app 10` on a logged-in macOS desktop. Defaults: 30 seconds settling after all visible desktop windows appear, then 30 seconds measuring idle process CPU. Optional `--settle`, `--idle`, and `--label` arguments follow the note count. Output is one JSON record. The script uses a temporary library and terminates only its own child process.

The window observer is compiled before the launch timer starts. The deterministic fixture has 10 visible and 2 hidden notes, mixed paper themes, the same text in both builds, and one generated 900×600 image. It does not depend on the user's wallpaper or library. Timing uses a monotonic clock. Missing executables, missing windows, process failures and unparseable footprint measurements fail the run rather than reporting success.

`ready_ms` is time from process launch to observation of the expected WindowServer desktop surfaces. It includes observer process startup and polling overhead; it does not prove first pixel delivery, attachment completion, or input latency. These are repeated launches, not controlled cold-cache measurements. Footprint is macOS's reported physical footprint (rounded by the tool); RSS also includes shared mappings and must not be treated as private memory. CPU comes from `ps` cumulative process time, whose 0.01-second granularity limits conclusions near zero. Measurements exclude WindowServer and system-service CPU/GPU cost.

The October 31 rerun uses fresh release builds of baseline `9f36d89` and optimized/UI `d6e8ef3`, on this MacBookPro18,2, arm64, 64 GiB RAM, macOS 27.0.1. Three samples per build are interleaved A/B, B/A, A/B. Raw records include binary SHA-256 values. The active user session and OS caching are uncontrolled; results are descriptive, not statistical guarantees. The final custom card text contrast correction affects only the management list; it is separately built and smoke checked after the measurements.

Historical claims of 80% lower idle CPU and 18% faster launch are not assumed to hold. Use the rerun results below.

## Results

| Metric, 10 visible notes | Baseline | Optimized |
|---|---:|---:|
| Footprint, MB | 46 median (46–46) | 27 median (27–28) |
| Window-ready, ms | 411.1 median (406.1–443.9) | 310.9 median (305.8–322.1) |
| CPU seconds / 30 s idle | 0 median (0–0) | 0 median (0–0.13) |
| RSS, KiB | 125664 median (125440–125760) | 106576 median (106560–106848) |

Median footprint is 41.3% lower (46 → 27 MB); median window-ready time is 24.4% lower (411.1 → 310.9 ms). These measurements support the memory improvement and suggest quicker repeated launches on this machine. Both median idle samples are below the 0.01-second process-time resolution; one optimized sample recorded 0.13 seconds. The historical 80% idle-CPU improvement is **not reproduced** and should not be advertised. This benchmark does not measure typing latency, energy, or total compositor cost.

## Lightweight idle notes, October 31 rerun

Baseline: `main` at `bb1c08e` (flush notes, drag-to-stack, page dots). Candidate: idle notes without text editors, render-server fades, no hidden main menu, shared symbols. Same machine and methodology as above: three interleaved 10-note launches (B/C, C/B, B/C) and two 1-note launches each, 30 s settle, 30 s idle. Raw records: [`2026-10-31-lightweight.jsonl`](2026-10-31-lightweight.jsonl).

| Metric | Baseline | Candidate |
|---|---:|---:|
| Launch CPU, 10 notes (s) | 0.48–0.51 | 0.18–0.19 |
| Footprint, 10 notes (MB) | 27–28 | 20 |
| RSS, 10 notes (KiB) | ~106,600 | ~66,800 |
| Window-ready, 10 notes (ms) | 282–298 | 230–254 |
| Launch CPU / footprint, 1 note | 0.22–0.23 s / 23 MB | 0.15 s / 18 MB |
| Idle CPU over 30 s | < 0.01 s | < 0.01 s |

Apple Stickies with its single existing note, measured the same way on this machine: 30 MB footprint, 0.32 s launch CPU.

### Interaction CPU

`scripts/interaction/scenario.sh <app-binary> <label>` launches a temporary 10-note library with pinned notes, posts real input events (Accessibility permission required), and reports CPU seconds per step. Three runs each:

| Step | Baseline | Candidate |
|---|---:|---:|
| Pointer sweep across 8 notes | 0.15–0.17 | 0.14–0.15 |
| Click into a note, type 30 characters | 0.20–0.23 | 0.08–0.10 |
| Drag a note | 0.06–0.10 | 0.07 |
| Two stack swipes | 0.06–0.07 | 0.04–0.05 |
| Hide a note (fade out) | 0.07–0.08 | 0.03 |
| Open the Notes list | 0.11–0.13 | 0.13 |
| Open Settings | 0.08–0.09 | 0.08–0.09 |

### Limits found

- A bare AppKit process with no windows uses 7.4 MB here; ten empty panels plus a status item use 13 MB. Ten GoodSticky notes are within ~5 MB of that floor, about 2 MB of which is the text bitmaps.
- Every pointer move over any AppKit window costs about 1 ms of CPU in system event delivery and a Core Animation commit, even for an empty panel (Stickies: ~1.7 ms). Hover cost is therefore bounded by the system, not GoodSticky.
- The Notes list and Settings open with AppKit's standard window animation, kept on purpose; their remaining cost is AppKit building the window.
