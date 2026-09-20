import AppKit

// Menu-bar / accessory app: no Dock icon, driven entirely by the ⌘-Tab event tap.
let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
