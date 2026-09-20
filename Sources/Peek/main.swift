import AppKit

let app = NSApplication.shared
let controller: NSApplicationDelegate

if ProcessInfo.processInfo.environment["PEEK_SHOWCASE"] == "1" {
    // Screenshot mode: real windows + mock data for README captures.
    app.setActivationPolicy(.regular)
    controller = ShowcaseController()
} else {
    // Menu-bar / accessory app: no Dock icon, driven entirely by the ⌘-Tab event tap.
    app.setActivationPolicy(.accessory)
    controller = AppController()
}

app.delegate = controller
app.run()
