import AppKit
import SwiftUI

enum TimerMode: String, CaseIterable {
    case countdown = "Minuteur"
    case pomodoro = "Pomodoro"
    case stopwatch = "Chrono"
}

enum PomoPhase {
    case work, shortBreak, longBreak

    var label: String {
        switch self {
        case .work: return "Concentration"
        case .shortBreak: return "Pause courte"
        case .longBreak: return "Pause longue"
        }
    }

    var color: Color {
        switch self {
        case .work: return Theme.red
        case .shortBreak: return .green
        case .longBreak: return .teal
        }
    }
}

final class TimerManager: ObservableObject {
    static let shared = TimerManager()

    @Published private(set) var mode: TimerMode = .countdown
    @Published private(set) var running = false
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var phase: PomoPhase = .work
    @Published private(set) var pomodoros = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var laps: [TimeInterval] = []

    private var endDate: Date?
    private var swStart: Date?
    private var swAccum: TimeInterval = 0
    private var ticker: Timer?

    var isActive: Bool {
        mode == .stopwatch ? (running || elapsed > 0) : (running || remaining > 0)
    }
    var displayTime: TimeInterval { mode == .stopwatch ? elapsed : remaining }
    var ringProgress: Double {
        switch mode {
        case .stopwatch: return elapsed.truncatingRemainder(dividingBy: 60) / 60
        default: return total > 0 ? remaining / total : 0
        }
    }
    var tint: Color {
        switch mode {
        case .pomodoro: return phase.color
        case .stopwatch: return .cyan
        case .countdown: return .orange
        }
    }

    private func duration(for p: PomoPhase) -> TimeInterval {
        let d = UserDefaults.standard
        switch p {
        case .work: return Double(max(1, d.integer(forKey: "pomoWork"))) * 60
        case .shortBreak: return Double(max(1, d.integer(forKey: "pomoShort"))) * 60
        case .longBreak: return Double(max(1, d.integer(forKey: "pomoLong"))) * 60
        }
    }

    func setMode(_ m: TimerMode) {
        guard m != mode else { return }
        reset()
        mode = m
        if m == .pomodoro { total = duration(for: .work); remaining = 0 }
    }

    func startCountdown(_ seconds: TimeInterval) {
        reset()
        mode = .countdown
        total = seconds
        remaining = seconds
        UserDefaults.standard.set(seconds, forKey: "lastCountdown")
        resume()
    }

    func primaryAction() {
        if running { pause(); return }
        switch mode {
        case .countdown:
            if remaining <= 0 { startCountdown(UserDefaults.standard.double(forKey: "lastCountdown")) } else { resume() }
        case .pomodoro, .stopwatch:
            resume()
        }
    }

    func resume() {
        guard !running else { return }
        if mode == .stopwatch {
            swStart = Date()
        } else {
            if remaining <= 0 {
                guard mode == .pomodoro else { return }
                total = duration(for: phase)
                remaining = total
            }
            endDate = Date().addingTimeInterval(remaining)
        }
        running = true
        startTicker()
    }

    func pause() {
        guard running else { return }
        if mode == .stopwatch {
            swAccum += Date().timeIntervalSince(swStart ?? Date())
            swStart = nil
            elapsed = swAccum
        } else {
            remaining = max(0, endDate?.timeIntervalSinceNow ?? 0)
            endDate = nil
        }
        running = false
        stopTicker()
    }

    func reset() {
        running = false
        stopTicker()
        endDate = nil
        swStart = nil
        swAccum = 0
        elapsed = 0
        remaining = 0
        laps = []
        if mode == .pomodoro {
            phase = .work
            pomodoros = 0
            total = duration(for: .work)
        } else {
            total = 0
        }
    }

    func add(_ seconds: TimeInterval) {
        guard mode == .countdown else { return }
        total += seconds
        remaining += seconds
        if running { endDate = endDate?.addingTimeInterval(seconds) }
    }

    func lap() {
        guard mode == .stopwatch, running || elapsed > 0 else { return }
        laps.insert(elapsed, at: 0)
    }

    func skipPhase() {
        guard mode == .pomodoro else { return }
        let wasRunning = running
        pause()
        advancePhase()
        if wasRunning { resume() }
    }

