import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Vue racine

struct NotchRootView: View {
    @ObservedObject var state = NotchState.shared
    @ObservedObject var media = MediaManager.shared
    @ObservedObject var timer = TimerManager.shared
    @ObservedObject var garde = GardeManager.shared

    private var shapeSize: CGSize {
        if state.isOpen { return state.openSize }
        return CGSize(width: ClosedLayout.width(), height: ClosedLayout.height())
    }

    var body: some View {
        let size = shapeSize
        let top: CGFloat = state.isOpen ? 14 : 6
        let bottom: CGFloat = state.isOpen ? 26 : 12

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(topRadius: top, bottomRadius: bottom)
                    .fill(Color.black)
                if state.isOpen {
                    OpenNotchView()
                        .padding(.horizontal, top + 14)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                } else {
                    ClosedNotchView()
                        .padding(.horizontal, top + 2)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(NotchShape(topRadius: top, bottomRadius: bottom))
            .shadow(color: .black.opacity(state.isOpen ? 0.55 : 0), radius: 14, y: 6)
            Spacer(minLength: 0)
        }
        .frame(width: state.panelSize.width, height: state.panelSize.height, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: state.isOpen)
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: size)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }
}

// MARK: - Encoche fermée (« activités en direct »)

struct ClosedNotchView: View {
    @ObservedObject var state = NotchState.shared
    @ObservedObject var media = MediaManager.shared
    @ObservedObject var timer = TimerManager.shared
    @ObservedObject var garde = GardeManager.shared

    var body: some View {
        let side = ClosedLayout.sideWidth()
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leftSlot.frame(width: side, height: state.notchHeight)
                Spacer(minLength: 0)
                rightSlot.frame(width: side, height: state.notchHeight)
            }
            .frame(height: state.notchHeight)

            if let peek = state.sneak {
                HStack(spacing: 6) {
                    Image(systemName: peek.symbol).foregroundStyle(peek.tint)
                    Text(peek.text).lineLimit(1).truncationMode(.tail)
                }
                .font(.system(size: 11, weight: .semibold))
                .frame(height: 26)
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { NotchController.shared?.open() }
    }

