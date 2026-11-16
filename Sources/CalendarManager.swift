import AppKit
import EventKit
import SwiftUI

struct EventItem: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
    let meetingURL: URL?

    var timeLabel: String {
        let cal = Calendar.current
        let now = Date()
        let tf = DateFormatter()
        tf.locale = Theme.fr
        tf.dateFormat = "HH:mm"
        let dayPrefix = cal.isDateInTomorrow(start) ? "Demain · " : ""
        if allDay { return dayPrefix + "Toute la journée" }
        if start <= now && end > now { return "En cours · jusqu'à \(tf.string(from: end))" }
        let minutes = Int(start.timeIntervalSince(now) / 60)
        if minutes >= 0 && minutes < 60 { return "Dans \(max(1, minutes)) min · \(tf.string(from: start))" }
        return dayPrefix + "\(tf.string(from: start)) – \(tf.string(from: end))"
    }
}

struct ReminderItem: Identifiable {
    let id: String
    let title: String
    let due: Date?
    let reminder: EKReminder
}

final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    let store = EKEventStore()
    @Published var events: [EventItem] = []
    @Published var reminders: [ReminderItem] = []
    @Published var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
    private var timer: Timer?

    var hasCalendarAccess: Bool { calendarStatus == .fullAccess }
    var hasRemindersAccess: Bool { remindersStatus == .fullAccess }

    func start() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload()
        }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.reload() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        requestAccess()
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.calendarStatus = EKEventStore.authorizationStatus(for: .event)
                self.store.requestFullAccessToReminders { _, _ in
                    DispatchQueue.main.async {
                        self.remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
                        self.reload()
                    }
                }
            }
        }
    }

    func askOrOpenSettings() {
        if calendarStatus == .notDetermined { requestAccess() } else { openPrivacyPane("Privacy_Calendars") }
    }

    func reload() {
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        remindersStatus = EKEventStore.authorizationStatus(for: .reminder)

        if hasCalendarAccess {
            let now = Date()
            let startOfDay = Calendar.current.startOfDay(for: now)
            let end = Calendar.current.date(byAdding: .day, value: 2, to: startOfDay) ?? now.addingTimeInterval(172800)
            let predicate = store.predicateForEvents(withStart: startOfDay, end: end, calendars: nil)
            let found = store.events(matching: predicate)
                .filter { $0.endDate > now }
                .sorted { $0.startDate < $1.startDate }
            events = found.prefix(8).map { e in
                EventItem(id: (e.eventIdentifier ?? UUID().uuidString) + "-\(e.startDate.timeIntervalSince1970)",
                          title: e.title ?? "Sans titre",
                          start: e.startDate,
                          end: e.endDate,
                          allDay: e.isAllDay,
                          color: e.calendar.map { Color(cgColor: $0.cgColor) } ?? Theme.red,
                          meetingURL: CalendarManager.meetingURL(e))
            }
        }

        if hasRemindersAccess {
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            store.fetchReminders(matching: predicate) { [weak self] found in
                let items: [ReminderItem] = (found ?? []).map { r in
                    let due = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                    return ReminderItem(id: r.calendarItemIdentifier, title: r.title ?? "Rappel", due: due, reminder: r)
                }
                .sorted { a, b in
                    switch (a.due, b.due) {
                    case let (x?, y?): return x < y
                    case (_?, nil): return true
                    case (nil, _?): return false
                    default: return a.title < b.title
                    }
                }
                DispatchQueue.main.async { self?.reminders = Array(items.prefix(10)) }
            }
        }
    }

    func complete(_ item: ReminderItem) {
        item.reminder.isCompleted = true
        try? store.save(item.reminder, commit: true)
        withAnimation { reminders.removeAll { $0.id == item.id } }
    }

    static func meetingURL(_ e: EKEvent) -> URL? {
        var texts: [String] = []
        if let u = e.url { texts.append(u.absoluteString) }
        if let l = e.location { texts.append(l) }
        if let n = e.notes { texts.append(n) }
        let pattern = "https?://[^\\s<>\"]*(meet\\.google\\.com|zoom\\.us|teams\\.microsoft\\.com|teams\\.live\\.com|webex\\.com|whereby\\.com|meet\\.jit\\.si|discord\\.gg|discord\\.com)[^\\s<>\"]*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range), let r = Range(match.range, in: text) {
                return URL(string: String(text[r]))
            }
        }
        return nil
    }
}
