import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ControlView: View {
    @State private var selection = Set<UUID>()

    var body: some View {
        HSplitView {
            SetlistPane(selection: $selection)
                .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
            SidePanel()
                .frame(minWidth: 360, idealWidth: 400, maxWidth: 480, maxHeight: .infinity)
        }
    }
}

// MARK: - Setlist

struct SetlistPane: View {
    @EnvironmentObject var setlist: Setlist
    @EnvironmentObject var engine: PlaybackEngine
    @Binding var selection: Set<UUID>

    private var totalTime: String {
        formatTime(setlist.cues.reduce(0) { $0 + $1.duration })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Setlist").font(.title2.bold())
                Text("\(setlist.cues.count) videos · \(totalTime)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button { setlist.chooseVideos() } label: { Label("Add Videos", systemImage: "plus") }
                Button {
                    setlist.remove(ids: selection)
                    selection.removeAll()
                } label: { Label("Remove", systemImage: "minus") }
                .disabled(selection.isEmpty)
            }
            .padding(12)
            Divider()

            if setlist.cues.isEmpty {
                EmptyDropZone()
            } else {
                List(selection: $selection) {
                    ForEach(Array(setlist.cues.enumerated()), id: \.element.id) { index, cue in
                        CueRow(index: index, cue: cue)
                            .tag(cue.id)
                    }
                    .onMove { setlist.move(from: $0, to: $1) }
                    .onInsert(of: [.fileURL]) { index, providers in
                        loadFileURLs(providers) { setlist.add(urls: $0, at: index) }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .onDeleteCommand {
                    setlist.remove(ids: selection)
                    selection.removeAll()
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    rowMenu(ids)
                } primaryAction: { ids in
                    // Double-click plays the video now.
                    if let id = ids.first { engine.playNow(id) }
                }
            }

            Divider()
            Text("Drag rows to reorder · drop videos from Finder · double-click plays a video now · right-click for its own loop")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<UUID>) -> some View {
        if ids.count == 1, let id = ids.first {
            Button("Play Now") { engine.playNow(id) }
            Button("Set as Next") { engine.arm(id) }
            Divider()
            Button("Choose Loop for After This Video…") { setlist.chooseLoop(for: id) }
            if setlist.cues.first(where: { $0.id == id })?.loop != nil {
                Button("Use the Default Loop") { setlist.setLoop(nil, for: id) }
            }
            Divider()
        }
        if !ids.isEmpty {
            Button("Show in Finder") {
                let urls = setlist.cues.filter { ids.contains($0.id) }.map { $0.file.url }
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
            Button("Remove") {
                setlist.remove(ids: ids)
                selection.subtract(ids)
            }
        }
    }
}

struct CueRow: View {
    @EnvironmentObject var setlist: Setlist
    @EnvironmentObject var engine: PlaybackEngine
    let index: Int
    let cue: Cue

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(.title3, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
            Thumbnail(image: setlist.thumbnails[cue.file.path])
                .frame(width: 112, height: 63)
            VStack(alignment: .leading, spacing: 3) {
                Text(cue.title).font(.headline).lineLimit(1)
                HStack(spacing: 8) {
                    Text(formatTime(cue.duration)).monospacedDigit()
                    if let loop = cue.loop {
                        Label("then loop: \(loop.name)", systemImage: "repeat").lineLimit(1)
                    } else {
                        Label("then default loop", systemImage: "repeat")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if setlist.missing.contains(cue.file.path) {
                    Label("File not found", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 8)
            if engine.playingCueID == cue.id {
                StateBadge(text: engine.phase == .playing ? "PLAYING" : "LOOP AFTER",
                           color: engine.phase == .playing ? .green : .orange)
            }
            if engine.armedCueID == cue.id {
                StateBadge(text: "NEXT", color: .blue)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StateBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
    }
}

struct Thumbnail: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "film").foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

struct EmptyDropZone: View {
    @EnvironmentObject var setlist: Setlist
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Drop videos here").font(.title3)
            Button("Add Videos…") { setlist.chooseVideos() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(targeted ? Color.accentColor.opacity(0.12) : Color.clear)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            loadFileURLs(providers) { setlist.add(urls: $0) }
            return true
        }
    }
}

/// Reads dropped Finder files, keeping the order they were dropped in.
func loadFileURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    final class Collected {
        let lock = NSLock()
        var urls: [Int: URL] = [:]
    }
    let collected = Collected()
    let group = DispatchGroup()
    let fileURLType = UTType.fileURL.identifier
    for (i, provider) in providers.enumerated() where provider.hasItemConformingToTypeIdentifier(fileURLType) {
        group.enter()
        _ = provider.loadDataRepresentation(forTypeIdentifier: fileURLType) { data, _ in
            if let data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                collected.lock.lock()
                collected.urls[i] = url
                collected.lock.unlock()
            }
            group.leave()
        }
    }
    group.notify(queue: .main) {
        completion(collected.urls.keys.sorted().compactMap { collected.urls[$0] })
    }
}

// MARK: - Side panel

struct SidePanel: View {
    @EnvironmentObject var engine: PlaybackEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StageMonitor()
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topLeading) { PhaseTag().padding(8) }
                ClockView(clock: engine.clock)
                if let error = engine.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                TransportView()
                GroupBox("Loop visual") { LoopPicker().padding(4) }
                GroupBox("Output") { OutputSettings().padding(4) }
                ShortcutHelp()
            }
            .padding(14)
        }
    }
}

struct PhaseTag: View {
    @EnvironmentObject var engine: PlaybackEngine

    private var phaseInfo: (String, Color) {
        if engine.blackout { return ("BLACKOUT", .gray) }
        switch engine.phase {
        case .idle: return ("STANDBY", .gray)
        case .playing: return ("PLAYING", .green)
        case .loop: return ("LOOP", .orange)
        }
    }