    @ViewBuilder private var leftSlot: some View {
        if garde.status == .intervention {
            PulsingIcon(symbol: "flame.fill", color: Theme.red)
        } else if media.isPlaying {
            Group {
                if let art = media.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        media.accent.opacity(0.5)
                        Image(systemName: "music.note").font(.system(size: 10, weight: .bold))
                    }
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else if garde.showInNotch && garde.status != .aucun {
            Image(systemName: garde.status.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(garde.status.color)
        }
    }

    @ViewBuilder private var rightSlot: some View {
        if timer.isActive {
            Text(fmtClock(timer.displayTime))
                .font(.system(size: 11.5, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(timer.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if garde.status == .intervention, let current = garde.current {
            Text(fmtClock(garde.now.timeIntervalSince(current.start)))
                .font(.system(size: 11.5, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.red)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if media.isPlaying {
            AudioBars(color: media.accent, playing: media.isPlaying)
        }
    }
}

struct PulsingIcon: View {
    let symbol: String
    let color: Color
    @State private var on = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
            .opacity(on ? 1 : 0.35)
            .scaleEffect(on ? 1.12 : 0.88)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

struct AudioBars: View {
    let color: Color
    let playing: Bool
    @State private var heights: [CGFloat] = [0.4, 0.7, 0.5, 0.8]
    private let ticker = Timer.publish(every: 0.28, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: 3 + heights[i] * 11)
            }
        }
        .frame(height: 16)
        .onReceive(ticker) { _ in
            guard playing else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                heights = heights.map { _ in CGFloat.random(in: 0.15...1) }
            }
        }
    }
}

// MARK: - Encoche ouverte

struct OpenNotchView: View {
    @ObservedObject var state = NotchState.shared
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            HeaderView()
            Group {
                switch state.tab {
                case .home: HomeView()
                case .shelf: ShelfView()
                case .clipboard: ClipboardView()
                case .notes: NotesView()
                case .apps: AppsView()
                case .network: NetworkView()
                case .timer: TimerView()
                case .garde: GardeView()
                case .mirror: MirrorView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            if state.tab != .shelf { state.tab = .shelf }
            ShelfManager.loadURLs(providers) { urls in ShelfManager.shared.add(urls) }
            return true
        }
    }
}

struct HeaderView: View {
    @ObservedObject var state = NotchState.shared

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.leftTabs) { TabButton(tab: $0) }
            Spacer(minLength: state.notchWidth + 12)
            ForEach(NotchTab.rightTabs) { TabButton(tab: $0) }
            BatteryBadge().padding(.horizontal, 4)
            IconButton(symbol: state.pinned ? "pin.fill" : "pin", size: 11, active: state.pinned,
                       help: state.pinned ? "Ne plus garder ouvert" : "Garder ouvert") {
                state.pinned.toggle()
            }
            IconButton(symbol: "gearshape.fill", size: 11, help: "Réglages") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
        }
        .frame(height: max(26, state.notchHeight))
    }
}

struct TabButton: View {
    let tab: NotchTab
    @ObservedObject var state = NotchState.shared
    @ObservedObject var garde = GardeManager.shared

    var body: some View {
        let selected = state.tab == tab
        let alert = tab == .garde && garde.status == .intervention
        Button {
            withAnimation(.easeInOut(duration: 0.16)) { state.tab = tab }
        } label: {
            Image(systemName: tab.symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(alert ? Theme.red : (selected ? Color.white : Color.white.opacity(0.42)))
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.15) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.title)
    }
}

struct BatteryBadge: View {
    @ObservedObject var sys = SystemMonitor.shared

    var body: some View {
        if sys.battery.present {
            HStack(spacing: 3) {
                Text("\(sys.battery.level)%")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                Image(systemName: SystemMonitor.symbol(for: sys.battery))
                    .font(.system(size: 12))
                    .foregroundStyle(SystemMonitor.color(for: sys.battery))
            }
            .foregroundStyle(.white.opacity(0.8))
            .help(sys.battery.charging ? "En charge" : "Batterie")
        }
    }
}

// MARK: - Composants réutilisables

struct Card<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
    }
}

struct SectionTitle: View {
    let title: String
    let symbol: String
    var tint: Color = .white

    init(_ title: String, symbol: String, tint: Color = .white) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title)
        }
        .font(.system(size: 10.5, weight: .bold))
        .foregroundStyle(.white.opacity(0.8))
        .lineLimit(1)
    }
}

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 12
    var active: Bool = false
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.white.opacity(0.6))
                .frame(width: size + 14, height: size + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle())
        .help(help)
    }
}

struct HoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
    }

    private struct HoverBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hover = false

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(hover ? 0.12 : 0)))
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .onHover { hover = $0 }
                .animation(.easeOut(duration: 0.12), value: hover)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.32 : 0.15)))
            .foregroundStyle(.white)
            .contentShape(Capsule())
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var mono: Bool = true
    var copyable: Bool = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 64, alignment: .leading)
                .lineLimit(1)
            Text(copied ? "Copié ✓" : value)
                .font(.system(size: 10.5, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundStyle(copied ? Color.green : Color.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10.5))
        .contentShape(Rectangle())
        .onTapGesture {
            guard copyable, value != "—", value != "…" else { return }
            copyToPasteboard(value)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { copied = false }
        }
        .help(copyable ? "Clique pour copier" : "")
    }
}

struct GaugeRow: View {
    let label: String
    let value: Double
    let text: String
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(text).fontWeight(.medium).lineLimit(1)
            }
            .font(.system(size: 10))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, value))))
                }
            }
            .frame(height: 4)
        }
    }
}
