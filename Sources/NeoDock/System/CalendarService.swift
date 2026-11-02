import AppKit
import EventKit
import Observation

/// Die nächsten Termine von heute und morgen. Die Kalender-Freigabe wird erst erfragt,
/// wenn jemand auf das Widget klickt.
@Observable
final class CalendarService {
    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let isAllDay: Bool
    }

    private(set) var events: [Event] = []
    private(set) var access = EKEventStore.authorizationStatus(for: .event)
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var task: Task<Void, Never>?
    static let refresh: Duration = .seconds(60)
    /// Wie weit vorausgeschaut wird (Einstellung „Kalender-Vorschau“).
    var lookahead: TimeInterval = 36 * 3600
    static let limit = 6

    var hasAccess: Bool { access == .fullAccess }
    var next: Event? { events.first { !$0.isAllDay } ?? events.first }

    func start() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.reload()
                try? await Task.sleep(for: Self.refresh)
            }
        }
    }

    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        access = EKEventStore.authorizationStatus(for: .event)
        reload()
    }

    func reload() {
        access = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else { events = []; return }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(lookahead), calendars: nil)
        let found = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(Self.limit)
            // Alle Vorkommen einer Serie teilen den eventIdentifier — die Startzeit macht sie eindeutig.
            .map { Event(id: "\($0.eventIdentifier ?? UUID().uuidString)|\($0.startDate.timeIntervalSinceReferenceDate)",
                         title: $0.title ?? "Termin",
                         start: $0.startDate, isAllDay: $0.isAllDay) }
        if found != events { events = Array(found) }
    }

    static func openCalendar() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