    var body: some View {
        StateBadge(text: phaseInfo.0, color: phaseInfo.1)
    }
}

struct ClockView: View {
    @ObservedObject var clock: ShowClock

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Elapsed").font(.caption).foregroundStyle(.secondary)
                    Text(formatTime(clock.elapsed))
                        .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Remaining").font(.caption).foregroundStyle(.secondary)
                    Text("-" + formatTime(max(0, clock.duration - clock.elapsed)))
                        .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(clock.duration > 0 && clock.duration - clock.elapsed < 10 ? Color.orange : Color.primary)
                }
            }
            SeekBar(clock: clock)
        }
    }
}

/// The time bar under the preview. Click or drag it to jump to a point in the playing video.
struct SeekBar: View {
    @EnvironmentObject var engine: PlaybackEngine
    @ObservedObject var clock: ShowClock
    @State private var dragFraction: Double?
    @State private var hovering = false

    private var canSeek: Bool { engine.phase == .playing && clock.duration > 0 }
    private var active: Bool { canSeek && (hovering || dragFraction != nil) }

    private var fraction: Double {
        if let dragFraction { return dragFraction }
        guard clock.duration > 0 else { return 0 }
        return min(max(clock.elapsed / clock.duration, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let barHeight: CGFloat = active ? 8 : 6
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                    .frame(height: barHeight)
                Capsule().fill(Color.accentColor)
                    .frame(width: max(barHeight, width * CGFloat(fraction)), height: barHeight)
                    .opacity(fraction > 0 ? 1 : 0)
                if active {
                    Circle().fill(Color.white)
                        .shadow(color: .black.opacity(0.35), radius: 1.5)
                        .frame(width: 14, height: 14)
                        .offset(x: width * CGFloat(fraction) - 7)
                }
            }
            .frame(width: width, height: geo.size.height)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard canSeek else { return }
                        let f = Double(min(max(value.location.x / width, 0), 1))
                        engine.isScrubbing = true
                        dragFraction = f
                        engine.seek(to: f * clock.duration, precise: false)
                    }
                    .onEnded { value in
                        if canSeek {
                            let f = Double(min(max(value.location.x / width, 0), 1))
                            engine.seek(to: f * clock.duration, precise: true)
                        }
                        engine.isScrubbing = false
                        dragFraction = nil
                    }
            )
        }
        .frame(height: 14)
        .help(canSeek ? "Click or drag to jump to a point in the video" : "")
    }
}

struct TransportView: View {
    @EnvironmentObject var setlist: Setlist
    @EnvironmentObject var engine: PlaybackEngine

    private var nextTitle: String {
        guard let id = engine.armedCueID, let cue = setlist.cues.first(where: { $0.id == id }) else {
            return "End of setlist"
        }
        return cue.title
    }

    var body: some View {
        VStack(spacing: 8) {
            Button { engine.next() } label: {
                VStack(spacing: 2) {
                    Text("NEXT").font(.system(size: 26, weight: .heavy))
                    Text(nextTitle).font(.caption).lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(engine.armedCueID == nil)

            HStack {
                Button { engine.armPrevious() } label: { Label("Back", systemImage: "backward.end") }
                Button { engine.showLoop() } label: { Label("Loop", systemImage: "repeat") }
                Button { engine.toggleBlackout() } label: {
                    Label("Blackout", systemImage: engine.blackout ? "sun.max" : "moon.fill")
                }
                Button(role: .destructive) { engine.stop() } label: { Label("Stop", systemImage: "stop.fill") }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct LoopPicker: View {
    @EnvironmentObject var setlist: Setlist

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Thumbnail(image: setlist.defaultLoop.flatMap { setlist.thumbnails[$0.path] })
                    .frame(width: 96, height: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text(setlist.defaultLoop?.name ?? "No loop chosen (black)").lineLimit(1)
                    Text("Plays after each video until you press Next.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Choose…") { setlist.chooseLoop(for: nil) }
                if setlist.defaultLoop != nil {
                    Button("Clear") { setlist.setDefaultLoop(nil) }
                }
            }
            Text("A video can have its own loop: right-click it in the setlist.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OutputSettings: View {
    @EnvironmentObject var setlist: Setlist
    @EnvironmentObject var output: OutputController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Screen", selection: $output.screenID) {
                ForEach(output.screens, id: \.displayID) { screen in
                    Text(screen.localizedName).tag(Optional(screen.displayID))
                }
            }
            Button(output.isShowing ? "Hide Output (Esc)" : "Show Output Full Screen (F)") {
                output.toggle()
            }
            Picker("Picture", selection: $setlist.fillScreen) {
                Text("Fit").tag(false)
                Text("Fill (crops edges)").tag(true)
            }
            .pickerStyle(.segmented)
            HStack {
                Text("Crossfade")
                Slider(value: $setlist.crossfade, in: 0...3, step: 0.1)
                Text(String(format: "%.1f s", setlist.crossfade))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            Toggle("Play the videos' own sound", isOn: $setlist.videoAudio)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShortcutHelp: View {
    private let rows: [(String, String)] = [
        ("Space  →  Page Down", "Next video"),
        ("←  Page Up", "Move NEXT back one (doesn't play)"),
        ("L", "Loop visual now"),
        ("B", "Blackout on / off"),
        ("F", "Show / hide output"),
        ("Esc", "Hide output"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Keys").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(rows.indices, id: \.self) { i in
                HStack {
                    Text(rows[i].0).font(.caption.monospaced()).frame(width: 140, alignment: .leading)
                    Text(rows[i].1).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
