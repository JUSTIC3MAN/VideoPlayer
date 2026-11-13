import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ControlView: View {
    @State private var selection = Set<UUID>()

    var body: some View {
        HSplitView {
            SetlistPane(selection: $selection)
                .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
            SidePanel(selection: $selection)
                .frame(minWidth: 360, idealWidth: 400, maxWidth: 480, maxHeight: .infinity)
        }
    }
}

// MARK: - Setlist

struct SetlistPane: View {
    @EnvironmentObject var setlist: Setlist
    @EnvironmentObject var engine: PlaybackEngine
    @Binding var selection: Set<UUID>

    private var selectedRows: [Cue] { setlist.cues.filter { selection.contains($0.id) } }

    /// Add Videos goes into the column of the selected row, else the last column.
    private var targetColumn: UUID? { selectedRows.first.map { setlist.columnID(of: $0) } }

    private static let addTileWidth: CGFloat = 96

    var body: some View {
        let layout = SetlistLayout(cues: setlist.cues)
        let total = setlist.cues.filter { !$0.isLoop }.reduce(0) { $0 + $1.duration }
        let selectionIsLoops = !selectedRows.isEmpty && selectedRows.allSatisfy { $0.isLoop }
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Setlist").font(.title2.bold()).fixedSize()
                // On a narrow window the count gives way first, so the buttons keep their full names.
                Text("\(layout.videoCount) videos · \(layout.loopCount) \(layout.loopCount == 1 ? "loop" : "loops") · \(formatTime(total))")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
                Spacer(minLength: 0)
                Button { setlist.chooseVideos(into: targetColumn) } label: { Label("Add Videos", systemImage: "plus") }
                    .fixedSize()
                    .help("Adds videos to the column of the selected video (or to the last column)")
                Button { setlist.setLoopRows(selection, !selectionIsLoops) } label: {
                    Label(selectionIsLoops ? "Use as Video" : "Use as Loop",
                          systemImage: selectionIsLoops ? "film" : "infinity")
                }
                .fixedSize()
                .disabled(selection.isEmpty)
                .help(selectionIsLoops ? "Turns the selected loops back into videos"
                                       : "Turns the selected videos into loops. A loop plays after the videos below it.")
                Button {
                    setlist.remove(ids: selection)
                    selection.removeAll()
                } label: { Label("Remove", systemImage: "minus") }
                .fixedSize()
                .disabled(selection.isEmpty)
            }
            .padding(12)
            Divider()

            // The columns side by side. They share the width (at least 250 points each) and scroll sideways
            // when there are more than fit.
            GeometryReader { geo in
                let count = CGFloat(max(setlist.columns.count, 1))
                let free = geo.size.width - 20 - Self.addTileWidth - 10 * count
                let width = max(250, floor(free / count))
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(setlist.columns) { column in
                            ColumnView(column: column, layout: layout, compact: width < 430, selection: $selection)
                                .frame(width: width)
                        }
                        AddColumnTile { setlist.renamingColumn = setlist.addColumn() }
                            .frame(width: Self.addTileWidth)
                    }
                    .padding(10)
                    .frame(height: geo.size.height)
                }
            }

            Divider()
            Text("Drag to reorder or to another column · double-click a column's name to rename it · double-click a video to play it (or a loop to show it) · right-click for more")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }
}

/// One named column: an artist or a part of the show.
struct ColumnView: View {
    @EnvironmentObject var setlist: Setlist
    @EnvironmentObject var engine: PlaybackEngine
    let column: ShowColumn
    let layout: SetlistLayout
    let compact: Bool
    @Binding var selection: Set<UUID>
    @FocusState private var nameFocused: Bool

    private var renaming: Bool { setlist.renamingColumn == column.id }

    private func finishRenaming() {
        guard renaming else { return }
        setlist.renamingColumn = nil
        showLog("Column named \(setlist.columnName(column.id))")
    }

