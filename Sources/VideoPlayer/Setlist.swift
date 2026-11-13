import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// The setlist and show settings. Saved automatically, so the app reopens where you left off.
///
/// The setlist holds videos and loops in named columns (artists or parts of the show). The show plays the
/// columns left to right, each from top to bottom. A loop row plays after every video below it, up to the
/// next loop row, so a loop at the top of a column plays after that column's videos.
final class Setlist: ObservableObject {
    /// Every row in show order: column by column, left to right, each column top to bottom.
    @Published var cues: [Cue] = [] { didSet { scheduleSave() } }
    /// The columns, left to right. There is always at least one.
    @Published var columns: [ShowColumn] = [ShowColumn(name: "Part 1")] { didSet { scheduleSave() } }
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

    /// Adds videos to a column (nil or unknown: the last column), at a position in that column (nil: the end).
    func add(urls: [URL], to columnID: UUID? = nil, at index: Int? = nil) {
        let videos = urls.filter(Self.isVideo)
        guard !videos.isEmpty else { showLog("Add: none of the chosen files are videos"); NSSound.beep(); return }
        let column = columnID.flatMap { id in columns.contains { $0.id == id } ? id : nil } ?? columns[columns.count - 1].id
        let newCues = videos.map { Cue(file: FileRef(url: $0), column: column) }
        var rows = cues(in: column)
        rows.insert(contentsOf: newCues, at: min(max(index ?? rows.count, 0), rows.count))
        replace(column, with: rows)
        showLog("Added \(newCues.count) video(s) to \(columnName(column)); setlist now \(cues.count) rows")
        for cue in newCues { loadInfo(cueID: cue.id, path: cue.file.path) }
    }

    func remove(ids: Set<UUID>) {
        cues.removeAll { ids.contains($0.id) }
    }

    // MARK: - Columns

    /// The column a row is in. Rows from before columns existed (or whose column is gone) are in the first one.
    func columnID(of cue: Cue) -> UUID {
        if let id = cue.column, columns.contains(where: { $0.id == id }) { return id }
        return columns[0].id
    }

    func cues(in columnID: UUID) -> [Cue] {
        cues.filter { self.columnID(of: $0) == columnID }
    }

    func columnName(_ id: UUID) -> String {
        let name = columns.first { $0.id == id }?.name ?? ""
        return name.isEmpty ? "Untitled" : name
    }

    /// Show order from each column's rows: every column, left to right.
    private func showOrder(_ rowsOf: (UUID) -> [Cue]) -> [Cue] {
        columns.flatMap { column in
            rowsOf(column.id).map { cue -> Cue in
                var cue = cue
                cue.column = column.id
                return cue
            }
        }
    }

    private func rowsByColumn(_ rows: [Cue]) -> [UUID: [Cue]] {
        Dictionary(grouping: rows, by: { self.columnID(of: $0) })
    }

    private func replace(_ columnID: UUID, with rows: [Cue]) {
        let others = rowsByColumn(cues)
        cues = showOrder { $0 == columnID ? rows : (others[$0] ?? []) }
    }

    /// Adds an empty column at the right end and returns it (so its name can be typed in straight away).
    @discardableResult
    func addColumn() -> UUID {
        var number = columns.count + 1
        while columns.contains(where: { $0.name == "Part \(number)" }) { number += 1 }
        let column = ShowColumn(name: "Part \(number)")
        columns.append(column)
        showLog("Added column \(column.name); columns: \(columnSummary())")
        return column.id
    }

    func renameColumn(_ id: UUID, to name: String) {
        guard let i = columns.firstIndex(where: { $0.id == id }), columns[i].name != name else { return }
        columns[i].name = name
    }

    /// Moves a column left (-1) or right (+1). The show order follows.
    func moveColumn(_ id: UUID, by offset: Int) {
        guard let i = columns.firstIndex(where: { $0.id == id }), columns.indices.contains(i + offset) else { return }
        let rows = rowsByColumn(cues)
        columns.swapAt(i, i + offset)
        cues = showOrder { rows[$0] ?? [] }
        showLog("Moved column \(columnName(id)); columns: \(columnSummary())")
    }

    /// Removes a column. Its rows go to the end of the column on its left (the first column's go to the
    /// start of the next one), so no video is lost.
    func removeColumn(_ id: UUID) {
        guard columns.count > 1, let i = columns.firstIndex(where: { $0.id == id }) else { return }
        var rows = rowsByColumn(cues)
        let moving = rows[id] ?? []
        if i > 0 {
            rows[columns[i - 1].id, default: []] += moving
        } else {
            rows[columns[i + 1].id] = moving + (rows[columns[i + 1].id] ?? [])
        }
        let name = columnName(id)
        columns.remove(at: i)
        cues = showOrder { rows[$0] ?? [] }
        showLog("Removed column \(name); columns: \(columnSummary())")
    }

