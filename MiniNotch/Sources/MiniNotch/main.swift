import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Keep delegate alive
    objc_setAssociatedObject(app, "MiniNotchDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.run()
}
