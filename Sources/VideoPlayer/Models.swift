import Foundation

/// A video file on disk. The bookmark lets the setlist follow a file that was moved or renamed.
struct FileRef: Codable, Equatable {
    var path: String
    var bookmark: Data?

    init(url: URL) {
        path = url.path
        bookmark = try? url.bookmarkData()
    }

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    /// Re-finds the file through its bookmark (called once when a setlist is loaded).
    mutating func refresh() {
        guard let bookmark else { return }
        var stale = false
        if let found = try? URL(resolvingBookmarkData: bookmark,
                                options: [.withoutUI, .withoutMounting],
                                relativeTo: nil,
                                bookmarkDataIsStale: &stale) {
            path = found.path
            if stale { self.bookmark = try? found.bookmarkData() }
        }
    }
}

/// A named column of the setlist: one artist or part of the show. The show plays the columns left to right,
/// each from top to bottom.
struct ShowColumn: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
}

/// One row of the setlist: a video, or a loop.
///
/// A loop row's video repeats after the videos it belongs to: the ones whose numbers were typed into it, or,
/// with no numbers typed, every video below it up to the next such loop row. A loop that no video plays
/// (an artist with only loops) is a stop of its own for Next and Previous. Any video can be turned into a
/// loop and back.
struct Cue: Identifiable, Codable, Equatable {
    var id = UUID()
    var file: FileRef
    /// Loop shown after this video instead of the loop above it (right-click menu). nil = the loop above it.
    var loop: FileRef?
    var duration: Double = 0
    /// true = this row is a loop (see above).
    var isLoop = false
    /// The column it is in. nil (setlists from before columns): the first column.
    var column: UUID?
    /// For a loop row: the videos it plays after, picked by typing their numbers. They stay with those videos
    /// when the setlist is reordered. nil: the videos below it instead.
    var covers: [UUID]?

    var title: String { file.name }

    init(file: FileRef, isLoop: Bool = false, column: UUID? = nil, covers: [UUID]? = nil) {
        self.file = file
        self.isLoop = isLoop
        self.column = column
        self.covers = covers
    }

    private enum CodingKeys: String, CodingKey { case id, file, loop, duration, isLoop, column, covers }

    // Written out so setlists saved before loop rows existed (no "isLoop") still open.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        file = try c.decode(FileRef.self, forKey: .file)
        loop = try c.decodeIfPresent(FileRef.self, forKey: .loop)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        isLoop = try c.decodeIfPresent(Bool.self, forKey: .isLoop) ?? false
        column = try c.decodeIfPresent(UUID.self, forKey: .column)
        covers = try c.decodeIfPresent([UUID].self, forKey: .covers)
    }
}

/// What is saved to disk (the current setlist and any "Save Setlist As" file).
struct ShowFile: Codable {
    /// 4: named columns. 3: loops are rows in the setlist. 2 had Loops 1–3 taking turns. 1 had a single loop.
    var version = 4
    var cues: [Cue]
    /// The columns, left to right (version 4). Missing in older setlists: made when loading.
    var columns: [ShowColumn]?
    /// Version 2's Loops 1–3. Only read (they become loop rows), never written.
    var loopSlots: [FileRef?]?
    /// Version 1's single loop. Only read (it becomes a loop row), never written.
    var defaultLoop: FileRef?
    var crossfade: Double
    var fillScreen: Bool
    var videoAudio: Bool
}

/// Row numbers, which loop plays after each video, and the stops for Next, worked out in one pass over the
/// setlist (for the setlist rows, the Loops panel, the engine and the log).
///
/// Which loop plays after a video: its own loop (right-click menu), else the loop whose typed numbers include
/// it, else the nearest loop row above it that has no typed numbers, else none (black).
struct SetlistLayout {
    /// One loop row and the videos it plays after.
    struct Part {
        var number: Int               // Loop 1, Loop 2 … in setlist order
        var title: String
        var videos: [Int] = []        // video numbers, in order
        /// Its videos were picked by typing their numbers (not by where it sits).
        var typed = false
    }