    /// A drag within one column.
    func move(in columnID: UUID, from source: IndexSet, to destination: Int) {
        var rows = cues(in: columnID)
        rows.move(fromOffsets: source, toOffset: destination)
        replace(columnID, with: rows)
        showLog("Reordered column \(columnName(columnID))")
    }

    /// Moves rows into a column (Move to Column, or a drag from another column), at a position in that
    /// column (nil: the end). The position counts the column's rows as they are before the move.
    func moveRows(_ ids: Set<UUID>, to columnID: UUID, at index: Int? = nil) {
        let moving = cues.filter { ids.contains($0.id) }
        guard !moving.isEmpty, columns.contains(where: { $0.id == columnID }) else { return }
        let target = cues(in: columnID)
        let position = index.map { i in target.prefix(i).filter { !ids.contains($0.id) }.count }
        var rows = target.filter { !ids.contains($0.id) }
        rows.insert(contentsOf: moving, at: min(max(position ?? rows.count, 0), rows.count))
        let others = rowsByColumn(cues.filter { !ids.contains($0.id) })
        cues = showOrder { $0 == columnID ? rows : (others[$0] ?? []) }
        showLog("Moved \(moving.map(\.title).joined(separator: ", ")) to column \(columnName(columnID))")
    }

    /// For the log: "Kimiko (3 rows), Ras Manuel (4 rows)".
    func columnSummary() -> String {
        let rows = rowsByColumn(cues)
        return columns.map { "\(columnName($0.id)) (\(rows[$0.id]?.count ?? 0) rows)" }.joined(separator: ", ")
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

    /// Add Videos: into a column (nil: the last column).
    func chooseVideos(into columnID: UUID? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Add videos to the setlist"
        panel.allowedContentTypes = Self.videoTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        showLog("Add Videos: opening the file window")
        let result = panel.runModal()
        showLog("Add Videos: \(result == .OK ? "\(panel.urls.count) file(s) chosen" : "cancelled")")
        if result == .OK { add(urls: panel.urls, to: columnID) }
    }

    /// Add Loop…: picks a video and puts it in the setlist as a loop row above the row at `index` (in
    /// show order). With no index: at the top if there are no loops yet (so it plays after every video),
    /// else at the end.
    func chooseLoopRow(insertAt index: Int?) {
        let position = index ?? (cues.contains { $0.isLoop } ? cues.count : 0)
        if position < cues.count {
            let anchor = cues[position]
            let column = columnID(of: anchor)
            chooseLoopRow(column: column, at: cues(in: column).firstIndex { $0.id == anchor.id })
        } else {
            chooseLoopRow(column: cues.isEmpty ? columns[0].id : columns[columns.count - 1].id, at: nil)
        }
    }

    /// Add Loop…: picks a video and puts it in a column as a loop row, at a position in that column (nil: the end).
    func chooseLoopRow(column: UUID, at index: Int?) {
        guard let url = pickOneVideo(title: "Choose a loop video") else { return }
        let cue = Cue(file: FileRef(url: url), isLoop: true, column: column)
        var rows = cues(in: column)
        rows.insert(cue, at: min(max(index ?? rows.count, 0), rows.count))
        replace(column, with: rows)
        loadInfo(cueID: cue.id, path: cue.file.path)
        showLog("Added loop \(cue.title) to \(columnName(column)); loops: \(loopSummary())")
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
        ShowFile(cues: cues, columns: columns, crossfade: crossfade, fillScreen: fillScreen, videoAudio: videoAudio)
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

        // Setlists from before columns: a new column starts at each loop row, so each part of the show
        // gets its own column ("Part 1", "Part 2" …, ready to be renamed).
        var loadedColumns = show.columns ?? []
        if loadedColumns.isEmpty {
            var rowsInColumn = 0
            for i in show.cues.indices {
                if loadedColumns.isEmpty || (show.cues[i].isLoop && rowsInColumn > 0) {
                    loadedColumns.append(ShowColumn(name: "Part \(loadedColumns.count + 1)"))
                    rowsInColumn = 0
                }
                show.cues[i].column = loadedColumns.last?.id
                rowsInColumn += 1
            }
            if loadedColumns.isEmpty { loadedColumns = [ShowColumn(name: "Part 1")] }
        }

        isLoading = true
        columns = loadedColumns
        let rows = rowsByColumn(show.cues)
        cues = showOrder { rows[$0] ?? [] }
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
        showLog("Columns: \(columnSummary())")
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
