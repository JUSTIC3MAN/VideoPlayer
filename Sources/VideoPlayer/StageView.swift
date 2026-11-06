import AppKit
import AVFoundation
import SwiftUI

/// One screen's picture: the loop at the bottom, the two video players above it, and a black layer on top.
/// The output window and the preview in the control window are both StageViews bound to the same players,
/// so the preview is exactly what the audience sees.
final class StageView: NSView {
    private let loopLayer = AVPlayerLayer()
    private let slotLayers = [AVPlayerLayer(), AVPlayerLayer()]
    private let blackLayer = CALayer()

    /// Hide the mouse pointer over this view (used for the output window).
    var hidesCursor = false {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    /// false = fit the whole picture (black bars if the shape differs), true = fill the screen (crops edges).
    var fill = false {
        didSet {
            let gravity: AVLayerVideoGravity = fill ? .resizeAspectFill : .resizeAspect
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in playerLayers { layer.videoGravity = gravity }
            CATransaction.commit()
        }
    }

    private var playerLayers: [AVPlayerLayer] { [loopLayer, slotLayers[0], slotLayers[1]] }
    private var allLayers: [CALayer] { [loopLayer, slotLayers[0], slotLayers[1], blackLayer] }

    private static let blankCursor = NSCursor(
        image: NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true },
        hotSpot: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        layer = root          // layer-hosting view: we manage the layers ourselves
        wantsLayer = true
        layerContentsRedrawPolicy = .never

        for layer in playerLayers {
            layer.videoGravity = .resizeAspect
            layer.backgroundColor = NSColor.clear.cgColor
        }
        loopLayer.opacity = 0
        loopLayer.zPosition = 0
        slotLayers[0].opacity = 0
        slotLayers[0].zPosition = 1
        slotLayers[1].opacity = 0
        slotLayers[1].zPosition = 2
        blackLayer.backgroundColor = NSColor.black.cgColor
        blackLayer.opacity = 1
        blackLayer.zPosition = 10
        for layer in allLayers { root.addSublayer(layer) }
        layoutLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func bind(slots: [AVPlayer], loop: AVPlayer) {
        slotLayers[0].player = slots[0]
        slotLayers[1].player = slots[1]
        loopLayer.player = loop
    }

    /// Shows a visual state. Video fades use Core Animation; the loop layer always switches instantly
    /// because it only changes while it is covered (by a video or by black).
    func apply(_ v: StageVisual, duration: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slotLayers[v.topSlot].zPosition = 2
        slotLayers[1 - v.topSlot].zPosition = 1
        loopLayer.opacity = v.loopAlpha
        CATransaction.commit()

        CATransaction.begin()
        if duration > 0 {
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        slotLayers[0].opacity = v.slotAlpha[0]
        slotLayers[1].opacity = v.slotAlpha[1]
        blackLayer.opacity = v.black ? 1 : 0
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutLayers()
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in allLayers { layer.frame = bounds }
        CATransaction.commit()
    }

    override func resetCursorRects() {
        if hidesCursor { addCursorRect(bounds, cursor: Self.blankCursor) }
    }
}

/// The preview monitor in the control window.
struct StageMonitor: NSViewRepresentable {
    @EnvironmentObject var engine: PlaybackEngine

    func makeNSView(context: Context) -> StageView {
        let view = StageView(frame: .zero)
        engine.attach(view)
        return view
    }

    func updateNSView(_ nsView: StageView, context: Context) {}
}
