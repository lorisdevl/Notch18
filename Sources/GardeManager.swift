import AppKit
import SwiftUI

enum GardeStatus: String, Codable, CaseIterable, Identifiable {
    case aucun, disponible, astreinte, garde, indisponible, intervention
    var id: String { rawValue }

    var label: String {
        switch self {
        case .aucun: return "Pas de statut"
        case .disponible: return "Disponible"
        case .astreinte: return "Astreinte"
        case .garde: return "Garde postée"
        case .indisponible: return "Indisponible"
        case .intervention: return "En intervention"
        }
    }

    var symbol: String {
        switch self {
        case .aucun: return "circle.dashed"
        case .disponible: return "checkmark.circle.fill"
        case .astreinte: return "bell.badge.fill"
        case .garde: return "building.2.fill"
        case .indisponible: return "moon.zzz.fill"
        case .intervention: return "flame.fill"
        }
    }

    var color: Color {
        switch self {
        case .aucun: return .gray
        case .disponible: return .green
        case .astreinte: return .orange
        case .garde: return Color(red: 0.38, green: 0.62, blue: 1)
        case .indisponible: return Color(white: 0.6)
        case .intervention: return Theme.red
        }
    }

    static let selectable: [GardeStatus] = [.disponible, .astreinte, .garde, .indisponible, .aucun]
}

enum InterStepKind: String, CaseIterable {
    case alerte = "Alerte"
    case depart = "Départ"
    case surPlace = "Sur les lieux"
    case transport = "Transport"
    case hopital = "Hôpital"
    case retour = "Retour dispo"

    var symbol: String {
        switch self {
        case .alerte: return "bell.fill"
        case .depart: return "car.fill"
        case .surPlace: return "mappin.and.ellipse"
        case .transport: return "arrow.triangle.turn.up.right.diamond.fill"
        case .hopital: return "cross.case.fill"
        case .retour: return "house.fill"
        }
    }
}

struct InterStep: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: String
    var date: Date
}

struct Intervention: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Date
    var nature: String = ""
    var steps: [InterStep] = []
    var end: Date?

    var duration: TimeInterval { (end ?? Date()).timeIntervalSince(start) }

    func time(of kind: InterStepKind) -> Date? {
        steps.first(where: { $0.kind == kind.rawValue })?.date
    }

    func summary() -> String {
        let day = DateFormatter()
        day.locale = Theme.fr
        day.dateFormat = "EEEE d MMMM yyyy"
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"
        var lines = ["Intervention du \(day.string(from: start))"]
        if !nature.isEmpty { lines.append("Nature : \(nature)") }
        for s in steps {
            let delta = s.date.timeIntervalSince(start)
            lines.append("• \(s.kind) : \(tf.string(from: s.date))" + (delta >= 60 ? "  (+\(fmtDuration(delta)))" : ""))
        }
        lines.append("Durée totale : \(fmtDuration(duration))")
        return lines.joined(separator: "\n")
    }
}

private struct GardeSave: Codable {
    var status: GardeStatus
    var since: Date
    var previous: GardeStatus
    var current: Intervention?
    var history: [Intervention]
}

/// Mode garde pour sapeur-pompier volontaire : statut, horodatage d'intervention, historique.
/// Outil perso de prise de notes : il ne remplace pas les outils officiels du SDIS.
final class GardeManager: ObservableObject {
    static let shared = GardeManager()

    @Published private(set) var status: GardeStatus = .aucun
    @Published private(set) var statusSince = Date()
    @Published private(set) var previousStatus: GardeStatus = .disponible
    @Published private(set) var current: Intervention?
    @Published private(set) var history: [Intervention] = []
    @Published private(set) var now = Date()

    private var ticker: Timer?
    private let file = "garde.json"

    var showInNotch: Bool { UserDefaults.standard.bool(forKey: "showGardeInNotch") }

    init() {
        if let s = Storage.load(GardeSave.self, from: file) {
            status = s.status
            statusSince = s.since
            previousStatus = s.previous
            current = s.current
            history = s.history
        }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.status != .aucun || self.current != nil else { return }
            self.now = Date()
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func persist() {
        Storage.save(GardeSave(status: status, since: statusSince, previous: previousStatus,
                               current: current, history: history), to: file)
    }

    func setStatus(_ s: GardeStatus) {
        if current != nil {
            // Pendant une intervention, on choisit le statut auquel revenir ensuite.
            previousStatus = s
        } else {
            guard s != status else { return }
            status = s
            statusSince = Date()
            now = Date()
        }
        persist()
    }

    func isSelected(_ s: GardeStatus) -> Bool {
        current != nil ? previousStatus == s : status == s
    }

    func mark(_ kind: InterStepKind) {
        if current == nil {
            if status != .intervention { previousStatus = (status == .aucun || status == .indisponible) ? .disponible : status }
            current = Intervention(start: Date(), steps: [InterStep(kind: InterStepKind.alerte.rawValue, date: Date())])
            status = .intervention
            statusSince = Date()
            now = Date()
            if kind == .alerte { persist(); return }
        }
        guard var c = current else { return }
        if let i = c.steps.firstIndex(where: { $0.kind == kind.rawValue }) {
            c.steps[i].date = Date()
        } else {
            c.steps.append(InterStep(kind: kind.rawValue, date: Date()))
        }
        c.steps.sort { $0.date < $1.date }
        current = c
        if kind == .retour { finish() } else { persist() }
    }

    func clearStep(_ kind: InterStepKind) {
        guard var c = current, kind != .alerte else { return }
        c.steps.removeAll { $0.kind == kind.rawValue }
        current = c
        persist()
    }

    func setNature(_ text: String) {
        guard var c = current else { return }
        c.nature = text
        current = c
        persist()
    }

    func finish() {
        guard var c = current else { return }
        c.end = Date()
        history.insert(c, at: 0)
        if history.count > 60 { history.removeLast(history.count - 60) }
        current = nil
        status = previousStatus
        statusSince = Date()
        persist()
    }

    func cancel() {
        current = nil
        status = previousStatus
        statusSince = Date()
        persist()
    }

    func delete(_ i: Intervention) {
        history.removeAll { $0.id == i.id }
        persist()
    }
}

struct GardeView: View {
    @ObservedObject var g = GardeManager.shared
    @State private var copiedID: UUID?

