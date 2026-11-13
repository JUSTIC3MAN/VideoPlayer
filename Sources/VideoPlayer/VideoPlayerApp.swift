import SwiftUI
import AppKit

@main
struct VideoPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("VideoPlayer", id: "main") {
            ControlView()
                .environmentObject(appDelegate.setlist)
                .environmentObject(appDelegate.engine)
                .environmentObject(appDelegate.output)
                .environmentObject(appDelegate.gamepad)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { appDelegate.updater.check(userInitiated: true) }
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Videos…") { appDelegate.setlist.chooseVideos() }
                    .keyboardShortcut("o", modifiers: [.command])
                Button("Add Column") { appDelegate.setlist.renamingColumn = appDelegate.setlist.addColumn() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("Open Setlist…") { appDelegate.setlist.openSetlistFile() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Save Setlist As…") { appDelegate.setlist.saveSetlistFile() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            // Show controls live on plain keys (Space, arrows, P, L, B, F, Esc), handled in AppDelegate,
            // so a presentation clicker works too, and on a game controller (Gamepad.swift).
            // The menu lists them for reference.
            CommandMenu("Show") {
                Button("Next  (Space, →, Page Down, controller A)") { appDelegate.engine.next() }
                Button("Previous Video  (controller B)") { appDelegate.engine.playPrevious() }
                Button("Pause / Resume  (P, controller Y)") { appDelegate.engine.togglePause() }
                Button("Back One  (←, Page Up)") { appDelegate.engine.armPrevious() }
                Button("Loop Visual  (L, controller X)") { appDelegate.engine.showLoop() }
                Button("Blackout  (B)") { appDelegate.engine.toggleBlackout() }
                Divider()
                Button("Show / Hide Output  (F, Esc)") { appDelegate.output.toggle() }
                Divider()
                Button("Stop Show") { appDelegate.engine.stop() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let setlist = Setlist()
    lazy var engine = PlaybackEngine(setlist: setlist)
    lazy var output = OutputController(engine: engine)
    lazy var gamepad = GamepadInput(engine: engine)
    let updater = Updater()

    private var keyMonitor: Any?
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Keep the display awake and stop macOS from throttling the app during a show.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleDisplaySleepDisabled, .latencyCritical],
            reason: "VideoPlayer show playback")

        // Look for a newer version on GitHub a few seconds after launch (only speaks up if there is one).
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.updater.check(userInitiated: false)
        }

        // Xbox controller: A = Next, B = previous video, X = the songs' loop, Y = pause.
        _ = gamepad

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        setlist.saveNow()
    }

    /// Show keys. Returns true when the key was used.
    private func handleKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) { return false }
        if NSApp.modalWindow != nil || NSApp.keyWindow is NSPanel { return false }     // open/save dialogs
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable { return false }

        switch event.keyCode {
        case 49, 124, 121:          // Space, Right arrow, Page Down
            engine.next()
            return true
        case 123, 116:              // Left arrow, Page Up
            engine.armPrevious()
            return true
        case 53:                    // Esc
            guard output.isShowing else { return false }
            output.hide()
            return true
        default:
            break
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "p":
            engine.togglePause()
            return true
        case "l":
            engine.showLoop()
            return true
        case "b", ".":              // many clickers send "." or "b" for their blank-screen button
            engine.toggleBlackout()
            return true
        case "f":
            output.toggle()
            return true
        default:
            return false
        }
    }
}
