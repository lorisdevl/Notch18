import AppKit
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home, shelf, clipboard, notes, apps, network, timer, garde, mirror
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .shelf: return "tray.full.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .notes: return "note.text"
        case .apps: return "square.grid.2x2.fill"
        case .network: return "network"
        case .timer: return "timer"
        case .garde: return "flame.fill"
        case .mirror: return "camera.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return "Accueil"
        case .shelf: return "Étagère & AirDrop"
        case .clipboard: return "Presse-papiers"
        case .notes: return "Notes rapides"
        case .apps: return "Mes apps"
        case .network: return "Réseau & système"
        case .timer: return "Minuteur"
        case .garde: return "Mode garde"
        case .mirror: return "Miroir"
        }
    }

    static let leftTabs: [NotchTab] = [.home, .shelf, .clipboard, .notes, .apps]
    static let rightTabs: [NotchTab] = [.network, .timer, .garde, .mirror]
}

struct SneakPeek: Equatable {
    let id = UUID()
    let symbol: String
    let text: String
    let tint: Color
}

final class NotchState: ObservableObject {
    static let shared = NotchState()

    @Published var isOpen = false
    @Published var tab: NotchTab = .home
    @Published var pinned = false
    @Published var sneak: SneakPeek?
    @Published var notchWidth: CGFloat = 185
    @Published var notchHeight: CGFloat = 32
    @Published var hasNotch = false
    var stickyUntilHover = false

    let openSize = CGSize(width: 700, height: 272)
    let margin: CGFloat = 26
    var panelSize: CGSize { CGSize(width: openSize.width + margin * 2, height: openSize.height + margin) }

    func updateMetrics(for screen: NSScreen) {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notchWidth = max(120, screen.frame.width - left.width - right.width)
            notchHeight = screen.safeAreaInsets.top
            hasNotch = true
        } else {
            notchWidth = 190
            notchHeight = max(24, NSStatusBar.system.thickness)
            hasNotch = false
        }
    }

    func showSneak(symbol: String, text: String, tint: Color = .white, duration: Double = 2.8) {
        guard !isOpen else { return }
        let peek = SneakPeek(symbol: symbol, text: text, tint: tint)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { sneak = peek }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.sneak?.id == peek.id else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { self.sneak = nil }
        }
    }
}

/// Taille de l'encoche fermée selon ce qui est « en direct » (musique, minuteur, garde…).
enum ClosedLayout {
    static func sideWidth() -> CGFloat {
        let timer = TimerManager.shared
        let garde = GardeManager.shared
        let media = MediaManager.shared
        if timer.isActive || garde.status == .intervention { return 56 }
        if media.isPlaying || (garde.showInNotch && garde.status != .aucun) { return 30 }
        return 0
    }

    static func width() -> CGFloat {
        let state = NotchState.shared
        var w = state.notchWidth + sideWidth() * 2 + 12
        if state.sneak != nil { w = max(w, 360) }
        return w
    }

    static func height() -> CGFloat {
        let state = NotchState.shared
        return state.notchHeight + (state.sneak != nil ? 28 : 0)
    }
}

/// Forme de l'encoche : petits arrondis inversés en haut, grands arrondis en bas.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius
        let b = bottomRadius
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Thème & utilitaires

enum Theme {
    static let red = Color(red: 0.93, green: 0.23, blue: 0.24)
    static let card = Color.white.opacity(0.065)
    static let fr = Locale(identifier: "fr_FR")
}

func fmtClock(_ t: TimeInterval) -> String {
    let s = Int(max(0, t))
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

func fmtDuration(_ t: TimeInterval) -> String {
    let m = Int(max(0, t) / 60)
    if m < 60 { return "\(m) min" }
    if m < 60 * 24 { return "\(m / 60) h \(String(format: "%02d", m % 60))" }
    return "\(m / (60 * 24)) j \(m % (60 * 24) / 60) h"
}

func fmtBytes(_ b: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(max(0, b)), countStyle: .file)
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

func openPrivacyPane(_ anchor: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
        NSWorkspace.shared.open(url)
    }
}

enum Storage {
    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notch18", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

enum Shell {
    /// Lance un programme (sans passer par un shell) et renvoie sa sortie standard.
    static func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
