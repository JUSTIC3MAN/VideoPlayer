import AVFoundation
import AppKit
import Combine

/// Writes what the show does to the system log (Console app, filter "VideoPlayer") and to stderr.
func showLog(_ message: String) {
    NSLog("[VideoPlayer] %@", message)
}

enum ShowPhase: Equatable {
    case idle      // nothing on screen yet (black)
    case playing   // a setlist video is playing
    case loop      // the loop visual is playing, waiting for Next
}

/// What every screen (output + preview) shows. All screens get the same values at the same time.
struct StageVisual: Equatable {
    var slotAlpha: [Float] = [0, 0]   // the two video players
    var topSlot = 0                   // which of the two sits on top (the one fading in)
    var loopAlpha: Float = 0          // the loop player, underneath both
    var black = true                  // black layer over everything
}

/// The clock is separate so only the time display redraws 5 times a second, not the whole window.
final class ShowClock: ObservableObject {
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
}

/// Plays the show.
///
/// How it stays smooth:
/// - Two video players take turns. While one plays (or the loop is up), the next video is already
///   loaded and its first frame decoded in the other player, so Next starts instantly.
/// - The loop runs on its own AVQueuePlayer with AVPlayerLooper, which repeats with no gap.
/// - Decoding is done by the Mac's video hardware (AVFoundation); fades are Core Animation.
final class PlaybackEngine: ObservableObject {
    @Published private(set) var phase: ShowPhase = .idle
    @Published private(set) var playingCueID: UUID?
    @Published var armedCueID: UUID? {
        didSet { if armedCueID != oldValue { prepareArmed() } }
    }
    @Published private(set) var blackout = false
    @Published private(set) var loopName: String?
    @Published var lastError: String?

    let clock = ShowClock()
    let slotPlayers = [AVPlayer(), AVPlayer()]
    let loopPlayer = AVQueuePlayer()

    private let setlist: Setlist
    private var slotCueID: [UUID?] = [nil, nil]
    private var slotPath: [String?] = [nil, nil]
    private var slotTokens: [[NSObjectProtocol]] = [[], []]
    private var slotStatus: [AnyCancellable?] = [nil, nil]
    private var timeTokens: [Any] = []
    private var volumeTimers: [Timer?] = [nil, nil]
    private var activeSlot = 0
    private var visual = StageVisual()
    private let stages = NSHashTable<StageView>.weakObjects()
    private var looper: AVPlayerLooper?
    private var loopPath: String?
    private var fadeGeneration = 0
    private var fadeInFlight = false
    private var lastGo = Date.distantPast
    /// true when NEXT was picked by hand (Set as Next / Back). Otherwise NEXT follows the setlist order.
    private var armedByUser = false
    private var bag = Set<AnyCancellable>()

