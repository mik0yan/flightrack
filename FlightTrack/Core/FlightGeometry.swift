import Foundation

public struct RelativeAircraftPosition: Sendable, Equatable {
    public let eastMeters: Double
    public let northMeters: Double
    public let upMeters: Double
    public let azimuthDegrees: Double
    public let elevationDegrees: Double
    /// Slant distance from observer to target, including altitude.
    public let distanceKilometers: Double
}

public enum FlightGeometry {
    /// Great-circle surface distance. Radius filtering deliberately excludes altitude.
    public static func distanceKilometers(from: GeoCoordinate, to: GeoCoordinate) -> Double {
        let lat1 = from.latitude.radians
        let lat2 = to.latitude.radians
        let deltaLat = lat2 - lat1
        let deltaLon = (to.longitude - from.longitude).radians
        let a = pow(sin(deltaLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(deltaLon / 2), 2)
        return 6_371.0088 * 2 * atan2(sqrt(max(0, min(1, a))), sqrt(max(0, 1 - a)))
    }

    public static func bearingDegrees(from: GeoCoordinate, to: GeoCoordinate) -> Double {
        let lat1 = from.latitude.radians
        let lat2 = to.latitude.radians
        let lonDifference = (to.longitude - from.longitude).radians
        let y = sin(lonDifference) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lonDifference)
        return normalizedDegrees(atan2(y, x).degrees)
    }

    /// WGS84 Earth-centered coordinates converted to the observer's local East/North/Up frame.
    /// Unlike flat altitude subtraction, this accounts for Earth curvature over long ranges.
    public static func relativePosition(
        observer: GeoCoordinate,
        observerAltitudeMeters: Double,
        target: GeoCoordinate,
        targetAltitudeMeters: Double
    ) -> RelativeAircraftPosition {
        let origin = ecef(coordinate: observer, altitudeMeters: observerAltitudeMeters)
        let destination = ecef(coordinate: target, altitudeMeters: targetAltitudeMeters)
        let dx = destination.x - origin.x
        let dy = destination.y - origin.y
        let dz = destination.z - origin.z
        let latitude = observer.latitude.radians
        let longitude = observer.longitude.radians
        let east = -sin(longitude) * dx + cos(longitude) * dy
        let north = -sin(latitude) * cos(longitude) * dx - sin(latitude) * sin(longitude) * dy + cos(latitude) * dz
        let up = cos(latitude) * cos(longitude) * dx + cos(latitude) * sin(longitude) * dy + sin(latitude) * dz
        let horizontal = hypot(east, north)
        return RelativeAircraftPosition(
            eastMeters: east,
            northMeters: north,
            upMeters: up,
            azimuthDegrees: normalizedDegrees(atan2(east, north).degrees),
            elevationDegrees: atan2(up, horizontal).degrees,
            distanceKilometers: hypot(horizontal, up) / 1_000
        )
    }

    private static func ecef(coordinate: GeoCoordinate, altitudeMeters: Double) -> (x: Double, y: Double, z: Double) {
        let majorAxis = 6_378_137.0
        let flattening = 1 / 298.257223563
        let eccentricitySquared = flattening * (2 - flattening)
        let latitude = coordinate.latitude.radians
        let longitude = coordinate.longitude.radians
        let normalRadius = majorAxis / sqrt(1 - eccentricitySquared * pow(sin(latitude), 2))
        return (
            (normalRadius + altitudeMeters) * cos(latitude) * cos(longitude),
            (normalRadius + altitudeMeters) * cos(latitude) * sin(longitude),
            (normalRadius * (1 - eccentricitySquared) + altitudeMeters) * sin(latitude)
        )
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        let value = value.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
