import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// The setlist and show settings. Saved automatically, so the app reopens where you left off.
final class Setlist: ObservableObject {
    @Published var cues: [Cue] = [] { didSet { scheduleSave() } }
    @Published var defaultLoop: FileRef? { didSet { scheduleSave() } }
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

    func setDefaultLoop(_ url: URL?) {
        defaultLoop = url.map { FileRef(url: $0) }
        if let url { loadThumbnail(path: url.path) }
    }

    /// The loop that plays after a given video (its own loop, or the default one).
    func loopFor(cueID: UUID?) -> FileRef? {
        if let cueID, let cue = cues.first(where: { $0.id == cueID }), let own = cue.loop { return own }
        return defaultLoop
    }

    // MARK: - Panels

    func chooseVideos() {
        let panel = NSOpenPanel()
        panel.title = "Add videos to the setlist"
        panel.allowedContentTypes = Self.videoTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    func chooseLoop(for cueID: UUID?) {
        let panel = NSOpenPanel()
        panel.title = cueID == nil ? "Choose the default loop video" : "Choose the loop for after this video"
        panel.allowedContentTypes = Self.videoTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let cueID { setLoop(url, for: cueID) } else { setDefaultLoop(url) }
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
        ShowFile(cues: cues, defaultLoop: defaultLoop, crossfade: crossfade,
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
        show.defaultLoop?.refresh()

        isLoading = true
        cues = show.cues
        defaultLoop = show.defaultLoop
        crossfade = show.crossfade
        fillScreen = show.fillScreen
        videoAudio = show.videoAudio
        isLoading = false

        for cue in cues {
            loadInfo(cueID: cue.id, path: cue.file.path)
            if let loop = cue.loop { loadThumbnail(path: loop.path) }
        }
        if let loop = defaultLoop { loadThumbnail(path: loop.path) }
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
