import AppKit

// Menu-bar ("accessory") app: no Dock icon, no main window — the UI lives in
// the status bar and in per-app mirror windows created on demand.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = AppController()
app.delegate = controller

app.run()
