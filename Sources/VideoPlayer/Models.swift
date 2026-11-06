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

/// One video in the setlist.
struct Cue: Identifiable, Codable, Equatable {
    var id = UUID()
    var file: FileRef
    /// Loop shown after this video. nil = use Loops 1–3 in turn.
    var loop: FileRef?
    var duration: Double = 0

    var title: String { file.name }
}

/// What is saved to disk (the current setlist and any "Save Setlist As" file).
struct ShowFile: Codable {
    var version = 2
    var cues: [Cue]
    /// Loop 1–3 (version 2). They take turns after the videos.
    var loopSlots: [FileRef?]?
    /// Version 1 had one loop; still read from older setlists (and written as Loop 1's file for them).
    var defaultLoop: FileRef?
    var crossfade: Double
    var fillScreen: Bool
    var videoAudio: Bool
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let t = Int(seconds.rounded(.down))
    if t >= 3600 { return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) }
    return String(format: "%d:%02d", t / 60, t % 60)
}
