<div align="center">
  <h1>Gleam ✨</h1>
  <p><strong>Your Mac's invisible photographer.<br/>It only shoots when you smile.</strong></p>
  <p>
    <img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square" />
    <img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift" />
    <img src="https://img.shields.io/badge/100%25_on--device-blue?style=flat-square" />
    <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" />
  </p>
</div>

---

## What is Gleam?

Gleam sits quietly in your menu bar and watches for one thing: **your smile**.

The moment it catches one, it silently takes a photo — no sound, no flash, no interruption. At the end of each week, it hands you a collage of every happy moment it witnessed.

You'll forget it's running. Then one day you'll open it and find 200 pictures of yourself smiling.

---

## Features

- **Invisible** — lives in your menu bar, never interrupts your flow
- **Smile-triggered** — uses Apple's `CIDetector` + Vision to detect genuine smiles
- **100% on-device** — no camera stream ever leaves your Mac. No cloud. No accounts.
- **Auto-organized** — photos saved to `~/Pictures/Gleam/YYYY/MM/`
- **Smile stats** — today's count, weekly total, your happiest hour
- **Weekly report** — every Sunday, a collage of your best moments

---

## How it works

```
Camera (20fps)
    │
    ├─ CIDetector.hasSmile ─── Apple's built-in smile detection
    │
    ├─ VNDetectFaceLandmarksRequest ─── head pose gate + landmark analysis
    │
    ↓
Fused smile score (Apple 60% + Landmarks 40%)
    │
    ↓
State machine: sustained smile > ~0.6s → capture!
    │
    ↓
~/Pictures/Gleam/2025/05/smile.jpg
```

All processing happens locally using Apple's **CoreImage** and **Vision** frameworks. Gleam never accesses the internet.

---

## Privacy

> "Your smiles, only yours."

- **No recording** — frames are processed in memory and immediately discarded
- **No telemetry** — zero analytics, zero crash reporting to any server
- **Open source** — read every line of the code that touches your camera
- **macOS camera permission** — you'll see the green indicator light whenever it's active

---

## Requirements

- macOS 14 Sonoma or later
- A Mac with a built-in or external camera
- Xcode 15+ (to build from source)

---

## Install

### Option A — Download (recommended)

1. Download `Gleam-1.0.0.dmg` from [Releases](https://github.com/sontianye/Gleam/releases)
2. Open the DMG, drag **Gleam** to **Applications**
3. On first launch, right-click Gleam → Open (or run `xattr -cr /Applications/Gleam.app`)

> macOS may warn "app is damaged" for unsigned apps. This is normal for open-source software. The `xattr` command above removes the quarantine flag. See [this issue](https://github.com/sontianye/Gleam/issues/1) for details.

### Option B — Build from source

```bash
git clone https://github.com/sontianye/Gleam.git
cd Gleam
swift build -c release
swift run Gleam
```

---

## Usage

1. Launch Gleam — it appears in your menu bar as a smiling face
2. Grant camera permission when prompted
3. Work, code, watch, laugh — Gleam does the rest
4. Click the menu bar icon to see today's stats and recent captures
5. Click **Open Library** to browse all your moments

---

## Smile detection

Gleam fuses two detection methods for robustness:

1. **Apple's CIDetector** (`hasSmile`) — the same engine behind iOS Camera timer and Photos app
2. **Custom landmark analysis** — mouth-corner raise, eye involvement (Duchenne marker), head pose gate

A state machine with hysteresis prevents false triggers from talking, yawning, or head movement. Only sustained, genuine smiles trigger a capture.

---

## Tech stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 5.9 with strict concurrency |
| Smile detection | CoreImage `CIDetector` + Vision `VNDetectFaceLandmarksRequest` |
| Camera | AVFoundation + AsyncStream |
| UI | SwiftUI + AppKit menu bar |
| Concurrency | Swift actors + async/await |
| Image output | CoreImage JPEG export |
| Weekly report | CoreGraphics collage renderer |

---

## Project structure

```
Sources/Gleam/
├── main.swift                  Entry point
├── AppDelegate.swift           App lifecycle
├── SmilePipeline.swift         Orchestration (camera → detect → save)
├── CameraCapture.swift         AVFoundation async frame stream
├── FaceAnalyzer.swift          CIDetector + Vision smile detection
├── PhotoManager.swift          Photo storage + metadata
├── StatsManager.swift          Daily/weekly stats
├── StatusBarController.swift   Menu bar item
├── PopoverView.swift           SwiftUI popover UI
├── WeeklyReportGenerator.swift Collage renderer
├── WeeklyReportScheduler.swift UNUserNotifications scheduler
└── GleamError.swift            Error types
```

---

## Contributing

PRs are welcome. Please keep the spirit of the project:
- **No cloud features**
- **No tracking**
- **Simple, focused, delightful**

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

---

## License

MIT — do whatever you want, just keep the spirit alive.

---

<div align="center">
  <sub>Built with Swift + Apple Vision by <a href="https://github.com/sontianye">Tianye Song</a></sub>
</div>
