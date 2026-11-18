import Foundation

public struct GeoCoordinate: Hashable, Codable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

/// A single receiver observation. Missing altitude or age remains unknown.
public struct Aircraft: Decodable, Hashable, Identifiable, Sendable {
    public let hex: String
    public let callsign: String?
    public let registration: String?
    public let typeCode: String?
    public let latitude: Double?
    public let longitude: Double?
    public let barometricAltitudeFeet: Double?
    public let geometricAltitudeFeet: Double?
    public let groundSpeedKnots: Double?
    public let trackDegrees: Double?
    public let verticalRateFeetPerMinute: Double?
    public let isOnGround: Bool
    public let positionAgeSeconds: Double?
    public let lastMessageAgeSeconds: Double?

    public var id: String { hex }
    public var coordinate: GeoCoordinate? {
        guard let latitude, let longitude else { return nil }
        let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
        return coordinate.isValid ? coordinate : nil
    }
    public var altitudeMeters: Double? {
        (geometricAltitudeFeet ?? barometricAltitudeFeet).map { $0 * 0.3048 }
    }
    public var groundSpeedKilometersPerHour: Double? {
        groundSpeedKnots.map { $0 * 1.852 }
    }

    public init(
        hex: String,
        callsign: String? = nil,
        registration: String? = nil,
        typeCode: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        barometricAltitudeFeet: Double? = nil,
        geometricAltitudeFeet: Double? = nil,
        groundSpeedKnots: Double? = nil,
        trackDegrees: Double? = nil,
        verticalRateFeetPerMinute: Double? = nil,
        isOnGround: Bool = false,
        positionAgeSeconds: Double? = nil,
        lastMessageAgeSeconds: Double? = nil
    ) {
        self.hex = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.callsign = callsign?.nilIfBlank
        self.registration = registration?.nilIfBlank
        self.typeCode = typeCode?.nilIfBlank
        self.latitude = latitude?.finiteOrNil
        self.longitude = longitude?.finiteOrNil
        self.barometricAltitudeFeet = barometricAltitudeFeet?.finiteOrNil
        self.geometricAltitudeFeet = geometricAltitudeFeet?.finiteOrNil
        self.groundSpeedKnots = groundSpeedKnots?.finiteOrNil
        self.trackDegrees = trackDegrees?.finiteOrNil
        self.verticalRateFeetPerMinute = verticalRateFeetPerMinute?.finiteOrNil
        self.isOnGround = isOnGround
        self.positionAgeSeconds = positionAgeSeconds?.finiteOrNil
        self.lastMessageAgeSeconds = lastMessageAgeSeconds?.finiteOrNil
    }

    private enum CodingKeys: String, CodingKey {
        case hex, callsign = "flight", registration = "r", typeCode = "t"
        case latitude = "lat", longitude = "lon", barometricAltitudeFeet = "alt_baro"
        case geometricAltitudeFeet = "alt_geom", groundSpeedKnots = "gs", trackDegrees = "track"
        case barometricRate = "baro_rate", geometricRate = "geom_rate"
        case positionAgeSeconds = "seen_pos", lastMessageAgeSeconds = "seen"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let hex = try values.decode(String.self, forKey: .hex)
        guard hex.nilIfBlank != nil else {
            throw DecodingError.dataCorruptedError(forKey: .hex, in: values, debugDescription: "Missing aircraft identifier")
        }
        self.init(
            hex: hex,
            callsign: values.stringOrNil(forKey: .callsign),
            registration: values.stringOrNil(forKey: .registration),
            typeCode: values.stringOrNil(forKey: .typeCode),
            latitude: values.doubleOrNil(forKey: .latitude),
            longitude: values.doubleOrNil(forKey: .longitude),
            barometricAltitudeFeet: values.doubleOrNil(forKey: .barometricAltitudeFeet),
            geometricAltitudeFeet: values.doubleOrNil(forKey: .geometricAltitudeFeet),
            groundSpeedKnots: values.doubleOrNil(forKey: .groundSpeedKnots),
            trackDegrees: values.doubleOrNil(forKey: .trackDegrees),
            verticalRateFeetPerMinute: values.doubleOrNil(forKey: .geometricRate) ?? values.doubleOrNil(forKey: .barometricRate),
            isOnGround: values.stringOrNil(forKey: .barometricAltitudeFeet)?.lowercased() == "ground",
            positionAgeSeconds: values.doubleOrNil(forKey: .positionAgeSeconds),
            lastMessageAgeSeconds: values.doubleOrNil(forKey: .lastMessageAgeSeconds)
        )
    }
}

public struct FlightSnapshot: Sendable {
    public let aircraft: [Aircraft]
    public let capturedAt: Date

    public init(aircraft: [Aircraft], capturedAt: Date) {
        self.aircraft = aircraft
        self.capturedAt = capturedAt
    }
}

extension KeyedDecodingContainer {
    func stringOrNil(forKey key: Key) -> String? {
        (try? decode(String.self, forKey: key))?.nilIfBlank
    }

    func doubleOrNil(forKey key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value.finiteOrNil }
        if let text = try? decode(String.self, forKey: key) { return Double(text)?.finiteOrNil }
        return nil
    }
}

extension String {
    var nilIfBlank: String? {
        let clean = trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}

extension Double {
    var finiteOrNil: Double? { isFinite ? self : nil }
}
