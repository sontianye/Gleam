import AppKit
import SwiftUI
import Combine

/// Manages the macOS menu-bar item and its popover.
///
/// Icon semantics — **one flash means one photo**:
///
///   • Idle, running     → outline `face.smiling`
///   • Idle, paused      → dimmed `moon.zzz`
///   • Photo captured    → brief flash of `sparkles` (≈1.2s), then back to idle
///
/// The icon is no longer a live readout of `smileIntensity`. That earlier
/// behavior produced constant flicker that didn't correspond to any actual
/// capture, breaking the trust signal. Now the menu bar speaks only when
/// something has actually happened.
@MainActor
final class StatusBarController {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let pipeline: SmilePipeline
    private var cancellables = Set<AnyCancellable>()

    /// In-flight flash animation. Cancelled if a new capture lands quickly.
    private var flashTask: Task<Void, Never>?

    private static let flashDuration: Duration = .milliseconds(1200)

    init(pipeline: SmilePipeline, photoManager: PhotoManager, statsManager: StatsManager) {
        self.pipeline = pipeline
        setupStatusItem()
        setupPopover(photoManager: photoManager, statsManager: statsManager)
        bindPipeline()
        pipeline.start()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = idleImage(running: false)
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func setupPopover(photoManager: PhotoManager, statsManager: StatsManager) {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 460)
        popover.behavior = .transient
        popover.animates = true
        let root = PopoverView(pipeline: pipeline,
                               photoManager: photoManager,
                               statsManager: statsManager)
        popover.contentViewController = NSHostingController(rootView: root)
    }

    // MARK: - Reactive binding

    private func bindPipeline() {
        // Idle icon tracks running/paused state
        pipeline.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] running in
                guard let self else { return }
                // Don't override an in-flight flash — let it complete
                if self.flashTask == nil {
                    self.statusItem.button?.image = self.idleImage(running: running)
                }
            }
            .store(in: &cancellables)

        // Capture events drive the flash. We dropFirst() to avoid flashing on
        // the initial nil → nil propagation at launch.
        pipeline.$lastCaptureDate
            .dropFirst()
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.flashCaptureIndicator()
            }
            .store(in: &cancellables)
    }

    // MARK: - Flash animation

    private func flashCaptureIndicator() {
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            guard let self, let button = self.statusItem.button else { return }

            button.image = self.flashImage()
            // Subtle scale pulse for an extra beat of feedback
            self.pulseAlpha(button: button)

            try? await Task.sleep(for: Self.flashDuration)
            guard !Task.isCancelled else { return }

            button.image = self.idleImage(running: self.pipeline.isRunning)
            self.flashTask = nil
        }
    }

    private func pulseAlpha(button: NSStatusBarButton) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            button.animator().alphaValue = 0.35
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                button.animator().alphaValue = 1.0
            }
        }
    }

    // MARK: - Icon assets

    private func idleImage(running: Bool) -> NSImage? {
        templateImage(named: running ? "face.smiling" : "moon.zzz")
    }

    private func flashImage() -> NSImage? {
        // `sparkles` reads as "moment captured" — distinct from the resting face.
        templateImage(named: "sparkles")
    }

    private func templateImage(named name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Gleam")
        img?.isTemplate = true
        return img
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