    init(setlist: Setlist) {
        self.setlist = setlist

        for player in slotPlayers {
            player.actionAtItemEnd = .pause
            player.automaticallyWaitsToMinimizeStalling = false
            player.allowsExternalPlayback = false
            player.isMuted = !setlist.videoAudio
        }
        loopPlayer.isMuted = true
        loopPlayer.automaticallyWaitsToMinimizeStalling = false
        loopPlayer.allowsExternalPlayback = false

        for (i, player) in slotPlayers.enumerated() {
            let token = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 5), queue: .main) { [weak self] time in
                guard let self, self.activeSlot == i, self.phase == .playing else { return }
                self.clock.elapsed = max(0, time.seconds)
                if self.clock.duration <= 0,
                   let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                    self.clock.duration = d
                }
            }
            timeTokens.append(token)
        }

        armedCueID = setlist.cues.first?.id

        // @Published fires before the value changes, so hop to the next run loop pass to read the new value.
        setlist.$cues
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.cuesChanged() }
            .store(in: &bag)
        setlist.$defaultLoop
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.loopSettingChanged() }
            .store(in: &bag)
        setlist.$videoAudio
            .receive(on: RunLoop.main)
            .sink { [weak self] on in self?.slotPlayers.forEach { $0.isMuted = !on } }
            .store(in: &bag)
        setlist.$fillScreen
            .receive(on: RunLoop.main)
            .sink { [weak self] fill in self?.stages.allObjects.forEach { $0.fill = fill } }
            .store(in: &bag)

        prepareLoop(for: nil)
        DispatchQueue.main.async { [weak self] in self?.prepareArmed() }
    }

    // MARK: - Screens

    func attach(_ stage: StageView) {
        stages.add(stage)
        stage.bind(slots: slotPlayers, loop: loopPlayer)
        stage.fill = setlist.fillScreen
        stage.apply(currentVisual(), duration: 0)
    }

    private func currentVisual() -> StageVisual {
        var v = visual
        v.black = blackout || phase == .idle
        return v
    }

    private func render(_ duration: Double) {
        let v = currentVisual()
        for stage in stages.allObjects { stage.apply(v, duration: duration) }
    }

    // MARK: - Setlist helpers

    private var cues: [Cue] { setlist.cues }

    func index(of id: UUID?) -> Int? {
        guard let id else { return nil }
        return cues.firstIndex { $0.id == id }
    }

    private func cueAfter(_ id: UUID?) -> UUID? {
        guard let i = index(of: id) else { return cues.first?.id }
        return i + 1 < cues.count ? cues[i + 1].id : nil
    }

    /// The video NEXT should point to when it follows the setlist order.
    private var automaticNext: UUID? {
        playingCueID == nil ? cues.first?.id : cueAfter(playingCueID)
    }

    private func cuesChanged() {
        if armedByUser, index(of: armedCueID) != nil {
            prepareArmed()                       // keep the hand-picked NEXT (its file may have changed)
        } else {
            armedByUser = false
            let next = automaticNext             // order changed: NEXT follows the new order
            if armedCueID != next { armedCueID = next } else { prepareArmed() }
        }
        // The current video's own loop may have been changed: swap it while the loop is hidden.
        if phase == .playing, !fadeInFlight { prepareLoop(for: playingCueID) }
    }

    private func loopSettingChanged() {
        switch phase {
        case .loop:
            prepareLoop(for: playingCueID)   // swap the loop on screen right away
            loopPlayer.play()
        case .playing:
            if !fadeInFlight { prepareLoop(for: playingCueID) }
        case .idle:
            prepareLoop(for: nil)
        }
    }

    // MARK: - Transport

    /// Next: plays the video marked NEXT. Ignores a second press during the fade (protects
    /// against a double-click on a remote skipping a song).
    func next() {
        let lockout = max(0.35, min(setlist.crossfade, 1.0))
        guard Date().timeIntervalSince(lastGo) > lockout else { showLog("Next ignored (pressed again during the fade)"); return }
        guard let i = index(of: armedCueID) else { showLog("Next: nothing armed (setlist empty or at the end)"); NSSound.beep(); return }
        go(to: i)
    }

    /// Moves NEXT back by one video. Does not play anything.
    func armPrevious() {
        guard !cues.isEmpty else { return }
        let i = index(of: armedCueID) ?? cues.count
        armedByUser = true
        armedCueID = cues[max(0, i - 1)].id
    }

    func arm(_ id: UUID) {
        armedByUser = true
        armedCueID = id
    }

    func playNow(_ id: UUID) {
        if let i = index(of: id) { go(to: i) }
    }

    func go(to index: Int) {
        guard cues.indices.contains(index) else { return }
        let cue = cues[index]
        let fade = max(0, setlist.crossfade)
        let target = 1 - activeSlot
        let old = activeSlot
        let wasPlaying = phase == .playing

        lastGo = Date()
        lastError = nil
        blackout = false
        showLog("Play #\(index + 1) \"\(cue.title)\" (from \(phase), fade \(fade)s)")

        if slotCueID[target] != cue.id || slotPath[target] != cue.file.path || slotPlayers[target].currentItem == nil {
            load(slot: target, cue: cue)
        } else if slotPlayers[target].currentTime().seconds > 0.01 {
            slotPlayers[target].seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        activeSlot = target
        phase = .playing
        playingCueID = cue.id
        clock.elapsed = 0
        clock.duration = cue.duration
        armedByUser = false
        armedCueID = cueAfter(cue.id)

        let player = slotPlayers[target]
        player.isMuted = !setlist.videoAudio
        if wasPlaying && fade > 0 {
            player.volume = 0
            rampVolume(slot: target, to: 1, over: fade)
            rampVolume(slot: old, to: 0, over: fade)
        } else {
            volumeTimers[target]?.invalidate()
            player.volume = 1
        }
        player.playImmediately(atRate: 1)

        visual.topSlot = target
        visual.slotAlpha[target] = 1
        render(fade)

        fadeInFlight = true
        fadeGeneration += 1
        let generation = fadeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.05) { [weak self] in
            guard let self, self.fadeGeneration == generation else { return }
            self.fadeInFlight = false
            self.visual.slotAlpha[old] = 0
            self.visual.loopAlpha = 0
            self.render(0)
            self.volumeTimers[old]?.invalidate()
            self.slotPlayers[old].pause()
            self.slotPlayers[old].volume = 1
            self.loopPlayer.pause()
            self.prepareLoop(for: cue.id)   // the loop for after this video
            self.prepareArmed()             // the next video, ready in the free player
        }
    }

    /// Shows the loop visual. Called automatically when a video ends, or with the Loop button.
    func showLoop() {
        let fade = max(0, setlist.crossfade)
        let wasBlack = blackout
        blackout = false
        if phase == .loop {
            if wasBlack { render(0.4) }
            return
        }
        showLog("Loop visual: \(setlist.loopFor(cueID: playingCueID)?.name ?? "none chosen (black)")")
        if looper == nil { prepareLoop(for: playingCueID) }
        loopPlayer.play()

        let wasIdle = phase == .idle
        phase = .loop
        clock.elapsed = 0
        clock.duration = 0
        visual.loopAlpha = 1
        visual.slotAlpha = [0, 0]
        render(wasIdle ? max(fade, 0.4) : fade)

        let active = activeSlot
        rampVolume(slot: active, to: 0, over: fade)
        fadeInFlight = true
        fadeGeneration += 1
        let generation = fadeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.05) { [weak self] in
            guard let self, self.fadeGeneration == generation else { return }
            self.fadeInFlight = false
            for (i, player) in self.slotPlayers.enumerated() {
                self.volumeTimers[i]?.invalidate()
                player.pause()
                player.volume = 1
            }
            self.prepareArmed()
        }
    }

    func toggleBlackout() {
        blackout.toggle()
        showLog("Blackout \(blackout ? "on" : "off")")
        render(0.4)
    }

    /// Fades to black, stops everything and puts NEXT back on the first video.
    func stop() {
        showLog("Stop")
        phase = .idle
        blackout = false
        playingCueID = nil
        clock.elapsed = 0
        clock.duration = 0
        render(0.5)
        rampVolume(slot: 0, to: 0, over: 0.5)
        rampVolume(slot: 1, to: 0, over: 0.5)

        fadeInFlight = true
        fadeGeneration += 1
        let generation = fadeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self, self.fadeGeneration == generation else { return }
            self.fadeInFlight = false
            for (i, player) in self.slotPlayers.enumerated() {
                self.volumeTimers[i]?.invalidate()
                player.pause()
                player.volume = 1
            }
            self.loopPlayer.pause()
            self.visual.slotAlpha = [0, 0]
            self.visual.loopAlpha = 0
            self.render(0)
            self.prepareLoop(for: nil)
            self.armedByUser = false
            if self.armedCueID == self.cues.first?.id {
                self.prepareArmed()
            } else {
                self.armedCueID = self.cues.first?.id
            }
        }
    }

    // MARK: - Players

    private func load(slot: Int, cue: Cue) {
        for token in slotTokens[slot] { NotificationCenter.default.removeObserver(token) }
        slotTokens[slot] = []

        let item = AVPlayerItem(url: cue.file.url)
        slotCueID[slot] = cue.id
        slotPath[slot] = cue.file.path

        let center = NotificationCenter.default
        slotTokens[slot].append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.videoEnded(slot: slot)
        })
        slotTokens[slot].append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.videoEnded(slot: slot)
        })
        let title = cue.title
        slotStatus[slot] = item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak item] status in
                guard status == .failed, let self else { return }
                self.lastError = "Can't play \"\(title)\": \(item?.error?.localizedDescription ?? "unknown error")"
                showLog(self.lastError ?? "")
                if self.activeSlot == slot, self.phase == .playing { self.showLoop() }
            }

        slotPlayers[slot].replaceCurrentItem(with: item)
    }

    private func videoEnded(slot: Int) {
        guard slot == activeSlot, phase == .playing else { return }
        showLog("Video ended")
        showLoop()
    }

    /// Loads the NEXT video into the free player so it starts instantly. Never touches a player on screen.
    private func prepareArmed() {
        guard let i = index(of: armedCueID) else { return }
        let slot = 1 - activeSlot
        guard visual.slotAlpha[slot] == 0 else { return }
        let cue = cues[i]
        if slotCueID[slot] != cue.id || slotPath[slot] != cue.file.path || slotPlayers[slot].currentItem == nil {
            load(slot: slot, cue: cue)
        } else if slotPlayers[slot].currentTime().seconds > 0.01 {
            slotPlayers[slot].seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    /// Puts the right loop video in the loop player (the video's own loop, or the default).
    private func prepareLoop(for cueID: UUID?) {
        let ref = setlist.loopFor(cueID: cueID)
        guard ref?.path != loopPath || (ref != nil && looper == nil) else { return }
        looper?.disableLooping()
        looper = nil
        loopPlayer.removeAllItems()
        loopPath = ref?.path
        loopName = ref?.name
        guard let ref, ref.exists else { return }
        looper = AVPlayerLooper(player: loopPlayer, templateItem: AVPlayerItem(url: ref.url))
    }

    private func rampVolume(slot: Int, to target: Float, over seconds: Double) {
        volumeTimers[slot]?.invalidate()
        let player = slotPlayers[slot]
        guard seconds > 0 else { player.volume = target; return }
        let start = player.volume
        let begin = Date()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] t in
            let f = min(1, Date().timeIntervalSince(begin) / seconds)
            player.volume = start + (target - start) * Float(f)
            if f >= 1 {
                t.invalidate()
                self?.volumeTimers[slot] = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        volumeTimers[slot] = timer
    }
}
