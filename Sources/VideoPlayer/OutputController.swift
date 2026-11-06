import AppKit
import Combine

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Borderless, never takes keyboard focus, so the control window keeps receiving key presses.
final class OutputWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The full-screen output window on the projector / second display.
final class OutputController: ObservableObject {
    @Published private(set) var isShowing = false
    @Published private(set) var screens: [NSScreen] = NSScreen.screens
    @Published var screenID: CGDirectDisplayID? {
        didSet {
            UserDefaults.standard.set(Int(screenID ?? 0), forKey: Self.screenKey)
            if isShowing { place() }
        }
    }

    private static let screenKey = "outputDisplayID"
    private let engine: PlaybackEngine
    private var window: OutputWindow?
    private var screenObserver: NSObjectProtocol?

    init(engine: PlaybackEngine) {
        self.engine = engine
        let saved = UserDefaults.standard.integer(forKey: Self.screenKey)
        if saved != 0, NSScreen.screens.contains(where: { $0.displayID == CGDirectDisplayID(saved) }) {
            screenID = CGDirectDisplayID(saved)
        } else {
            screenID = Self.preferredScreenID()
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.screens = NSScreen.screens
            if !self.screens.contains(where: { $0.displayID == self.screenID }) {
                self.screenID = OutputController.preferredScreenID()
            }
            if self.isShowing { self.place() }
        }
    }

    /// An external display if there is one (screens[0] is the one with the menu bar).
    private static func preferredScreenID() -> CGDirectDisplayID? {
        let screens = NSScreen.screens
        return (screens.count > 1 ? screens[1] : screens.first)?.displayID
    }

    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.displayID == screenID } ?? NSScreen.screens.last
    }

    func show() {
        guard let screen = targetScreen else { return }
        if window == nil {
            let w = OutputWindow(contentRect: screen.frame, styleMask: [.borderless],
                                 backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.backgroundColor = .black
            w.isOpaque = true
            w.hasShadow = false
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.title = "VideoPlayer Output"

            let stage = StageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            stage.autoresizingMask = [.width, .height]
            stage.hidesCursor = true
            w.contentView = stage
            engine.attach(stage)
            window = w
        }
        place()
        window?.orderFrontRegardless()
        isShowing = true
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    func hide() {
        window?.orderOut(nil)
        isShowing = false
    }

    func toggle() {
        isShowing ? hide() : show()
    }

    private func place() {
        guard let window, let screen = targetScreen else { return }
        window.setFrame(screen.frame, display: true)
    }
}
