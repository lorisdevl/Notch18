import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Notes rapides

struct NotesView: View {
    @AppStorage("quickNotes") private var notes = ""
    @State private var copied = false

    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.locale = Theme.fr; f.dateFormat = "dd/MM HH:mm"; return f
    }()

    var body: some View {
        Card(padding: 8) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    SectionTitle("Notes rapides", symbol: "note.text", tint: .yellow)
                    Spacer()
                    Button("Horodater") {
                        let sep = (notes.isEmpty || notes.hasSuffix("\n")) ? "" : "\n"
                        notes += sep + "[\(Self.stamp.string(from: Date()))] "
                    }
                    Button(copied ? "Copié ✓" : "Tout copier") {
                        copyToPasteboard(notes)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    }
                }
                .buttonStyle(PillButtonStyle())
                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Clique ici et écris : idée, numéro, matériel à récupérer, devoir à rendre…")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.top, 1)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $notes)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                }
            }
        }
    }
}

// MARK: - Mes apps

struct LaunchApp: Identifiable, Equatable {
    var id: String { path }
    let path: String
    var name: String { (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "") }
    var url: URL { URL(fileURLWithPath: path) }
}

final class LauncherManager: ObservableObject {
    static let shared = LauncherManager()

    @Published var apps: [LaunchApp] = []
    private let key = "launcherApps"

    init() {
        if let saved = UserDefaults.standard.array(forKey: key) as? [String] {
            apps = saved.filter { FileManager.default.fileExists(atPath: $0) }.map { LaunchApp(path: $0) }
        } else {
            let defaults = ["com.spfire34.cisalertes", "fr.loris.MonFrigo", "notion.id", "com.microsoft.VSCode",
                            "com.netacad.PacketTracer9.0.1", "com.apple.Safari", "com.apple.mail", "com.apple.iCal",
                            "net.whatsapp.WhatsApp", "com.hnc.Discord", "com.apple.Terminal", "com.apple.systempreferences"]
            apps = defaults.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                .map { LaunchApp(path: $0.path) }
            save()
        }
    }

    func open(_ app: LaunchApp) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        NotchController.shared?.close()
    }

    func remove(_ app: LaunchApp) {
        apps.removeAll { $0 == app }
        save()
    }

    func move(_ app: LaunchApp, by offset: Int) {
        guard let i = apps.firstIndex(of: app) else { return }
        let j = min(max(0, i + offset), apps.count - 1)
        guard i != j else { return }
        apps.swapAt(i, j)
        save()
    }

    func addViaPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Ajouter"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            for url in panel.urls where !apps.contains(where: { $0.path == url.path }) {
                apps.append(LaunchApp(path: url.path))
            }
            save()
        }
    }

    private func save() { UserDefaults.standard.set(apps.map { $0.path }, forKey: key) }
}

struct AppsView: View {
    @ObservedObject var launcher = LauncherManager.shared
    private let columns = Array(repeating: GridItem(.fixed(70), spacing: 6), count: 8)

    var body: some View {
        Card(padding: 8) {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(launcher.apps) { AppTile(app: $0) }
                    Button { launcher.addViaPanel() } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.3),
                                                                                           style: StrokeStyle(lineWidth: 1.2, dash: [4])))
                            Text("Ajouter").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.6))
                        }
                        .frame(width: 70, height: 66)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct AppTile: View {
    let app: LaunchApp
    @State private var hover = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 40, height: 40)
                .scaleEffect(hover ? 1.1 : 1)
            Text(app.name).font(.system(size: 9.5)).lineLimit(1).frame(width: 66)
        }
        .frame(width: 70, height: 66)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hover ? 0.1 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hover)
        .onTapGesture { LauncherManager.shared.open(app) }
        .contextMenu {
            Button("Ouvrir") { LauncherManager.shared.open(app) }
            Button("Déplacer à gauche") { LauncherManager.shared.move(app, by: -1) }
            Button("Déplacer à droite") { LauncherManager.shared.move(app, by: 1) }
            Divider()
            Button("Retirer") { LauncherManager.shared.remove(app) }
        }
        .help(app.name)
    }
}

// MARK: - Miroir (caméra)

final class CameraManager: ObservableObject {
    static let shared = CameraManager()

    let session = AVCaptureSession()
    @Published var authorized: Bool?
    private var configured = false
    private let queue = DispatchQueue(label: "notch18.camera")

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    self.authorized = ok
                    if ok { self.run() }
                }
            }
        default:
            authorized = false
        }
    }

    private func run() {
        queue.async {
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                if let device = AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                self.session.commitConfiguration()
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
}

final class PreviewNSView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewNSView { PreviewNSView(session: session) }
    func updateNSView(_ nsView: PreviewNSView, context: Context) {}
}

struct MirrorView: View {
    @ObservedObject var cam = CameraManager.shared
    @AppStorage("mirrorFlip") private var flip = true

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card)
                if cam.authorized == false {
                    VStack(spacing: 6) {
                        Image(systemName: "video.slash.fill").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                        Text("Autorise la caméra pour Notch18")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                        Button("Ouvrir les réglages") { openPrivacyPane("Privacy_Camera") }
                            .buttonStyle(PillButtonStyle())
                    }
                } else {
                    CameraPreview(session: cam.session)
                        .scaleEffect(x: flip ? -1 : 1, y: 1)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .frame(width: 340)

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("Miroir", symbol: "camera.fill", tint: .pink)
                    Text("Vérifie ta tête avant une visio, un oral ou une photo.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Image en miroir", isOn: $flip)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(size: 10.5))
                    Spacer(minLength: 0)
                    Text("La caméra s'éteint dès que tu quittes cet onglet.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { cam.start() }
        .onDisappear { cam.stop() }
    }
}
