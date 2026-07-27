import AppKit

// Top-level code is not main-actor isolated, but it does run on the main thread,
// so assert that once and set the app up inside. `run()` blocks until quit, which
// keeps the local delegate reference alive for the lifetime of the process.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
}
