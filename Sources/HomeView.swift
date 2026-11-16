import AppKit
import SwiftUI

struct HomeView: View {
    var body: some View {
        HStack(spacing: 10) {
            MediaCard().frame(width: 282)
            CalendarCard().frame(width: 196)
            WeatherCard()
        }
    }
}

// MARK: - Musique

struct MediaCard: View {
    @ObservedObject var media = MediaManager.shared

    var body: some View {
        Card {
            if media.hasTrack { player } else { empty }
        }
    }

    private var artwork: some View {
        ZStack {
            if let image = media.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [media.accent.opacity(0.7), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: media.accent.opacity(0.55), radius: 12, y: 3)
        .scaleEffect(media.isPlaying ? 1 : 0.92)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: media.isPlaying)
        .onTapGesture { media.openPlayer() }
        .help("Ouvrir \(media.source?.name ?? "le lecteur")")
    }

    private var player: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 4) {
                Text(media.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(media.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 0)
                SeekBar(progress: media.progress, tint: media.accent) { media.seek($0) }
                HStack {
                    Text(fmtClock(media.position))
                    Spacer()
                    Text("-" + fmtClock(max(0, media.duration - media.position)))
                }
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 16) {
                    IconButton(symbol: "backward.fill", size: 13, help: "Précédent") { media.previous() }
                    IconButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", size: 20, active: true,
                               help: media.isPlaying ? "Pause" : "Lecture") { media.playPause() }
                    IconButton(symbol: "forward.fill", size: 13, help: "Suivant") { media.next() }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.35))
            Text(media.automationDenied
                 ? "Autorise Notch18 dans Réglages Système › Confidentialité › Automatisation"
                 : "Rien en lecture")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 6) {
                Button("Spotify") { media.launch(.spotify) }
                Button("Musique") { media.launch(.music) }
            }
            .buttonStyle(PillButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SeekBar: View {
    let progress: Double
    let tint: Color
    let onSeek: (Double) -> Void
    @State private var hover = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(tint).frame(width: max(0, geo.size.width * CGFloat(progress)))
            }
            .frame(height: hover ? 6 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                guard geo.size.width > 0 else { return }
                onSeek(min(1, max(0, value.location.x / geo.size.width)))
            })
            .onHover { hover = $0 }
        }
        .frame(height: 10)
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

// MARK: - Calendrier

struct CalendarCard: View {
    @ObservedObject var cal = CalendarManager.shared

    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.locale = Theme.fr; f.dateFormat = "EEEE"; return f
    }()
    private static let month: DateFormatter = {
        let f = DateFormatter(); f.locale = Theme.fr; f.dateFormat = "MMMM yyyy"; return f
    }()

    var body: some View {
        let now = Date()
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text("\(Calendar.current.component(.day, from: now))")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Self.weekday.string(from: now).capitalized)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.red)
                        Text(Self.month.string(from: now).capitalized)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                    IconButton(symbol: "calendar", size: 11, help: "Ouvrir Calendrier") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                        }
                    }
                }

                if !cal.hasCalendarAccess {
                    Button("Autoriser l'accès au calendrier") { cal.askOrOpenSettings() }
                        .buttonStyle(PillButtonStyle(tint: Theme.red))
                } else if cal.events.isEmpty {
                    Text("Rien de prévu aujourd'hui ni demain 🎉")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    ForEach(cal.events.prefix(cal.reminders.isEmpty ? 4 : 3)) { EventRow(event: $0) }
                }

                if !cal.reminders.isEmpty {
                    Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                    ForEach(cal.reminders.prefix(2)) { item in
                        HStack(spacing: 6) {
                            Button { cal.complete(item) } label: {
                                Image(systemName: "circle").font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .help("Marquer comme fait")
                            Text(item.title).font(.system(size: 10.5)).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct EventRow: View {
    let event: EventItem

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(event.timeLabel).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let url = event.meetingURL {
                IconButton(symbol: "video.fill", size: 10, help: "Rejoindre la visio") { NSWorkspace.shared.open(url) }
            }
        }
    }
}

// MARK: - Météo

struct WeatherCard: View {
    @ObservedObject var weather = WeatherManager.shared

    private static let hour: DateFormatter = {
        let f = DateFormatter(); f.locale = Theme.fr; f.dateFormat = "HH'h'"; return f
    }()

    var body: some View {
        Card {
            if let d = weather.data {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: WeatherManager.symbol(d.code, isDay: d.isDay))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 22))
                        Text("\(Int(d.temp.rounded()))°")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                    }
                    Text(WeatherManager.describe(d.code))
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                    Text("\(weather.cityLabel) · ↑\(Int(d.max.rounded()))° ↓\(Int(d.min.rounded()))°")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Image(systemName: "wind")
                        Text("\(Int(d.wind.rounded())) km/h")
                        if let g = d.gusts, g >= 45 {
                            Text("· raf. \(Int(g.rounded()))")
                                .foregroundStyle(g >= 70 ? Color.red : Color.orange)
                        }
                    }
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        ForEach(d.hours.prefix(4)) { h in
                            let hr = Calendar.current.component(.hour, from: h.date)
                            VStack(spacing: 2) {
                                Text(Self.hour.string(from: h.date))
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(.white.opacity(0.5))
                                Image(systemName: WeatherManager.symbol(h.code, isDay: hr >= 7 && hr < 20))
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 11))
                                Text("\(Int(h.temp.rounded()))°")
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { weather.refresh(force: true) }
                .help("Clique pour actualiser")
            } else {
                VStack(spacing: 6) {
                    if weather.error == nil { ProgressView().controlSize(.small) }
                    Text(weather.error ?? "Météo…")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                    if weather.error != nil {
                        Button("Réessayer") { weather.refresh(force: true) }.buttonStyle(PillButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
