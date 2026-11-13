import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// The setlist and show settings. Saved automatically, so the app reopens where you left off.
///
/// The setlist holds videos and loops. A loop row plays after every video below it, up to the next
/// loop row, so the loops split the show into parts (for example videos 1–4 with one loop, videos 5–7
/// with another).
final class Setlist: ObservableObject {
    @Published var cues: [Cue] = [] { didSet { scheduleSave() } }
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
        showLog("Added \(newCues.count) video(s); setlist now \(cues.count) rows")
        for cue in newCues { loadInfo(cueID: cue.id, path: cue.file.path) }
    }

    func remove(ids: Set<UUID>) {
        cues.removeAll { ids.contains($0.id) }
    }

    func move(from source: IndexSet, to destination: Int) {
        cues.move(fromOffsets: source, toOffset: destination)
    }

    /// Turns rows into loops (isLoop true) or back into videos.
    func setLoopRows(_ ids: Set<UUID>, _ isLoop: Bool) {
        var changed = cues
        var names: [String] = []
        for i in changed.indices where ids.contains(changed[i].id) && changed[i].isLoop != isLoop {
            changed[i].isLoop = isLoop
            names.append(changed[i].title)
        }
        guard !names.isEmpty else { return }
        cues = changed
        showLog("\(isLoop ? "Now a loop" : "Now a video"): \(names.joined(separator: ", ")); loops: \(loopSummary())")
    }

    /// A video's own loop (right-click menu). nil = back to the loop above it.
    func setLoop(_ url: URL?, for cueID: UUID) {
        guard let i = cues.firstIndex(where: { $0.id == cueID }) else { return }
        cues[i].loop = url.map { FileRef(url: $0) }
        if let url { loadThumbnail(path: url.path) }
    }

    /// The loop that plays after a row, and the loop row it comes from (nil for a video's own loop).
    /// A video uses its own loop if it has one, otherwise the nearest loop row above it; with no loop row
    /// above it the screen goes black. Before any video has played (cueID nil) it is the first loop row.
    func loopSource(cueID: UUID?) -> (ref: FileRef?, rowID: UUID?) {
        guard let cueID, let i = cues.firstIndex(where: { $0.id == cueID }) else {
            let first = cues.first { $0.isLoop }
            return (first?.file, first?.id)
        }
        let cue = cues[i]
        if cue.isLoop { return (cue.file, cue.id) }
        if let own = cue.loop { return (own, nil) }
        if let row = cues[..<i].last(where: { $0.isLoop }) { return (row.file, row.id) }
        return (nil, nil)
    }

    func loopFor(cueID: UUID?) -> FileRef? {
        loopSource(cueID: cueID).ref
    }

    /// Before any video has played (or after Stop): the loop of the part the NEXT video is in,
    /// or the first loop row when NEXT has no loop.
    func loopSourceBeforeShow(next: UUID?) -> (ref: FileRef?, rowID: UUID?) {
        let source = loopSource(cueID: next)
        if source.ref != nil { return source }
        let first = cues.first { $0.isLoop }
        return (first?.file, first?.id)
    }

    /// For the log: "loop_bars (videos 1-2), loop_2 (videos 3-4)".
    func loopSummary() -> String {
        let layout = SetlistLayout(cues: cues)
        let loops = cues.filter { $0.isLoop }.map { cue -> String in
            guard let part = layout.parts[cue.id], let first = part.firstVideo, let last = part.lastVideo else {
                return "\(cue.title) (no videos)"
            }
            return "\(cue.title) (videos \(first)-\(last))"
        }
        return loops.isEmpty ? "none" : loops.joined(separator: ", ")
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

    /// Add Loop…: picks a video and puts it in the setlist as a loop row at `index` (above that row).
    /// With no index: at the top if there are no loops yet (so it plays after every video), else at the end.
    func chooseLoopRow(insertAt index: Int?) {
        guard let url = pickOneVideo(title: "Choose a loop video") else { return }
        let cue = Cue(file: FileRef(url: url), isLoop: true)
        let position = index ?? (cues.contains { $0.isLoop } ? cues.count : 0)
        cues.insert(cue, at: min(max(position, 0), cues.count))
        loadInfo(cueID: cue.id, path: cue.file.path)
        showLog("Added loop \(cue.title); loops: \(loopSummary())")
    }

    /// Choose a loop video for after one particular video (instead of the loop above it).
    func chooseLoop(for cueID: UUID) {
        guard let url = pickOneVideo(title: "Choose the loop for after this video") else { return }
        setLoop(url, for: cueID)
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
        ShowFile(cues: cues, crossfade: crossfade, fillScreen: fillScreen, videoAudio: videoAudio)
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

        // Setlists from before loop rows: Loop 1 (or version 1's single loop) becomes a loop row at the
        // top, so it still plays after every video. Loops 2 and 3 go at the end, ready to be dragged
        // above the first video of the part they should play in.
        if show.version < 3 {
            let old = (show.loopSlots ?? [show.defaultLoop]).compactMap { $0 }
            if let first = old.first {
                show.cues.insert(Cue(file: first, isLoop: true), at: 0)
                show.cues += old.dropFirst().map { Cue(file: $0, isLoop: true) }
                showLog("Moved the old loops into the setlist as loop rows: \(old.map(\.name).joined(separator: ", "))")
            }
        }
        for i in show.cues.indices {
            show.cues[i].file.refresh()
            show.cues[i].loop?.refresh()
        }

        isLoading = true
        cues = show.cues
        crossfade = show.crossfade
        fillScreen = show.fillScreen
        videoAudio = show.videoAudio
        isLoading = false

        for cue in cues {
            loadInfo(cueID: cue.id, path: cue.file.path)
            if let loop = cue.loop { loadThumbnail(path: loop.path) }
        }
        let layout = SetlistLayout(cues: cues)
        showLog("Loaded setlist: \(layout.videoCount) videos, \(layout.loopCount) loops: \(loopSummary())")
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