    private static let tf: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let df: DateFormatter = {
        let f = DateFormatter(); f.locale = Theme.fr; f.dateFormat = "dd/MM HH:mm"; return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Card(padding: 8) { statusList }.frame(width: 150)
            Card { interventionPanel }
            Card(padding: 8) { historyList }.frame(width: 172)
        }
    }

    private var statusList: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionTitle(g.current != nil ? "Statut après" : "Mon statut", symbol: "person.fill.checkmark", tint: .green)
                .padding(.bottom, 2)
            ForEach(GardeStatus.selectable) { s in
                Button { g.setStatus(s) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: s.symbol).foregroundStyle(s.color).frame(width: 14)
                        Text(s.label).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10.5, weight: g.isSelected(s) ? .bold : .regular))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(g.isSelected(s) ? s.color.opacity(0.22) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            if g.status != .aucun {
                Text("\(g.status.label) depuis \(fmtDuration(g.now.timeIntervalSince(g.statusSince)))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
            }
        }
    }

    private var interventionPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let c = g.current {
                HStack(spacing: 6) {
                    PulsingIcon(symbol: "flame.fill", color: Theme.red)
                    Text("Intervention en cours").font(.system(size: 11.5, weight: .bold))
                    Spacer()
                    Text(fmtClock(g.now.timeIntervalSince(c.start)))
                        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.red)
                }
                TextField("Nature (SAP, AVP, feu de…)", text: Binding(get: { g.current?.nature ?? "" },
                                                                      set: { g.setNature($0) }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").foregroundStyle(Theme.red)
                    Text("Prêt à décaler").font(.system(size: 11.5, weight: .bold))
                    Spacer()
                }
                Text("Appuie sur « Alerte » au bip : chaque étape est horodatée, puis tu copies le résumé.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                ForEach(InterStepKind.allCases, id: \.self) { kind in
                    let time = g.current?.time(of: kind)
                    Button { g.mark(kind) } label: {
                        VStack(spacing: 2) {
                            Image(systemName: kind.symbol).font(.system(size: 12, weight: .semibold))
                            Text(kind.rawValue).font(.system(size: 9.5, weight: .semibold)).lineLimit(1)
                            Text(time.map { Self.tf.string(from: $0) } ?? "--:--")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(time == nil ? 0.35 : 0.9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 9)
                            .fill(time != nil ? Theme.red.opacity(0.28) : Color.white.opacity(0.07)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if time != nil && kind != .alerte {
                            Button("Effacer cette étape") { g.clearStep(kind) }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
            if let c = g.current {
                HStack(spacing: 6) {
                    Button(copiedID == c.id ? "Copié ✓" : "Copier le résumé") {
                        copyToPasteboard(c.summary())
                        flash(c.id)
                    }
                    .buttonStyle(PillButtonStyle(tint: Theme.red))
                    Spacer()
                    Button("Terminer") { g.finish() }.buttonStyle(PillButtonStyle())
                    Button("Annuler") { g.cancel() }.buttonStyle(PillButtonStyle())
                }
            }
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("Historique", symbol: "clock.arrow.circlepath", tint: .orange)
            if g.history.isEmpty {
                Text("Tes interventions terminées apparaîtront ici.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(g.history) { i in
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text(Self.df.string(from: i.start)).font(.system(size: 10, weight: .semibold))
                                    Spacer()
                                    Text(copiedID == i.id ? "Copié ✓" : fmtDuration(i.duration))
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(copiedID == i.id ? Color.green : Color.white.opacity(0.55))
                                }
                                Text(i.nature.isEmpty ? "Sans nature" : i.nature)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                            .padding(5)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                copyToPasteboard(i.summary())
                                flash(i.id)
                            }
                            .contextMenu {
                                Button("Copier le résumé") { copyToPasteboard(i.summary()) }
                                Button("Supprimer") { g.delete(i) }
                            }
                            .help("Clique pour copier le résumé")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func flash(_ id: UUID) {
        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == id { copiedID = nil }
        }
    }
}
