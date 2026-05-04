# Contributing to Gleam

Thank you for considering a contribution! Gleam is intentionally small and focused — please read this before opening a PR.

---

## The spirit of the project

Before contributing, internalize these three constraints:

1. **No cloud** — Gleam is 100% on-device. No network calls, ever.
2. **No tracking** — No analytics, no crash reporting, no telemetry.
3. **Simple and delightful** — If a feature needs a settings screen to explain, it probably doesn't belong here.

---

## How to contribute

### Reporting bugs

Open an [issue](https://github.com/sontianye/Gleam/issues) with:
- macOS version
- Steps to reproduce
- What you expected vs. what happened

### Suggesting features

Open an issue tagged `enhancement`. Describe the use case, not just the feature.

### Submitting code

1. Fork the repo and create a branch: `git checkout -b feature/your-idea`
2. Make your change — keep it focused (one PR = one thing)
3. Test on a real Mac with a real camera
4. Open a PR with a clear description of *why* this change improves Gleam

---

## Code style

- Swift 5.9+, strict concurrency enabled
- All shared mutable state must live in an `actor`
- Prefer `async/await` over callbacks
- No third-party dependencies — Apple frameworks only
- Keep files under ~200 lines; split if needed

---

## What we're likely to accept

✅ Bug fixes  
✅ Sensitivity / detection improvements  
✅ Performance wins (lower CPU, better frame skip)  
✅ Accessibility improvements  
✅ Better weekly report layout  

## What we'll probably decline

❌ Cloud sync / backup features  
❌ Social sharing built-in  
❌ Subscriptions or IAP  
❌ Heavy dependencies  
❌ Features that require extra permissions beyond Camera  

---

## Questions?

Open an issue or reach out at [songtianye1997@gmail.com](mailto:songtianye1997@gmail.com).