    private func advancePhase() {
        if phase == .work {
            pomodoros += 1
            phase = pomodoros % 4 == 0 ? .longBreak : .shortBreak
        } else {
            phase = .work
        }
        total = duration(for: phase)
        remaining = total
    }

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        if mode == .stopwatch {
            elapsed = swAccum + Date().timeIntervalSince(swStart ?? Date())
            return
        }
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 { finish() }
    }

    private func finish() {
        running = false
        endDate = nil
        stopTicker()
        NSSound(named: "Glass")?.play()
        if mode == .pomodoro {
            let finished = phase
            advancePhase()
            NotchState.shared.showSneak(symbol: "timer", text: "\(finished.label) terminée — \(phase.label)",
                                        tint: phase.color, duration: 4)
            if UserDefaults.standard.bool(forKey: "pomoAuto") { resume() }
        } else {
            remaining = 0
            total = 0
            NotchState.shared.showSneak(symbol: "bell.fill", text: "Minuteur terminé !", tint: .orange, duration: 5)
        }
    }
}

struct TimerView: View {
    @ObservedObject var t = TimerManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Card {
                VStack(spacing: 8) {
                    Picker("", selection: Binding(get: { t.mode }, set: { t.setMode($0) })) {
                        ForEach(TimerMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)

                    ZStack {
                        Circle().stroke(Color.white.opacity(0.1), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: CGFloat(t.ringProgress))
                            .stroke(t.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.25), value: t.ringProgress)
                        VStack(spacing: 1) {
                            Text(fmtClock(t.displayTime))
                                .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                            if t.mode == .pomodoro {
                                Text(t.phase.label).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(t.phase.color)
                            }
                        }
                    }
                    .frame(width: 104, height: 104)

                    HStack(spacing: 14) {
                        IconButton(symbol: "arrow.counterclockwise", size: 12, help: "Réinitialiser") { t.reset() }
                        IconButton(symbol: t.running ? "pause.fill" : "play.fill", size: 18, active: true,
                                   help: t.running ? "Pause" : "Démarrer") { t.primaryAction() }
                        switch t.mode {
                        case .countdown:
                            IconButton(symbol: "plus", size: 12, help: "+1 min") { t.add(60) }
                        case .pomodoro:
                            IconButton(symbol: "forward.end.fill", size: 12, help: "Phase suivante") { t.skipPhase() }
                        case .stopwatch:
                            IconButton(symbol: "flag.fill", size: 12, help: "Tour") { t.lap() }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: 250)

            Card { side }
        }
    }

    @ViewBuilder private var side: some View {
        switch t.mode {
        case .countdown:
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Départs rapides", symbol: "bolt.fill", tint: .orange)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach([1, 2, 3, 5, 10, 15, 20, 30, 45, 60], id: \.self) { m in
                        Button("\(m) min") { t.startCountdown(Double(m) * 60) }
                            .buttonStyle(PillButtonStyle(tint: .orange))
                    }
                }
                Text("Le temps restant s'affiche dans l'encoche, et une alerte sonne à la fin.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
            }
        case .pomodoro:
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Pomodoro", symbol: "brain.head.profile", tint: Theme.red)
                Text("Cycles de concentration, puis une pause. Une pause longue après 4 cycles. Parfait pour réviser.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.65))
                HStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i < t.pomodoros % 4 || (t.pomodoros > 0 && t.pomodoros % 4 == 0 && t.phase == .longBreak)
                                  ? Theme.red : Color.white.opacity(0.15))
                            .frame(width: 10, height: 10)
                    }
                    Text("\(t.pomodoros) terminé\(t.pomodoros > 1 ? "s" : "")")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Text("Durées modifiables dans les réglages.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 0)
            }
        case .stopwatch:
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle("Tours", symbol: "flag.fill", tint: .cyan)
                if t.laps.isEmpty {
                    Text("Appuie sur le drapeau pour enregistrer un tour.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(t.laps.enumerated()), id: \.offset) { i, lap in
                                HStack {
                                    Text("Tour \(t.laps.count - i)").foregroundStyle(.white.opacity(0.6))
                                    Spacer()
                                    Text(fmtClock(lap)).monospacedDigit()
                                }
                                .font(.system(size: 11))
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
