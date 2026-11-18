import Foundation

/// Synthetic fixtures only. The UI must clearly mark the complete session as demo data.
public enum DemoData {
    public static func snapshot(around center: GeoCoordinate, at: Date = Date()) -> FlightSnapshot {
        let aircraft = (0..<6).map { index in
            let bearing = Double(index) * 60 + 12
            let distance = Double(4 + index * 5)
            let coordinate = destination(from: center, bearing: bearing, distanceKilometers: distance)
            return Aircraft(
                hex: String(format: "f%05x", index + 1),
                callsign: "DEMO\(100 + index)",
                registration: "DEMO-\(index + 1)",
                typeCode: index.isMultiple(of: 2) ? "A320" : "B738",
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                barometricAltitudeFeet: Double(8_000 + index * 3_000),
                geometricAltitudeFeet: Double(8_150 + index * 3_000),
                groundSpeedKnots: Double(210 + index * 30),
                trackDegrees: (bearing + 120).truncatingRemainder(dividingBy: 360),
                verticalRateFeetPerMinute: index.isMultiple(of: 2) ? 480 : -360,
                positionAgeSeconds: 1,
                lastMessageAgeSeconds: 0.4
            )
        }
        return FlightSnapshot(aircraft: aircraft, capturedAt: at)
    }

    public static func details(for aircraft: Aircraft) -> AircraftDetails {
        AircraftDetails(
            aircraft: AircraftMetadata(
                manufacturer: aircraft.typeCode == "A320" ? "Airbus（演示）" : "Boeing（演示）",
                typeName: aircraft.typeCode == "A320" ? "A320-200（演示）" : "737-800（演示）",
                registration: aircraft.registration,
                owner: "演示航空 · 虚构数据",
                ownerCountry: "演示"
            ),
            route: FlightRoute(
                callsignIATA: aircraft.callsign,
                airlineName: "演示航空 · 虚构航线",
                origin: AirportInfo(name: "演示出发机场", iata: "AAA", icao: "DEMO", city: "演示城市 A"),
                destination: AirportInfo(name: "演示到达机场", iata: "BBB", icao: "TEST", city: "演示城市 B")
            )
        )
    }

    private static func destination(from origin: GeoCoordinate, bearing: Double, distanceKilometers: Double) -> GeoCoordinate {
        let angularDistance = distanceKilometers / 6_371.0088
        let bearing = bearing * .pi / 180
        let latitude = origin.latitude * .pi / 180
        let longitude = origin.longitude * .pi / 180
        let targetLatitude = asin(sin(latitude) * cos(angularDistance) + cos(latitude) * sin(angularDistance) * cos(bearing))
        let targetLongitude = longitude + atan2(sin(bearing) * sin(angularDistance) * cos(latitude), cos(angularDistance) - sin(latitude) * sin(targetLatitude))
        let normalizedLongitude = ((targetLongitude * 180 / .pi + 540).truncatingRemainder(dividingBy: 360)) - 180
        return GeoCoordinate(latitude: targetLatitude * 180 / .pi, longitude: normalizedLongitude)
    }
}
