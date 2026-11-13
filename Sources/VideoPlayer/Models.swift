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
/// Next never plays a loop row. A loop row's video repeats after every video below it, up to the next
/// loop row, so each loop row starts a part of the show. Any video can be turned into a loop and back.
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

    var title: String { file.name }

    init(file: FileRef, isLoop: Bool = false, column: UUID? = nil) {
        self.file = file
        self.isLoop = isLoop
        self.column = column
    }

    private enum CodingKeys: String, CodingKey { case id, file, loop, duration, isLoop, column }

    // Written out so setlists saved before loop rows existed (no "isLoop") still open.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        file = try c.decode(FileRef.self, forKey: .file)
        loop = try c.decodeIfPresent(FileRef.self, forKey: .loop)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        isLoop = try c.decodeIfPresent(Bool.self, forKey: .isLoop) ?? false
        column = try c.decodeIfPresent(UUID.self, forKey: .column)
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

/// Row numbers and the parts of the show, worked out in one pass over the setlist
/// (for the setlist rows, the Loops panel and the log).
struct SetlistLayout {
    /// One loop row and the videos it plays after.
    struct Part {
        var number: Int               // Loop 1, Loop 2 … in setlist order
        var title: String
        var firstVideo: Int? = nil    // video numbers; nil = no videos below it yet
        var lastVideo: Int? = nil

        var videos: [Int] {
            guard let firstVideo, let lastVideo else { return [] }
            return Array(firstVideo...lastVideo)
        }
    }

    private(set) var videoNumber: [UUID: Int] = [:]
    /// Keyed by the loop row's id.
    private(set) var parts: [UUID: Part] = [:]
    /// Video id → the loop row above it.
    private(set) var loopAbove: [UUID: UUID] = [:]
    private(set) var videoCount = 0
    private(set) var loopCount = 0
    /// Videos with no loop row above them and no loop of their own: the screen goes black after them.
    private(set) var videosWithoutLoop: [Int] = []

    init(cues: [Cue]) {
        var current: UUID?
        for cue in cues {
            if cue.isLoop {
                loopCount += 1
                parts[cue.id] = Part(number: loopCount, title: cue.title)
                current = cue.id
            } else {
                videoCount += 1
                videoNumber[cue.id] = videoCount
                if let current {
                    loopAbove[cue.id] = current
                    if parts[current]?.firstVideo == nil { parts[current]?.firstVideo = videoCount }
                    parts[current]?.lastVideo = videoCount
                } else if cue.loop == nil {
                    videosWithoutLoop.append(videoCount)
                }
            }
        }
    }
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
