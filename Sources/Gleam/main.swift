import AppKit

// Top-level code in an executable runs on the main thread by definition.
// MainActor.assumeIsolated tells the compiler this explicitly, allowing us
// to instantiate @MainActor types (AppDelegate) without async/await.
MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}
