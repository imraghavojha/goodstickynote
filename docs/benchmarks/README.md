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
