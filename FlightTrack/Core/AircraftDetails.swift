import Foundation

public struct AircraftDetails: Sendable {
    public let aircraft: AircraftMetadata?
    public let route: FlightRoute?
    public let fetchedAt: Date

    public init(aircraft: AircraftMetadata?, route: FlightRoute?, fetchedAt: Date = Date()) {
        self.aircraft = aircraft
        self.route = route
        self.fetchedAt = fetchedAt
    }
}

public struct AircraftMetadata: Decodable, Sendable {
    public let manufacturer: String?
    public let typeName: String?
    public let registration: String?
    public let owner: String?
    public let ownerCountry: String?
    public let photoURL: URL?

    public init(manufacturer: String? = nil, typeName: String? = nil, registration: String? = nil,
                owner: String? = nil, ownerCountry: String? = nil, photoURL: URL? = nil) {
        self.manufacturer = manufacturer?.nilIfBlank
        self.typeName = typeName?.nilIfBlank
        self.registration = registration?.nilIfBlank
        self.owner = owner?.nilIfBlank
        self.ownerCountry = ownerCountry?.nilIfBlank
        self.photoURL = photoURL
    }

    private enum CodingKeys: String, CodingKey {
        case manufacturer, typeName = "type", registration, owner = "registered_owner"
        case ownerCountry = "registered_owner_country_name", photoURL = "url_photo", thumbnail = "url_photo_thumbnail"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let image = values.stringOrNil(forKey: .photoURL) ?? values.stringOrNil(forKey: .thumbnail)
        let url = image.flatMap(URL.init(string:)).flatMap { url in url.scheme == "https" ? url : nil }
        self.init(manufacturer: values.stringOrNil(forKey: .manufacturer), typeName: values.stringOrNil(forKey: .typeName),
                  registration: values.stringOrNil(forKey: .registration), owner: values.stringOrNil(forKey: .owner),
                  ownerCountry: values.stringOrNil(forKey: .ownerCountry), photoURL: url)
    }
}

public struct FlightRoute: Decodable, Sendable {
    public let callsignIATA: String?
    public let airlineName: String?
    public let origin: AirportInfo?
    public let destination: AirportInfo?

    public init(callsignIATA: String? = nil, airlineName: String? = nil, origin: AirportInfo? = nil, destination: AirportInfo? = nil) {
        self.callsignIATA = callsignIATA?.nilIfBlank
        self.airlineName = airlineName?.nilIfBlank
        self.origin = origin
        self.destination = destination
    }

    private enum CodingKeys: String, CodingKey { case callsignIATA = "callsign_iata", airline, origin, destination }
    private struct Airline: Decodable { let name: String? }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            callsignIATA: values.stringOrNil(forKey: .callsignIATA),
            airlineName: (try? values.decodeIfPresent(Airline.self, forKey: .airline))?.name,
            origin: try values.decodeIfPresent(AirportInfo.self, forKey: .origin),
            destination: try values.decodeIfPresent(AirportInfo.self, forKey: .destination)
        )
    }
}

public struct AirportInfo: Decodable, Sendable {
    public let name: String?
    public let iata: String?
    public let icao: String?
    public let city: String?
    public let latitude: Double?
    public let longitude: Double?

    public init(name: String? = nil, iata: String? = nil, icao: String? = nil, city: String? = nil,
                latitude: Double? = nil, longitude: Double? = nil) {
        self.name = name?.nilIfBlank
        self.iata = iata?.nilIfBlank
        self.icao = icao?.nilIfBlank
        self.city = city?.nilIfBlank
        self.latitude = latitude?.finiteOrNil
        self.longitude = longitude?.finiteOrNil
    }

    private enum CodingKeys: String, CodingKey {
        case name, iata = "iata_code", icao = "icao_code", city = "municipality", latitude, longitude
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: values.stringOrNil(forKey: .name), iata: values.stringOrNil(forKey: .iata),
                  icao: values.stringOrNil(forKey: .icao), city: values.stringOrNil(forKey: .city),
                  latitude: values.doubleOrNil(forKey: .latitude), longitude: values.doubleOrNil(forKey: .longitude))
    }
}
