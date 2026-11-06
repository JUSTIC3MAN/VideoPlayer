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
    /// Loop shown after this video. nil = use the default loop.
    var loop: FileRef?
    var duration: Double = 0

    var title: String { file.name }
}

/// What is saved to disk (the current setlist and any "Save Setlist As" file).
struct ShowFile: Codable {
    var version = 1
    var cues: [Cue]
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
