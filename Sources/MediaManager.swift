import AppKit
import SwiftUI

enum MediaSource: String {
    case spotify, music

    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    var name: String { self == .spotify ? "Spotify" : "Musique" }
}

/// Lit et pilote Spotify / Apple Music via AppleScript (autorisation « Automatisation » demandée au 1er usage).
final class MediaManager: ObservableObject {
    static let shared = MediaManager()

    @Published var source: MediaSource?
    @Published var isPlaying = false
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var duration: Double = 0
    @Published var position: Double = 0
    @Published var artwork: NSImage?
    @Published var accent: Color = Theme.red
    @Published var automationDenied = false

    private var timer: Timer?
    private var trackKey = ""
    private var compiled: [String: NSAppleScript] = [:]

    var hasTrack: Bool { source != nil && !title.isEmpty }
    var progress: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }

    func start() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    /// Toutes les secondes pendant la lecture, toutes les 3 s sinon (économise la batterie).
    private var idleTicks = 0
    private func tick() {
        if isPlaying { poll(); return }
        idleTicks += 1
        if idleTicks >= 3 { idleTicks = 0; poll() }
    }

    private func isRunning(_ s: MediaSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: s.bundleID).isEmpty
    }

    private func statusScript(_ s: MediaSource) -> String {
        switch s {
        case .spotify:
            return """
            tell application id "com.spotify.client"
                if player state is stopped then return "stopped"
                set st to "0"
                if player state is playing then set st to "1"
                set tr to current track
                set d to (duration of tr) / 1000
                return st & "|~|" & (name of tr) & "|~|" & (artist of tr) & "|~|" & (album of tr) & "|~|" & (d as string) & "|~|" & (player position as string) & "|~|" & (artwork url of tr)
            end tell
            """
        case .music:
            return """
            tell application id "com.apple.Music"
                if player state is stopped then return "stopped"
                set st to "0"
                if player state is playing then set st to "1"
                set tr to current track
                return st & "|~|" & (name of tr) & "|~|" & (artist of tr) & "|~|" & (album of tr) & "|~|" & ((duration of tr) as string) & "|~|" & (player position as string) & "|~|" & ""
            end tell
            """
        }
    }

    func poll() {
        var results: [(MediaSource, [String])] = []
        for s in [MediaSource.spotify, MediaSource.music] where isRunning(s) {
            if let out = run(statusScript(s))?.stringValue, out != "stopped", !out.isEmpty {
                let parts = out.components(separatedBy: "|~|")
                if parts.count >= 6 { results.append((s, parts)) }
            }
        }
        let pick = results.first(where: { $0.1[0] == "1" })
            ?? results.first(where: { $0.0 == source })
            ?? results.first
        guard let pick else {
            if source != nil { clear() }
            return
        }
        apply(pick.0, pick.1)
    }

    private func num(_ s: String) -> Double {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func apply(_ s: MediaSource, _ p: [String]) {
        let playing = p[0] == "1"
        let key = s.rawValue + "|" + p[1] + "|" + p[2] + "|" + p[3]
        if source != s { source = s }
        if isPlaying != playing { isPlaying = playing }
        if title != p[1] { title = p[1] }
        if artist != p[2] { artist = p[2] }
        if album != p[3] { album = p[3] }
        let d = num(p[4])
        if duration != d { duration = d }
        position = num(p[5])

        if key != trackKey {
            trackKey = key
            loadArtwork(s, url: p.count > 6 ? p[6] : "")
            if playing, !p[1].isEmpty, UserDefaults.standard.bool(forKey: "showTrackSneak") {
                let text = p[2].isEmpty ? p[1] : "\(p[1]) — \(p[2])"
                NotchState.shared.showSneak(symbol: "music.note", text: text, tint: accent)
            }
        }
    }

    private func clear() {
        source = nil
        isPlaying = false
        title = ""; artist = ""; album = ""
        duration = 0; position = 0
        trackKey = ""
        setArtwork(nil)
    }

    private func loadArtwork(_ s: MediaSource, url: String) {
        switch s {
        case .spotify:
            guard !url.isEmpty, let u = URL(string: url) else { setArtwork(nil); return }
            let expected = trackKey
            URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
                let image = data.flatMap { NSImage(data: $0) }
                DispatchQueue.main.async {
                    guard let self, self.trackKey == expected else { return }
                    self.setArtwork(image)
                }
            }.resume()
        case .music:
            let script = """
            tell application id "com.apple.Music"
                try
                    return raw data of artwork 1 of current track
                end try
            end tell
            """
            let data = run(script, cache: true)?.data
            setArtwork(data.flatMap { NSImage(data: $0) })
        }
    }

    private func setArtwork(_ image: NSImage?) {
        withAnimation(.easeInOut(duration: 0.3)) {
            artwork = image
            if let image, let c = MediaManager.dominantColor(image) {
                accent = Color(nsColor: c)
            } else {
                accent = Theme.red
            }
        }
    }

    // MARK: Commandes

    func playPause() {
        isPlaying.toggle()
        command("playpause")
    }

    func next() { command("next track") }
    func previous() { command("previous track") }

    func seek(_ fraction: Double) {
        guard duration > 0 else { return }
        let target = Int(fraction * duration)
        position = Double(target)
        command("set player position to \(target)")
    }

    func launch(_ s: MediaSource) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: s.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openPlayer() {
        if let s = source { launch(s) }
    }

    private func command(_ cmd: String) {
        guard let s = source else { return }
        run("tell application id \"\(s.bundleID)\" to \(cmd)", cache: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.poll() }
    }

    @discardableResult
    private func run(_ source: String, cache: Bool = true) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if cache, let existing = compiled[source] {
            script = existing
        } else {
            guard let s = NSAppleScript(source: source) else { return nil }
            var compileError: NSDictionary?
            guard s.compileAndReturnError(&compileError) else { return nil }
            if cache { compiled[source] = s }
            script = s
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 {
                if !automationDenied { automationDenied = true }
            }
            return nil
        }
        if automationDenied { automationDenied = false }
        return result
    }

    static func dominantColor(_ image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let base = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                           blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(1, s * 1.25), brightness: max(0.72, b), alpha: 1)
    }
}
