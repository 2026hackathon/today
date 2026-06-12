import AppKit

MainActor.assumeIsolated {
    // 单实例（新实例优先）：启动时先退掉旧实例，
    // swift run 反复调试时不会越积越多刘海
    let myPID = ProcessInfo.processInfo.processIdentifier
    for running in NSWorkspace.shared.runningApplications
    where running.processIdentifier != myPID
        && running.executableURL?.lastPathComponent == "MiniNotch" {
        if !running.terminate() {
            running.forceTerminate()
        }
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Keep delegate alive
    objc_setAssociatedObject(app, "MiniNotchDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.run()
}