    private(set) var videoNumber: [UUID: Int] = [:]
    /// Keyed by the loop row's id.
    private(set) var parts: [UUID: Part] = [:]
    /// Video id → the loop row that plays after it (videos with their own loop or no loop aren't in it).
    private(set) var loopOf: [UUID: UUID] = [:]
    private(set) var videoCount = 0
    private(set) var loopCount = 0
    /// Videos with no loop at all: the screen goes black after them.
    private(set) var videosWithoutLoop: [Int] = []
    /// What Next and Previous step through, column by column: when the show moves into a column, that column's
    /// loop comes up first (the first loop in it, or else the loop of its first video), so an artist's loop is up
    /// while they walk on; then the column's videos, and its loops that no video plays. A loop can be in it twice
    /// (the first loop for two columns). Columns with nothing to stop on (say, loops parked there for their typed
    /// numbers) add nothing.
    private(set) var steps: [UUID] = []

    init(cues: [Cue]) {
        // Every loop first (a video can come before the loop its typed numbers put it in)
        var typedLoop: [UUID: UUID] = [:]
        for cue in cues where cue.isLoop {
            loopCount += 1
            parts[cue.id] = Part(number: loopCount, title: cue.title, typed: cue.covers != nil)
            for video in cue.covers ?? [] where typedLoop[video] == nil { typedLoop[video] = cue.id }
        }
        var above: UUID?      // the nearest loop row above with no typed numbers
        for cue in cues {
            if cue.isLoop {
                if cue.covers == nil { above = cue.id }
            } else {
                videoCount += 1
                videoNumber[cue.id] = videoCount
                guard cue.loop == nil else { continue }          // it has its own loop
                if let loop = typedLoop[cue.id] ?? above {
                    loopOf[cue.id] = loop
                    parts[loop]?.videos.append(videoCount)
                } else {
                    videosWithoutLoop.append(videoCount)
                }
            }
        }
        var loopUp: UUID?       // the loop that is up after the previous column's last stop
        var start = 0
        while start < cues.count {
            var end = start
            while end < cues.count && cues[end].column == cues[start].column { end += 1 }
            let rows = cues[start..<end]
            let own = rows.filter { !$0.isLoop || (parts[$0.id]?.videos.isEmpty ?? true) }.map(\.id)
            if let last = own.last {
                let first = rows.first(where: { $0.isLoop })?.id ?? rows.first(where: { !$0.isLoop }).flatMap { loopOf[$0.id] }
                if let first, !own.contains(first), first != loopUp { steps.append(first) }
                steps += own
                loopUp = parts[last] != nil ? last : loopOf[last]
            }
            start = end
        }
    }

    func isStop(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return steps.contains(id)
    }
}

/// For the log: "1-4", "1-2, 5-5" (always first-last, so a single video reads "3-3").
func videoRunsForLog(_ numbers: [Int]) -> String {
    var runs: [(first: Int, last: Int)] = []
    for n in numbers.sorted() {
        if let last = runs.last, last.last + 1 == n { runs[runs.count - 1].last = n } else { runs.append((n, n)) }
    }
    return runs.map { "\($0.first)-\($0.last)" }.joined(separator: ", ")
}

/// "video 3", "videos 1–4", "videos 1–2, 5" (empty: "no videos").
func videosText(_ numbers: [Int]) -> String {
    guard !numbers.isEmpty else { return "no videos" }
    var runs: [(first: Int, last: Int)] = []
    for n in numbers.sorted() {
        if let last = runs.last, last.last + 1 == n {
            runs[runs.count - 1].last = n
        } else {
            runs.append((n, n))
        }
    }
    let text = runs.map { $0.first == $0.last ? "\($0.first)" : "\($0.first)–\($0.last)" }.joined(separator: ", ")
    return (numbers.count == 1 ? "video " : "videos ") + text
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let t = Int(seconds.rounded(.down))
    if t >= 3600 { return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) }
    return String(format: "%d:%02d", t / 60, t % 60)
}
