// What Next (A) steps through, worked out by the app's own SetlistLayout for small made-up shows.
// Built and run by the UI test: swiftc Sources/VideoPlayer/Models.swift .github/layout-check/main.swift
import Foundation

var failures = 0

func file(_ name: String) -> FileRef { FileRef(url: URL(fileURLWithPath: "/tmp/layout-check/\(name).mp4")) }

func video(_ name: String, in column: UUID, ownLoop: String? = nil) -> Cue {
    var cue = Cue(file: file(name), column: column)
    if let ownLoop { cue.loop = file(ownLoop) }
    return cue
}

func loop(_ name: String, in column: UUID) -> Cue { Cue(file: file(name), isLoop: true, column: column) }

/// Types video numbers into a loop: the loop then plays after those videos.
func typeNumbers(_ videos: [Cue], into name: String, _ cues: inout [Cue]) {
    guard let i = cues.firstIndex(where: { $0.title == name && $0.isLoop }) else { fatalError("no loop \(name)") }
    cues[i].covers = videos.map(\.id)
}

func check(_ name: String, _ cues: [Cue], _ want: [String]) {
    let got = SetlistLayout(cues: cues).steps.map { id in cues.first { $0.id == id }?.title ?? "?" }
    if got == want {
        print("ok    \(name): \(got.joined(separator: " → "))")
    } else {
        failures += 1
        print("FAIL  \(name)\n      got:  \(got.joined(separator: " → "))\n      want: \(want.joined(separator: " → "))")
    }
}

do {  // The UI test's setlist: the show starts with the first column's loop; column 2 starts with its loop
    let a = UUID(), b = UUID()
    check("test setlist", [loop("loop_bars", in: a), video("red", in: a), video("blue", in: a),
                           loop("loop_2", in: b), video("green", in: b), video("yellow", in: b, ownLoop: "loop_3")],
          ["loop_bars", "red", "blue", "loop_2", "green", "yellow"])
}

do {  // A DJ with only a loop between two artists whose loops have typed numbers
    let a = UUID(), dj = UUID(), c = UUID()
    let a1 = video("a1", in: a), a2 = video("a2", in: a), a3 = video("a3", in: a), a4 = video("a4", in: a)
    let c5 = video("c5", in: c), c6 = video("c6", in: c)
    var cues = [loop("loopA", in: a), a1, a2, a3, a4, loop("loopDJ", in: dj), loop("loopC", in: c), c5, c6]
    typeNumbers([a1, a2, a3, a4], into: "loopA", &cues)
    typeNumbers([c5, c6], into: "loopC", &cues)
    check("DJ between artists", cues, ["loopA", "a1", "a2", "a3", "a4", "loopDJ", "loopC", "c5", "c6"])
}

do {  // Two loops-only artists in a row
    let a = UUID(), dj1 = UUID(), dj2 = UUID(), c = UUID()
    check("two DJs in a row", [loop("loopA", in: a), video("a1", in: a), loop("dj1", in: dj1), loop("dj2", in: dj2),
                               loop("loopC", in: c), video("c1", in: c)],
          ["loopA", "a1", "dj1", "dj2", "loopC", "c1"])
}

do {  // Every loop parked in one column with typed numbers: each artist still gets their loop first
    let l = UUID(), a = UUID(), b = UUID()
    let a1 = video("a1", in: a), a2 = video("a2", in: a), b3 = video("b3", in: b)
    var cues = [loop("loop1", in: l), loop("loop2", in: l), a1, a2, b3]
    typeNumbers([a1, a2], into: "loop1", &cues)
    typeNumbers([b3], into: "loop2", &cues)
    check("loops parked in one column", cues, ["loop1", "a1", "a2", "loop2", "b3"])
}

do {  // An artist with no loop of their own: the loop already up stays (no extra stop)
    let a = UUID(), b = UUID()
    check("artist without a loop", [loop("loopA", in: a), video("a1", in: a), video("b1", in: b), video("b2", in: b)],
          ["loopA", "a1", "b1", "b2"])
}

do {  // The same loop typed for two artists side by side: already up, so no extra stop
    let a = UUID(), b = UUID()
    let a1 = video("a1", in: a), b2 = video("b2", in: b)
    var cues = [loop("loopX", in: a), a1, b2]
    typeNumbers([a1, b2], into: "loopX", &cues)
    check("same loop for two artists", cues, ["loopX", "a1", "b2"])
}

do {  // A DJ's loop that the next artist's videos also play after: shown once, between them
    let a = UUID(), dj = UUID(), b = UUID()
    check("DJ loop carries on", [loop("loopA", in: a), video("a1", in: a), loop("dj", in: dj), video("b1", in: b)],
          ["loopA", "a1", "dj", "b1"])
}

do {  // One loop for two artists with another artist between them: it comes up first for both
    let a = UUID(), b = UUID(), c = UUID()
    let a1 = video("a1", in: a), b2 = video("b2", in: b), c3 = video("c3", in: c)
    var cues = [loop("loopX", in: a), a1, loop("loopB", in: b), b2, c3]
    typeNumbers([a1, c3], into: "loopX", &cues)
    check("loop shared across the show", cues, ["loopX", "a1", "loopB", "b2", "loopX", "c3"])
}

if failures > 0 {
    print("::error title=Loop order check::\(failures) show(s) step in the wrong order")
    exit(1)
}
print("::notice title=Loop order check::every made-up show steps in the expected order")
