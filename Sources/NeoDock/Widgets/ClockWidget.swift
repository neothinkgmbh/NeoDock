import AppKit
import SwiftUI

struct ClockWidget: View {
    static let calendarID = "com.apple.iCal"

    var body: some View {
        TimelineView(.everyMinute) { context in
            WidgetTile(caption: context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                       tap: openCalendar, face: AnyView(ClockFace(date: context.date)), tint: .gray) {
                Text(context.date.formatted(date: .omitted, time: .shortened))
            }
        }
    }

    private func openCalendar() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.calendarID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

struct BatteryWidget: View {
    let status: BatteryStatus

    var body: some View {
        let tint: Color = status.percent <= 15 ? .red : status.percent <= 30 ? .yellow : .green
        WidgetTile(caption: status.isCharging ? "lädt" : "Akku",
                   face: AnyView(RingFace(progress: Double(status.percent) / 100, tint: tint,
                                          symbol: status.isCharging ? "bolt.fill" : "battery.100",
                                          label: status.isCharging ? nil : "\(status.percent)")),
                   tint: tint) {
            Text("\(status.percent) %")
        }
    }
}
