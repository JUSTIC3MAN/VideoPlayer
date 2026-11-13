import Combine
import GameController

/// Game controller buttons for the show: A = Next, B = previous video, X = the songs' loop, Y = pause / resume.
///
/// Made for an Xbox controller. PlayStation and other controllers that macOS supports work the same way,
/// with the buttons in the same places (on PlayStation: ✕ Next, ○ Previous, □ Loop, △ Pause).
/// Pair the controller once in System Settings → Bluetooth; after that it connects by itself when turned on.
final class GamepadInput: ObservableObject {
    /// The connected controller's name; nil when none is connected.
    @Published private(set) var controllerName: String?

    private let engine: PlaybackEngine
    private var observers: [NSObjectProtocol] = []

    init(engine: PlaybackEngine) {
        self.engine = engine
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let controller = note.object as? GCController else { return }
            self.attach(controller)
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            let controller = note.object as? GCController
            showLog("Game controller disconnected: \(controller?.vendorName ?? "controller")")
            self?.updateName(without: controller)
        })
        for controller in GCController.controllers() { attach(controller) }
        updateName(without: nil)
    }

    private func attach(_ controller: GCController) {
        // Keep the buttons working while another app (Ableton, say) is in front. Turned on only once a
        // controller has connected: turning it on before that can crash some macOS versions.
        if !GCController.shouldMonitorBackgroundEvents {
            GCController.shouldMonitorBackgroundEvents = true
        }
        let name = controller.vendorName ?? "Game controller"
        guard let pad = controller.extendedGamepad else {
            showLog("Game controller \(name) has no A / B / Y buttons, so it isn't used")
            return
        }
        controller.handlerQueue = .main
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self else { return }
            showLog("Controller A: Next")
            self.engine.next()
        }
        pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self else { return }
            showLog("Controller B: Previous")
            self.engine.playPrevious()
        }
        pad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self else { return }
            showLog("Controller X: Loop")
            self.engine.showLoop()
        }
        pad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self else { return }
            showLog("Controller Y: Pause / Resume")
            self.engine.togglePause()
        }
        showLog("Game controller connected: \(name)")
        updateName(without: nil)
    }

    /// `without`: a controller that is disconnecting (it can still be listed while it goes).
    private func updateName(without gone: GCController?) {
        let pads = GCController.controllers().filter { $0 !== gone && $0.extendedGamepad != nil }
        let name = pads.first.map { $0.vendorName ?? "Game controller" }
        if controllerName != name { controllerName = name }
    }
}
