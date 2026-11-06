import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// The setlist and show settings. Saved automatically, so the app reopens where you left off.
final class Setlist: ObservableObject {
    @Published var cues: [Cue] = [] { didSet { scheduleSave() } }
    /// Loop 1, Loop 2, Loop 3 (nil = empty slot). After video 1 comes Loop 1, after video 2 Loop 2,
    /// after video 3 Loop 3, after video 4 Loop 1 again, and so on. Empty slots are skipped.
    @Published var loopSlots: [FileRef?] = Array(repeating: nil, count: Setlist.loopSlotCount) { didSet { scheduleSave() } }
    static let loopSlotCount = 3
    @Published var crossfade: Double = 0.5 { didSet { scheduleSave() } }
    @Published var fillScreen = false { didSet { scheduleSave() } }
    @Published var videoAudio = true { didSet { scheduleSave() } }

    /// Thumbnails keyed by file path (videos and loops).
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    /// Paths of files that could not be found.
    @Published private(set) var missing: Set<String> = []

    private var saveWork: DispatchWorkItem?
    private var isLoading = false

    private static let videoTypes: [UTType] = [.movie, .video]

    private var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VideoPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Current Setlist.json")
    }

    init() {
        load(from: storeURL)
    }

    // MARK: - Editing

    static func isVideo(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }

    func add(urls: [URL], at index: Int? = nil) {
        let videos = urls.filter(Self.isVideo)
        guard !videos.isEmpty else { showLog("Add: none of the chosen files are videos"); NSSound.beep(); return }
        let newCues = videos.map { Cue(file: FileRef(url: $0)) }
        let position = min(max(index ?? cues.count, 0), cues.count)
        cues.insert(contentsOf: newCues, at: position)
        showLog("Added \(newCues.count) video(s); setlist now \(cues.count)")
        for cue in newCues { loadInfo(cueID: cue.id, path: cue.file.path) }
    }

    func remove(ids: Set<UUID>) {
        cues.removeAll { ids.contains($0.id) }
    }

    func move(from source: IndexSet, to destination: Int) {
        cues.move(fromOffsets: source, toOffset: destination)
    }

    func setLoop(_ url: URL?, for cueID: UUID) {
        guard let i = cues.firstIndex(where: { $0.id == cueID }) else { return }
        cues[i].loop = url.map { FileRef(url: $0) }
        if let url { loadThumbnail(path: url.path) }
    }

    func setLoopSlot(_ slot: Int, _ url: URL?) {
        guard loopSlots.indices.contains(slot) else { return }
        loopSlots[slot] = url.map { FileRef(url: $0) }
        if let url { loadThumbnail(path: url.path) }
    }

    /// The loop that plays after a video: its own loop if it has one, otherwise Loops 1–3 in turn by the
    /// video's place in the setlist (video 1 → Loop 1, 2 → Loop 2, 3 → Loop 3, 4 → Loop 1 …).
    /// Before any video has played (cueID nil) it is the first loop.
    func loopFor(cueID: UUID?) -> FileRef? {
        let filled = loopSlots.compactMap { $0 }
        guard let cueID, let i = cues.firstIndex(where: { $0.id == cueID }) else { return filled.first }
        if let own = cues[i].loop { return own }
        return filled.isEmpty ? nil : filled[i % filled.count]
    }

    /// Which loop slot (1–3) follows the video at this position. nil when it has its own loop or no loops are set.
    func loopSlotNumber(forCueAt i: Int) -> Int? {
        guard cues.indices.contains(i), cues[i].loop == nil else { return nil }
        let filled = loopSlots.indices.filter { loopSlots[$0] != nil }
        guard !filled.isEmpty else { return nil }
        return filled[i % filled.count] + 1
    }

    // MARK: - Panels

    func chooseVideos() {
        let panel = NSOpenPanel()
        panel.title = "Add videos to the setlist"
        panel.allowedContentTypes = Self.videoTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        showLog("Add Videos: opening the file window")
        let result = panel.runModal()
        showLog("Add Videos: \(result == .OK ? "\(panel.urls.count) file(s) chosen" : "cancelled")")
        if result == .OK { add(urls: panel.urls) }
    }

    /// Choose a loop video for after one particular video (overrides the turn-taking loops).
    func chooseLoop(for cueID: UUID) {
        guard let url = pickOneVideo(title: "Choose the loop for after this video") else { return }
        setLoop(url, for: cueID)
    }

    /// Choose the video for Loop 1, 2 or 3 (slot 0, 1, 2).
    func chooseLoopSlot(_ slot: Int) {
        guard let url = pickOneVideo(title: "Choose the video for Loop \(slot + 1)") else { return }
        setLoopSlot(slot, url)
    }

    private func pickOneVideo(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = Self.videoTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func saveSetlistFile() {
        let panel = NSSavePanel()
        panel.title = "Save setlist"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Setlist.json"
        if panel.runModal() == .OK, let url = panel.url { write(to: url) }
    }

    func openSetlistFile() {
        let panel = NSOpenPanel()
        panel.title = "Open a saved setlist"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(from: url)
        saveNow()
    }

    // MARK: - Saving

    private func snapshot() -> ShowFile {
        ShowFile(cues: cues, loopSlots: loopSlots, defaultLoop: loopSlots.compactMap { $0 }.first, crossfade: crossfade,
                 fillScreen: fillScreen, videoAudio: videoAudio)
    }

    private func write(to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot()) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func scheduleSave() {
        guard !isLoading else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        write(to: storeURL)
    }

    private func load(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              var show = try? JSONDecoder().decode(ShowFile.self, from: data) else { return }
        for i in show.cues.indices {
            show.cues[i].file.refresh()
            show.cues[i].loop?.refresh()
        }
        // Older setlists had a single loop: it becomes Loop 1.
        var slots = show.loopSlots ?? [show.defaultLoop]
        if slots.count < Self.loopSlotCount { slots += Array(repeating: nil, count: Self.loopSlotCount - slots.count) }
        slots = Array(slots.prefix(Self.loopSlotCount))
        for i in slots.indices { slots[i]?.refresh() }

        isLoading = true
        cues = show.cues
        loopSlots = slots
        crossfade = show.crossfade
        fillScreen = show.fillScreen
        videoAudio = show.videoAudio
        isLoading = false

        for cue in cues {
            loadInfo(cueID: cue.id, path: cue.file.path)
            if let loop = cue.loop { loadThumbnail(path: loop.path) }
        }
        for case let loop? in loopSlots { loadThumbnail(path: loop.path) }
        showLog("Loaded setlist: \(cues.count) videos; loops: \(loopSlots.map { $0?.name ?? "-" }.joined(separator: ", "))")
    }

    // MARK: - Durations and thumbnails (loaded in the background)

    private func loadInfo(cueID: UUID, path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            missing.insert(path)
            return
        }
        missing.remove(path)
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        Task { @MainActor [weak self] in
            let seconds = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
            guard let self else { return }
            if seconds.isFinite, seconds > 0,
               let i = self.cues.firstIndex(where: { $0.id == cueID }),
               abs(self.cues[i].duration - seconds) > 0.01 {
                self.cues[i].duration = seconds
            }
            await self.makeThumbnail(asset: asset, path: path, duration: seconds)
        }
    }

    func loadThumbnail(path: String) {
        guard thumbnails[path] == nil, FileManager.default.fileExists(atPath: path) else { return }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        Task { @MainActor [weak self] in
            let seconds = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
            await self?.makeThumbnail(asset: asset, path: path, duration: seconds)
        }
    }

    @MainActor
    private func makeThumbnail(asset: AVAsset, path: String, duration: Double) async {
        guard thumbnails[path] == nil else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        let at = duration.isFinite && duration > 2 ? min(duration * 0.25, 10) : 0
        guard let result = try? await generator.image(at: CMTime(seconds: at, preferredTimescale: 600)) else { return }
        thumbnails[path] = NSImage(cgImage: result.image, size: .zero)
    }
}
