import AppKit

@MainActor
private func launch() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)

    // NSApplication.delegate 不持有对象，必须自己保证生命周期，
    // 否则 release 构建下 delegate 会被提前释放，菜单和热键全部失效
    withExtendedLifetime(delegate) {
        app.run()
    }
}

MainActor.assumeIsolated {
    launch()
}