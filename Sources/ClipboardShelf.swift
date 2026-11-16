import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Presse-papiers

struct ClipItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date: Date
    var pinned = false

    var preview: String {
        let flat = text.replacingOccurrences(of: "\n", with: " ⏎ ").trimmingCharacters(in: .whitespaces)
        return String(flat.prefix(220))
    }
    var isURL: Bool { text.hasPrefix("http://") || text.hasPrefix("https://") }
}

/// Historique local du presse-papiers (texte uniquement ; les mots de passe marqués « masqués » sont ignorés).
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published var items: [ClipItem] = []
    private var lastChange = NSPasteboard.general.changeCount
    private var skipNext = false
    private var timer: Timer?
    private let maxItems = 60
    private let file = "clipboard.json"

    var sorted: [ClipItem] {
        items.filter { $0.pinned } + items.filter { !$0.pinned }
    }

    func start() {
        items = Storage.load([ClipItem].self, from: file) ?? []
        let t = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        if skipNext { skipNext = false; return }
        guard UserDefaults.standard.bool(forKey: "clipboardEnabled") else { return }
        let types = pb.types ?? []
        let ignored = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword"]
        if types.contains(where: { ignored.contains($0.rawValue) }) { return }
        guard let s = pb.string(forType: .string),
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              s.count < 20000 else { return }
        if let i = items.firstIndex(where: { $0.text == s }) {
            var existing = items.remove(at: i)
            existing.date = Date()
            items.insert(existing, at: 0)
        } else {
            items.insert(ClipItem(text: s, date: Date()), at: 0)
        }
        trim()
        save()
    }

    func copy(_ item: ClipItem) {
        skipNext = true
        copyToPasteboard(item.text)
        if let i = items.firstIndex(of: item) {
            var it = items.remove(at: i)
            it.date = Date()
            items.insert(it, at: 0)
            save()
        }
    }

    func togglePin(_ item: ClipItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].pinned.toggle()
        save()
    }

    func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearUnpinned() {
        items.removeAll { !$0.pinned }
        save()
    }

    private func trim() {
        var unpinned = 0
        items = items.filter { item in
            if item.pinned { return true }
            unpinned += 1
            return unpinned <= maxItems
        }
    }

    private func save() { Storage.save(items, to: file) }
}

struct ClipboardView: View {
    @ObservedObject var clip = ClipboardManager.shared
    @AppStorage("clipboardEnabled") private var enabled = true
    @State private var query = ""
    @State private var copiedID: UUID?

    private var filtered: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let base = clip.sorted
        return q.isEmpty ? base : base.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    TextField("Rechercher dans l'historique…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                Text("\(clip.items.count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                Button("Vider (sauf épinglés)") { clip.clearUnpinned() }
                    .buttonStyle(PillButtonStyle())
            }

            if !enabled {
                placeholder("Historique désactivé dans les réglages.")
            } else if filtered.isEmpty {
                placeholder(query.isEmpty ? "Copie du texte (⌘C) : il apparaîtra ici." : "Aucun résultat.")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { item in
                            ClipRow(item: item, copied: copiedID == item.id) {
                                clip.copy(item)
                                copiedID = item.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    if copiedID == item.id { copiedID = nil }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard").font(.system(size: 24)).foregroundStyle(.white.opacity(0.3))
            Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
    }
}

struct ClipRow: View {
    let item: ClipItem
    let copied: Bool
    let onCopy: () -> Void
    @State private var hover = false

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Theme.fr
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.pinned ? "pin.fill" : (item.isURL ? "link" : "text.alignleft"))
                .font(.system(size: 10))
                .foregroundStyle(item.pinned ? Color.orange : Color.white.opacity(0.45))
                .frame(width: 14)
            Text(item.preview)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hover {
                IconButton(symbol: item.pinned ? "pin.slash" : "pin", size: 9, help: item.pinned ? "Désépingler" : "Épingler") {
                    ClipboardManager.shared.togglePin(item)
                }
                IconButton(symbol: "trash", size: 9, help: "Supprimer") { ClipboardManager.shared.delete(item) }
            }
            Text(copied ? "Copié ✓" : Self.relative.localizedString(for: item.date, relativeTo: Date()))
                .font(.system(size: 9.5))
                .foregroundStyle(copied ? Color.green : Color.white.opacity(0.4))
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hover ? 0.1 : 0.04)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
        .onHover { hover = $0 }
        .help(String(item.text.prefix(600)))
    }
}

// MARK: - Étagère & AirDrop

struct ShelfItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var path: String
    var added: Date
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
}

final class ShelfManager: ObservableObject {
    static let shared = ShelfManager()

    @Published var items: [ShelfItem] = []
    private let file = "shelf.json"

    init() {
        items = (Storage.load([ShelfItem].self, from: file) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        var changed = false
        for url in urls where url.isFileURL {
            if !items.contains(where: { $0.path == url.path }) {
                items.insert(ShelfItem(path: url.path, added: Date()), at: 0)
                changed = true
            }
        }
        if changed { save() }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func airdrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        if service.canPerform(withItems: urls) { service.perform(withItems: urls) }
    }

    func airdropAll() { airdrop(items.map { $0.url }) }

    private func save() { Storage.save(items, to: file) }

    static func loadURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}

struct ShelfView: View {
    @ObservedObject var shelf = ShelfManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Card(padding: 8) {
                if shelf.items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.35))
                        Text("Glisse des fichiers sur l'encoche pour les garder sous la main")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                        Text("Puis fais-les glisser où tu veux : mail, dossier, WhatsApp…")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(shelf.items) { ShelfItemView(item: $0) }
                            }
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            Text("\(shelf.items.count) élément\(shelf.items.count > 1 ? "s" : "")")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            Button("Tout envoyer par AirDrop") { shelf.airdropAll() }
                            Button("Vider l'étagère") { shelf.clear() }
                        }
                        .buttonStyle(PillButtonStyle())
                    }
                }
            }
            AirDropZone().frame(width: 124)
        }
    }
}

struct ShelfItemView: View {
    let item: ShelfItem
    @State private var hover = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 46, height: 46)
            Text(item.name)
                .font(.system(size: 9.5))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 76)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hover ? 0.12 : 0)))
        .overlay(alignment: .topTrailing) {
            if hover {
                Button { ShelfManager.shared.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Retirer de l'étagère")
            }
        }
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Ouvrir") { NSWorkspace.shared.open(item.url) }
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Envoyer par AirDrop") { ShelfManager.shared.airdrop([item.url]) }
            Button("Copier le chemin") { copyToPasteboard(item.path) }
            Divider()
            Button("Retirer de l'étagère") { ShelfManager.shared.remove(item) }
        }
        .help(item.path)
    }
}

struct AirDropZone: View {
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(targeted ? Color.white : Color.blue)
            Text("AirDrop").font(.system(size: 12, weight: .bold))
            Text("Dépose ici pour envoyer")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(targeted ? Color.blue.opacity(0.4) : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.white.opacity(targeted ? 0.8 : 0.18), style: StrokeStyle(lineWidth: 1.5, dash: [5])))
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            ShelfManager.loadURLs(providers) { urls in ShelfManager.shared.airdrop(urls) }
            return true
        }
        .animation(.easeOut(duration: 0.15), value: targeted)
    }
}
