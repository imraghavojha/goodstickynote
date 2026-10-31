"""Reproducible macOS process measurements. Outputs one JSON record per run."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import struct
import subprocess
import tempfile
import time
import uuid
import zlib


def positive(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def fixture(root, count):
    attachments = root / "Attachments"
    attachments.mkdir()
    # Deterministic 900x600 RGB PNG, independent of installed wallpapers.
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    pixels = b"".join(b"\0" + bytes(c for x in range(900) for c in (x % 256, y % 256, (x + y) % 256)) for y in range(600))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 900, 600, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b"")
    (attachments / "photo.png").write_bytes(png)
    themes = ["butter", "sage", "rose", "sky", "lilac", "linen", "graphite"]
    notes = []
    for i in range(count + 2):
        note = dict(id=str(uuid.UUID(int=i + 1)).upper(), text=f"Note {i}\n" + "A line of text for the benchmark. " * 12,
                    themeID=themes[i % 7], opacity=1.0, x=60 + i % 5 * 240, y=120 + (i // 5) % 3 * 200,
                    width=220, height=280 if i == 0 else 180, hidden=i >= count, pinned=False,
                    attachments=[], created=750000000, modified=750000000)
        if i == 0:
            note["attachments"] = [dict(id=str(uuid.UUID(int=10000)).upper(), name="photo.png", storedName="photo.png")]
        notes.append(note)
    (root / "notes.json").write_text(json.dumps(dict(notes=notes, preferences=dict(keyCode=45, modifiers=6144,
        defaultTheme="butter", defaultOpacity=1.0, desktopLayoutVersion=2))))


def cpu_seconds(pid):
    value = subprocess.check_output(["ps", "-o", "time=", "-p", str(pid)], text=True).strip()
    parts = [float(part) for part in value.split(":")]
    return sum(part * 60 ** index for index, part in enumerate(reversed(parts)))


def run(args):
    binary = Path(args.app).resolve() / "Contents/MacOS/GoodSticky"
    if not binary.is_file():
        raise RuntimeError(f"App executable missing: {binary}")
    with tempfile.TemporaryDirectory(prefix="GoodStickyBenchmark-") as directory:
        root = Path(directory)
        fixture(root, args.count)
        process = None
        try:
            with (root / "app.log").open("w") as log:
                start = time.monotonic()
                process = subprocess.Popen([str(binary)], env=dict(os.environ, GOODSTICKY_DATA_DIR=directory), stdout=log, stderr=log)
                subprocess.run([".build/checks/bench-windows", str(process.pid), str(args.count)], check=True, capture_output=True, timeout=18)
                ready_ms = (time.monotonic() - start) * 1000
                time.sleep(args.settle)
                if process.poll() is not None:
                    raise RuntimeError("App exited during settling")
                cpu_start = cpu_seconds(process.pid)
                idle_start = time.monotonic()
                time.sleep(args.idle)
                cpu_end = cpu_seconds(process.pid)
                idle_elapsed = time.monotonic() - idle_start
                rss = int(subprocess.check_output(["ps", "-o", "rss=", "-p", str(process.pid)], text=True))
                footprint = subprocess.run(["footprint", str(process.pid)], capture_output=True, text=True, timeout=20, check=True)
                match = re.search(r"Footprint:\s*([\d.]+)\s*([KMG])B", footprint.stdout)
                if not match:
                    raise RuntimeError("Cannot parse footprint output")
                mb = float(match[1]) * {"K": 1 / 1024, "M": 1, "G": 1024}[match[2]]
                print(json.dumps(dict(label=args.label, app=str(binary), binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                    macos=platform.mac_ver()[0], architecture=platform.machine(), visible_notes=args.count, hidden_notes=2,
                    fixture="deterministic-rgb-v1", ready_ms=round(ready_ms, 1), settle_seconds=args.settle,
                    idle_seconds=round(idle_elapsed, 3), cpu_at_idle_start=cpu_start, idle_cpu_seconds=round(cpu_end - cpu_start, 3),
                    idle_cpu_percent=round(100 * (cpu_end - cpu_start) / idle_elapsed, 3), footprint_mb=mb, rss_kb=rss)), flush=True)
        finally:
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app")
    parser.add_argument("count", type=positive)
    parser.add_argument("--settle", type=positive, default=30)
    parser.add_argument("--idle", type=positive, default=30)
    parser.add_argument("--label", default="candidate")
    run(parser.parse_args())