    var body: some View {
        let rows = setlist.cues(in: column.id)
        let videos = rows.filter { !$0.isLoop }
        let index = setlist.columns.firstIndex { $0.id == column.id } ?? 0
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if renaming {
                    TextField("Name this column", text: Binding(get: { column.name },
                                                                set: { setlist.renameColumn(column.id, to: $0) }))
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .focused($nameFocused)
                        .onSubmit { finishRenaming() }   // Return: back to the show keys (Space, arrows …)
                        .onAppear { DispatchQueue.main.async { nameFocused = true } }
                        .onChange(of: nameFocused) { focused in if !focused { finishRenaming() } }
                } else {
                    Text(setlist.columnName(column.id))
                        .font(.headline)
                        .foregroundStyle(column.name.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { setlist.renamingColumn = column.id }
                        .help("Double-click to rename this column")
                }
                Text("\(videos.count) \(videos.count == 1 ? "video" : "videos")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Menu {
                    Button("Add Videos to This Column…") { setlist.chooseVideos(into: column.id) }
                    Button("Add Loop to the Top of This Column…") { setlist.chooseLoopRow(column: column.id, at: 0) }
                    Divider()
                    Button("Rename") { setlist.renamingColumn = column.id }
                    Button("Move Column Left") { setlist.moveColumn(column.id, by: -1) }
                        .disabled(index == 0)
                    Button("Move Column Right") { setlist.moveColumn(column.id, by: 1) }
                        .disabled(index == setlist.columns.count - 1)
                    Divider()
                    Button("Remove Column (its videos move to the next column over)") { setlist.removeColumn(column.id) }
                        .disabled(setlist.columns.count == 1)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Column options")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()

            if rows.isEmpty {
                ColumnDropZone(column: column.id)
            } else {
                List(selection: $selection) {
                    ForEach(rows) { cue in
                        SetlistRow(cue: cue, layout: layout, compact: compact)
                            .tag(cue.id)
                            .itemProvider { NSItemProvider(object: cue.id.uuidString as NSString) }
                    }
                    .onMove { setlist.move(in: column.id, from: $0, to: $1) }
                    .onInsert(of: [.fileURL, .plainText]) { index, providers in
                        receiveDrop(providers, into: column.id, at: index, setlist: setlist)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .onDeleteCommand {
                    setlist.remove(ids: selection)
                    selection.removeAll()
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    RowMenu(ids: ids, selection: $selection)
                } primaryAction: { ids in
                    // Double-click plays a video now, or shows a loop now.
                    if let id = ids.first { engine.playNow(id) }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// What a column accepts when something is dropped on it: videos from Finder, or setlist rows dragged
/// from another column.
func receiveDrop(_ providers: [NSItemProvider], into column: UUID, at index: Int?, setlist: Setlist) {
    let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
    if !files.isEmpty {
        loadFileURLs(files) { setlist.add(urls: $0, to: column, at: index) }
        return
    }
    let group = DispatchGroup()
    final class Found { var ids: [UUID] = [] }
    let found = Found()
    for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
        group.enter()
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            DispatchQueue.main.async {
                if let text = object as? NSString, let id = UUID(uuidString: text as String) { found.ids.append(id) }
                group.leave()
            }
        }
    }
    group.notify(queue: .main) {
        guard !found.ids.isEmpty else { return }
        setlist.moveRows(Set(found.ids), to: column, at: index)
    }
}

/// An empty column: drop videos here, or add them.
struct ColumnDropZone: View {
    @EnvironmentObject var setlist: Setlist
    let column: UUID
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("Drop videos here").foregroundStyle(.secondary)
            Button("Add Videos…") { setlist.chooseVideos(into: column) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(targeted ? Color.accentColor.opacity(0.12) : Color.clear)
        .onDrop(of: [.fileURL, .plainText], isTargeted: $targeted) { providers in
            receiveDrop(providers, into: column, at: 0, setlist: setlist)
            return true
        }
    }
}

/// The "+ Column" tile after the last column.
struct AddColumnTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.title2)
                Text("Add Column").font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .help("Adds a column you can name, for an artist or a part of the show")
    }
}

/// The right-click menu for setlist rows.
struct RowMenu: View {
    @EnvironmentObject var setlist: Setlist
    @EnvironmentObject var engine: PlaybackEngine
    let ids: Set<UUID>
    @Binding var selection: Set<UUID>

    var body: some View {
        let rows = setlist.cues.filter { ids.contains($0.id) }
        let fromColumns = Set(rows.map { setlist.columnID(of: $0) })
        if rows.count == 1, let cue = rows.first {
            if cue.isLoop {
                Button("Show This Loop Now") { engine.showLoop(row: cue.id) }
                Divider()
                Button("Use as Video") { setlist.setLoopRows([cue.id], false) }
            } else {
                Button("Play Now") { engine.playNow(cue.id) }
                Button("Set as Next") { engine.arm(cue.id) }
                Divider()
                Button("Use as Loop") { setlist.setLoopRows([cue.id], true) }
                Button("Choose Loop for After This Video…") { setlist.chooseLoop(for: cue.id) }
                if cue.loop != nil {
                    Button("Use the Loop Above It") { setlist.setLoop(nil, for: cue.id) }
                }
            }
            Divider()
        } else if rows.count > 1 {
            let allLoops = rows.allSatisfy { $0.isLoop }
            Button(allLoops ? "Use as Videos" : "Use as Loops") { setlist.setLoopRows(ids, !allLoops) }
            Divider()
        }
        if !rows.isEmpty && setlist.columns.count > 1 {
            Menu("Move to Column") {
                ForEach(setlist.columns.filter { !(fromColumns.count == 1 && fromColumns.contains($0.id)) }) { column in
                    Button(setlist.columnName(column.id)) { setlist.moveRows(ids, to: column.id) }
                }
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

/// A setlist row: a video, or a loop that starts a part of the show.
struct SetlistRow: View {
    let cue: Cue
    let layout: SetlistLayout
    var compact = false

    var body: some View {
        if cue.isLoop {
            LoopRow(cue: cue, part: layout.parts[cue.id], compact: compact)
        } else {
            CueRow(cue: cue,
                   number: layout.videoNumber[cue.id] ?? 0,
                   loopAbove: layout.loopAbove[cue.id].flatMap { layout.parts[$0] },
                   compact: compact)
        }
    }
}

struct CueRow: View {
    @EnvironmentObject var setlist: Setlist
    @EnvironmentObject var engine: PlaybackEngine
    let cue: Cue
    let number: Int
    /// The part of the show this video is in (the loop row above it).
    let loopAbove: SetlistLayout.Part?
    /// Narrow column: smaller picture and number.
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            Text("\(number)")
                .font(.system(compact ? .body : .title3, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: compact ? 22 : 32, alignment: .trailing)
            Thumbnail(image: setlist.thumbnails[cue.file.path])
                .frame(width: compact ? 72 : 112, height: compact ? 40 : 63)
            VStack(alignment: .leading, spacing: 3) {
                Text(cue.title).font(.headline).lineLimit(1)
                HStack(spacing: 8) {
                    Text(formatTime(cue.duration)).monospacedDigit().fixedSize()
                    if compact {
                        // Narrow column: just which loop follows
                        if cue.loop != nil {
                            Label("own loop", systemImage: "repeat").lineLimit(1)
                        } else if let part = loopAbove {
                            Label("Loop \(part.number)", systemImage: "repeat").lineLimit(1)
                        } else {
                            Label("no loop", systemImage: "repeat").lineLimit(1)
                        }
                    } else if let loop = cue.loop {
                        Label("then its own loop: \(loop.name)", systemImage: "repeat").lineLimit(1)
                    } else if let part = loopAbove {
                        Label("then Loop \(part.number): \(part.title)", systemImage: "repeat").lineLimit(1)
                    } else {
                        Label("then black (no loop above it)", systemImage: "repeat").lineLimit(1)
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
                if engine.phase == .playing {
                    StateBadge(text: engine.paused ? "PAUSED" : "PLAYING",
                               color: engine.paused ? .yellow : .green,
                               textColor: engine.paused ? .black : .white)
                } else {
                    StateBadge(text: "LOOP AFTER", color: .orange)
                }
            }
            if engine.armedCueID == cue.id {
                StateBadge(text: "NEXT", color: .blue)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A loop row. Its loop plays after every video below it, up to the next loop row.
struct LoopRow: View {
    @EnvironmentObject var setlist: Setlist
    @EnvironmentObject var engine: PlaybackEngine
    let cue: Cue
    let part: SetlistLayout.Part?
    var compact = false

    private var coverage: String {
        guard let part, !part.videos.isEmpty else {
            return compact ? "No videos below it yet" : "No videos below it yet: drag it above the first video it should follow"
        }
        return (compact ? "After " : "Plays after ") + videosText(part.videos)
    }

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            Image(systemName: "infinity")
                .font(.system(size: compact ? 14 : 17, weight: .bold))
                .foregroundStyle(.orange)
                .frame(width: compact ? 22 : 32, alignment: .trailing)
            Thumbnail(image: setlist.thumbnails[cue.file.path])
                .frame(width: compact ? 72 : 112, height: compact ? 40 : 63)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.orange, lineWidth: 2))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("LOOP \(part?.number ?? 0)")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    Text(cue.title).font(.headline).lineLimit(1)
                }
                Text(coverage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if setlist.missing.contains(cue.file.path) {
                    Label("File not found", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 8)
            if engine.phase == .loop && engine.loopRowID == cue.id {
                StateBadge(text: engine.paused ? "PAUSED" : "ON SCREEN",
                           color: engine.paused ? .yellow : .orange,
                           textColor: engine.paused ? .black : .white)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StateBadge: View {
    let text: String
    let color: Color
    var textColor: Color = .white

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
            .foregroundStyle(textColor)
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
    @Binding var selection: Set<UUID>

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
                GroupBox("Loops") { LoopSchedule(selection: $selection).padding(4) }
                GroupBox("Output") { OutputSettings().padding(4) }
                ShortcutHelp()
            }
            .padding(14)
        }
    }
}

struct PhaseTag: View {
    @EnvironmentObject var engine: PlaybackEngine

    var body: some View {
        if engine.blackout {
            StateBadge(text: "BLACKOUT", color: .gray)
        } else if engine.paused {
            StateBadge(text: "PAUSED", color: .yellow, textColor: .black)
        } else {
            switch engine.phase {
            case .idle: StateBadge(text: "STANDBY", color: .gray)
            case .playing: StateBadge(text: "PLAYING", color: .green)
            case .loop: StateBadge(text: "LOOP", color: .orange)
            }
        }
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
                Button { engine.playPrevious() } label: { Label("Previous", systemImage: "backward.end.fill") }
                    .disabled(engine.playingCueID == nil)
                    .help("Plays the video before the one playing now (B on a game controller)")
                Button { engine.togglePause() } label: {
                    Label(engine.paused ? "Resume" : "Pause", systemImage: engine.paused ? "play.fill" : "pause.fill")
                        .frame(minWidth: 64)
                }
                .disabled(engine.phase == .idle)
                .help("Freezes the picture; press again to carry on (P, or Y on a game controller)")
                Button { engine.showLoop() } label: { Label("Loop", systemImage: "repeat") }
                    .help("Shows the loop for the current song (L, or X on a game controller)")
            }
            .frame(maxWidth: .infinity)

            HStack {
                Button { engine.armPrevious() } label: { Label("Back One", systemImage: "arrow.up") }
                    .help("Moves NEXT up one video without playing it (← or Page Up)")
                Button { engine.toggleBlackout() } label: {
                    Label("Blackout", systemImage: engine.blackout ? "sun.max" : "moon.fill")
                }
                Button(role: .destructive) { engine.stop() } label: { Label("Stop", systemImage: "stop.fill") }
            }
            .frame(maxWidth: .infinity)

            ControllerStatus()
        }
    }
}

/// Shows whether a game controller is connected and what its buttons do.
struct ControllerStatus: View {
    @EnvironmentObject var gamepad: GamepadInput

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "gamecontroller.fill")
                .foregroundStyle(gamepad.controllerName == nil ? Color.secondary : Color.green)
            if let name = gamepad.controllerName {
                Text("\(name): A Next · B Previous · X Loop · Y Pause")
            } else {
                Text("No game controller. Pair an Xbox controller in System Settings → Bluetooth.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The loops in setlist order and the videos each one plays after (the parts of the show).
struct LoopSchedule: View {
    @EnvironmentObject var setlist: Setlist
    @Binding var selection: Set<UUID>

    /// Add Loop… puts the new loop above the first selected row.
    private var insertIndex: Int? {
        setlist.cues.firstIndex { selection.contains($0.id) }
    }

    var body: some View {
        let layout = SetlistLayout(cues: setlist.cues)
        let loops = setlist.cues.filter { $0.isLoop }
        VStack(alignment: .leading, spacing: 8) {
            if loops.isEmpty {
                Text("No loops yet, so the screen goes black after each video.")
                    .foregroundStyle(.secondary)
            }
            ForEach(loops) { cue in
                let part = layout.parts[cue.id]
                HStack(spacing: 8) {
                    Text("\(part?.number ?? 0)")
                        .font(.system(.body, design: .rounded).bold())
                        .foregroundStyle(.orange)
                        .frame(width: 14)
                    Thumbnail(image: setlist.thumbnails[cue.file.path])
                        .frame(width: 72, height: 40)
                    Text(cue.title).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(videosText(part?.videos ?? []))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture { selection = [cue.id] }
                .help("Click to select it in the setlist")
            }
            if !loops.isEmpty && !layout.videosWithoutLoop.isEmpty {
                Label("\(videosText(layout.videosWithoutLoop).capitalizedFirst) \(layout.videosWithoutLoop.count == 1 ? "has" : "have") no loop above, so the screen goes black after.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Add Loop…") { setlist.chooseLoopRow(insertAt: insertIndex) }
                .help("Adds a loop above the selected row (with nothing selected: at the top, or at the end if there are loops already)")
            Text("Any video can be a loop: select it and click Use as Loop, or right-click it. A loop plays after every video below it, up to the next loop, so each loop covers one part of the show. Drag a loop up or down to change how many videos it covers. Double-click a loop to show it now.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension String {
    /// "videos 1–2" → "Videos 1–2"
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
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
        ("P", "Pause / resume"),
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
