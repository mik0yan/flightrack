import SwiftUI

enum SkyTheme {
    static let canvas = Color(red: 0.045, green: 0.070, blue: 0.105)
    static let panel = Color(red: 0.075, green: 0.110, blue: 0.155)
    static let accent = Color(red: 0.32, green: 0.91, blue: 0.79)
    static let line = Color.white.opacity(0.09)
}

struct SkyBadge: View {
    let text: String
    var color: Color = SkyTheme.accent
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }
}

enum FlightDisplay {
    static func callsign(_ aircraft: Aircraft) -> String {
        aircraft.callsign?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? aircraft.registration?.nilIfEmpty ?? aircraft.hex.uppercased()
    }

    static func distance(_ aircraft: Aircraft, from center: GeoCoordinate) -> String {
        guard let coordinate = aircraft.coordinate else { return "位置未知" }
        let kilometers = FlightGeometry.distanceKilometers(from: center, to: coordinate)
        return kilometers.formatted(.number.precision(.fractionLength(1))) + " km"
    }

    static func altitude(_ aircraft: Aircraft) -> String {
        if aircraft.isOnGround { return "地面" }
        guard let altitude = aircraft.altitudeMeters else { return "—" }
        return altitude.formatted(.number.precision(.fractionLength(0))) + " m"
    }

    static func speed(_ aircraft: Aircraft) -> String {
        guard let speed = aircraft.groundSpeedKilometersPerHour else { return "—" }
        return speed.formatted(.number.precision(.fractionLength(0))) + " km/h"
    }

    static func coordinate(_ coordinate: GeoCoordinate) -> String {
        String(format: "%.5f, %.5f", coordinate.longitude, coordinate.latitude)
    }

    static func effectiveAgeSeconds(_ aircraft: Aircraft, snapshotDate: Date?, now: Date = Date()) -> Double? {
        guard let reportedAge = aircraft.positionAgeSeconds, let snapshotDate else { return nil }
        return max(0, reportedAge) + max(0, now.timeIntervalSince(snapshotDate))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct SourceCredits: View {
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Text(compact ? "数据" : "位置数据")
                .foregroundStyle(.secondary)
            Link("adsb.fi", destination: URL(string: "https://adsb.fi/")!)
            Text("·").foregroundStyle(.secondary)
            Link("adsbdb", destination: URL(string: "https://www.adsbdb.com/")!)
        }
        .font(.caption)
        .tint(SkyTheme.accent)
        .accessibilityElement(children: .contain)
    }
}

struct SkyEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(SkyTheme.accent)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

struct FlightPositionAgeLabel: View {
    let aircraft: Aircraft
    let snapshotDate: Date?
    let isDemo: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            let age = FlightDisplay.effectiveAgeSeconds(aircraft, snapshotDate: snapshotDate, now: timeline.date)
            let stale = age.map { $0 > 60 } ?? true
            Label {
                if isDemo {
                    Text("演示位置 · 非实时")
                } else if let age {
                    Text("\(stale ? "位置已过期" : "位置更新") · \(Int(age)) 秒前")
                        .monospacedDigit()
                } else {
                    Text("位置更新时间未知")
                }
            } icon: {
                Image(systemName: isDemo ? "sparkles" : (stale ? "clock.badge.exclamationmark" : "clock"))
            }
            .font(.caption)
            .foregroundStyle(isDemo || stale ? Color.orange : Color.secondary)
        }
    }
}
