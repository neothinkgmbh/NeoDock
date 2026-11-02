import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Rechter Bereich wie im macOS-Dock: Ordner-Stapel (per Ziehen ablegen) und der Papierkorb.
struct StacksRow: View {
    @Bindable var model: DockModel
    @State private var isTargeted = false
    static let trashURL = URL(filePath: NSHomeDirectory()).appending(path: ".Trash")
    static let trashIcon = NSImage(contentsOfFile:
        "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/TrashIcon.icns") ?? NSImage()
    static let fullTrashIcon = NSImage(contentsOfFile:
        "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FullTrashIcon.icns") ?? trashIcon

    var body: some View {
        HStack(alignment: .bottom, spacing: DockMetrics.stackSpacing) {
            ForEach(model.settings.stackFolders, id: \.self) { path in
                StackIcon(url: URL(filePath: path), size: model.iconSize, model: model)
            }
            Button { NSWorkspace.shared.open(Self.trashURL) } label: {
                Image(nsImage: model.trash.isFull ? Self.fullTrashIcon : Self.trashIcon).resizable().interpolation(.high)
                    .frame(width: model.iconSize, height: model.iconSize)
            }
            .buttonStyle(DockPressStyle())
            .accessibilityLabel("Papierkorb")
            .help("Papierkorb — Dateien hierher ziehen, um sie zu löschen")
            .contextMenu {
                Button("Öffnen") { NSWorkspace.shared.open(Self.trashURL) }
                Button("Papierkorb entleeren …") { model.trash.emptyAfterConfirmation() }
                    .disabled(!model.trash.isFull)
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                FileDrops.loadURLs(providers) { FileDrops.trash($0); model.trash.refreshSoon() }
                return true
            }
        }
        .padding(Space.xxs)
        .background(isTargeted ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: DockMetrics.tileCorner))
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter(DockSettings.isPlainFolder)
            folders.forEach(model.settings.addStack)
            return !folders.isEmpty
        } isTargeted: { isTargeted = $0 }
        .help("Ordner hierher ziehen, um ihn als Stapel abzulegen")
    }
}

struct StackIcon: View {
    let url: URL
    let size: CGFloat
    let model: DockModel
    @State private var midX: CGFloat = 0
    @State private var isTargeted = false

    var body: some View {
        Button { model.onToggleCard?(.folder(url), midX) } label: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
                .frame(width: size, height: size)
        }
        .buttonStyle(DockPressStyle())
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { midX = $0 }
        .scaleEffect(isTargeted ? DockMetrics.dropTargetScale : 1, anchor: .bottom)
        .animation(.snappy(duration: 0.15), value: isTargeted)
        // Dateien auf den Stapel ziehen legt sie in den Ordner (wie im macOS-Dock).
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            FileDrops.loadURLs(providers) { FileDrops.place($0, into: url) }
            return true
        }
        .contextMenu {
            Button("Im Finder öffnen") { NSWorkspace.shared.open(url) }
            Button("Aus der Leiste entfernen") { model.settings.removeStack(url.path) }
        }
        .accessibilityLabel(FileManager.default.displayName(atPath: url.path))
        .help(FileManager.default.displayName(atPath: url.path))
    }
}

/// Neueste Einträge eines Ordners für die Stapel-Karte.
nonisolated enum FolderListing {
    struct Item: Identifiable, Equatable, Sendable {
        let url: URL
        let modified: Date
        var id: URL { url }
    }

    static let limit = 15

    nonisolated static func recent(in folder: URL) -> [Item]? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return nil }
        return urls
            .map { Item(url: $0, modified: (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
            .sorted { $0.modified > $1.modified }
            .prefix(limit)
            .map { $0 }
    }
}
